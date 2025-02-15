//
//  main.swift
//  FengNiao
//
//  Created by WANG WEI on 2017/3/7.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import Foundation
import CommandLineKit
import Rainbow
import FengNiaoKit
import PathKit

let appVersion = "0.8.1"

#if os(Linux)
let EX_OK: Int32 = 0
let EX_USAGE: Int32 = 64
#endif

let cli = CommandLineKit.CommandLine()
cli.formatOutput = { s, type in
    var str: String
    switch(type) {
    case .error: str = s.red.bold
    case .optionFlag: str = s.green.underline
    default: str = s
    }
    
    return cli.defaultFormat(s: str, type: type)
}

let projectPathOption = StringOption(
    shortFlag: "p", longFlag: "project",
    helpMessage: "Root path of your Xcode project. Default is current folder.")
cli.addOption(projectPathOption)

let isForceOption = BoolOption(
    longFlag: "force",
    helpMessage: "Delete the found unused files without asking.")
cli.addOption(isForceOption)

let excludePathOption = MultiStringOption(
    shortFlag: "e", longFlag: "exclude",
    helpMessage: "Exclude paths from search.")
cli.addOption(excludePathOption)

let verboseOption = BoolOption(longFlag: "verbose",
    helpMessage: "Display log messages in details.")
cli.addOption(verboseOption)

let resourceExtOption = MultiStringOption(
    shortFlag: "r", longFlag: "resource-extensions",
    helpMessage: "Resource file extensions need to be searched. Default is 'imageset jpg png gif pdf'")
cli.addOption(resourceExtOption)

let fileExtOption = MultiStringOption(
    shortFlag: "f", longFlag: "file-extensions",
    helpMessage: "In which types of files we should search for resource usage. Default is 'm mm swift xib storyboard plist'")
cli.addOption(fileExtOption)

let skipProjRefereceCleanOption = BoolOption(
    longFlag: "skip-proj-reference",
    helpMessage: "Skip the Project file (.pbxproj) reference cleaning. By skipping it, the project file will be left untouched. You may want to skip ths step if you are trying to build multiple projects with dependency and keep .pbxproj unchanged while compiling."
)
cli.addOption(skipProjRefereceCleanOption)

let versionOption = BoolOption(longFlag: "version", helpMessage: "Print version.")
cli.addOption(versionOption)

let helpOption = BoolOption(shortFlag: "h", longFlag: "help",
                      helpMessage: "Print this help message.")
cli.addOption(helpOption)

do {
    try cli.parse()
} catch {
    cli.printUsage(error)
    exit(EX_USAGE)
}

if !cli.unparsedArguments.isEmpty {
    print("Unknow arguments: \(cli.unparsedArguments)".red)
    cli.printUsage()
    exit(EX_USAGE)
}

if helpOption.value {
    cli.printUsage()
    exit(EX_OK)
}

if versionOption.value {
    print(appVersion)
    exit(EX_OK);
}

let projectPath = projectPathOption.value ?? "."
let isForce = isForceOption.value 
let excludePaths = excludePathOption.value ?? []
let resourceExtentions = resourceExtOption.value ?? ["imageset", "jpg", "png", "gif", "pdf"]
let fileExtensions = fileExtOption.value ?? ["h", "m", "mm", "swift", "xib", "storyboard", "plist"]
shouldDisplayLog = verboseOption.value == true ? true : false

let fengNiao = FengNiao(projectPath: projectPath,
                        excludedPaths: excludePaths,
                        resourceExtensions: resourceExtentions,
                        searchInFileExtensions: fileExtensions)

let unusedFiles: [FileInfo] 

do {
    fengiaoPrint("Searching unused file. This may take a while...")
    unusedFiles = try fengNiao.unusedFiles()
} catch {
    guard let e = error as? FengNiaoError else {
        fengiaoPrint("Unknown Error: \(error)".red.bold)
        exit(EX_USAGE)
    }
    switch e {
    case .noResourceExtension:
        fengiaoPrint("You need to specify some resource extensions as search target. Use --resource-extensions to specify.".red.bold)
    case .noFileExtension:
        fengiaoPrint("You need to specify some file extensions to search in. Use --file-extensions to specify.".red.bold)
    }
    exit(EX_USAGE)
}

if unusedFiles.isEmpty {
    fengiaoPrint("😎 Hu, you have no unused resources in path: \(Path(projectPath).absolute()).".green.bold)
    exit(EX_OK)
}

if !isForce {
    var result = promptResult(files: unusedFiles)
    // while result == .list {
    //     for file in unusedFiles.sorted(by: { $0.size > $1.size }) {
    //         print("\(file.readableSize) \(file.path.string)")
    //     }
    //     result = promptResult(files: unusedFiles)
    // }
    fengiaoPrint("\n")
    switch result {
    case .list:
        for file in unusedFiles.sorted(by: { $0.size > $1.size }) {
            // fengiaoPrint("\(file.readableSize) \(file.path.abbreviate().string)", forced: true)lastComponent
            let currentPath = Path.current.string
            fengiaoPrint("\(file.readableSize) \(file.path.string.replacingOccurrences(of: currentPath, with: ""))", forced: true)
        }
        exit(EX_OK)
    case .delete:
        break
    case .ignore:
        fengiaoPrint("Ignored. Nothing to do, bye!".green.bold)
        exit(EX_OK)
    }
}

fengiaoPrint("Deleting unused files...⚙".bold)

let (deleted, failed) = FengNiao.delete(unusedFiles)
guard failed.isEmpty else {
    fengiaoPrint("\(unusedFiles.count - failed.count) unused files are deleted. But we encountered some error while deleting these \(failed.count) files:".yellow.bold)
    for (fileInfo, err) in failed {
        fengiaoPrint("\(fileInfo.path.string) - \(err.localizedDescription)")
    }
    exit(EX_USAGE)
}


fengiaoPrint("\(unusedFiles.count) unused files are deleted.".green.bold)

if !skipProjRefereceCleanOption.value {
    if let children = try? Path(projectPath).absolute().children(){
        fengiaoPrint("Now Deleting unused Reference in project.pbxproj...⚙".bold)
        for path in children {
            if path.lastComponent.hasSuffix("xcodeproj"){
                let pbxproj = path + "project.pbxproj"
                FengNiao.deleteReference(projectFilePath: pbxproj, deletedFiles: deleted)
            }
        }
        fengiaoPrint("Unused Reference deleted successfully.".green.bold)
    }
}
