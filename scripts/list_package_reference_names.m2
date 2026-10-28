-- Print the canonical record names owned by one package, one per line.

load "./load_package.m2"
args := drop(scriptCommandLine, 1);
if #args == 0 then error "expected a package name";
scan(packageReferenceNames(first args), print);
exit 0
