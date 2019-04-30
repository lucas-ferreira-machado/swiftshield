import Foundation

if CommandLine.arguments.contains("-help") {
    Logger.log(.helpText)
    exit()
}

Logger.verbose = CommandLine.arguments.contains("-verbose")
SourceKit.verbose = CommandLine.arguments.contains("-show-sourcekit-queries")

Logger.log(.version)
Logger.log(.verbose)

if let filePathToDeobfuscate = UserDefaults.standard.string(forKey: "deobfuscate") {
    if let mapFilePath = UserDefaults.standard.string(forKey: "deobfuscate-map") {
        let file = File(filePath: filePathToDeobfuscate)
        let mapFile = File(filePath: mapFilePath)
        Logger.log(.deobfuscatorStarted)
        Deobfuscator.deobfuscate(file: file, mapFile: mapFile)
        exit()
    } else {
        Logger.log(.helpText)
        exit(error: true)
    }
}

let mixed = CommandLine.arguments.contains("-mixed")
let automatic = CommandLine.arguments.contains("-automatic")
let dryRun = CommandLine.arguments.contains("-dry-run")

Logger.log(.mode)

let basePath = UserDefaults.standard.string(forKey: "project-root") ?? ""
let obfuscationCharacterCount = abs(UserDefaults.standard.integer(forKey: "obfuscation-character-count"))
let protectedClassNameSize = obfuscationCharacterCount == 0 ? 32 : obfuscationCharacterCount

let protector: Protector
if automatic {
    let schemeToBuild = UserDefaults.standard.string(forKey: "automatic-project-scheme") ?? ""
    let projectToBuild = UserDefaults.standard.string(forKey: "automatic-project-file") ?? ""
    let modulesToIgnore = UserDefaults.standard.string(forKey: "ignore-modules")?.components(separatedBy: ",") ?? []
    let tag = UserDefaults.standard.string(forKey: "tag") ?? "__s"
    protector = MixedSwiftShield(basePath: basePath, projectToBuild: projectToBuild, schemeToBuild: schemeToBuild, modulesToIgnore: Set(modulesToIgnore), dryRun: dryRun, tag: tag)
} else if automatic {
    let schemeToBuild = UserDefaults.standard.string(forKey: "automatic-project-scheme") ?? ""
    let projectToBuild = UserDefaults.standard.string(forKey: "automatic-project-file") ?? ""
    let modulesToIgnore = UserDefaults.standard.string(forKey: "ignore-modules")?.components(separatedBy: ",") ?? []
    protector = AutomaticSwiftShield(basePath: basePath, projectToBuild: projectToBuild, schemeToBuild: schemeToBuild, modulesToIgnore: Set(modulesToIgnore), protectedClassNameSize: protectedClassNameSize, dryRun: dryRun)
} else {
    let tag = UserDefaults.standard.string(forKey: "tag") ?? "__s"
    protector = ManualSwiftShield(basePath: basePath, tag: tag, protectedClassNameSize: protectedClassNameSize, dryRun: dryRun)
}

let obfuscationData = protector.protect()
if obfuscationData.obfuscationDict.isEmpty {
    Logger.log(.foundNothingError)
    exit(error: true)
}

if dryRun == false {
    protector.protectStoryboards(data: obfuscationData)
    protector.writeToFile(data: obfuscationData)
    protector.markProjectsAsProtected()
}

Logger.log(.finished)
exit()
