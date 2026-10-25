-- Print one standard-distribution package name per line. User-installed
-- packages are intentionally absent because --script runs M2 with -q.

load(currentFileDirectory | "load_package.m2")
scan(standardPackageNames(), pkg -> print pkg)
exit 0
