import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import MacGiver

final class LocalizationTests: XCTestCase {
    private var appBundle: Bundle { Bundle(for: AppState.self) }

    func testEveryLanguageHasCompleteCompiledResources() throws {
        XCTAssertEqual(appBundle.developmentLocalization, "en")
        XCTAssertTrue(Set(["en", "pt", "es"]).isSubset(of: Set(appBundle.localizations)))

        // Read the actual compiled tables instead of localizedString, whose
        // English fallback can hide missing translations.
        for ext in ["strings", "stringsdict"] {
            let english = try table(language: "en", extension: ext)
            XCTAssertFalse(english.isEmpty)
            for language in ["pt", "es"] {
                let translated = try table(language: language, extension: ext)
                XCTAssertEqual(Set(translated.keys), Set(english.keys), "Incomplete \(language).\(ext)")
            }
        }
        XCTAssertGreaterThan(try table(language: "en", extension: "strings").count, 60)
    }

    func testNativeLanguageMatchingIncludesRegionalVariantsAndFallback() {
        let available = appBundle.localizations
        for (preferences, expected) in [
            (["pt-BR", "en"], "pt"), (["pt-PT", "en"], "pt"),
            (["es-MX", "en"], "es"), (["es-ES", "en"], "es"),
            (["en-GB", "pt"], "en"), (["fr", "es-MX", "en"], "es")
        ] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: preferences).first, expected)
        }
    }

    func testModelStringsUseTheAppLanguage() throws {
        // Run this suite with xcodebuild -testLanguage en / pt / es. These are
        // fresh host launches, so both Foundation and SwiftUI use native selection.
        let language = try XCTUnwrap(appBundle.preferredLocalizations.first)
        let expected = try XCTUnwrap([
            "en": ["On battery", "Charging", "Fully charged", "Plugged in · not charging", "Status unavailable",
                   "Leaving the battery", "Entering the battery", "No battery power flow", "Reading unavailable",
                   "Until full", "Time remaining", "On external power", "Estimating…"],
            "pt": ["Usando a bateria", "Carregando", "Carga completa", "Conectado · sem carregar", "Estado indisponível",
                   "Saindo da bateria", "Entrando na bateria", "Sem fluxo de energia na bateria", "Leitura indisponível",
                   "Até completar", "Tempo restante", "Na alimentação externa", "Calculando…"],
            "es": ["Usando la batería", "Cargando", "Carga completa", "Conectado · sin cargar", "Estado no disponible",
                   "Saliendo de la batería", "Entrando en la batería", "Sin flujo de energía en la batería", "Lectura no disponible",
                   "Hasta completar", "Tiempo restante", "Con alimentación externa", "Calculando…"]
        ][language], "Unexpected app language: \(language)")

        let states: [BatteryReading.State] = [.discharging, .charging, .charged, .pluggedIn, .unknown]
        var actual = states.map(\.localizedTitle)
        actual += [6.9, -6.9, 0, nil].map { BatteryReading(watts: $0).flowText }
        actual += [BatteryReading(state: .charging).timeTitle, BatteryReading().timeTitle,
                   BatteryReading(state: .pluggedIn).timeText, BatteryReading().timeText]
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(BatteryReading(state: .charged).timeText, expected[2])
        XCTAssertEqual(BatteryReading.State.discharging.rawValue, "On battery", "Identity must remain language-independent")
    }

    func testDurationBoundariesUseLocalizedUnits() throws {
        let language = try XCTUnwrap(appBundle.preferredLocalizations.first)
        let expected = language == "en" ? ["0m", "1m", "59m", "1h 0m", "1h 1m", "2h 11m"]
            : ["0 min", "1 min", "59 min", "1 h 0 min", "1 h 1 min", "2 h 11 min"]
        let actual = [0, 1, 59, 60, 61, 131].map { BatteryReading(minutesRemaining: $0).timeText }
        XCTAssertEqual(actual, expected)
    }

    func testPluralCountsInTheSelectedLanguage() throws {
        let language = try XCTUnwrap(appBundle.preferredLocalizations.first)
        let expected = try XCTUnwrap([
            "en": ["0 utilities active", "1 utility active", "2 utilities active"],
            "pt": ["0 utilitário ativo", "1 utilitário ativo", "2 utilitários ativos"],
            "es": ["0 utilidades activas", "1 utilidad activa", "2 utilidades activas"]
        ][language])
        let badges = try XCTUnwrap([
            "en": ["0 ON", "1 ON", "2 ON"],
            "pt": ["0 ATIVO", "1 ATIVO", "2 ATIVOS"],
            "es": ["0 ACTIVAS", "1 ACTIVA", "2 ACTIVAS"]
        ][language])
        for count in 0...2 {
            let text = String(localized: "\(count) utilities active", bundle: appBundle)
            XCTAssertEqual(text, expected[count])
            XCTAssertEqual(String(localized: "\(count) ON", bundle: appBundle), badges[count])
        }
    }

    func testRegionalNumberFormattingPreservesScaleAndDirection() {
        // POSIX gives a deterministic decimal point even when the user has
        // customized the separators for the current region in System Settings.
        for (identifier, decimal) in [("en_US_POSIX", "."), ("pt_BR", ","), ("es_ES", ",")] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(BatteryReading.formatPower(6.9, locale: locale), "+6\(decimal)9 W")
            XCTAssertEqual(BatteryReading.formatPower(-6.9, locale: locale), "-6\(decimal)9 W")
            XCTAssertEqual(BatteryReading.formatPower(6.9, signed: false, locale: locale), "6\(decimal)9 W")
            for percent in [0.0, 50, 100] {
                let text = BatteryReading.formatPercent(percent, locale: locale)
                XCTAssertTrue(text.hasPrefix(String(Int(percent))), text)
                XCTAssertTrue(text.hasSuffix("%"), text)
            }
        }
        XCTAssertEqual(BatteryReading().percentText, "—")
        XCTAssertEqual(BatteryReading().signedPowerText, "—")
        XCTAssertEqual(BatteryReading(watts: -6.9).powerText, BatteryReading.formatPower(6.9, signed: false))
    }

    @MainActor
    func testBacklightErrorIsLocalizedAndClearsOnRecovery() throws {
        var brightness: Double?
        let state = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { brightness }, writeBrightness: { _ in false }
        ))
        let language = try XCTUnwrap(appBundle.preferredLocalizations.first)
        let expected = try XCTUnwrap([
            "en": "Could not read the built-in keyboard backlight. Try again.",
            "pt": "Não foi possível consultar a iluminação do teclado integrado. Tente novamente.",
            "es": "No se pudo consultar la iluminación del teclado integrado. Vuelve a intentarlo."
        ][language])
        XCTAssertEqual(state.keyboardLightMessage, expected)
        brightness = 0.4
        state.refreshKeyboardLight()
        XCTAssertNil(state.keyboardLightMessage)
    }

    @MainActor
    func testLocalizedPanelsRender() async throws {
        let monitor = BatteryMonitor(startAutomatically: false, readBattery: {
            BatteryReading(availability: .available, percent: 84, state: .pluggedIn,
                           watts: -6.9, healthPercent: 98, cycles: 43)
        })
        monitor.refreshBattery()
        let storage = StorageMonitor(startAutomatically: false, readStorage: {
            StorageReading.decode(totalBytes: 1_000_000_000_000, freeBytes: 420_000_000_000)
        })
        storage.refreshStorage()
        let litKeyboard = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { 0.4 }, writeBrightness: { _ in false }
        ))
        let audioMixer = AudioMixer(hardware: LocalizationAudioHardware())
        try await attachPanel(MenuBarView().environmentObject(litKeyboard).environmentObject(monitor).environmentObject(storage).environmentObject(audioMixer), name: "compact")

        let unavailableKeyboard = AppState(keyboardBacklightController: KeyboardBacklightController(
            readBrightness: { nil }, writeBrightness: { _ in false }
        ))
        try await attachPanel(MenuBarView().environmentObject(unavailableKeyboard).environmentObject(monitor).environmentObject(storage).environmentObject(audioMixer), name: "keyboard-error")
        try await attachPanel(BatteryMenuPanel().environmentObject(monitor).padding(14).frame(width: 380), name: "battery-details")
        try await attachPanel(StorageMenuPanel().environmentObject(storage).padding(14).frame(width: 380), name: "storage-details")
        try await attachPanel(VolumeMenuPanel().environmentObject(audioMixer).padding(14).frame(width: 380), name: "volume-details")
        let noBattery = BatteryMonitor(startAutomatically: false, readBattery: { BatteryReading(availability: .noBattery) })
        noBattery.refreshBattery()
        try await attachPanel(BatteryMenuPanel().environmentObject(noBattery).padding(14).frame(width: 380), name: "no-battery")
        let unavailable = BatteryMonitor(startAutomatically: false, readBattery: { BatteryReading() })
        try await attachPanel(BatteryMenuPanel().environmentObject(unavailable).padding(14).frame(width: 380), name: "battery-unavailable")
    }

    @MainActor
    private func attachPanel<V: View>(_ view: V, name: String) async throws {
        // Hosting through AppKit includes native pickers, progress indicators,
        // and scroll views that ImageRenderer cannot capture.
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(appBundle.preferredLocalizations.first ?? "unknown")-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func table(language: String, extension ext: String) throws -> [String: Any] {
        let url = try XCTUnwrap(appBundle.url(forResource: "Localizable", withExtension: ext, subdirectory: nil, localization: language))
        XCTAssertTrue(url.path.contains("/\(language).lproj/"), "Unexpected fallback: \(url)")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}

@MainActor
private final class LocalizationAudioHardware: AudioHardwareProviding {
    func outputDevices() -> [AudioOutputDevice] {
        [AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", volume: 0.64, isMuted: false,
                           isDefault: true, canSetVolume: true, canSetMute: true)]
    }

    func setVolume(_ volume: Float, for deviceID: UInt32) -> Bool { true }

    func setMuted(_ muted: Bool, for deviceID: UInt32) -> Bool { true }
}
