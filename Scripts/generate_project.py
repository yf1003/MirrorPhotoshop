#!/usr/bin/env python3
"""Generate the dependency-free two-target Xcode project using only Python stdlib."""
from pathlib import Path
import hashlib
import plistlib
import json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PSDMirror.xcodeproj"
PROJECT.mkdir(exist_ok=True)

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = []
def obj(name, body):
    objects.append(f"\t\t{uid(name)} = {{ {body} }};")

def listing(values):
    return "(" + ", ".join(values) + ")"

shared = [str(path.relative_to(ROOT)) for path in sorted((ROOT / "Shared").glob("*.swift"))]
targets = {
    "PSDMirror": {"dir": "iOS", "sdk": "iphoneos", "bundle": "$(PSDMIRROR_IOS_BUNDLE_ID)", "platform": "iOS"},
    "PSDMirrorMac": {"dir": "Mac", "sdk": "macosx", "bundle": "$(PSDMIRROR_MAC_BUNDLE_ID)", "platform": "Mac"},
}
sources = shared + [str(path.relative_to(ROOT)) for directory in ("iOS", "Mac") for path in sorted((ROOT / directory).glob("*.swift"))]
for source in sources:
    obj(source, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(source)}; sourceTree = "<group>";')
obj("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Shared/Assets.xcassets"; sourceTree = "<group>";')
obj("signing", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "Config/Signing.xcconfig"; sourceTree = "<group>";')

for name, target in targets.items():
    product = name + ".app"
    obj(product, f'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {quote(product)}; sourceTree = BUILT_PRODUCTS_DIR;')
    buildfiles = []
    for source in [s for s in sources if s.startswith(target["dir"] + "/") or s in shared]:
        buildname = name + ":" + source
        obj(buildname, f"isa = PBXBuildFile; fileRef = {uid(source)};")
        buildfiles.append(uid(buildname))
    obj(name + ":sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing(buildfiles)}; runOnlyForDeploymentPostprocessing = 0;")
    obj(name + ":frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    obj(name + ":assets", f"isa = PBXBuildFile; fileRef = {uid('assets')};")
    obj(name + ":resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid(name + ':assets')}); runOnlyForDeploymentPostprocessing = 0;")
    for config in ("Debug", "Release"):
        settings = {
            "PRODUCT_NAME": name, "PRODUCT_BUNDLE_IDENTIFIER": target["bundle"],
            "SWIFT_VERSION": "5.0", "SDKROOT": target["sdk"],
            "CODE_SIGN_STYLE": "Automatic",
            "INFOPLIST_FILE": target["dir"] + "/Info.plist",
            "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "CLANG_ENABLE_MODULES": "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }
        if target["platform"] == "iOS":
            settings.update({"IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO"})
        else:
            settings.update({"MACOSX_DEPLOYMENT_TARGET": "14.0", "ENABLE_APP_SANDBOX": "NO", "CODE_SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "", "COMBINE_HIDPI_IMAGES": "YES"})
        pairs = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
        obj(name + ":" + config, f"isa = XCBuildConfiguration; baseConfigurationReference = {uid('signing')}; buildSettings = {{ {pairs} }}; name = {config};")
    obj(name + ":configs", f"isa = XCConfigurationList; buildConfigurations = {listing([uid(name + ':Debug'), uid(name + ':Release')])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    phases = [uid(name + ":" + phase) for phase in ("sources", "frameworks", "resources")]
    obj(name, f"isa = PBXNativeTarget; buildConfigurationList = {uid(name + ':configs')}; buildPhases = {listing(phases)}; buildRules = (); dependencies = (); name = {name}; productName = {name}; productReference = {uid(product)}; productType = \"com.apple.product-type.application\";")

for config in ("Debug", "Release"):
    obj("project:" + config, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; DEBUG_INFORMATION_FORMAT = {quote("dwarf" if config == "Debug" else "dwarf-with-dsym")}; }}; name = {config};')
obj("project:configs", f"isa = XCConfigurationList; buildConfigurations = {listing([uid('project:Debug'), uid('project:Release')])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
obj("products", f'isa = PBXGroup; children = {listing([uid(n + ".app") for n in targets])}; name = Products; sourceTree = "<group>";')
obj("main", f'isa = PBXGroup; children = {listing([uid(s) for s in sources] + [uid("assets"), uid("signing"), uid("products")])}; sourceTree = "<group>";')
obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2630; }}; buildConfigurationList = {uid("project:configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans"); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {listing([uid(n) for n in targets])};')
text = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n"
(PROJECT / "project.pbxproj").write_text(text)
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
for name in targets:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name)}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:PSDMirror.xcodeproj"/>'
    (scheme_dir / (name + ".xcscheme")).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

base = {"CFBundleDevelopmentRegion": "zh_CN", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "PSD Mirror", "CFBundleDisplayName": "PSD Mirror", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "NSLocalNetworkUsageDescription": "连接你选择的 Mac，在 iPhone 上全屏预览 PSD 设计稿。", "NSBonjourServices": ["_psdmirror._tcp"], "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True}}
ios = dict(base, LSRequiresIPhoneOS=True, UILaunchScreen={}, UIRequiresFullScreen=True,
           NSCameraUsageDescription="扫描 Mac 上的 PSD Mirror 二维码，自动连接并预览设计稿。",
           UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
           UIViewControllerBasedStatusBarAppearance=True, UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes": False})
mac = dict(base, LSMinimumSystemVersion="14.0", NSPrincipalClass="NSApplication", NSHighResolutionCapable=True)
for folder, value in (("iOS", ios), ("Mac", mac)):
    with (ROOT / folder / "Info.plist").open("wb") as handle:
        plistlib.dump(value, handle, sort_keys=False)
print(PROJECT)
