import Foundation

class ObfuscationData {
    var files: [File]
    var storyboards: [File]

    var obfuscationDict: [String: String] = [:]

    var allObfuscatedNames: Set<String> {
        return Set(obfuscationDict.values)
    }

    init(files: [File] = [], storyboards: [File] = []) {
        self.files = files
        self.storyboards = storyboards
    }
    
    func merge(with: ObfuscationData) {
        for (k, v) in with.obfuscationDict {
            // If a key is already present it will be overritten
            self.obfuscationDict[k] = v
        }
        for file in with.files {
            if !self.files.contains(file) {
                self.files.append(file)
            }
        }
        for file in with.storyboards {
            if !self.storyboards.contains(file) {
                self.storyboards.append(file)
            }
        }
    }
}

final class AutomaticObfuscationData: ObfuscationData {

    let modules: [Module]

    var usrDict: Set<String> = []
    var referencesDict: [File: [ReferenceData]] = [:]
    var usrRelationDict: [String: SourceKitdResponse.Variant] = [:]
    var indexedFiles: [(File, SourceKitdResponse)] = []

    var moduleNames: Set<String> {
        return Set(modules.compactMap { $0.name })
    }

    var plists: [File] {
        return modules.flatMap { $0.plists }
    }

    var mainModule: Module? {
        return modules.last
    }

    init(modules: [Module] = []) {
        self.modules = modules
        let files = modules.flatMap { $0.sourceFiles }
        let storyboards = modules.flatMap { $0.xibFiles }
        super.init(files: files, storyboards: storyboards)
    }
}
