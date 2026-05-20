import Foundation

/// Simple mutex-protected box for sharing data between threads
final class MutexBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(initialValue: T) { _value = initialValue }

    func get() -> T {
        lock.lock()
        let v = _value
        lock.unlock()
        return v
    }

    func update(_ block: (inout T) -> Void) {
        lock.lock()
        block(&_value)
        lock.unlock()
    }
}

struct EnvCheckResult: Sendable {
    let javaAvailable: Bool
    let javaPath: String?
    let javaVersion: String?
    let jarAvailable: Bool
    let jarPath: String?
}

struct ScanCommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let outputDir: String
}

struct ScanResults {
    var packagePath: String
    var packageInfo: PackageInfo?
    var duplicateResult: DuplicateResult?
    var fileSizeResult: FileSizeResult?
    var suffixResult: SuffixResult?
    var htmlPaths: [String]
}

struct PackageInfo {
    var name: String
    var bundleName: String
    var type: String
}

struct DuplicateResult {
    var taskDesc: String
    var totalDuplicateFiles: Int
    var duplicateSOFiles: Int
    var details: [DuplicateEntry]
}

struct DuplicateEntry: Identifiable {
    let id = UUID()
    var fileName: String
    var count: Int
    var sizeBytes: Int
    var md5: String
    var files: [String]
}

struct FileSizeResult {
    var taskDesc: String
    var threshold: Int
    var largeFileCount: Int
    var details: [FileSizeEntry]
}

struct FileSizeEntry: Identifiable {
    let id = UUID()
    var path: String
    var sizeBytes: Int
}

struct SuffixResult {
    var taskDesc: String
    var entries: [SuffixEntry]
    var totalSize: Int
}

struct SuffixEntry: Identifiable {
    let id = UUID()
    var suffix: String
    var fileCount: Int
    var totalSizeBytes: Int
    var files: [SuffixFileDetail]
}

struct SuffixFileDetail: Identifiable {
    let id = UUID()
    var path: String
    var sizeBytes: Int
}

@Observable
final class ScanService {
    var javaAvailable = false
    var javaPath: String?
    var javaVersion: String?
    var jarAvailable = false
    var jarPath: String?
    var jarPathOverride: String?

    var isScanning = false
    var scanProgress: String = ""
    var scanProgressDetail: String = ""
    var scanError: String?

    var results: ScanResults?

    var enableDuplicate = true
    var enableFileSize = true
    var fileSizeThreshold: Int = 512
    var enableSuffix = true

    var inputFilePath: String?
    var inputFileName: String?

    var effectiveJarPath: String? {
        jarPathOverride ?? jarPath
    }

    var canStartScan: Bool {
        javaAvailable && (jarAvailable || jarPathOverride != nil)
            && inputFilePath != nil && !isScanning
    }

    func checkEnvironment() async {
        let result: EnvCheckResult = await Task.detached {
            var javaPath: String? = nil
            var javaVersion: String? = nil

            // Method 1: use `which java` to find the current java
            let whichProc = Process()
            whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProc.arguments = ["java"]
            let whichEnv = Self.processEnvironment()
            whichProc.environment = whichEnv
            let whichPipe = Pipe()
            whichProc.standardOutput = whichPipe
            if let _ = try? whichProc.run() {
                whichProc.waitUntilExit()
                if whichProc.terminationStatus == 0 {
                    let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                    let found = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let found, !found.isEmpty, FileManager.default.fileExists(atPath: found) {
                        javaPath = found
                    }
                }
            }

            // Method 2: fallback to common paths if which didn't work
            if javaPath == nil {
                let searchPaths = [
                    "/usr/local/opt/openjdk@17/bin/java",
                    "/usr/local/opt/openjdk@21/bin/java",
                    "/usr/local/opt/openjdk@11/bin/java",
                    "/opt/homebrew/opt/openjdk@17/bin/java",
                    "/opt/homebrew/opt/openjdk@21/bin/java",
                    "/usr/local/bin/java",
                    "/opt/homebrew/bin/java",
                    "/usr/bin/java",
                ]
                for path in searchPaths {
                    guard FileManager.default.fileExists(atPath: path) else { continue }
                    let testProc = Process()
                    testProc.executableURL = URL(fileURLWithPath: path)
                    testProc.arguments = ["-version"]
                    let testPipe = Pipe()
                    testProc.standardError = testPipe
                    testProc.environment = whichEnv
                    do {
                        try testProc.run()
                    } catch {
                        continue
                    }
                    testProc.waitUntilExit()
                    if testProc.terminationStatus == 0 {
                        javaPath = path
                        break
                    }
                }
            }

            // Get java version from the found path
            if let foundJavaPath = javaPath {
                let verProc = Process()
                verProc.executableURL = URL(fileURLWithPath: foundJavaPath)
                verProc.arguments = ["-version"]
                let verPipe = Pipe()
                verProc.standardError = verPipe
                verProc.environment = whichEnv
                if let _ = try? verProc.run() {
                    verProc.waitUntilExit()
                    let data = verPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if let range = output.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                        javaVersion = String(output[range])
                    }
                }
            }

            // Find JAR: default path first, then search DevEco SDK directory
            var jarPath: String? = nil
            let defaultJar = "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/app_check_tool.jar"
            if FileManager.default.fileExists(atPath: defaultJar) {
                jarPath = defaultJar
            } else {
                // Search under DevEco SDK directory for app_check_tool.jar
                let sdkRoot = "/Applications/DevEco-Studio.app/Contents/sdk"
                if let enumerator = FileManager.default.enumerator(atPath: sdkRoot) {
                    while let file = enumerator.nextObject() as? String {
                        if file.hasSuffix("app_check_tool.jar") {
                            let fullPath = (sdkRoot as NSString).appendingPathComponent(file)
                            if FileManager.default.fileExists(atPath: fullPath) {
                                jarPath = fullPath
                                break
                            }
                        }
                    }
                }
            }

            return EnvCheckResult(
                javaAvailable: javaPath != nil,
                javaPath: javaPath,
                javaVersion: javaVersion,
                jarAvailable: jarPath != nil,
                jarPath: jarPath
            )
        }.value

        self.javaAvailable = result.javaAvailable
        self.javaPath = result.javaPath
        self.javaVersion = result.javaVersion
        self.jarAvailable = result.jarAvailable
        self.jarPath = result.jarPath
    }

    func startScan() async {
        guard let inputPath = inputFilePath,
              let javaExec = javaPath,
              let jarExec = effectiveJarPath else {
            scanError = "环境未就绪: Java=\(javaPath ?? "nil"), JAR=\(effectiveJarPath ?? "nil")"
            return
        }

        guard FileManager.default.fileExists(atPath: inputPath) else {
            scanError = "输入文件不可访问: \(inputPath)"
            return
        }
        guard FileManager.default.fileExists(atPath: jarExec) else {
            scanError = "JAR 文件不可访问: \(jarExec)"
            return
        }
        guard FileManager.default.fileExists(atPath: javaExec) else {
            scanError = "Java 不可访问: \(javaExec)"
            return
        }

        isScanning = true
        scanError = nil
        results = nil
        scanProgressDetail = ""

        let baseTempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hm_check_" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(atPath: baseTempDir, withIntermediateDirectories: true)
        } catch {
            scanError = "无法创建临时目录: \(error.localizedDescription)"
            isScanning = false
            return
        }

        var duplicateResult: DuplicateResult? = nil
        var fileSizeResult: FileSizeResult? = nil
        var suffixResult: SuffixResult? = nil
        var htmlPaths: [String] = []
        var allErrors: [String] = []

        if enableDuplicate {
            scanProgress = "步骤 1/3"
            scanProgressDetail = "扫描重复文件..."
            let outDir = (baseTempDir as NSString).appendingPathComponent("duplicate")
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            let cmd = await runScanCommand(
                javaExec: javaExec, jarExec: jarExec,
                inputPath: inputPath, outputPath: outDir,
                extraArgs: ["--stat-duplicate", "true"]
            )
            duplicateResult = Self.parseDuplicateJSON(outputDir: outDir)
            collectHTMLPaths(outputDir: outDir, into: &htmlPaths)
            if cmd.exitCode != 0 && duplicateResult == nil {
                allErrors.append("Duplicate: \(cmd.stderr)")
            }
        }

        if enableFileSize {
            let step = enableDuplicate ? "步骤 2/3" : "步骤 1/2"
            scanProgress = step
            scanProgressDetail = "扫描大文件..."
            let outDir = (baseTempDir as NSString).appendingPathComponent("filesize")
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            let cmd = await runScanCommand(
                javaExec: javaExec, jarExec: jarExec,
                inputPath: inputPath, outputPath: outDir,
                extraArgs: ["--stat-file-size", String(fileSizeThreshold)]
            )
            fileSizeResult = Self.parseFileSizeJSON(outputDir: outDir, threshold: fileSizeThreshold)
            collectHTMLPaths(outputDir: outDir, into: &htmlPaths)
            if cmd.exitCode != 0 && fileSizeResult == nil {
                allErrors.append("FileSize: \(cmd.stderr)")
            }
        }

        if enableSuffix {
            let totalSteps = (enableDuplicate ? 1 : 0) + (enableFileSize ? 1 : 0) + 1
            scanProgress = "步骤 \(totalSteps)/\(totalSteps)"
            scanProgressDetail = "扫描文件后缀..."
            let outDir = (baseTempDir as NSString).appendingPathComponent("suffix")
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            let cmd = await runScanCommand(
                javaExec: javaExec, jarExec: jarExec,
                inputPath: inputPath, outputPath: outDir,
                extraArgs: ["--stat-suffix", "true"]
            )
            suffixResult = Self.parseSuffixJSON(outputDir: outDir)
            collectHTMLPaths(outputDir: outDir, into: &htmlPaths)
            if cmd.exitCode != 0 && suffixResult == nil {
                allErrors.append("Suffix: \(cmd.stderr)")
            }
        }

        if duplicateResult == nil && fileSizeResult == nil && suffixResult == nil {
            scanError = allErrors.joined(separator: "\n")
        } else if !allErrors.isEmpty {
            scanError = "部分扫描出现问题:\n" + allErrors.joined(separator: "\n")
        }

        results = ScanResults(
            packagePath: inputPath,
            packageInfo: parsePackageInfo(inputPath: inputPath),
            duplicateResult: duplicateResult,
            fileSizeResult: fileSizeResult,
            suffixResult: suffixResult,
            htmlPaths: htmlPaths
        )

        scanProgress = "完成"
        scanProgressDetail = ""
        isScanning = false
    }

    private func runScanCommand(
        javaExec: String, jarExec: String,
        inputPath: String, outputPath: String,
        extraArgs: [String]
    ) async -> ScanCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: javaExec)
                process.arguments = [
                    "-jar", jarExec,
                    "--input", inputPath,
                    "--out-path", outputPath,
                ] + extraArgs
                process.environment = Self.processEnvironment()
                process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

                let cmdLine = "\(javaExec) -jar \(jarExec) --input \(inputPath) --out-path \(outputPath) \(extraArgs.joined(separator: " "))"

                // Read stdout/stderr concurrently to avoid pipe buffer deadlock
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Read stderr concurrently in background to prevent pipe deadlock
                let stderrDataBox = MutexBox<Data>(initialValue: Data())
                DispatchQueue.global(qos: .default).async {
                    stderrDataBox.update { box in
                        box.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ScanCommandResult(
                        exitCode: -1, stdout: "",
                        stderr: "进程启动失败: \(error.localizedDescription)\nCMD: \(cmdLine)",
                        outputDir: outputPath
                    ))
                    return
                }
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrDataBox.get()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: ScanCommandResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr.isEmpty ? "CMD: \(cmdLine) Exit:\(process.terminationStatus)" : "CMD: \(cmdLine)\nExit: \(process.terminationStatus)\n\(stderr)",
                    outputDir: outputPath
                ))
            }
        }
    }

    /// Build environment dict with a proper PATH so java can find its runtime libs
    nonisolated static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // macOS apps get a very limited PATH. Inject common tool locations.
        let extraPaths = [
            "/usr/local/opt/openjdk@17/bin",
            "/usr/local/opt/openjdk@21/bin",
            "/usr/local/opt/openjdk@11/bin",
            "/opt/homebrew/opt/openjdk@17/bin",
            "/opt/homebrew/opt/openjdk@21/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let validExtraPaths = extraPaths.filter { FileManager.default.fileExists(atPath: $0) }
        env["PATH"] = (validExtraPaths.joined(separator: ":") + ":" + existingPath)

        // Set JAVA_HOME if not already set
        if env["JAVA_HOME"] == nil {
            // Search for JAVA_HOME dynamically
            let homeCandidates = [
                "/opt/homebrew/Cellar/openjdk@17",
                "/opt/homebrew/Cellar/openjdk@21",
                "/opt/homebrew/Cellar/openjdk@11",
                "/usr/local/Cellar/openjdk@17",
                "/usr/local/Cellar/openjdk@21",
                "/usr/local/Cellar/openjdk@11",
                "/Library/Java/JavaVirtualMachines",
            ]
            for candidate in homeCandidates {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: candidate) {
                    for versionDir in contents.sorted().reversed() {
                        let home = candidate + "/" + versionDir + "/libexec/openjdk.jdk/Contents/Home"
                        if FileManager.default.fileExists(atPath: home) {
                            env["JAVA_HOME"] = home
                            break
                        }
                    }
                }
                if env["JAVA_HOME"] != nil { break }
            }
        }
        return env
    }

    private func collectHTMLPaths(outputDir: String, into paths: inout [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDir)) ?? []
        for file in files where file.hasSuffix(".html") {
            paths.append((outputDir as NSString).appendingPathComponent(file))
        }
    }

    private func parsePackageInfo(inputPath: String) -> PackageInfo? {
        let url = URL(fileURLWithPath: inputPath)
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return PackageInfo(name: name, bundleName: name, type: ext.isEmpty ? "unknown" : ext)
    }

    // MARK: - JSON Parsing

    nonisolated private static func findJSONFile(outputDir: String) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDir)) ?? []
        return files.first(where: { $0.hasSuffix(".json") })
            .map { (outputDir as NSString).appendingPathComponent($0) }
    }

    nonisolated private static func readJSONArray(outputDir: String) -> [[String: Any]]? {
        guard let jsonPath = findJSONFile(outputDir: outputDir),
              let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return array
    }

    nonisolated static func parseDuplicateJSON(outputDir: String) -> DuplicateResult? {
        guard let array = readJSONArray(outputDir: outputDir),
              let first = array.first
        else { return nil }

        let taskDesc = first["taskDesc"] as? String ?? "find the duplicated files"
        var totalDuplicateFiles = 0
        var soCount = 0
        var entries: [DuplicateEntry] = []

        if let resultArray = first["result"] as? [[String: Any]] {
            for group in resultArray {
                let md5 = group["md5"] as? String ?? ""
                let size = group["size"] as? Int ?? 0

                var filePaths: [String] = []
                if let filesArray = group["files"] as? [String] {
                    filePaths = filesArray
                } else if let filesArray = group["files"] as? [[String: Any]] {
                    filePaths = filesArray.compactMap { $0["file"] as? String }
                }

                let count = filePaths.count
                totalDuplicateFiles += count

                for path in filePaths {
                    if path.hasSuffix(".so") { soCount += 1 }
                }

                let representativeName = filePaths.first ?? "unknown"
                entries.append(DuplicateEntry(
                    fileName: representativeName,
                    count: count,
                    sizeBytes: size,
                    md5: md5,
                    files: filePaths
                ))
            }
        }

        return DuplicateResult(
            taskDesc: taskDesc,
            totalDuplicateFiles: totalDuplicateFiles,
            duplicateSOFiles: soCount,
            details: entries
        )
    }

    nonisolated static func parseFileSizeJSON(outputDir: String, threshold: Int) -> FileSizeResult? {
        guard let array = readJSONArray(outputDir: outputDir),
              let first = array.first
        else { return nil }

        let taskDesc = first["taskDesc"] as? String ?? "find files exceeding size limit"
        var entries: [FileSizeEntry] = []

        if let resultArray = first["result"] as? [[String: Any]] {
            for item in resultArray {
                let path = item["path"] as? String ?? item["file"] as? String ?? ""
                let size = item["size"] as? Int ?? 0
                entries.append(FileSizeEntry(path: path, sizeBytes: size))
            }
        }

        return FileSizeResult(
            taskDesc: taskDesc,
            threshold: threshold,
            largeFileCount: entries.count,
            details: entries
        )
    }

    nonisolated static func parseSuffixJSON(outputDir: String) -> SuffixResult? {
        guard let array = readJSONArray(outputDir: outputDir),
              let first = array.first
        else { return nil }

        let taskDesc = first["taskDesc"] as? String ?? "file suffix distribution"
        var entries: [SuffixEntry] = []
        var grandTotal: Int = 0

        if let resultArray = first["result"] as? [[String: Any]] {
            for group in resultArray {
                let suffix = group["suffix"] as? String ?? ""
                let totalSize = group["totalSize"] as? Int ?? 0
                grandTotal += totalSize

                var files: [SuffixFileDetail] = []
                if let filesArray = group["files"] as? [[String: Any]] {
                    for f in filesArray {
                        let filePath = f["file"] as? String ?? f["path"] as? String ?? ""
                        let size = f["size"] as? Int ?? 0
                        files.append(SuffixFileDetail(path: filePath, sizeBytes: size))
                    }
                }

                entries.append(SuffixEntry(
                    suffix: suffix,
                    fileCount: files.count,
                    totalSizeBytes: totalSize,
                    files: files
                ))
            }
        }

        return SuffixResult(taskDesc: taskDesc, entries: entries, totalSize: grandTotal)
    }
}
