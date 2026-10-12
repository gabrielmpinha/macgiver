import AppKit
import Combine
import Foundation

enum HomebrewPackageKind: String, CaseIterable, Identifiable, Equatable {
    case formula
    case cask

    var id: String { rawValue }
    var commandFlag: String { self == .formula ? "--formula" : "--cask" }
    var title: String { self == .formula ? String(localized: "Formula") : String(localized: "App") }
}

struct HomebrewPackage: Identifiable, Hashable {
    let name: String
    let installedVersion: String
    let latestVersion: String?
    let kind: HomebrewPackageKind

    var id: String { "\(kind.rawValue):\(name)" }
    var isOutdated: Bool { latestVersion != nil }
}

@MainActor
final class HomebrewManager: ObservableObject {
    @Published private(set) var packages: [HomebrewPackage] = []
    @Published private(set) var isAvailable = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var runningPackageID: String?
    @Published private(set) var batchProgressMessage: String?
    @Published private(set) var isBatchRunning = false
    @Published private(set) var terminalRetryPackages: [HomebrewPackage] = []
    @Published private(set) var logText = ""
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let executable: URL?

    init(executable: URL? = HomebrewManager.findBrew()) {
        self.executable = executable
        isAvailable = executable != nil
    }

    func refresh() async {
        guard let executable else {
            isAvailable = false
            return
        }
        guard !isRefreshing, runningPackageID == nil else { return }

        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let formulaOutput = try await HomebrewCommand.run(executable: executable, arguments: ["list", "--formula", "--versions"])
            let caskOutput = try await HomebrewCommand.run(executable: executable, arguments: ["list", "--cask", "--versions"])
            let outdatedOutput = try await HomebrewCommand.run(executable: executable, arguments: ["outdated", "--json=v2"])
            let outdated = try Self.decodeOutdated(outdatedOutput)
            let formulae = Self.decodeInstalled(formulaOutput, kind: .formula, outdated: outdated.formulaeByName)
            let casks = Self.decodeInstalled(caskOutput, kind: .cask, outdated: outdated.casksByName)
            packages = (formulae + casks).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            isAvailable = true
            isLoaded = true
            statusMessage = String(localized: "Packages refreshed")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upgrade(_ package: HomebrewPackage) async {
        await upgrade([package])
    }

    func upgrade(_ selectedPackages: [HomebrewPackage]) async {
        let outdatedPackages = selectedPackages.filter(\.isOutdated)
        guard !outdatedPackages.isEmpty, !isBatchRunning, runningPackageID == nil else { return }

        isBatchRunning = true
        terminalRetryPackages = []
        statusMessage = nil
        errorMessage = nil
        logText = ""
        appendLog(String(localized: "Starting update of \(outdatedPackages.count) packages…") + "\n")
        defer {
            isBatchRunning = false
            runningPackageID = nil
            batchProgressMessage = nil
        }

        var failedPackages: [HomebrewPackage] = []
        for (index, package) in outdatedPackages.enumerated() {
            runningPackageID = package.id
            batchProgressMessage = String(localized: "Updating \(index + 1) of \(outdatedPackages.count): \(package.name)")
            appendLog("\n$ brew upgrade \(package.kind.commandFlag) --no-ask \(package.name)\n")
            do {
                _ = try await run(package, action: .upgrade)
                appendLog("\n✓ \(String(localized: "Updated \(package.name)"))\n")
            } catch {
                appendLog("\n✕ \(String(localized: "Failed to update \(package.name)"))\n\(error.localizedDescription)\n")
                terminalRetryPackages.append(package)
                failedPackages.append(package)
            }
            runningPackageID = nil
        }

        await refreshAfterOperation()
        if failedPackages.isEmpty {
            statusMessage = String(localized: "All selected updates completed")
            appendLog("\n\(statusMessage ?? "")\n")
        } else {
            statusMessage = String(localized: "Some updates failed")
            errorMessage = String(localized: "Review the operation log for details.")
            appendLog("\n\(statusMessage ?? "")\n")
        }
    }

    func uninstall(_ package: HomebrewPackage) async {
        guard !isBatchRunning, runningPackageID == nil else { return }
        runningPackageID = package.id
        statusMessage = nil
        errorMessage = nil
        terminalRetryPackages = []
        logText = ""
        appendLog("$ brew uninstall \(package.kind.commandFlag) \(package.name)\n")
        defer { runningPackageID = nil }

        do {
            _ = try await run(package, action: .uninstall)
            statusMessage = String(localized: "Uninstalled \(package.name)")
            appendLog("\n✓ \(statusMessage ?? "")\n")
            await refreshAfterOperation()
        } catch {
            errorMessage = error.localizedDescription
            appendLog("\n✕ \(error.localizedDescription)\n")
        }
    }

    func retryUpdateInTerminal(_ package: HomebrewPackage) {
        guard let executable else { return }
        let arguments = [package.kind.commandFlag, "--no-ask", package.name]
        let command = ([executable.path, "upgrade"] + arguments).map(Self.shellQuoted).joined(separator: " ")
        let commandURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGiver-Homebrew-\(UUID().uuidString).command")
        let script = """
        #!/bin/bash
        \(command)
        command_status=$?
        printf '\\nMacGiver update exited with status %s.\\n' "$command_status"
        read -r -p 'Press Return to close this window…' _
        rm -f -- \(Self.shellQuoted(commandURL.path))
        exit "$command_status"
        """

        do {
            try Data(script.utf8).write(to: commandURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandURL.path)
            guard NSWorkspace.shared.open(commandURL) else {
                throw HomebrewCommandError.failed(String(localized: "macOS could not open Terminal."))
            }
            appendLog("\n\(String(localized: "Opened Terminal to retry \(package.name)."))\n")
        } catch {
            errorMessage = error.localizedDescription
            appendLog("\n✕ \(error.localizedDescription)\n")
        }
    }

    func clearLog() {
        logText = ""
    }

    private func run(_ package: HomebrewPackage, action: PackageAction) async throws -> String {
        guard let executable else { throw HomebrewCommandError.failed(String(localized: "Homebrew was not found.")) }
        var arguments = [action.command, package.kind.commandFlag]
        if action == .upgrade { arguments.append("--no-ask") }
        arguments.append(package.name)
        return try await HomebrewCommand.run(
            executable: executable,
            arguments: arguments,
            allowAutoUpdate: action == .upgrade,
            onOutput: { [weak self] chunk in await self?.appendLog(chunk) }
        )
    }

    private func refreshAfterOperation() async {
        guard let executable else { return }
        do {
            let formulaOutput = try await HomebrewCommand.run(executable: executable, arguments: ["list", "--formula", "--versions"])
            let caskOutput = try await HomebrewCommand.run(executable: executable, arguments: ["list", "--cask", "--versions"])
            let outdatedOutput = try await HomebrewCommand.run(executable: executable, arguments: ["outdated", "--json=v2"])
            let outdated = try Self.decodeOutdated(outdatedOutput)
            packages = (Self.decodeInstalled(formulaOutput, kind: .formula, outdated: outdated.formulaeByName)
                + Self.decodeInstalled(caskOutput, kind: .cask, outdated: outdated.casksByName))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendLog(_ text: String) {
        logText.append(text)
        if logText.count > 24_000 {
            logText = String(logText.suffix(24_000))
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func decodeInstalled(
        _ output: String,
        kind: HomebrewPackageKind,
        outdated: [String: String]
    ) -> [HomebrewPackage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let name = parts.first.map(String.init) else { return nil }
            let installedVersion = parts.dropFirst().map(String.init).joined(separator: ", ")
            return HomebrewPackage(
                name: name,
                installedVersion: installedVersion.isEmpty ? String(localized: "Version unavailable") : installedVersion,
                latestVersion: outdated[name],
                kind: kind
            )
        }
    }

    private static func decodeOutdated(_ output: String) throws -> OutdatedPackages {
        try JSONDecoder().decode(OutdatedPackages.self, from: Data(output.utf8))
    }

    private static func findBrew() -> URL? {
        let commonPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        let pathEntries = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map { "\($0)/brew" }
        return (commonPaths + pathEntries).first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private struct OutdatedPackages: Decodable {
        let formulae: [OutdatedPackage]
        let casks: [OutdatedPackage]

        var formulaeByName: [String: String] { Dictionary(uniqueKeysWithValues: formulae.map { ($0.name, $0.currentVersion) }) }
        var casksByName: [String: String] { Dictionary(uniqueKeysWithValues: casks.map { ($0.name, $0.currentVersion) }) }

        enum CodingKeys: String, CodingKey {
            case formulae
            case casks
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            formulae = try container.decodeIfPresent([OutdatedPackage].self, forKey: .formulae) ?? []
            casks = try container.decodeIfPresent([OutdatedPackage].self, forKey: .casks) ?? []
        }
    }

    private struct OutdatedPackage: Decodable {
        let name: String
        let currentVersion: String

        enum CodingKeys: String, CodingKey {
            case name
            case currentVersion = "current_version"
        }
    }

    private enum PackageAction: Equatable {
        case upgrade
        case uninstall

        var command: String { self == .upgrade ? "upgrade" : "uninstall" }
    }
}

private enum HomebrewCommand {
    static func run(
        executable: URL,
        arguments: [String],
        allowAutoUpdate: Bool = false,
        onOutput: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            if !allowAutoUpdate { environment["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
            process.environment = environment
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                var outputData = Data()
                var pendingLineData = Data()
                while true {
                    let chunk = outputPipe.fileHandleForReading.availableData
                    guard !chunk.isEmpty else { break }
                    outputData.append(chunk)
                    pendingLineData.append(chunk)
                    while let newlineIndex = pendingLineData.firstIndex(of: 0x0A) {
                        let line = pendingLineData[..<newlineIndex]
                        await onOutput(String(decoding: line, as: UTF8.self) + "\n")
                        pendingLineData.removeSubrange(...newlineIndex)
                    }
                }
                if !pendingLineData.isEmpty {
                    await onOutput(String(decoding: pendingLineData, as: UTF8.self))
                }
                process.waitUntilExit()
                let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    throw HomebrewCommandError.failed(output.isEmpty ? "brew \(arguments.joined(separator: " "))" : output)
                }
                return output
            } catch let error as HomebrewCommandError {
                throw error
            } catch {
                throw HomebrewCommandError.failed(error.localizedDescription)
            }
        }.value
    }
}

private enum HomebrewCommandError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let detail):
            "\(String(localized: "Homebrew command failed"))\n\(detail)"
        }
    }
}
