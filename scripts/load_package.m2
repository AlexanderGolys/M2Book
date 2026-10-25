-- Script mode omits user package paths. Make installed dependencies available
-- while loading M2Book itself from this checkout.
installedPackages := applicationDirectory() | "local/" | Layout#1#"packages";
if isDirectory installedPackages and not member(installedPackages, path) then
    path = append(path, installedPackages);

needsPackage("M2Book", FileName => currentFileDirectory | "../M2Book.m2")
