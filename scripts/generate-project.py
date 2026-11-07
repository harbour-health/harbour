#!/usr/bin/env python3
"""Generate a small, deterministic Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(name, body):
    key = ident(name)
    objects[key] = '{ ' + body + ' }'
    return key

def refs(items):
    return '(' + ', '.join(items) + ',)'

source_refs, builds = [], []
for path in sorted((root / 'Harbour').glob('*.swift')):
    ref = add(path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
    source_refs.append(ref)
    builds.append(add('build-' + path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
asset = add('Assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
source_refs.append(asset)
asset_build = add('AssetsBuild', f'isa = PBXBuildFile; fileRef = {asset};')
resource_builds = [asset_build]
privacy = add('PrivacyManifest', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>";')
source_refs.append(privacy)
resource_builds.append(add('PrivacyManifestBuild', f'isa = PBXBuildFile; fileRef = {privacy};'))
languages = sorted(path.name.removesuffix('.lproj') for path in (root / 'Harbour').glob('*.lproj'))
localized_files = sorted({path.name for folder in (root / 'Harbour').glob('*.lproj') for path in folder.glob('*.strings*')})
for filename in localized_files:
    children = []
    for language in languages:
        if not (root / 'Harbour' / f'{language}.lproj' / filename).exists():
            continue
        filetype = 'text.plist.stringsdict' if filename.endswith('.stringsdict') else 'text.plist.strings'
        children.append(add(f'{language}-{filename}', f'isa = PBXFileReference; lastKnownFileType = {filetype}; name = "{language}"; path = "{language}.lproj/{filename}"; sourceTree = "<group>";'))
    variant = add(f'Localized-{filename}', f'isa = PBXVariantGroup; children = {refs(children)}; name = "{filename}"; sourceTree = "<group>";')
    source_refs.append(variant)
    resource_builds.append(add(f'LocalizedBuild-{filename}', f'isa = PBXBuildFile; fileRef = {variant};'))
for filename, filetype in [('Info.plist', 'text.plist.xml'), ('Harbour.entitlements', 'text.plist.entitlements')]:
    source_refs.append(add(filename, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {filename}; sourceTree = "<group>";'))
app = add('AppProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Harbour.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('TestProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = HarbourUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
test_refs, test_builds = [], []
for path in sorted((root / 'HarbourUITests').glob('*.swift')):
    ref = add('UITestSource-' + path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
    test_refs.append(ref)
    test_builds.append(add('UITestBuild-' + path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
source_group = add('Sources', f'isa = PBXGroup; children = {refs(source_refs)}; path = Harbour; sourceTree = "<group>";')
test_group = add('TestGroup', f'isa = PBXGroup; children = {refs(test_refs)}; path = HarbourUITests; sourceTree = "<group>";')
products = add('Products', f'isa = PBXGroup; children = {refs([app, test_product])}; name = Products; sourceTree = "<group>";')
group = add('RootGroup', f'isa = PBXGroup; children = {refs([source_group, test_group, products])}; sourceTree = "<group>";')
packages, product_deps, package_builds = [], [], []
for name in ['HarbourCore', 'HarbourRuntime', 'HarbourReports', 'HarbourSpeech']:
    package = add('Package-' + name, f'isa = XCLocalSwiftPackageReference; relativePath = {name};')
    packages.append(package)
    product = add('Product-' + name, f'isa = XCSwiftPackageProductDependency; package = {package}; productName = {name};')
    product_deps.append(product)
    package_builds.append(add('Link-' + name, f'isa = PBXBuildFile; productRef = {product};'))
sources = add('SourcePhase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('LinkPhase', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs(package_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources = add('ResourcePhase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
test_sources = add('TestSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(test_builds)}; runOnlyForDeploymentPostprocessing = 0;')
test_frameworks = add('TestFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

def config_list(name, settings):
    configurations = []
    for mode in ['Debug', 'Release']:
        flags = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; DEBUG_INFORMATION_FORMAT = dwarf; ONLY_ACTIVE_ARCH = YES;' if mode == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        configurations.append(add(name + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} {flags} }}; name = {mode};'))
    return add(name + 'Configurations', f'isa = XCConfigurationList; buildConfigurations = {refs(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = config_list('Project', 'IPHONEOS_DEPLOYMENT_TARGET = 18.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = complete;')
app_configs = config_list('App', 'PRODUCT_NAME = Harbour; PRODUCT_BUNDLE_IDENTIFIER = com.matteopolak.harbour; TARGETED_DEVICE_FAMILY = "1,2"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Harbour/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = Harbour; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = Harbour/Harbour.entitlements; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
test_configs = config_list('Test', 'PRODUCT_NAME = HarbourUITests; PRODUCT_BUNDLE_IDENTIFIER = com.matteopolak.harbour.uitests; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = Harbour; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic;')
target = add('AppTarget', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs([sources, frameworks, resources])}; buildRules = (); dependencies = (); name = Harbour; packageProductDependencies = {refs(product_deps)}; productName = Harbour; productReference = {app}; productType = "com.apple.product-type.application";')
region_refs = refs(['en', 'Base'] + ['"' + language + '"' for language in languages if language != 'en'])
project_id = ident('Project')
proxy = add('TestProxy', f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Harbour;')
dependency = add('TestDependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
test_target = add('TestTarget', f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs([test_sources, test_frameworks])}; buildRules = (); dependencies = {refs([dependency])}; name = HarbourUITests; productName = HarbourUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
unit_product = add('UnitProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = HarbourTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
unit_refs, unit_builds = [], []
for path in sorted((root / 'HarbourTests').glob('*.swift')):
    unit_ref = add('UnitSource-' + path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
    unit_refs.append(unit_ref)
    unit_builds.append(add('UnitBuild-' + path.name, f'isa = PBXBuildFile; fileRef = {unit_ref};'))
unit_group = add('UnitGroup', f'isa = PBXGroup; children = {refs(unit_refs)}; path = HarbourTests; sourceTree = "<group>";')
objects[group] = '{ isa = PBXGroup; children = ' + refs([source_group, test_group, unit_group, products]) + '; sourceTree = "<group>"; }'
objects[products] = '{ isa = PBXGroup; children = ' + refs([app, test_product, unit_product]) + '; name = Products; sourceTree = "<group>"; }'
unit_sources = add('UnitSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(unit_builds)}; runOnlyForDeploymentPostprocessing = 0;')
unit_frameworks = add('UnitFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
unit_configs = config_list('Unit', 'PRODUCT_NAME = HarbourTests; PRODUCT_BUNDLE_IDENTIFIER = com.matteopolak.harbour.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Harbour.app/Harbour"; BUNDLE_LOADER = "$(TEST_HOST)"; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic;')
unit_target = add('UnitTarget', f'isa = PBXNativeTarget; buildConfigurationList = {unit_configs}; buildPhases = {refs([unit_sources, unit_frameworks])}; buildRules = (); dependencies = {refs([dependency])}; name = HarbourTests; productName = HarbourTests; productReference = {unit_product}; productType = "com.apple.product-type.bundle.unit-test";')
# Shared ActivityKit schema and the embedded WidgetKit extension.
activity_ref = add('ActivityAttributes', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Shared/HarbourActivityAttributes.swift; sourceTree = SOURCE_ROOT;')
activity_build = add('ActivityAttributesAppBuild', f'isa = PBXBuildFile; fileRef = {activity_ref};')
objects[sources] = '{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ' + refs(builds + [activity_build]) + '; runOnlyForDeploymentPostprocessing = 0; }'
widget_ref = add('ActivityWidgetSource', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HarbourActivity.swift; sourceTree = "<group>";')
widget_build = add('ActivityWidgetBuild', f'isa = PBXBuildFile; fileRef = {widget_ref};')
activity_widget_build = add('ActivityAttributesWidgetBuild', f'isa = PBXBuildFile; fileRef = {activity_ref};')
widget_group = add('ActivityWidgetGroup', f'isa = PBXGroup; children = {refs([widget_ref])}; path = HarbourActivity; sourceTree = "<group>";')
widget_product = add('ActivityWidgetProduct', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = HarbourActivity.appex; sourceTree = BUILT_PRODUCTS_DIR;')
widget_sources = add('ActivityWidgetSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs([widget_build, activity_widget_build])}; runOnlyForDeploymentPostprocessing = 0;')
widget_frameworks = add('ActivityWidgetFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
widget_configs = config_list('ActivityWidget', 'PRODUCT_NAME = HarbourActivity; PRODUCT_BUNDLE_IDENTIFIER = com.matteopolak.harbour.activity; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = HarbourActivity/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = Harbour; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic; APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
widget_target = add('ActivityWidgetTarget', f'isa = PBXNativeTarget; buildConfigurationList = {widget_configs}; buildPhases = {refs([widget_sources, widget_frameworks])}; buildRules = (); dependencies = (); name = HarbourActivity; productName = HarbourActivity; productReference = {widget_product}; productType = "com.apple.product-type.app-extension";')
widget_proxy = add('ActivityWidgetProxy', f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {widget_target}; remoteInfo = HarbourActivity;')
widget_dependency = add('ActivityWidgetDependency', f'isa = PBXTargetDependency; target = {widget_target}; targetProxy = {widget_proxy};')
widget_embed = add('ActivityWidgetEmbedBuild', f'isa = PBXBuildFile; fileRef = {widget_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
embed_phase = add('ActivityWidgetEmbed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {refs([widget_embed])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
objects[target] = '{ isa = PBXNativeTarget; buildConfigurationList = ' + app_configs + '; buildPhases = ' + refs([sources, frameworks, resources, embed_phase]) + '; buildRules = (); dependencies = ' + refs([widget_dependency]) + '; name = Harbour; packageProductDependencies = ' + refs(product_deps) + '; productName = Harbour; productReference = ' + app + '; productType = "com.apple.product-type.application"; }'
objects[group] = '{ isa = PBXGroup; children = ' + refs([source_group, test_group, unit_group, widget_group, activity_ref, products]) + '; sourceTree = "<group>"; }'
objects[products] = '{ isa = PBXGroup; children = ' + refs([app, test_product, unit_product, widget_product]) + '; name = Products; sourceTree = "<group>"; }'
add('Project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 27.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; {test_target} = {{ TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = {region_refs}; mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = {refs(packages)}; targets = {refs([target, test_target, unit_target, widget_target])};')
project = root / 'Harbour.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {value};' for key, value in objects.items()) + f'\n}}; rootObject = {project_id}; }}\n')
schemes = project / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = lambda key, name: f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Harbour.xcodeproj"/>'
(schemes / 'Harbour.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(target, 'Harbour.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test_target, 'HarbourUITests.xctest')}</TestableReference><TestableReference skipped="NO">{reference(unit_target, 'HarbourTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target, 'Harbour.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target, 'Harbour.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
