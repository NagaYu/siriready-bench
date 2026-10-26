#!/usr/bin/env python3
"""Generate a minimal Xcode project (app + UI-testing target) without third-party tools.

Standard library only. Uses file-system-synchronized groups (objectVersion 77), so source
files are picked up from folders and never listed in the project. Object IDs are derived from
names, so regenerating produces byte-identical projects.

  python3.12 Apps/tools/make_xcodeproj.py --name MessagesOK --bundle-id dev.siriready.messages.ok \
      --app-dir MessagesOK/App --shared-dir Shared/Messages --test-dir Harness --out Apps
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib


def oid(*parts):
    return hashlib.sha1("/".join(parts).encode()).hexdigest()[:24].upper()


def quote(v):
    s = str(v)
    if s and all(c.isalnum() or c in "._/$" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dict_str(d, indent):
    pad = "\t" * indent
    out = "{\n"
    for k, v in d.items():
        out += f"{pad}\t{quote(k)} = {render(v, indent + 1)};\n"
    return out + pad + "}"


def render(v, indent):
    if isinstance(v, dict):
        return dict_str(v, indent)
    if isinstance(v, list):
        return "(\n" + "".join("\t" * (indent + 1) + render(x, indent + 1) + ",\n" for x in v) + "\t" * indent + ")"
    return quote(v)


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TARGETED_DEVICE_FAMILY": "1",
}


def project(name, bundle_id, app_dir, shared_dirs, test_dir, team=""):
    P = lambda *p: oid(name, *p)  # noqa: E731
    ids = {k: P(k) for k in ("project", "main", "products", "app", "test", "app_product", "test_product",
                              "app_src", "app_fw", "app_res", "test_src", "test_fw", "test_res",
                              "proxy", "dep", "proj_cfgs", "app_cfgs", "test_cfgs")}
    groups = {app_dir: P("group", app_dir), test_dir: P("group", test_dir)}
    for d in shared_dirs:
        groups[d] = P("group", d)
    objects = {}
    for path, gid in groups.items():
        objects[gid] = {"isa": "PBXFileSystemSynchronizedRootGroup", "path": path, "sourceTree": "<group>"}
    objects[ids["app_product"]] = {"isa": "PBXFileReference", "explicitFileType": "wrapper.application",
                                   "includeInIndex": 0, "path": f"{name}.app", "sourceTree": "BUILT_PRODUCTS_DIR"}
    objects[ids["test_product"]] = {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle",
                                    "includeInIndex": 0, "path": f"{name}UITests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"}
    objects[ids["main"]] = {"isa": "PBXGroup", "children": list(groups.values()) + [ids["products"]], "sourceTree": "<group>"}
    objects[ids["products"]] = {"isa": "PBXGroup", "children": [ids["app_product"], ids["test_product"]],
                                "name": "Products", "sourceTree": "<group>"}
    for phase, isa in (("src", "PBXSourcesBuildPhase"), ("fw", "PBXFrameworksBuildPhase"), ("res", "PBXResourcesBuildPhase")):
        for t in ("app", "test"):
            objects[ids[f"{t}_{phase}"]] = {"isa": isa, "buildActionMask": 2147483647, "files": [],
                                            "runOnlyForDeploymentPostprocessing": 0}
    objects[ids["proxy"]] = {"isa": "PBXContainerItemProxy", "containerPortal": ids["project"], "proxyType": 1,
                             "remoteGlobalIDString": ids["app"], "remoteInfo": name}
    objects[ids["dep"]] = {"isa": "PBXTargetDependency", "target": ids["app"], "targetProxy": ids["proxy"]}
    objects[ids["app"]] = {
        "isa": "PBXNativeTarget", "buildConfigurationList": ids["app_cfgs"],
        "buildPhases": [ids["app_src"], ids["app_fw"], ids["app_res"]], "buildRules": [], "dependencies": [],
        "fileSystemSynchronizedGroups": [groups[app_dir]] + [groups[d] for d in shared_dirs],
        "name": name, "productName": name, "productReference": ids["app_product"],
        "productType": "com.apple.product-type.application"}
    objects[ids["test"]] = {
        "isa": "PBXNativeTarget", "buildConfigurationList": ids["test_cfgs"],
        "buildPhases": [ids["test_src"], ids["test_fw"], ids["test_res"]], "buildRules": [], "dependencies": [ids["dep"]],
        "fileSystemSynchronizedGroups": [groups[test_dir]],
        "name": f"{name}UITests", "productName": f"{name}UITests", "productReference": ids["test_product"],
        "productType": "com.apple.product-type.bundle.ui-testing"}
    objects[ids["project"]] = {
        "isa": "PBXProject",
        "attributes": {"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 2710, "LastUpgradeCheck": 2710,
                       "TargetAttributes": {ids["app"]: {"CreatedOnToolsVersion": "27.1"},
                                            ids["test"]: {"CreatedOnToolsVersion": "27.1", "TestTargetID": ids["app"]}}},
        "buildConfigurationList": ids["proj_cfgs"], "developmentRegion": "en", "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base"], "mainGroup": ids["main"], "minimizedProjectReferenceProxies": 1,
        "preferredProjectObjectVersion": 77, "productRefGroup": ids["products"], "projectDirPath": "", "projectRoot": "",
        "targets": [ids["app"], ids["test"]]}

    signing = {"CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": team}
    target_settings = {
        "app": {**signing, "PRODUCT_BUNDLE_IDENTIFIER": bundle_id, "PRODUCT_NAME": "$(TARGET_NAME)",
                "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_CFBundleDisplayName": name, "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
                "ENABLE_PREVIEWS": "NO", "SWIFT_EMIT_LOC_STRINGS": "NO"},
        "test": {**signing, "PRODUCT_BUNDLE_IDENTIFIER": bundle_id + ".uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
                 "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": name, "SWIFT_EMIT_LOC_STRINGS": "NO",
                 "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1"},
    }
    for scope, list_id in (("proj", ids["proj_cfgs"]), ("app", ids["app_cfgs"]), ("test", ids["test_cfgs"])):
        cfg_ids = []
        for cfg in ("Debug", "Release"):
            cid = P("cfg", scope, cfg)
            cfg_ids.append(cid)
            if scope == "proj":
                settings = dict(COMMON)
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if cfg == "Debug" else "dwarf-with-dsym",
                                 "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if cfg == "Debug" else "-O",
                                 "ONLY_ACTIVE_ARCH": "YES" if cfg == "Debug" else "NO",
                                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if cfg == "Debug" else "",
                                 "ENABLE_TESTABILITY": "YES" if cfg == "Debug" else "NO"})
            else:
                settings = target_settings[scope]
            objects[cid] = {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": cfg}
        objects[list_id] = {"isa": "XCConfigurationList", "buildConfigurations": cfg_ids,
                            "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"}

    body = "// !$*UTF8*$!\n" + render({"archiveVersion": 1, "classes": {}, "objectVersion": 77,
                                         "objects": dict(sorted(objects.items())), "rootObject": ids["project"]}, 0) + "\n"
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2710" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app']}" BuildableName = "{name}.app" BlueprintName = "{name}" ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['test']}" BuildableName = "{name}UITests.xctest" BlueprintName = "{name}UITests" ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app']}" BuildableName = "{name}.app" BlueprintName = "{name}" ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    return body, scheme


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--name", required=True)
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--app-dir", required=True, help="app sources folder, relative to --out")
    ap.add_argument("--shared-dir", action="append", default=[], help="extra app source folder(s), relative to --out")
    ap.add_argument("--test-dir", required=True, help="UI-testing target folder, relative to --out")
    ap.add_argument("--team", default="", help="DEVELOPMENT_TEAM (empty: simulator / sign-to-run-locally only)")
    ap.add_argument("--out", required=True, help="directory that will contain <name>.xcodeproj")
    args = ap.parse_args(argv)
    body, scheme = project(args.name, args.bundle_id, args.app_dir, args.shared_dir, args.test_dir, args.team)
    proj = pathlib.Path(args.out) / f"{args.name}.xcodeproj"
    (proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text(body, encoding="utf-8")
    (proj / "xcshareddata" / "xcschemes" / f"{args.name}.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"wrote {proj}")


if __name__ == "__main__":
    main()
