//
//  ManualWorkspaceSwiftShield.swift
//  swiftshield
//
//  Created by lmachado on 06/07/20.
//  Copyright © 2020 Bruno Rocha. All rights reserved.
//

import Foundation

class ManualWorkspaceSwiftShield: Protector {
    let tag: String
    var subProjects : [SubProject] = []
    let workspaceFilePath: String
    let scheme: String
    let modulesToIgnore: Set<String>
    var isWorkspace: Bool {
        return workspaceFilePath.hasSuffix(".xcworkspace")
    }
    
    init(basePath: String, scheme: String, workspaceFilePath: String, modulesToIgnore: Set<String>, dryRun: Bool, tag: String) {
        self.tag = tag
        self.workspaceFilePath = workspaceFilePath
        self.scheme = scheme
        self.modulesToIgnore = modulesToIgnore
        super.init(basePath: basePath, dryRun: dryRun)
    }
    
    override func protect() -> ObfuscationData {
        
        guard isWorkspace else {
            Logger.log(.projectError)
            exit(error: true)
        }
        
        if isWorkspace {
            let xcworkspacedataUrl = URL(fileURLWithPath: "\(workspaceFilePath)/contents.xcworkspacedata")
            if let data = try? Data(contentsOf: xcworkspacedataUrl ) {
                guard let xcworkspaceDataXML = try? AEXMLDocument(xml: data, options: AEXMLOptions()) else {
                    exit()
                }
                let fileRefLocations = getFileRefLocations(xcworkspaceDataXML: xcworkspaceDataXML)
                for location in fileRefLocations {
                    if location.hasSuffix(".xcodeproj") {
                        if !location.hasSuffix("Pods.xcodeproj") {
                            addNewSubSubProject(location: location)
                        }
                    }
                }
            }
        }
              
        let obfuscationData = ObfuscationData()
        
        for xproj in subProjects {
            let manualProtector = ManualSubProjectSwiftShield(basePath: xproj.projectBasePath, projFilePath: xproj.projectFilePath, tag: self.tag, protectedClassNameSize: protectedClassNameSize, dryRun: self.dryRun, modulesToIgnore:self.modulesToIgnore, obfuscationData: obfuscationData)
            obfuscationData.merge(with: manualProtector.protect())
        }
        
        if dryRun == false {
            writeToFile(data: obfuscationData);
        }
        
        return obfuscationData
    }
    
    func addNewSubSubProject(location: String) {
        let basePathUrl = URL(fileURLWithPath: basePath)
        let relativeURL = URL(fileURLWithPath: location, relativeTo: basePathUrl)
        print(relativeURL.path)
        if FileManager.default.fileExists(atPath: relativeURL.path) {
            subProjects.append(SubProject(projectFilePath: relativeURL.path))
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
    
    internal final class SubProject {
        
        let projectBasePath : String
        let projectFilePath : String
        var hasSwiftSource : Bool
        var hasObjCSource : Bool
        
        init(projectFilePath: String) {
            self.projectFilePath = projectFilePath
            self.hasSwiftSource = false
            self.hasObjCSource = false
            self.projectBasePath  = URL(fileURLWithPath: projectFilePath).deletingLastPathComponent().path
            let pbxproj = projectFilePath+"/project.pbxproj"
            if FileManager.default.fileExists(atPath: pbxproj) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: pbxproj)) {
                    if let contentsOf = String(data: data, encoding: .utf8) {
                        self.hasSwiftSource = contentsOf.contains(".swift in Sources")
                        self.hasObjCSource = contentsOf.contains(".m in Sources") || contentsOf.contains(".mm in Sources")
                    }
                }
            }
        }
    }
    
    internal final class ManualSubProjectSwiftShield: ManualSwiftShield {
        
        let modulesToIgnore: Set<String>
        let obfuscationData: ObfuscationData
        var projectFilePath: String = ""
        init(basePath: String, projFilePath: String, tag: String, protectedClassNameSize: Int, dryRun: Bool, modulesToIgnore: Set<String>, obfuscationData: ObfuscationData) {
            self.modulesToIgnore = modulesToIgnore
            self.obfuscationData = obfuscationData
            super.init(basePath: basePath, tag: tag, protectedClassNameSize: protectedClassNameSize, dryRun: dryRun)
            self.projectFilePath = projFilePath+"/project.pbxproj"
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
            obfsData.merge(with: self.obfuscationData)
            obfsData.files.forEach { protect(file: $0, obfsData: obfsData) }
            obfsData.storyboards.forEach { protect(file: $0, obfsData: obfsData) }
            renameFiles(obfsData: obfsData)
            return obfsData
        }
        
        func renameFiles(obfsData: ObfuscationData) {
            if dryRun == false {
                var allFiles: [File] = []
                allFiles.append(contentsOf: obfsData.files)
                allFiles.append(contentsOf: obfsData.storyboards)
                for file in allFiles {
                    renameFile(file: file, obfsData: obfsData)
                }
            }
        }
        
        func renameFile(file: File, obfsData: ObfuscationData) {
            do {
                var destinationFilePath = file.path
                if let filenameComplete = destinationFilePath.split(separator: "/").last, let subString = filenameComplete.split(separator: ".").first {
                    let filename = String(subString)
                    if filename.hasSuffix(tag) {
                        let obfuscatedName: String = {
                            guard let protected = obfsData.obfuscationDict[filename] else {
                                let protected = String.random(length: protectedClassNameSize,
                                                              excluding: obfsData.allObfuscatedNames)
                                obfsData.obfuscationDict[filename] = protected
                                return protected
                            }
                            return protected
                        }()
                        do {
                            destinationFilePath =  file.path.replacingOccurrences(of: filename, with: obfuscatedName)
                            if let indexOfFile = obfsData.files.index(of: file) {
                                obfsData.files.remove(at: indexOfFile)
                                obfsData.files.append(File(filePath: destinationFilePath))
                            }
                            let fileString = try String(contentsOfFile: file.path, encoding: .utf8)
                            try fileString.write(toFile: destinationFilePath, atomically: false, encoding: .utf8)
                            
                        } catch {
                            print(error)
                        }
                        var projFileString = try String(contentsOfFile: projectFilePath, encoding: .utf8)
                        projFileString = projFileString.replacingOccurrences(of: " \(filename)", with: " \(obfuscatedName)")
                        try projFileString.write(toFile: projectFilePath, atomically: false, encoding: .utf8)
                    }
                }
               
            } catch {
                Logger.log(.fatal(error: error.localizedDescription))
                exit(1)
            }
        }
    }
}
