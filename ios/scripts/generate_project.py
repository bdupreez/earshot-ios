#!/usr/bin/env python3
"""Generate the dependency-free Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib
import argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output-project", type=Path, help="Generate a clean project elsewhere without touching local signing edits")
args = parser.parse_args()
PROJECT = args.output_project or ROOT / "Earshot.xcodeproj"
if args.output_project is None and PROJECT.joinpath("project.pbxproj").exists():
    existing = PROJECT.joinpath("project.pbxproj").read_text()
    if "DEVELOPMENT_TEAM" in existing or "PROVISIONING_PROFILE" in existing:
        parser.error("Local signing settings detected. Use --output-project and reconcile file membership without replacing local build settings.")
PROJECT.mkdir(parents=True, exist_ok=True)
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(object_key, isa, **kw):
    key = ident(object_key); objects[key] = dict(isa=isa, **kw); return key
def ref(name): return ident(name)
def quote(value): return json.dumps(str(value))
def emit(value):
    if isinstance(value, dict): return "{ " + " ".join(f"{k} = {emit(v)};" for k,v in value.items()) + " }"
    if isinstance(value, list): return "( " + ", ".join(emit(x) for x in value) + ", )" if value else "()"
    return quote(value)

shared_files = sorted((ROOT / "Shared").glob("*.swift"))
app_files = sorted((ROOT / "Earshot").rglob("*.swift")) + shared_files
test_files = sorted((ROOT / "EarshotTests").glob("*.swift"))
ui_files = sorted((ROOT / "EarshotUITests").glob("*.swift"))
widget_files = sorted((ROOT / "EarshotWidget").glob("*.swift")) + shared_files + [ROOT / "Earshot/App/EarshotIntents.swift"]
groups = []
def files_group(name, paths):
    children=[]
    for path in paths:
        key=obj("file:"+str(path.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift" if path.suffix==".swift" else "text", path=str(path.relative_to(ROOT)), sourceTree="SOURCE_ROOT")
        children.append(key)
    return obj("group:"+name,"PBXGroup",children=children,name=name,sourceTree="<group>")
for name,paths in [("Earshot",app_files),("EarshotTests",test_files),("EarshotUITests",ui_files),("EarshotWidget",widget_files)]: groups.append(files_group(name, [p for p in paths if name != "EarshotWidget" or p not in app_files]))
resource_paths = [ROOT/"Earshot/Resources/Assets.xcassets", ROOT/"Earshot/Resources/LICENSE.txt", ROOT/"Earshot/Resources/THIRD_PARTY_NOTICES.txt", ROOT/"Earshot/Resources/Fonts"]
resources=[]
for p in resource_paths:
    resources.append(obj("file:"+str(p.relative_to(ROOT)),"PBXFileReference",lastKnownFileType="folder.assetcatalog" if p.suffix==".xcassets" else "folder" if p.is_dir() else "text",path=str(p.relative_to(ROOT)),sourceTree="SOURCE_ROOT"))
groups.append(obj("group:resources","PBXGroup",children=resources,name="Resources",sourceTree="<group>"))
products=[]; targets=[]
for name,paths,product,kind in [("Earshot",app_files,"Earshot.app","application"),("EarshotTests",test_files,"EarshotTests.xctest","bundle.unit-test"),("EarshotUITests",ui_files,"EarshotUITests.xctest","bundle.ui-testing"),("EarshotWidget",widget_files,"EarshotWidget.appex","app-extension")]:
    prod=obj("product:"+name,"PBXFileReference",explicitFileType="wrapper.application" if kind=="application" else "wrapper.app-extension" if kind=="app-extension" else "wrapper.cfbundle",includeInIndex="0",path=product,sourceTree="BUILT_PRODUCTS_DIR"); products.append(prod)
    builds=[obj("build:"+name+":"+str(p.relative_to(ROOT)),"PBXBuildFile",fileRef=ref("file:"+str(p.relative_to(ROOT)))) for p in paths]
    phases=[obj("sources:"+name,"PBXSourcesBuildPhase",buildActionMask="2147483647",files=builds,runOnlyForDeploymentPostprocessing="0"),obj("frameworks:"+name,"PBXFrameworksBuildPhase",buildActionMask="2147483647",files=[],runOnlyForDeploymentPostprocessing="0")]
    resource_builds=[obj("resource:"+str(p),"PBXBuildFile",fileRef=r) for p,r in zip(resource_paths,resources)] if name=="Earshot" else []
    phases.append(obj("resources:"+name,"PBXResourcesBuildPhase",buildActionMask="2147483647",files=resource_builds,runOnlyForDeploymentPostprocessing="0"))
    if name=="Earshot":
        embed=obj("embed:widget","PBXBuildFile",fileRef=ref("product:EarshotWidget"),settings={"ATTRIBUTES":["RemoveHeadersOnCopy"]})
        phases.append(obj("embed:extensions","PBXCopyFilesBuildPhase",buildActionMask="2147483647",dstPath="",dstSubfolderSpec="13",files=[embed],name="Embed App Extensions",runOnlyForDeploymentPostprocessing="0"))
    dependencies=[]
    depname="EarshotWidget" if name=="Earshot" else "Earshot" if "Tests" in name else None
    if depname:
        proxy=obj("proxy:"+name,"PBXContainerItemProxy",containerPortal=ref("project"),proxyType="1",remoteGlobalIDString=ref("target:"+depname),remoteInfo=depname)
        dependencies.append(obj("dependency:"+name,"PBXTargetDependency",target=ref("target:"+depname),targetProxy=proxy))
    configs=[]
    for conf in ["Debug","Release"]:
        settings={"PRODUCT_NAME":"$(TARGET_NAME)","PRODUCT_BUNDLE_IDENTIFIER":"dev.earshot.ios" + ("" if name=="Earshot" else ".widget" if name=="EarshotWidget" else "."+name),"SWIFT_VERSION":"5.0","IPHONEOS_DEPLOYMENT_TARGET":"17.0","TARGETED_DEVICE_FAMILY":"1,2","GENERATE_INFOPLIST_FILE":"YES","CODE_SIGN_STYLE":"Automatic","MARKETING_VERSION":"0.2.0","CURRENT_PROJECT_VERSION":"2","SWIFT_EMIT_LOC_STRINGS":"YES","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","SUPPORTS_MACCATALYST":"NO"}
        if name=="Earshot": settings.update({"INFOPLIST_FILE":"Earshot/Resources/Info.plist","GENERATE_INFOPLIST_FILE":"NO","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon","CODE_SIGN_ENTITLEMENTS":"Earshot/Resources/Earshot.entitlements"})
        if name=="EarshotWidget": settings.update({"INFOPLIST_FILE":"EarshotWidget/Info.plist","GENERATE_INFOPLIST_FILE":"NO","APPLICATION_EXTENSION_API_ONLY":"YES","SKIP_INSTALL":"YES","CODE_SIGN_ENTITLEMENTS":"EarshotWidget/EarshotWidget.entitlements"})
        if name=="EarshotTests": settings.update({"TEST_HOST":"$(BUILT_PRODUCTS_DIR)/Earshot.app/Earshot","BUNDLE_LOADER":"$(TEST_HOST)","SWIFT_EMIT_LOC_STRINGS":"NO"})
        if name=="EarshotUITests": settings.update({"TEST_TARGET_NAME":"Earshot","SWIFT_EMIT_LOC_STRINGS":"NO"})
        configs.append(obj("config:"+name+conf,"XCBuildConfiguration",buildSettings=settings,name=conf))
    configlist=obj("configs:"+name,"XCConfigurationList",buildConfigurations=configs,defaultConfigurationIsVisible="0",defaultConfigurationName="Release")
    targets.append(obj("target:"+name,"PBXNativeTarget",buildConfigurationList=configlist,buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=prod,productType="com.apple.product-type."+kind))
groups.append(obj("products","PBXGroup",children=products,name="Products",sourceTree="<group>"))
main=obj("main","PBXGroup",children=groups,sourceTree="<group>")
configs=[]
for conf in ["Debug","Release"]:
    settings={"SDKROOT":"iphoneos","CLANG_ENABLE_MODULES":"YES","CLANG_ENABLE_OBJC_ARC":"YES","ENABLE_USER_SCRIPT_SANDBOXING":"YES","SWIFT_OPTIMIZATION_LEVEL":"-Onone" if conf=="Debug" else "-O","DEBUG_INFORMATION_FORMAT":"dwarf" if conf=="Debug" else "dwarf-with-dsym","GCC_PREPROCESSOR_DEFINITIONS":["$(inherited)","DEBUG=1"] if conf=="Debug" else ["$(inherited)"],"ENABLE_TESTABILITY":"YES" if conf=="Debug" else "NO","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG" if conf=="Debug" else "","ONLY_ACTIVE_ARCH":"YES" if conf=="Debug" else "NO"}
    configs.append(obj("projectconfig:"+conf,"XCBuildConfiguration",buildSettings=settings,name=conf))
configlist=obj("projectconfigs","XCConfigurationList",buildConfigurations=configs,defaultConfigurationIsVisible="0",defaultConfigurationName="Release")
project=obj("project","PBXProject",attributes={"BuildIndependentTargetsInParallel":"YES","LastUpgradeCheck":"2640","TargetAttributes":{ref("target:EarshotTests"):{"TestTargetID":ref("target:Earshot")},ref("target:EarshotUITests"):{"TestTargetID":ref("target:Earshot")}}},buildConfigurationList=configlist,compatibilityVersion="Xcode 14.0",developmentRegion="en",hasScannedForEncodings="0",knownRegions=["en","Base"],mainGroup=main,productRefGroup=ref("products"),projectDirPath="",projectRoot="",targets=targets)
PROJECT.joinpath("project.pbxproj").write_text("// !$*UTF8*$!\n"+emit({"archiveVersion":"1","classes":{},"objectVersion":"56","objects":objects,"rootObject":project})+"\n")
scheme_dir=PROJECT/"xcshareddata/xcschemes"; scheme_dir.mkdir(parents=True,exist_ok=True)
def buildable(name,product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target:"+name)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Earshot.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable("Earshot","Earshot.app")}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable("EarshotTests","EarshotTests.xctest")}</TestableReference><TestableReference skipped="NO">{buildable("EarshotUITests","EarshotUITests.xctest")}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("Earshot","Earshot.app")}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("Earshot","Earshot.app")}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(scheme_dir/"Earshot.xcscheme").write_text(scheme)
print(f"Generated {PROJECT}: {len(app_files)} app, {len(test_files)} unit-test, {len(ui_files)} UI-test, {len(widget_files)} widget files")
