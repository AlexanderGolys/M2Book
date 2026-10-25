#!/usr/bin/env bash
# Extract every standard Macaulay2 package with a bounded persistent worker pool.
# Each worker preloads the complete standard runtime once, then extracts an
# interleaved package batch and an interleaved Core name shard. Atomic package
# and Core-shard checkpoints make interrupted runs resumable.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

output="${1:-m2-facts.jsonl}"
m2="${M2_BIN:-$(command -v M2)}"
jobs="${M2BOOK_JOBS:-4}"

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    echo "M2BOOK_JOBS must be a positive integer (got: $jobs)" >&2
    exit 2
fi
if [[ ! -x "$m2" ]]; then
    echo "M2 executable not found: $m2" >&2
    exit 2
fi

package_list="$("$m2" --script scripts/list_standard_packages.m2)"
if [[ -z "$package_list" ]]; then
    echo "no standard Macaulay2 packages found" >&2
    exit 2
fi
mapfile -t packages <<< "$package_list"
total="${#packages[@]}"
if (( total == 0 )); then
    echo "no standard Macaulay2 packages found" >&2
    exit 2
fi

work="$(mktemp -d /tmp/m2book-extract-all-XXXXXX)"
cleanup() {
    rm -rf -- "$work"
}
trap cleanup EXIT

extractor_hash="$(
    sha256sum M2Book.m2 M2Book/*.m2 M2Book/reference/*.m2 scripts/extract*.m2 |
        sha256sum |
        cut -d' ' -f1
)"
checkpoint_root="${M2BOOK_CHECKPOINT_DIR:-/tmp/m2book-checkpoints-$extractor_hash}"
mkdir -p "$checkpoint_root"

pending_packages=()
for package in "${packages[@]}"; do
    # Core is always produced from name shards below, never as a full package
    # batch (which would duplicate the dominant extraction work).
    if [[ "$package" != "Core" && ! -s "$checkpoint_root/$package.jsonl" ]]; then
        pending_packages+=("$package")
    fi
done
pending="${#pending_packages[@]}"

core_names=()
if [[ ! -s "$checkpoint_root/Core.jsonl" ]]; then
    core_name_list="$("$m2" --script scripts/list_package_reference_names.m2 Core)"
    if [[ -z "$core_name_list" ]]; then
        echo "no Core reference names found" >&2
        exit 2
    fi
    mapfile -t core_names <<< "$core_name_list"
fi
core_total="${#core_names[@]}"

work_items="$pending"
if (( core_total > work_items )); then
    work_items="$core_total"
fi
if (( work_items == 0 )); then
    workers=0
else
    workers="$jobs"
    if (( workers > work_items )); then
        workers="$work_items"
    fi
fi

core_workers="$workers"
if (( core_workers > core_total )); then
    core_workers="$core_total"
fi

declare -a worker_packages worker_core_names worker_core_parts
for ((worker = 1; worker <= workers; worker++)); do
    worker_packages[$worker]=""
    worker_core_names[$worker]="-"
    worker_core_parts[$worker]="-"
done

# Stripe packages across persistent workers. This avoids the systematic idle
# tail caused by contiguous alphabetical halves while retaining one preload per
# worker and package-level checkpoints.
for ((i = 0; i < pending; i++)); do
    worker="$((i % workers + 1))"
    package="${pending_packages[$i]}"
    if [[ -n "${worker_packages[$worker]}" ]]; then
        worker_packages[$worker]+=",$package"
    else
        worker_packages[$worker]="$package"
    fi
done

# Stripe sorted Core names as well. The former contiguous split concentrated
# 5,125 method installations in one shard and only 3,053 in the other.
if (( core_total > 0 )); then
    for ((worker = 1; worker <= core_workers; worker++)); do
        names_file="$work/Core-names-$worker.txt"
        : >"$names_file"
        worker_core_names[$worker]="$names_file"
        printf -v part '%s/.Core-shard-%02d-of-%02d.jsonl' \
            "$checkpoint_root" "$worker" "$core_workers"
        worker_core_parts[$worker]="$part"
    done
    for ((i = 0; i < core_total; i++)); do
        worker="$((i % core_workers + 1))"
        printf '%s\n' "${core_names[$i]}" >>"${worker_core_names[$worker]}"
    done
fi

export m2 root work workers checkpoint_root
run_worker() {
    local worker="$1"
    local packages_csv="$2"
    local core_names_file="$3"
    local core_part="$4"
    local package_part status

    printf -v package_part '%s/batch-%02d.jsonl' "$work" "$worker"
    if [[ -z "$packages_csv" ]]; then
        packages_csv="-"
        package_part="-"
    fi
    if [[ "$core_part" != "-" && -s "$core_part" ]]; then
        core_names_file="-"
        core_part="-"
    fi
    if [[ "$packages_csv" == "-" && "$core_part" == "-" ]]; then
        return 0
    fi

    printf -- '-- [worker %d/%d] preloading once for package batch and Core shard\n' \
        "$worker" "$workers"
    set -o pipefail
    M2BOOK_CHECKPOINT_DIR="$checkpoint_root" \
        "$m2" --script "$root/scripts/extract_all_packages_worker.m2" \
        "$package_part" "$packages_csv" "$core_names_file" "$core_part" 2>&1 |
        sed -u "s/^/-- [worker $worker\\/$workers] /"
    status="${PIPESTATUS[0]}"
    if (( status != 0 )); then
        printf -- '-- [worker %d/%d] FAILED with status %d\n' \
            "$worker" "$workers" "$status" >&2
        return "$status"
    fi
}
export -f run_worker

if (( workers > 0 )); then
    printf -- '-- extracting %d/%d pending packages and %d Core names with %d persistent workers; checkpoints: %s\n' \
        "$pending" "$total" "$core_total" "$workers" "$checkpoint_root"
    worker_specs=()
    for ((worker = 1; worker <= workers; worker++)); do
        packages_csv="${worker_packages[$worker]}"
        if [[ -z "$packages_csv" ]]; then
            packages_csv="-"
        fi
        worker_specs+=(
            "$worker" "$packages_csv"
            "${worker_core_names[$worker]}" "${worker_core_parts[$worker]}"
        )
    done
    if ! printf '%s\n' "${worker_specs[@]}" |
        xargs -r -n 4 -P "$workers" bash -c \
            'run_worker "$1" "$2" "$3" "$4"' _; then
        printf -- '-- extraction failed; completed checkpoints remain in %s\n' \
            "$checkpoint_root" >&2
        exit 1
    fi
fi

if [[ ! -s "$checkpoint_root/Core.jsonl" ]]; then
    core_temp="$checkpoint_root/Core.jsonl.tmp"
    : >"$core_temp"
    for ((worker = 1; worker <= core_workers; worker++)); do
        part="${worker_core_parts[$worker]}"
        if [[ ! -s "$part" ]]; then
            printf -- '-- missing Core shard: %s\n' "$part" >&2
            exit 1
        fi
        cat "$part" >>"$core_temp"
    done
    mv -f -- "$core_temp" "$checkpoint_root/Core.jsonl"
    printf -- '-- checkpointed Core: %s records from %d interleaved shards\n' \
        "$(wc -l <"$checkpoint_root/Core.jsonl")" "$core_workers"
fi

combined="$work/combined.jsonl"
: >"$combined"
for package in "${packages[@]}"; do
    part="$checkpoint_root/$package.jsonl"
    if [[ ! -s "$part" ]]; then
        printf -- '-- missing package checkpoint: %s\n' "$part" >&2
        exit 1
    fi
    cat "$part" >>"$combined"
done

"$m2" --script scripts/enrich_cross_references.m2 \
    "$combined" "$work/enriched.jsonl"
"$m2" --script scripts/enrich_sources.m2 \
    "$work/enriched.jsonl" "$work/sourced.jsonl" preload=all
mv -f -- "$work/sourced.jsonl" "$output"
records="$(wc -l <"$output")"
printf -- '-- wrote %s records from %d packages to %s using %d persistent full-runtime workers\n' \
    "$records" "$total" "$output" "$workers"
rm -rf -- "$checkpoint_root"
