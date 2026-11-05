import AppKit
import QuartzCore

/// A click-through pill near the bottom of the screen: a pulsing red dot, "Listening…"
/// and live voice bars while recording; a spinner and "Transcribing…" afterwards.
/// Grows into a card with the transcript when it couldn't be pasted.
@MainActor
final class IndicatorPanel {
    private static let size = NSSize(width: 200, height: 44)
    private static let cardWidth: CGFloat = 360
    private static let cardInset: CGFloat = 16
    private static let cardDuration: Duration = .seconds(8)
    private static let barCount = 5
    private static let barWeights: [CGFloat] = [0.55, 0.8, 1.0, 0.8, 0.55]

    private let panel: NSPanel
    private let background: NSVisualEffectView
    private let card: NSStackView
    private let cardTranscript = NSTextField(wrappingLabelWithString: "")
    private let dot = CALayer()
    private let spinner: NSProgressIndicator
    private let label = NSTextField(labelWithString: "")
    private let bars: [CALayer]
    private var envelope: CGFloat = 0
    /// Recent envelope values; the outer bars show slightly older ones so movement ripples outward.
    private var history: [CGFloat] = [0, 0, 0]
    private var hideTask: Task<Void, Never>?

    init() {
        let size = Self.size
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .vibrantDark)

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        self.background = background
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.masksToBounds = true
        panel.contentView = background

        dot.backgroundColor = NSColor.systemRed.cgColor
        dot.cornerRadius = 6
        dot.frame = CGRect(x: 18, y: (size.height - 12) / 2, width: 12, height: 12)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        dot.add(pulse, forKey: "pulse")
        background.layer?.addSublayer(dot)

        spinner = NSProgressIndicator(frame: NSRect(x: 15, y: (size.height - 18) / 2, width: 18, height: 18))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        background.addSubview(spinner)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 42, y: (size.height - 18) / 2, width: 110, height: 18)
        background.addSubview(label)

        bars = (0..<Self.barCount).map { index in
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = 2
            bar.frame = CGRect(x: 150 + CGFloat(index) * 7, y: size.height / 2 - 2, width: 4, height: 4)
            background.layer?.addSublayer(bar)
            return bar
        }

        let cardTitle = NSTextField(labelWithString: "Couldn’t paste. Your text is copied.")
        cardTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        cardTitle.textColor = .white
        cardTranscript.font = .systemFont(ofSize: 13)
        cardTranscript.textColor = .white.withAlphaComponent(0.8)
        cardTranscript.maximumNumberOfLines = 3
        cardTranscript.cell?.truncatesLastVisibleLine = true
        cardTranscript.preferredMaxLayoutWidth = Self.cardWidth - 2 * Self.cardInset
        let cardHint = NSTextField(labelWithString: "Click where you want it and press ⌘V.")
        cardHint.font = .systemFont(ofSize: 12)
        cardHint.textColor = .white.withAlphaComponent(0.6)
        card = NSStackView(views: [cardTitle, cardTranscript, cardHint])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 6
        card.isHidden = true
        card.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.cardInset),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth - 2 * Self.cardInset),
            card.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.cardInset - 2),
        ])
    }

    func showListening() {
        envelope = 0
        history = [0, 0, 0]
        update(level: 0)
        show("Listening…", listening: true)
    }

    func showTranscribing() {
        show("Transcribing…", listening: false)
        spinner.startAnimation(nil)
    }

    /// Shows a short message, then hides.
    func showMessage(_ text: String) {
        show(text, listening: false)
        hide(after: .seconds(1.5))
    }

    /// Shows the start of a transcript that's on the clipboard, because it couldn't be pasted.
    func showNotPasted(_ transcript: String) {
        hideTask?.cancel()
        spinner.stopAnimation(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.isHidden = true
        bars.forEach { $0.isHidden = true }
        CATransaction.commit()
        label.isHidden = true
        cardTranscript.stringValue = transcript
        card.isHidden = false
        card.layoutSubtreeIfNeeded()
        place(size: NSSize(width: Self.cardWidth, height: card.fittingSize.height + 2 * (Self.cardInset - 2)), cornerRadius: 14)
        hide(after: Self.cardDuration)
    }

    func hide(after delay: Duration = .zero) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            spinner.stopAnimation(nil)
            panel.orderOut(nil)
        }
    }

    /// Call ~30 times a second while listening with the current voice level (0...1).
    func update(level: Float) {
        let target = CGFloat(level)
        envelope += (target - envelope) * (target > envelope ? 0.5 : 0.15)  // fast attack, slow release
        history = [envelope, history[0], history[1]]
        let (center, inner, outer) = (history[0], history[1], history[2])

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, (level, weight)) in zip(bars, zip([outer, inner, center, inner, outer], Self.barWeights)) {
            let jitter = level > 0.05 ? CGFloat.random(in: 0.85...1) : 1
            let height = 4 + level * weight * jitter * 24
            bar.frame.origin.y = (Self.size.height - height) / 2
            bar.frame.size.height = height
        }
        CATransaction.commit()
    }

    private func show(_ text: String, listening: Bool) {
        hideTask?.cancel()
        label.stringValue = text
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.isHidden = !listening
        bars.forEach { $0.isHidden = !listening }
        CATransaction.commit()
        spinner.stopAnimation(nil)
        card.isHidden = true
        label.isHidden = false
        place(size: Self.size, cornerRadius: Self.size.height / 2)
    }

    private func place(size: NSSize, cornerRadius: CGFloat) {
        background.layer?.cornerRadius = cornerRadius
        // Show it on the screen the person is working on (where the pointer is).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 90, width: size.width, height: size.height),
                           display: true)
        }
        panel.orderFrontRegardless()
    }
}
