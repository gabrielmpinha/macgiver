import SwiftUI

struct HomebrewCollapsedSummary: View {
    @EnvironmentObject private var manager: HomebrewManager
    let onExpand: () -> Void

    private var updateCount: Int { manager.packages.filter(\.isOutdated).count }

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacGiverPalette.accent)
                    .frame(width: 32, height: 32)
                    .background(MacGiverPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew").font(.system(size: 12, weight: .semibold))
                    Text(summaryText).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if updateCount > 0 {
                    Text(updateCount.formatted())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(MacGiverPalette.warm, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Manage Homebrew packages")
        .accessibilityLabel(Text("Homebrew, \(manager.packages.count.formatted()) packages, \(updateCount.formatted()) updates. Manage packages"))
    }

    private var summaryText: String {
        guard manager.isAvailable else { return String(localized: "Package manager unavailable") }
        if !manager.isLoaded { return String(localized: "Open to load packages") }
        if manager.isRefreshing && manager.packages.isEmpty { return String(localized: "Loading packages…") }
        return String(localized: "\(manager.packages.count.formatted()) installed · \(updateCount.formatted()) updates")
    }
}

struct HomebrewMenuPanel: View {
    @EnvironmentObject private var manager: HomebrewManager
    let onCollapse: () -> Void

    @State private var searchText = ""
    @State private var showingUpdatesOnly = false
    @State private var packageToUninstall: HomebrewPackage?
    @State private var showingUninstallConfirmation = false
    @State private var selectedPackageIDs: Set<String> = []

    private var outdatedCount: Int { manager.packages.filter(\.isOutdated).count }
    private var selectedOutdatedPackages: [HomebrewPackage] {
        manager.packages.filter { $0.isOutdated && selectedPackageIDs.contains($0.id) }
    }

    private var visiblePackages: [HomebrewPackage] {
        manager.packages.filter { package in
            (!showingUpdatesOnly || package.isOutdated)
                && (searchText.isEmpty || package.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !manager.isAvailable {
                brewUnavailable
            } else {
                packageOverview
                searchField
                if outdatedCount > 0 { updateControls }
                operationLog
                packageList
            }

            feedback
        }
        .task { await manager.refresh() }
        .confirmationDialog(
            "Uninstall \(packageToUninstall?.name ?? "package")?",
            isPresented: $showingUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                guard let packageToUninstall else { return }
                Task { await manager.uninstall(packageToUninstall) }
                self.packageToUninstall = nil
            }
            Button("Cancel", role: .cancel) { packageToUninstall = nil }
        } message: {
            Text("Homebrew will remove this package. Apps and settings outside Homebrew may remain.")
        }
    }

    private var updateControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    Task { await manager.upgrade(manager.packages.filter(\.isOutdated)) }
                } label: {
                    Text("Update all (\(outdatedCount.formatted()))")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isBatchRunning || manager.runningPackageID != nil)

                Button {
                    Task { await manager.upgrade(selectedOutdatedPackages) }
                } label: {
                    Text("Update selected (\(selectedOutdatedPackages.count.formatted()))")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedOutdatedPackages.isEmpty || manager.isBatchRunning || manager.runningPackageID != nil)
            }

            HStack {
                Button("Select visible updates") {
                    selectedPackageIDs.formUnion(visiblePackages.filter(\.isOutdated).map(\.id))
                }
                .disabled(manager.isBatchRunning)
                Button("Clear selection") { selectedPackageIDs.removeAll() }
                    .disabled(selectedPackageIDs.isEmpty || manager.isBatchRunning)
                Spacer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MacGiverPalette.accent)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var operationLog: some View {
        if !manager.logText.isEmpty || manager.isBatchRunning {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Update log", systemImage: "text.alignleft")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if manager.isBatchRunning {
                        ProgressView().controlSize(.small)
                        if let progress = manager.batchProgressMessage {
                            Text(progress).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Button("Clear log") { manager.clearLog() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(manager.logText.isEmpty ? String(localized: "Waiting for Homebrew output…") : manager.logText)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("homebrew-log-end")
                    }
                    .frame(height: 112)
                    .onChange(of: manager.logText) { _, _ in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("homebrew-log-end", anchor: .bottom) }
                    }
                }

                if !manager.terminalRetryPackages.isEmpty {
                    HStack {
                        Text("Some installers may need administrator interaction.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        ForEach(manager.terminalRetryPackages) { package in
                            Button("Retry in Terminal") { manager.retryUpdateInTerminal(package) }
                                .buttonStyle(.bordered).controlSize(.mini)
                                .help("Retry update for \(package.name) in Terminal")
                        }
                    }
                }
            }
            .padding(9)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to quick controls")
            .accessibilityLabel("Back to quick controls")

            VStack(alignment: .leading, spacing: 2) {
                Text("Homebrew packages")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Installed formulas and apps")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await manager.refresh() }
            } label: {
                if manager.isRefreshing {
                    ProgressView().controlSize(.small).frame(width: 26, height: 26)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.06), in: Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(manager.isRefreshing || manager.runningPackageID != nil)
            .help("Refresh packages")
            .accessibilityLabel("Refresh packages")
        }
    }

    private var packageOverview: some View {
        HStack(spacing: 8) {
            overviewMetric(value: manager.packages.count, title: "Installed", symbol: "shippingbox.fill", tint: MacGiverPalette.accent)
            overviewMetric(value: outdatedCount, title: "Updates", symbol: "arrow.down.circle.fill", tint: outdatedCount > 0 ? MacGiverPalette.warm : MacGiverPalette.success)
        }
        .padding(10)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func overviewMetric(value: Int, title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value.formatted()).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        VStack(spacing: 8) {
            Picker("Package filter", selection: $showingUpdatesOnly) {
                Text("All").tag(false)
                Text("Updates").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search packages", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    @ViewBuilder
    private var packageList: some View {
        if manager.isRefreshing && manager.packages.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading installed packages…").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        } else if visiblePackages.isEmpty {
            VStack(spacing: 5) {
                Image(systemName: showingUpdatesOnly ? "checkmark.circle" : "shippingbox")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                Text(emptyTitle).font(.subheadline.weight(.medium))
                Text(emptySubtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 6) {
                ForEach(visiblePackages) { package in
                    packageRow(package)
                }
            }
        }
    }

    private func packageRow(_ package: HomebrewPackage) -> some View {
        HStack(spacing: 9) {
            Image(systemName: package.kind == .cask ? "app.dashed" : "terminal.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(package.kind == .cask ? MacGiverPalette.violet : MacGiverPalette.accent)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(package.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if package.isOutdated {
                        Circle().fill(MacGiverPalette.warm).frame(width: 6, height: 6)
                            .accessibilityLabel(Text("Update available"))
                    }
                }
                HStack(spacing: 5) {
                    Text(package.kind.title)
                    Text("·")
                    Text(package.installedVersion)
                    if let latestVersion = package.latestVersion {
                        Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                        Text(latestVersion).foregroundStyle(MacGiverPalette.warm)
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 3)

            if manager.runningPackageID == package.id {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else {
                if package.isOutdated {
                    Button {
                        if selectedPackageIDs.contains(package.id) {
                            selectedPackageIDs.remove(package.id)
                        } else {
                            selectedPackageIDs.insert(package.id)
                        }
                    } label: {
                        Image(systemName: selectedPackageIDs.contains(package.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15)).foregroundStyle(MacGiverPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .help(selectedPackageIDs.contains(package.id) ? "Deselect package \(package.name)" : "Select package \(package.name)")
                    .accessibilityLabel(Text(selectedPackageIDs.contains(package.id) ? "Deselect package \(package.name)" : "Select package \(package.name)"))

                    Button {
                        Task { await manager.upgrade(package) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17)).foregroundStyle(MacGiverPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Update \(package.name)")
                    .accessibilityLabel(Text("Update \(package.name)"))
                    .disabled(manager.isBatchRunning)
                }
                Button(role: .destructive) {
                    packageToUninstall = package
                    showingUninstallConfirmation = true
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Uninstall \(package.name)")
                .accessibilityLabel(Text("Uninstall \(package.name)"))
                .disabled(manager.isBatchRunning)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var brewUnavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 25)).foregroundStyle(.secondary)
            Text("Homebrew not found").font(.subheadline.weight(.semibold))
            Text("Install Homebrew, then reopen this panel to manage packages.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var feedback: some View {
        if let errorMessage = manager.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        } else if let statusMessage = manager.statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(MacGiverPalette.success).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyTitle: LocalizedStringKey {
        if showingUpdatesOnly && !manager.packages.isEmpty { return "Everything is up to date" }
        return searchText.isEmpty ? "No packages found" : "No matching packages"
    }

    private var emptySubtitle: LocalizedStringKey {
        if showingUpdatesOnly && !manager.packages.isEmpty { return "There are no available package updates." }
        return searchText.isEmpty ? "No Homebrew packages are installed." : "Try a different package name."
    }
}
