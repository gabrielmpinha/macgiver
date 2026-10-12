import AppKit
import Combine
import Foundation

struct GitHubRelease: Decodable, Identifiable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let publishedAt: Date
    let body: String
    let assets: [Asset]

    var id: String { tagName }
    var version: String { String(tagName.drop(while: { !$0.isNumber })) }
    var downloadURL: URL? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case body
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

@MainActor
final class GitHubReleaseChecker: ObservableObject {
    @Published private(set) var latestRelease: GitHubRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?

    var updateAvailable: Bool {
        guard let latestRelease else { return false }
        return Self.isVersion(latestRelease.version, newerThan: AppMetadata.version)
    }

    func checkIfNeeded() async {
        guard latestRelease == nil, errorMessage == nil else { return }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/gabrielmpinha/macgiver/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacGiver", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ReleaseCheckError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            latestRelease = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            errorMessage = String(localized: "Could not check GitHub for updates. Check your internet connection and try again.")
        }
    }

    func downloadLatestRelease() {
        guard let release = latestRelease else { return }
        NSWorkspace.shared.open(release.downloadURL ?? release.htmlURL)
    }

    func openReleasePage() {
        guard let latestRelease else { return }
        NSWorkspace.shared.open(latestRelease.htmlURL)
    }

    private static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let values = version.split(separator: ".").map { part -> Int? in
                Int(part.prefix(while: \.isNumber))
            }
            guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }
        }

        guard let candidateParts = components(candidate), let installedParts = components(installed) else { return false }
        for index in 0..<max(candidateParts.count, installedParts.count) {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let installedValue = index < installedParts.count ? installedParts[index] : 0
            if candidateValue != installedValue { return candidateValue > installedValue }
        }
        return false
    }

    private enum ReleaseCheckError: Error {
        case invalidResponse
    }
}
