
-- ---------------------------------------------------------------------------
-- Package export categorisation. Symbols are classified by their runtime
-- value:
--   function     -- Function, ScriptedFunctor, Command, Manipulator
--   operator     -- has operatorAttributes entry
--   type         -- Type instance
--   config_var   -- in globalAssignmentHooks (mutable runtime config)
--   history_var  -- o{n}, oo, ooo (REPL output history)
--   object       -- everything else (constants, plain values, option keys)
--
-- We filter out package-qualified duplicates (e.g. `JSON$toJSON`).
-- ---------------------------------------------------------------------------

categoriseExports = pkg -> (
    d := pkg.Dictionary;
    funcs := {};
    ops := {};
    types := {};
    configs := {};
    history := {};
    objs := {};
    scan(keys d, name -> (
        if not match("\\$", name) then (
            sym := try getGlobalSymbol name;
            val := if sym === null then try value sym;
            if val === null then objs = append(objs, name)
                else if instance(val, Type) then types = append(types, name)
                else if instance(val, Function) or instance(val, ScriptedFunctor)
            or instance(val, Command) or instance(val, Manipulator)
                then funcs = append(funcs, name)
                else if sym =!= null and operatorAttributes#?sym then ops = append(ops, name)
                else if sym =!= null and instance(sym, Symbol) and globalAssignmentHooks#?(symbolBody sym)
                then configs = append(configs, name)
                else if match("^o[0-9]+$", name) or name === "oo" or name === "ooo" or name === "oooo"
                then history = append(history, name)
                else objs = append(objs, name)
        )
    ));
    hashTable {
        FunctionsFun => sort funcs,
        OperatorsFun => sort ops,
        TypesFun => sort types,
        ConfigVarsFun => sort configs,
        HistoryVarsFun => sort history,
        ObjectsFun => sort objs
    }
)

-- ---------------------------------------------------------------------------
-- Author list from readPackage. Each author entry is a List of Option
-- objects (Name => ..., Email => ..., HomePage => ...).
-- ---------------------------------------------------------------------------

authorRecord = entry -> (
    result := new MutableHashTable from {NameFun => "", EmailFun => "", HomepageFun => ""};
    scan(entry, opt -> (
        if instance(opt, Option) then (
            key := toString first opt;
            val := toString last opt;
            if key === "Name" then result#NameFun = val
                else if key === "Email" then result#EmailFun = val
                else if key === "HomePage" then result#HomepageFun = val
        )
    ));
    new HashTable from result
)

authorList = info -> (
    raw := try info#Authors;
    if raw === null or not instance(raw, List) then {}
        else apply(raw, entry -> (
        author := authorRecord entry;
        author#NameFun
    )
    )
)

-- ---------------------------------------------------------------------------
-- Package extras. `readPackage` gives us the M2-level metadata; the
-- Dictionary gives us the exports. Source file path comes from the
-- package object itself.
-- ---------------------------------------------------------------------------

packageExtras = (name, pkg) -> (
    info := readPackage pkg;
    categorised := categoriseExports pkg;
    new MutableHashTable from {
        KindFun => "package",
        TitleFun => shortNameForRecordName(name),
        VersionFun => try toString info#Version,
        AuthorsFun => authorList info,
        ExportsFun => hashTable {
            FunctionsFun => apply(categorised#FunctionsFun, referenceKey),
            OperatorsFun => apply(categorised#OperatorsFun, referenceKey),
            TypesFun => apply(categorised#TypesFun, referenceKey),
            ObjectsFun => apply(categorised#ObjectsFun, referenceKey)
        }
    }
)

extractPackage = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    packageExtras(name, value)
)
