#!/usr/bin/env python3
"""Deterministic PBX project generator; no third-party project generator needed."""
import pathlib, hashlib
root=pathlib.Path(__file__).resolve().parents[1]
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def obj(k,s): objects[uid(k)]=s; return uid(k)
def arr(v): return '('+','.join(v)+',)'
def quote(s): return '"'+s.replace('"','\\"')+'"'
sources=[];children=[]
for p in sorted(list((root/'App').glob('*.swift'))+list((root/'Core').glob('*.swift'))):
    rel=str(p.relative_to(root))
    ref=obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = "<group>";')
    sources.append(obj('build'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
    children.append(ref)
models=obj('models','isa = PBXFileReference; lastKnownFileType = folder; path = Models; sourceTree = "<group>";')
children.append(models)
resource=obj('modelbuild',f'isa = PBXBuildFile; fileRef = {models};')
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Asobi.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
children.append(products)
group=obj('group',f'isa = PBXGroup; children = {arr(children)}; sourceTree = "<group>";')
packages=[];deps=[];frameworks=[]
for name,url,version,prods in [('mlx-swift-lm','https://github.com/ml-explore/mlx-swift-lm','3.32.3',['MLXLLM','MLXLMCommon']),('mlx-swift','https://github.com/ml-explore/mlx-swift','0.32.3',['MLX']),('swift-transformers','https://github.com/huggingface/swift-transformers','1.3.4',['Tokenizers'])]:
    pkg=obj(name,f'isa = XCRemoteSwiftPackageReference; repositoryURL = {quote(url)}; requirement = {{kind = exactVersion; version = {version};}};')
    packages.append(pkg)
    for prod in prods:
        dep=obj('dep'+prod,f'isa = XCSwiftPackageProductDependency; package = {pkg}; productName = {prod};');deps.append(dep)
        frameworks.append(obj('link'+prod,f'isa = PBXBuildFile; productRef = {dep};'))
sourcephase=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;')
resources=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({resource},); runOnlyForDeploymentPostprocessing = 0;')
frameworkphase=obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr(frameworks)}; runOnlyForDeploymentPostprocessing = 0;')
configs=[]
for mode in ['Debug','Release']:
    settings={'SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','PRODUCT_BUNDLE_IDENTIFIER':'com.aokijp.Asobi','PRODUCT_NAME':'$(TARGET_NAME)','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'asobi','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','SWIFT_STRICT_CONCURRENCY':'complete','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','CLANG_ENABLE_MODULES':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'}
    configs.append(obj(mode,'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {'+''.join(f'{k} = {quote(v)};' for k,v in settings.items())+'};'))
configlist=obj('configlist',f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pc=[]
for mode in ['Debug','Release']:
    pc.append(obj('project'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{}};'))
pcl=obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = {arr(pc)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = ({sourcephase},{frameworkphase},{resources},); buildRules = (); dependencies = (); name = Asobi; packageProductDependencies = {arr(deps)}; productName = Asobi; productReference = {product}; productType = "com.apple.product-type.application";')
project=obj('project',f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600;}}; buildConfigurationList = {pcl}; compatibilityVersion = "Xcode 15.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base,); mainGroup = {group}; packageReferences = {arr(packages)}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(root/'Asobi.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+''.join(k+' = {'+v+'};\n' for k,v in objects.items())+'}; rootObject = '+project+'; }\n')
(root/'Asobi.xcodeproj/xcshareddata/xcschemes/Asobi.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Asobi.app" BlueprintName="Asobi" ReferencedContainer="container:Asobi.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Asobi.app" BlueprintName="Asobi" ReferencedContainer="container:Asobi.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Xcode project generated')
