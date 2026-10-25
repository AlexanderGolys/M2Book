
-- ---------------------------------------------------------------------------
-- Type-hierarchy pass. M2's `ancestors x` and `parent x` are only
-- meaningful for actual `Type` values; for anything else they return
-- the trivial chain `(x, Nothing, Thing)`. We filter on
-- `instance(val, Type)` so the per-type fields stay accurate.
--
-- We also walk every name (not just types) because we need to invert
-- the parent map: any `T'` whose `parent T'` is `T` is a subtype of
-- `T`. The filter happens inside the scan, so non-type names are
-- skipped without polluting the tables.
-- ---------------------------------------------------------------------------

buildTypeHierarchy = (names, runtimeDict) -> (
    parentOf := new MutableHashTable;
    ancestorsOf := new MutableHashTable;
    childrenOf := new MutableHashTable;
    instancesOf := new MutableHashTable;
    scan(names, name -> (
        sym := symbolForName(runtimeDict, name);
        if sym =!= null then (
            val := valueForSymbol(sym);
            if val =!= valueFailed and instance(val, Type) then (
                p := try toString parent val;
                a := try stringList ancestors val else {};
                i := try stringList instances val else {};
                parentOf#name = p;
                ancestorsOf#name = a;
                instancesOf#name = i;
                if p =!= null then childrenOf#p = append(childrenOf#p ?? {}, name);
            );
        )
    ));
    (parentOf, ancestorsOf, childrenOf, instancesOf))

-- ---------------------------------------------------------------------------
-- TypeReference extension. v2 fields are `parent`, `ancestors`,
-- `subtypes`, `instances`, plus `constructors` and `common_operations`,
-- which are populated by the cross-reference pass after extraction.
--
-- `ancestors` excludes the type itself and its immediate parent; the
-- schema gives those their own fields. `subtypes` is built by
-- inverting the parent map: any T' whose parent is T is a subtype.
-- `instances` is the set of global symbols whose runtime value is an
-- instance of T (or any subtype); the v1 scraper stored the raw names,
-- v2 normalises them to ReferenceKey form via `referenceKey`.
-- ---------------------------------------------------------------------------

-- M2's `ancestors x` always returns a list (with at least `x` itself
-- in position 0). The schema's `ancestors` field excludes the type
-- itself and its immediate parent; both have their own fields.
--
-- Note: M2 list elements are Symbols (Types), not Strings, so the
-- comparison has to go through `toString`. The raw `a != parentKey`
-- would always be true because the classes differ. We use `select`
-- to drop the unwanted entries before normalising, so the result
-- is always a list of `referenceKey`-shaped strings.
ancestorsExcludingSelfAndParent = (ancestorsList, parentKey) -> (
    self := if #ancestorsList > 0 then toString ancestorsList#0;
    apply(
        select(drop(ancestorsList, 1), a -> (
            s := toString a;
            s =!= self and s =!= parentKey)),
        referenceKey))

typeExtras = (name, parentOf, ancestorsOf, childrenOf, instancesOf) -> (
    parentName := parentOf#name;
    parentKey := if parentName =!= null then referenceKey parentName;
    baseAncestors := ancestorsOf#name;
    new MutableHashTable from {
        KindFun => "type",
        ParentFun => parentKey,
        AncestorsFun => ancestorsExcludingSelfAndParent(baseAncestors, parentKey),
        SubtypesFun => apply(sort unique (childrenOf#name ?? {}), referenceKey),
        InstancesFun => apply(sort unique (instancesOf#name ?? {}), referenceKey),
        ConstructorsFun => {},
        CommonOperationsFun => {}
    })

extractType = (name, sym, value, db, entriesByName, parentOf, ancestorsOf, childrenOf, instancesOf) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    typeExtras(name, parentOf, ancestorsOf, childrenOf, instancesOf)
)
