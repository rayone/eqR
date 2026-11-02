import AppKit
import SwiftUI

/// Quick EQ body: the compact live response graph above three tone sliders
/// (Bass / Mid / Treble). Dragging a slider calls back with the axis and its
/// snapped value; `refreshGraph` redraws the curve from the new chain.
@MainActor
final class QuickEQBodyView: NSView {
    enum Axis: Int, CaseIterable {
        case bass, mid, treble, spatial
        var title: String {
            switch self {
            case .bass:
                return String(localized: "Bass", comment: "Quick EQ slider: low frequencies")
            case .mid:
                return String(localized: "Mid", comment: "Quick EQ slider: middle frequencies")
            case .treble:
                return String(localized: "Treble", comment: "Quick EQ slider: high frequencies")
            case .spatial:
                return String(localized: "Space", comment: "Quick EQ slider: stereo width")
            }
        }
    }

    private let graphHost: NSHostingView<FrequencyResponseView>
    private var sliders: [Axis: NSSlider] = [:]
    private var axisLabels: [NSTextField] = []
    private let sampleRate: Double
    private let onToneChange: (Axis, Double) -> Void

    init(
        filters: [EQFilter],
        tone: ProfileManager.ToneControls,
        spatialWidth: Double = 1.0,
        sampleRate: Double,
        onToneChange: @escaping (Axis, Double) -> Void
    ) {
        self.sampleRate = sampleRate
        self.onToneChange = onToneChange
        self.graphHost = NSHostingView(
            rootView: FrequencyResponseView(filters: filters, sampleRate: sampleRate, minimal: true)
        )
        super.init(frame: .zero)
        // View-based menu items are sized by Auto Layout: fix the content width
        // and let the vertical stack determine the height.
        translatesAutoresizingMaskIntoConstraints = false

        graphHost.translatesAutoresizingMaskIntoConstraints = false

        let rows = Axis.allCases.map {
            makeSliderRow($0, value: value(for: $0, in: tone, spatialWidth: spatialWidth))
        }
        let stack = NSStackView(views: [graphHost] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: QuickEQMenuMetrics.contentWidth),
            graphHost.heightAnchor.constraint(equalToConstant: QuickEQMenuMetrics.graphHeight),
            graphHost.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: QuickEQMenuMetrics.horizontalInset),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -QuickEQMenuMetrics.horizontalInset),
        ])
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        updateLabelsAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelsAppearance()
    }

    private func updateLabelsAppearance() {
        let color = Theme.isTokyoNight ? Theme.TokyoNight.nsFgDark : .labelColor
        axisLabels.forEach { $0.textColor = color }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Redraws the response curve after a tone change updates the chain.
    func refreshGraph(filters: [EQFilter]) {
        graphHost.rootView = FrequencyResponseView(
            filters: filters, sampleRate: sampleRate, minimal: true)
    }

    private func makeSliderRow(_ axis: Axis, value: Double) -> NSView {
        let name = NSTextField(labelWithString: axis.title)
        name.font = NSFont.menuFont(ofSize: 0)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 48).isActive = true
        axisLabels.append(name)

        let minVal = axis == .spatial ? 0.0 : QuickTone.range.lowerBound
        let maxVal = axis == .spatial ? 2.0 : QuickTone.range.upperBound

        let slider = ToneSlider(
            value: value, minValue: minVal,
            maxValue: maxVal, target: self, action: #selector(sliderChanged(_:))
        )
        slider.isContinuous = true
        slider.tag = axis.rawValue
        // The same gesture the band sliders and the graph's points answer to,
        // so "put it back" is one habit across the app rather than three.
        slider.onDoubleClick = { [weak self] in self?.reset(axis) }
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // The axis alone: the slider's value is the gain, and VoiceOver says
        // that it is a slider.
        slider.setAccessibilityLabel(axis.title)
        sliders[axis] = slider

        // No numeric readout: Control Center sliders never show values, and the
        // live graph above already gives visual feedback.
        let row = NSStackView(views: [name, slider])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// Back to the middle — 0 dB for tone tilts, 1.0 for neutral Space width.
    private func reset(_ axis: Axis) {
        let neutral = axis == .spatial ? 1.0 : 0.0
        sliders[axis]?.doubleValue = neutral
        onToneChange(axis, neutral)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let axis = Axis(rawValue: sender.tag) else { return }
        let snapped: Double
        if axis == .spatial {
            snapped = (sender.doubleValue * 20).rounded() / 20
        } else {
            // Snap to the 0.5 dB step used across the app for a subtle detent.
            snapped = (sender.doubleValue * 2).rounded() / 2
        }
        sender.doubleValue = snapped
        onToneChange(axis, snapped)
    }

    private func value(
        for axis: Axis, in tone: ProfileManager.ToneControls, spatialWidth: Double
    ) -> Double {
        switch axis {
        case .bass: return tone.bass
        case .mid: return tone.mid
        case .treble: return tone.treble
        case .spatial: return spatialWidth
        }
    }
}

/// A tone slider that answers a double-click by centring itself.
///
/// The second click is taken before `NSSlider` sees it, because the slider's
/// own `mouseDown` runs a tracking loop until the button comes up: handing it
/// the click would set the value from wherever the pointer happens to be, and
/// only then would the reset land — a visible flick on the way to the middle.
///
/// The *first* click of the pair still reaches the slider, so a double-click on
/// the track moves the knob there and then centres it. That is what a slider
/// does with a click; the pair still ends where it should.
private final class ToneSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {
        guard Theme.isTokyoNight else {
            super.drawKnob(knobRect)
            return
        }

        let insetRect = knobRect.insetBy(dx: 1, dy: 1)

        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(ovalIn: insetRect)
        Theme.TokyoNight.nsFg.setFill()
        path.fill()

        Theme.TokyoNight.nsBorderHighlight.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
private final class ToneSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { ToneSliderCell.self }
        set { super.cellClass = newValue }
    }

    var onDoubleClick: (() -> Void)?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        updateSliderAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateSliderAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateSliderAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSliderAppearance()
    }

    private func updateSliderAppearance() {
        if Theme.isTokyoNight {
            trackFillColor = isHovered ? Theme.TokyoNight.nsCyan : Theme.TokyoNight.nsBlue
        } else {
            trackFillColor = nil
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}
