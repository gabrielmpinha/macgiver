import AppKit
import OSLog
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
final class TextExtractorController {
    private var selectionPanel: TextSelectionPanel?
    private var resultPanel: NSPanel?
    private var extractionTask: Task<Void, Never>?
    private let captureRequest = ScreenCaptureRequest()
    private var capturedImage: CGImage?
    private var capturedScreenFrame = CGRect.zero

    func begin() {
        captureRequest.cancel()
        extractionTask?.cancel()
        extractionTask = nil
        cancelSelection()
        resultPanel?.orderOut(nil)

        guard let screen = Self.screen(containing: NSEvent.mouseLocation) else {
            showMessage(String(localized: "Could not find the active display. Try again."))
            return
        }

        captureRequest.start(operation: {
            try await ScreenCapture.image(for: screen)
        }, completion: { [weak self] result in
            switch result {
            case .success(let image):
                self?.beginSelection(image: image, screen: screen)
            case .failure(let error):
                self?.showMessage(ScreenCapture.failure(for: error).localizedDescription)
            }
        })
    }

    private func beginSelection(image: CGImage, screen: NSScreen) {
        capturedImage = image
        capturedScreenFrame = screen.frame

        let panel = TextSelectionPanel(frame: screen.frame)
        panel.onSelection = { [weak self, weak panel] selection in
            self?.finishSelection(selection, from: panel)
        }
        panel.onCancel = { [weak self] in
            self?.cancelSelection()
        }
        selectionPanel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    private func finishSelection(_ selection: CGRect, from panel: TextSelectionPanel?) {
        guard let panel, panel === selectionPanel else { return }

        panel.orderOut(nil)
        selectionPanel = nil

        guard let image = capturedImage,
              let crop = ScreenCapture.crop(image: image, selection: selection, in: capturedScreenFrame)
        else {
            capturedImage = nil
            showMessage(String(localized: "Select a larger area to extract text."))
            return
        }

        capturedImage = nil
        showProcessing()

        extractionTask = Task { [weak self] in
            do {
                let text = try await TextRecognitionService.recognize(crop)
                guard !Task.isCancelled else { return }
                self?.showText(text)
            } catch {
                guard !Task.isCancelled else { return }
                self?.showMessage(error.localizedDescription)
            }
        }
    }

    private func cancelSelection() {
        selectionPanel?.orderOut(nil)
        selectionPanel = nil
        capturedImage = nil
    }

    private func showProcessing() {
        presentResult(
            title: String(localized: "Text Extractor"),
            text: nil,
            message: String(localized: "Extracting text…"),
            isProcessing: true
        )
    }

    private func showText(_ text: String) {
        extractionTask = nil
        presentResult(
            title: String(localized: "Extracted Text"),
            text: text,
            message: nil,
            isProcessing: false
        )
    }

    private func showMessage(_ message: String) {
        presentResult(
            title: String(localized: "Text Extractor"),
            text: nil,
            message: message,
            isProcessing: false
        )
    }

    private func presentResult(title: String, text: String?, message: String?, isProcessing: Bool) {
        let content = TextExtractorResultView(
            text: text,
            message: message,
            isProcessing: isProcessing,
            onCopy: { [weak self] in self?.copy(text) }
        )
        let host = NSHostingView(rootView: content)
        let panel = resultPanel ?? makeResultPanel()

        panel.title = title
        panel.contentView = host
        panel.setContentSize(TextExtractorResultView.contentSize(hasText: text != nil))
        if !panel.isVisible {
            panel.center()
        }

        resultPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeResultPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: TextExtractorResultView.contentSize(hasText: true)),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = TextExtractorResultView.contentSize(hasText: false)
        return panel
    }

    private func copy(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

struct TextExtractorResultView: View {
    let text: String?
    let message: String?
    let isProcessing: Bool
    let onCopy: () -> Void

    @State private var didCopy = false

    static func contentSize(hasText: Bool) -> NSSize {
        hasText ? NSSize(width: 520, height: 340) : NSSize(width: 420, height: 180)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: isProcessing ? "text.viewfinder" : text == nil ? "exclamationmark.triangle" : "doc.text.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isProcessing ? MacGiverPalette.accent : text == nil ? MacGiverPalette.warm : MacGiverPalette.accent)
                Text(text == nil ? "Text Extractor" : "Extracted Text")
                    .font(.headline)
                Spacer()
            }

            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                }

                HStack {
                    Text("Select text or copy everything below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(didCopy ? "Copied" : "Copy All", action: copyAll)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            } else if isProcessing {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message ?? "Extracting text…")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                Text(message ?? "Could not extract text.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(
            width: Self.contentSize(hasText: text != nil).width,
            height: Self.contentSize(hasText: text != nil).height,
            alignment: .topLeading
        )
    }

    private func copyAll() {
        onCopy()
        didCopy = true
    }
}

private final class TextSelectionPanel: NSPanel {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let view = TextSelectionView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.onSelection = { [weak self] selection in
            self?.onSelection?(selection)
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
        }

        contentView = view
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TextSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        if let selection = selectionRect {
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            selection.fill()

            NSColor.white.withAlphaComponent(0.94).setStroke()
            let border = NSBezierPath(roundedRect: selection, xRadius: 4, yRadius: 4)
            border.lineWidth = 2
            border.stroke()
        } else {
            drawInstruction()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selection = selectionRect, selection.width >= 8, selection.height >= 8 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        onSelection?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawInstruction() {
        let message = String(localized: "Drag to highlight an area · Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let pillRect = CGRect(
            x: bounds.midX - textSize.width / 2 - 16,
            y: bounds.midY - textSize.height / 2 - 9,
            width: textSize.width + 32,
            height: textSize.height + 18
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10).fill()
        (message as NSString).draw(
            at: CGPoint(x: pillRect.minX + 16, y: pillRect.minY + 9),
            withAttributes: attributes
        )
    }
}

/// A superseded capture must never reopen a selection panel or display a stale error.
@MainActor
final class ScreenCaptureRequest {
    private var task: Task<Void, Never>?

    @discardableResult
    func start(
        operation: @escaping @MainActor () async throws -> CGImage,
        completion: @escaping @MainActor (Result<CGImage, Error>) -> Void
    ) -> Task<Void, Never> {
        cancel()
        let task = Task {
            let result: Result<CGImage, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            completion(result)
        }
        self.task = task
        return task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

enum ScreenCapture {
    enum Failure: LocalizedError {
        case permissionDenied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return String(localized: "Allow Screen Recording access for MacGiver in System Settings > Privacy & Security > Screen Recording, then try again.")
            case .unavailable:
                return String(localized: "Could not capture the display. Try again.")
            }
        }
    }

    static func failure(for error: Error) -> Failure {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == SCStreamError.userDeclined.rawValue {
            return .permissionDenied
        }
        Logger(subsystem: "com.macgiver.app", category: "TextExtractor")
            .error("Screen capture failed: \(error.domain, privacy: .public) (\(error.code))")
        return .unavailable
    }

    @MainActor
    static func image(for screen: NSScreen) async throws -> CGImage {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayID = screen.deviceDescription[screenNumberKey] as? CGDirectDisplayID else {
            throw Failure.unavailable
        }

        // Let ScreenCaptureKit request/enforce access. A preflight result can be stale
        // after authorization changes and must not prevent a real capture attempt.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.unavailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return image
    }

    static func crop(image: CGImage, selection: CGRect, in screenFrame: CGRect) -> CGImage? {
        let cropRect = pixelCropRect(
            imageSize: CGSize(width: image.width, height: image.height),
            selection: selection,
            screenFrame: screenFrame
        )
        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }
        return image.cropping(to: cropRect)
    }

    static func pixelCropRect(imageSize: CGSize, selection: CGRect, screenFrame: CGRect) -> CGRect {
        let localSelection = selection.standardized
        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        return CGRect(
            x: localSelection.minX * scaleX,
            y: (screenFrame.height - localSelection.maxY) * scaleY,
            width: localSelection.width * scaleX,
            height: localSelection.height * scaleY
        )
        .intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        .integral
    }
}

enum TextRecognitionService {
    enum RecognitionError: LocalizedError {
        case noText
        case failed

        var errorDescription: String? {
            switch self {
            case .noText:
                return String(localized: "No text was found in that area. Try a larger or sharper selection.")
            case .failed:
                return String(localized: "Could not recognize text in that area. Try again with a clearer selection.")
            }
        }
    }

    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])

                    let lines = request.results?.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    } ?? []

                    guard let text = normalizedText(lines) else {
                        throw RecognitionError.noText
                    }
                    continuation.resume(returning: text)
                } catch let error as RecognitionError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: RecognitionError.failed)
                }
            }
        }
    }

    static func normalizedText(_ lines: [String]) -> String? {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedLines.isEmpty else { return nil }
        return cleanedLines.joined(separator: "\n")
    }
}
