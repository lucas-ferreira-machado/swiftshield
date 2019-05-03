import Foundation

class MixedSwiftShield: AutomaticSwiftShield {
    let tag: String
    var subXProjects : [XProject] = []
    
    init(basePath: String, projectToBuild: String, schemeToBuild: String, modulesToIgnore: Set<String>, dryRun: Bool, tag: String) {
        self.tag = tag
        let autoProtectedClassNameSize = 32
        super.init(basePath: basePath, projectToBuild: projectToBuild, schemeToBuild: schemeToBuild, modulesToIgnore: modulesToIgnore, protectedClassNameSize: autoProtectedClassNameSize, dryRun: dryRun)
        
    }

    override func protect() -> ObfuscationData {
        
        SourceKit.start()
        defer {
            SourceKit.stop()
        }
        guard isWorkspace || projectToBuild.hasSuffix(".xcodeproj") else {
            Logger.log(.projectError)
            exit(error: true)
        }
       
        if isWorkspace {
            
            let xcworkspacedataUrl = URL(fileURLWithPath:projectToBuild+"/contents.xcworkspacedata")
            let projectToBuildUrl = URL(fileURLWithPath: projectToBuild)
            let projectName = projectToBuildUrl.lastPathComponent.replacingOccurrences(of: ".xcworkspace", with: ".xcodeproj")
            if let data = try? Data(contentsOf: xcworkspacedataUrl ) {
                guard let xcworkspaceDataXML = try? AEXMLDocument(xml: data, options: AEXMLOptions()) else {
                    exit()
                }
                let fileRefLocations = getFileRefLocations(xcworkspaceDataXML: xcworkspaceDataXML)
                for location in fileRefLocations {
                    if location.hasSuffix(".xcodeproj") {
                        if !location.hasSuffix("Pods.xcodeproj") && !location.hasSuffix(projectName) {
                            addNewSubXProject(location: location)
                        }
                    }
                }
            }
            
        }
        
        let projectBuilder = XcodeProjectBuilder(projectToBuild: projectToBuild, schemeToBuild: schemeToBuild, modulesToIgnore: modulesToIgnore)
        let modules = projectBuilder.getModulesAndCompilerArguments()
        let obfuscationData = AutomaticObfuscationData(modules: modules)
        index(obfuscationData: obfuscationData)
        findReferencesInIndexed(obfuscationData: obfuscationData)
        if obfuscationData.referencesDict.isEmpty {
            Logger.log(.foundNothingError)
            exit(error: true)
        }
        obfuscateNSPrincipalClassPlists(obfuscationData: obfuscationData)
        if dryRun == false {
            overwriteFiles(obfuscationData: obfuscationData)
        }
        
        var hasObjcSubProject = false
        for xproj in subXProjects {
            if !xproj.isSwift  {
                hasObjcSubProject = true
                break
            }
        }
        
        if hasObjcSubProject {
            
            let manualProtectedClassNameSize = 30
            for xproj in subXProjects {
                if xproj.isSwift == false {
                    let manualProtector = MixedManualSwiftShield(basePath: xproj.projectBasePath, tag: self.tag, protectedClassNameSize: manualProtectedClassNameSize, dryRun: self.dryRun, modulesToIgnore:self.modulesToIgnore, obfuscationData: obfuscationData)
                    let manualObfuscationData = manualProtector.protect()
                    mergeObfuscationData(obfuscationData, with: manualObfuscationData)
                }
            }
            
            let manualProtector = MixedManualSwiftShield(basePath: basePath, tag: self.tag, protectedClassNameSize: manualProtectedClassNameSize, dryRun: self.dryRun, modulesToIgnore:self.modulesToIgnore, obfuscationData: obfuscationData)
            mergeObfuscationData(obfuscationData, with: manualProtector.protect())

            if dryRun == false {
                writeToFile(data: obfuscationData);
            }
        }
        
        return obfuscationData
    }
    
    func addNewSubXProject(location: String) {
        let basePathUrl = URL(fileURLWithPath: basePath)
        let relativeURL = URL(fileURLWithPath: location, relativeTo: basePathUrl)
        print(relativeURL.path)
        if FileManager.default.fileExists(atPath: relativeURL.path) {
            subXProjects.append(XProject(projectFilePath: relativeURL.path))
        }
    }
    
    private func getFileRefLocations(xcworkspaceDataXML: AEXMLElement) -> [String] {
        let children = xcworkspaceDataXML.children
        var array : [String] = []
        for i in 0..<children.count {
            if children[i].name == "FileRef" {
                if let location = children[i].attributes["location"] {
                    print(location)
                    array.append(location.replacingOccurrences(of: "group:", with: ""))
                }
            } else {
                array.insert(contentsOf: getFileRefLocations(xcworkspaceDataXML:children[i]), at: 0)
            }
        }
        
        return array
    }
    
    override func writeToFile(data: ObfuscationData) {
        var path = "\(schemeToBuild)"
        for plist in (data as? AutomaticObfuscationData)?.mainModule?.plists ?? [] {
            guard let version = getPlistVersionAndNumber(plist) else {
                continue
            }
            path += " \(version.0) \(version.1)"
            break
        }
        writeToFile(data: data, path: "Mixed", info: "Mixed Mode")
    }

}

final class MixedManualSwiftShield: ManualSwiftShield {
    
    let modulesToIgnore: Set<String>
    let obfuscationData: ObfuscationData
    
    init(basePath: String, tag: String, protectedClassNameSize: Int, dryRun: Bool, modulesToIgnore: Set<String>, obfuscationData: ObfuscationData) {
        self.modulesToIgnore = modulesToIgnore
        self.obfuscationData = obfuscationData
        super.init(basePath: basePath, tag: tag, protectedClassNameSize: protectedClassNameSize, dryRun: dryRun)
    }
    
    override func protect() -> ObfuscationData {
        Logger.log(.tag(tag: tag))
        let files = getSourceFiles()
        Logger.log(.scanningDeclarations)
        let filteredFiles = files.filter {
            for module in self.modulesToIgnore {
                if $0.path.contains(module) {
                    return false
                }
            }
            return true
        }
        let obfsData = ObfuscationData(files: filteredFiles, storyboards: getStoryboardsAndXibs())
        mergeObfuscationData(obfsData, with: self.obfuscationData)
        obfsData.files.forEach { protect(file: $0, obfsData: obfsData) }
        obfuscationData.files.forEach { protect(file: $0, obfsData: obfsData) }
        return obfsData
    }
}

final class XProject {
    
    let projectBasePath : String
    let projectFilePath : String
    var isSwift : Bool
    
    init(projectFilePath: String) {
        self.projectFilePath = projectFilePath
        self.isSwift = false
        self.projectBasePath  = URL(fileURLWithPath: projectFilePath).deletingLastPathComponent().path
        let pbxproj = projectFilePath+"/project.pbxproj"
        if FileManager.default.fileExists(atPath: pbxproj) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: pbxproj)) {
                if let contentsOf = String(data: data, encoding: .utf8) {
                    self.isSwift = contentsOf.contains("sourcecode.swift")
                }
            }
        }
    }
    
}

func mergeObfuscationData( _ one: ObfuscationData, with: ObfuscationData) {
    for (k, v) in with.obfuscationDict {
        // If a key is already present it will be overritten
        one.obfuscationDict[k] = v
    }
}
