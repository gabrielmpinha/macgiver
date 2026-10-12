import SwiftUI

struct GitHubUpdatesPanel: View {
    @ObservedObject var checker: GitHubReleaseChecker
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back to quick controls")
                .accessibilityLabel("Back to quick controls")

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacGiver updates")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Current version: \(AppMetadata.version)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await checker.check() }
                } label: {
                    if checker.isChecking {
                        ProgressView().controlSize(.small).frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(.primary.opacity(0.06), in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(checker.isChecking)
                .help("Check for updates")
                .accessibilityLabel("Check for updates")
            }

            if checker.isChecking && checker.latestRelease == nil {
                ProgressView("Checking GitHub Releases…")
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else if let errorMessage = checker.errorMessage {
                ContentUnavailableView {
                    Label("Update check failed", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await checker.check() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else if let release = checker.latestRelease {
                releaseContent(release)
            } else {
                ProgressView("Checking GitHub Releases…")
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .task { await checker.checkIfNeeded() }
    }

    private func releaseContent(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: checker.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(checker.updateAvailable ? MacGiverPalette.warm : MacGiverPalette.success)
                VStack(alignment: .leading, spacing: 2) {
                    if checker.updateAvailable {
                        Text("Version \(release.version) is available")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("You’re up to date")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Latest version: \(release.version)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if checker.updateAvailable {
                    Button("Download update") { checker.downloadLatestRelease() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .contain)

            if checker.updateAvailable {
                Text("Download the DMG, open it, then drag MacGiver to Applications.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }

            HStack {
                Text(release.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(release.publishedAt, style: .date)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            ScrollView {
                Text((try? AttributedString(markdown: release.body.isEmpty ? String(localized: "No release notes were provided.") : release.body))
                    ?? AttributedString(release.body))
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(height: 190)
            .padding(9)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack {
                Label("Release notes from GitHub", systemImage: "checkmark.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("View on GitHub") { checker.openReleasePage() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacGiverPalette.accent)
            }
        }
    }
}
