
-- M2's operatorAttributes only ever uses Binary/Prefix/Postfix as form kinds
-- (verified against v1.26.05); there is no Option or Assignment operator
-- kind -- the `=>` operator that builds Options is itself just a Binary
-- operator. The `else` branch is a defensive fallback for forward compat.
operatorFormName = kind -> (
    s := toString kind;
    if s === "Binary" then "binary"
    else if s === "Prefix" then "prefix"
    else if s === "Postfix" then "postfix"
    else toString s
)

-- A binary operator takes two operands; prefix/postfix are unary.
operatorArity = formName -> if formName === "binary" then 2 else 1

-- For unary forms the operand sits on the opposite side of the token:
-- a prefix operator (-x) has its operand on the right, postfix on the left.
-- Binary forms have operands on both sides, so `side` is null.
operatorSide = formName -> (
    if formName === "prefix" then "right"
    else if formName === "postfix" then "left"
)

-- An operator form is a method installation specialised by syntactic
-- position: it extends the shared method-level base with the operator
-- extras. The only attribute M2 records is Flexible (the operator accepts
-- user-installed methods), so that is the only attribute-derived field.
operatorMethodRecord = (sym, formKind, formName, attrs) -> (
    attrSet := attrs#formKind;
    attrStrings := if instance(attrSet, Set) then apply(toList attrSet, toString) else {};
    name := toString sym | "_" | formName;
    base := methodBaseRecord(
        name,
        normalizeName name,
        referenceKey(packageForSymbol sym),
        {},
        null);
    fillMissingFields(base, hashTable {
        FormFun => formName,
        ArityFun => operatorArity formName,
        SideFun => operatorSide formName,
        FlexibleFun => member("Flexible", attrStrings)
    })
)

-- The assignment form `x op y = z` is a fourth operator form, installed under the
-- (op,=) method key and surfaced by `methods(sym, symbol =)`. M2 installs blanket
-- handlers for every flexible operator -- `(Type,Type)`/`(Type)` (the method-install
-- syntax) and `(Thing,Thing)` (the generic fallback, redundant with Flexible) -- so
-- only installations with a concrete operand are genuine typed assignment
-- operations (e.g. `M_(i,j) = v` :: ((_,=),MutableMatrix,Sequence)); we keep those.
genericAssignTypes := set {Type, Thing}
assignmentForms = sym -> (
    ms := try methods(sym, symbol =);
    if ms === null then return {};
    specific := select(toList ms, m ->
        instance(m, Sequence) and any(drop(toList m, 1), t -> not genericAssignTypes#?t));
    apply(specific, m -> hashTable {
        DomainFun => apply(drop(toList m, 1), referenceKey)
    }))

operatorInfoForSymbol = sym -> if operatorAttributes#?sym then (
    attrs := operatorAttributes#sym;
    formKinds := keys attrs;
    assignments := assignmentForms sym;
    -- the syntactic forms: Binary/Prefix/Postfix from operatorAttributes, plus the
    -- assignment form when a genuine typed `x op y = z` installation exists.
    forms := sort apply(formKinds, operatorFormName);
    if #assignments > 0 then forms = append(forms, "assignment");
    attrMap := new MutableHashTable;
    scan(formKinds, kind -> (
            attrSet := attrs#kind;
            attrList := if instance(attrSet, Set) then apply(sort toList attrSet, toString) else {};
            attrMap#(operatorFormName kind) = attrList;
        )
    );
    base := hashTable {
        TokenFun => toString sym,
        FormsFun => forms,
        AttributesFun => new HashTable from attrMap
    };
    if #assignments > 0 then base = merge(base, hashTable {AssignmentFun => assignments}, last);
    base
)

-- An operator's `methods` are its real per-domain installations (`methods symbol
-- <op>`, e.g. (+,Matrix,Matrix) -> Matrix), extracted exactly like a function's
-- -- with domain and typicalValue. The syntactic form metadata (binary/prefix/
-- postfix, flexible) lives in the `operator` field, not per installation.
operatorExtras = (sym, db, entriesByName) -> (
    new HashTable from {
        KindFun => "operator",
        OperatorFun => operatorInfoForSymbol(sym),
        MethodsFun => methodRecords(sym, sym, db, entriesByName)
    }
)

extractOperator = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    operatorExtras(sym, db, entriesByName)
)
