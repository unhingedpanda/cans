import AppKit
import SwiftUI

/// The console's material: one panel, grooves, scribble tape, and lamps.
/// Amber is the only "on" lamp; green means only "control link live"; red only "low battery".
/// Light mode is a grey anodized desk with ink legends; dark mode is a charcoal one.
enum Console {
    static let panel = tone(light: 0xDCDDDF, dark: 0x17181A)
    static let raised = tone(light: 0xF1F1F2, dark: 0x222427)
    static let groove = tone(light: 0xB4B6BA, dark: 0x0E0F10)
    static let seam = tone(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.07)
    static let tape = tone(light: 0xF2E9D0, dark: 0xECE9E1)
    static let tapeEdge = tone(light: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0)
    static let tapeInk = tone(light: 0x232220, dark: 0x232220)
    static let legend = tone(light: 0x1C1D20, dark: 0xECE9E1)
    static let dim = tone(light: 0x55575D, dark: 0x94928C)
    static let unlit = tone(light: 0xC2C4C8, dark: 0x3C3E42)
    static let amber = tone(light: 0xE8921F, dark: 0xF2A33A)
    /// Amber for text and thin marks: deep enough for 4.5:1 on the light panel.
    static let amberInk = tone(light: 0x8A4B00, dark: 0xF2A33A)
    static let signal = tone(light: 0x1FA355, dark: 0x46D07A)
    static let alarm = tone(light: 0xD23B3F, dark: 0xE5484D)
    /// Red for text: 5.3:1 on the light panel.
    static let alarmInk = tone(light: 0xA82327, dark: 0xE5484D)
    /// The backlight halo belongs to a dark room; on a daylight panel it reads as a smudge.
    static let glow = tone(light: 0xF2A33A, dark: 0xF2A33A, lightAlpha: 0, darkAlpha: 0.35)

    private static func tone(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        func rgb(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark, darkAlpha) : rgb(light, lightAlpha)
        })
    }

    static func legendFont(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

/// Condensed caps legend, the console's only typographic voice besides values.
struct Legend: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Console.dim

    init(_ text: String, size: CGFloat = 10, color: Color = Console.dim) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Console.legendFont(size))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Backlit push-button. Lit = amber lamp and dark legend; the legend text itself can change with state.
struct LampButton: View {
    let title: String
    var lit: Bool
    var enabled = true
    var height: CGFloat = 30
    var fontSize: CGFloat = 11
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if lit {
                    Circle().fill(Console.tapeInk).frame(width: 4, height: 4)
                }
                Text(title.uppercased())
                    .font(Console.legendFont(fontSize, weight: .bold))
                    .tracking(0.8)
            }
                .foregroundStyle(lit ? Console.tapeInk : (hovering ? Console.legend : Console.dim))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(lit ? Console.amber : Console.raised)
                        .shadow(color: lit ? Console.glow : .black.opacity(0.4),
                                radius: lit ? 6 : 1.5, y: lit ? 0 : 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(lit ? Color.white.opacity(0.25) : Console.seam, lineWidth: 0.75)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = enabled && $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: lit)
        .accessibilityLabel(title.prefix(1).uppercased() + title.dropFirst().lowercased())
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// Latching ON/OFF switch: the legend states the position, the lamp repeats it.
struct LatchButton: View {
    let accessibilityTitle: String
    let isOn: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        LampButton(title: isOn ? "On" : "Off", lit: isOn, enabled: enabled, height: 24, fontSize: 10.5, action: action)
            .frame(width: 52)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityIdentifier("latch.\(accessibilityTitle)")
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Segmented LED ladder: every level in the app reads on this one ramp.
struct LEDLadder: View {
    /// 0...1
    let fraction: Double
    var segments = 10
    var tint: Color = Console.amber
    var segmentSize = CGSize(width: 5, height: 9)
    /// A running segment chase for "working" states; static under Reduce Motion.
    var chasing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if chasing && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.08)) { context in
                let head = Int(context.date.timeIntervalSinceReferenceDate / 0.08) % (segments + 3)
                segmentRow { index in index <= head && index > head - 3 }
            }
        } else {
            staticLadder
        }
    }

    private func segmentRow(lit: @escaping (Int) -> Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit(index) ? tint : Console.unlit)
                    .frame(width: segmentSize.width, height: segmentSize.height)
            }
        }
        .accessibilityHidden(true)
    }

    private var staticLadder: some View {
        let litCount = Int((min(1, max(0, fraction)) * Double(segments)).rounded(.up))
        return HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < litCount ? tint : Console.unlit)
                    .frame(width: segmentSize.width, height: segmentSize.height)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12).delay(Double(index) * 0.015), value: litCount)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Off-white scribble tape with hand-written ink.
struct ScribbleTape: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Console.tapeInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .frame(height: size + 11)
            .background(Console.tape, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Console.tapeEdge, lineWidth: 0.75))
    }
}

/// Vertical fader in a groove. Snaps to device steps with a trackpad tick on each detent.
struct Fader: View {
    let label: String
    let accessibilityName: String
    let value: Int
    let range: ClosedRange<Int>
    var ticks: [Int] = []
    var enabled = true
    var resetValue: Int?
    var format: (Int) -> String = { "\($0)" }
    var tapeLabel: String? = nil
    var dimValue = false
    let onChange: (Int) -> Void

    @State private var dragging = false
    @State private var dragOrigin: (value: Int, y: CGFloat)?
    @FocusState private var focused: Bool
    private let grooveHeight: CGFloat = 112
    private let capSize = CGSize(width: 24, height: 13)

    private var travel: CGFloat { grooveHeight - capSize.height }
    private func position(for v: Int) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        return travel * (1 - CGFloat(v - range.lowerBound) / max(1, span))
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(format(value))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(dragging ? Console.amberInk : (enabled && !dimValue ? Console.legend : Console.dim))
                .frame(height: 13)

            ZStack(alignment: .top) {
                // Scale ticks on both sides of the groove.
                ForEach(ticks, id: \.self) { tick in
                    HStack(spacing: 16) {
                        Rectangle().frame(width: 4, height: 1)
                        Rectangle().frame(width: 4, height: 1)
                    }
                    .foregroundStyle(tick == resetValue ? Console.dim : Console.unlit)
                    .offset(y: position(for: tick) + capSize.height / 2)
                }
                Capsule()
                    .fill(Console.groove)
                    .overlay(Capsule().strokeBorder(Console.seam, lineWidth: 0.5))
                    .frame(width: 4, height: grooveHeight)
                cap.offset(y: position(for: value))
            }
            .frame(minWidth: 34, maxWidth: .infinity, minHeight: grooveHeight, maxHeight: grooveHeight, alignment: .top)
            .contentShape(Rectangle())
            .gesture(drag)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if enabled, let resetValue { onChange(resetValue) }
            })

            if let tapeLabel {
                // While riding the fader, its tape shows the live value in amber.
                Text(dragging ? format(value) : tapeLabel.uppercased())
                    .font(Console.legendFont(10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(dragging ? Console.amber : Console.tapeInk)
                    .frame(minWidth: 34, maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                    .background(dragging ? Console.tapeInk : .clear, in: RoundedRectangle(cornerRadius: 2))
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .overlay(alignment: .top) {
            if focused {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Console.amberInk, lineWidth: 1)
                    .frame(width: 40, height: grooveHeight + 21)
            }
        }
        .onKeyPress(.upArrow) { step(+1) }
        .onKeyPress(.downArrow) { step(-1) }
        // Accessibility last, so nothing added above wraps the element and hides its value.
        // Assistive tech sees a real slider (label, value, adjustable) instead of a drawn fader.
        .accessibilityRepresentation {
            Slider(value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                Text(accessibilityName)
            }
            .accessibilityValue(format(value))
            .disabled(!enabled)
        }
        .help(label)
    }

    private var cap: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Console.raised)
            .overlay {
                Rectangle()
                    .fill(dragging ? Console.amber : Console.legend.opacity(0.85))
                    .frame(height: 1.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Console.seam, lineWidth: 0.75)
            }
            .frame(width: capSize.width, height: capSize.height)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard enabled else { return .ignored }
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        if next != value { onChange(next) }
        return .handled
    }

    /// Relative drag: the cap moves by how far you drag, never jumps to where you clicked.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                guard enabled else { return }
                dragging = true
                let origin = dragOrigin ?? (value, gesture.startLocation.y)
                dragOrigin = origin
                let span = Double(range.upperBound - range.lowerBound)
                let delta = Double(origin.y - gesture.location.y) / Double(travel) * span
                let snapped = min(range.upperBound, max(range.lowerBound, origin.value + Int(delta.rounded())))
                if snapped != value {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    onChange(snapped)
                }
            }
            .onEnded { _ in
                dragging = false
                dragOrigin = nil
            }
    }
}

/// A rack unit row: title and optional detail on the left, the control on the right.
/// One settings row on a fixed grid: text on the left, the control right-aligned in a
/// fixed-width column, so every control across every section lines up.
struct RackRow<Control: View>: View {
    static var controlColumn: CGFloat { 184 }
    let title: String
    var detail: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Console.legend)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Console.dim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
                .frame(width: Self.controlColumn, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Console.seam).frame(height: 1) }
    }
}

/// A label/value line for read-only facts.
struct InfoRow: View {
    let label: String
    let value: String
    var warning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Console.dim)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .foregroundStyle(Console.legend)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 6)
    }
}

/// A small selector made of lamp buttons, exactly one lit.
struct LampSelector<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    let selection: Value?
    var width: CGFloat? = RackRow<EmptyView>.controlColumn
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                LampButton(title: option.title, lit: option.value == selection, height: 24, fontSize: 10.5) {
                    onSelect(option.value)
                }
            }
        }
        .frame(width: width)
    }
}

/// A rack unit: heading on the panel, a groove underneath, rows inside.
struct RackUnit<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        // A flush faceplate: full width, square, separated from the next unit by a groove.
        VStack(alignment: .leading, spacing: 2) {
            Legend(title, size: 11, color: Console.legend)
                .padding(.bottom, 2)
            content()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { GrooveSeam() }
    }
}

/// A small amber lamp: something here is waiting for you (an update). Pulses once as it lights.
struct UpdatePip: View {
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Console.amber)
            .frame(width: 6, height: 6)
            .shadow(color: Console.glow, radius: lit ? 4 : 0)
            .opacity(lit || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { lit = true } }
            .accessibilityHidden(true)
    }
}

/// A recessed groove between panel sections.
struct GrooveSeam: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Console.groove).frame(height: 1)
            Rectangle().fill(Console.seam).frame(height: 1)
        }
    }
}

/// The headphones on the channel: an illustration per model, alive with the mode.
/// Ambient: sound waves flow into the cups (more with a higher level). NC: a slow sealed ring.
/// Off: still. Click the headphones five times for a small party. All motion is Core Animation,
/// so it runs in the window server with no per-frame app work, and none under Reduce Motion.
struct ChannelPortrait: View {
    let modelName: String
    let mode: NoiseControlMode?
    let ambientLevel: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    @State private var partyToken = 0

    var body: some View {
        PortraitLayers(
            imageName: modelName.localizedCaseInsensitiveContains("XM5") ? "HeadphonesXM5" : "HeadphonesXM4",
            mode: mode, ambientLevel: ambientLevel, animated: !reduceMotion, partyToken: partyToken
        )
        .frame(width: 150, height: 124)
        .contentShape(Rectangle())
        .onTapGesture {
            taps += 1
            if taps >= 5 {
                taps = 0
                partyToken += 1
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PortraitLayers: NSViewRepresentable {
    let imageName: String
    let mode: NoiseControlMode?
    let ambientLevel: Int
    let animated: Bool
    let partyToken: Int

    func makeNSView(context: Context) -> PortraitLayerView { PortraitLayerView() }

    func updateNSView(_ view: PortraitLayerView, context: Context) {
        view.configure(image: NSImage(named: imageName), mode: mode, ambientLevel: ambientLevel,
                       animated: animated, partyToken: partyToken)
    }
}

final class PortraitLayerView: NSView {
    private let imageLayer = CALayer()
    private let effects = CALayer()
    private var signature = ""
    private var lastParty = 0
    private var lastConfig: (mode: NoiseControlMode?, level: Int, animated: Bool)?
    private var lastMode: NoiseControlMode??
    private let sheen = CAGradientLayer()

    /// Geometry of scripts/illustrations.py (viewBox 400x350): the near cup's outer face and the far cup.
    private enum Art {
        static let size = CGSize(width: 400, height: 350)
        static let nearCup = (center: CGPoint(x: 138, y: 226), rx: 64.0, ry: 82.0, rotation: -8.0)
        static let farCup = CGPoint(x: 298, y: 210)
    }

    private static let artBox = CGSize(width: 142, height: 114)

    /// Converts an illustration point into the image layer's (bottom-left origin) coordinates.
    private func art(_ p: CGPoint) -> CGPoint {
        let box = Self.artBox
        let scale = min(box.width / Art.size.width, box.height / Art.size.height)
        let offset = CGPoint(x: (box.width - Art.size.width * scale) / 2, y: (box.height - Art.size.height * scale) / 2)
        return CGPoint(x: offset.x + p.x * scale, y: box.height - (offset.y + p.y * scale))
    }

    private var artScale: CGFloat { min(Self.artBox.width / Art.size.width, Self.artBox.height / Art.size.height) }

    /// The same point in this view's coordinates (the image layer is centred in the view).
    private func artInView(_ p: CGPoint) -> CGPoint {
        let point = art(p)
        return CGPoint(x: point.x + (bounds.width - Self.artBox.width) / 2, y: point.y + (bounds.height - Self.artBox.height) / 2)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true  // effects stay inside the portrait, never over the readouts
        layer?.addSublayer(effects)
        layer?.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effects.frame = bounds
        // A few points of headroom so the idle float never clips the band against the frame.
        imageLayer.bounds = CGRect(origin: .zero, size: Self.artBox)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        if let config = lastConfig, !signature.hasSuffix("\(bounds.size)") {
            signature = ""  // geometry changed: rebuild effects for it
            rebuildIfNeeded(mode: config.mode, ambientLevel: config.level, animated: config.animated)
        }
    }

    func configure(image: NSImage?, mode: NoiseControlMode?, ambientLevel: Int, animated: Bool, partyToken: Int) {
        if let previous = lastMode, previous != mode, animated { pop() }
        lastMode = .some(mode)
        imageLayer.contents = image
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.opacity = mode == .off ? 0.72 : 1
        lastConfig = (mode, ambientLevel, animated)
        rebuildIfNeeded(mode: mode, ambientLevel: ambientLevel, animated: animated)
        if partyToken != lastParty {
            lastParty = partyToken
            if animated { party() }
        }
    }

    private func rebuildIfNeeded(mode: NoiseControlMode?, ambientLevel: Int, animated: Bool) {
        let next = "\(String(describing: mode))-\(ambientLevel / 5)-\(animated)-\(bounds.size)"
        guard next != signature, bounds.width > 0 else { return }
        signature = next
        rebuildEffects(mode: mode, ambientLevel: ambientLevel, animated: animated)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        signature = ""
        if let config = lastConfig { rebuildIfNeeded(mode: config.mode, ambientLevel: config.level, animated: config.animated) }
    }

    private func cgColor(_ color: Color) -> CGColor {
        var resolved = NSColor(color).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = NSColor(color).cgColor }
        return resolved
    }

    private func rebuildEffects(mode: NoiseControlMode?, ambientLevel: Int, animated: Bool) {
        effects.sublayers?.forEach { $0.removeFromSuperlayer() }
        sheen.removeFromSuperlayer()
        imageLayer.removeAnimation(forKey: "float")
        guard animated else { return }

        if mode != .off { addSheen() }

        // NC is calm: a slower, smaller drift. Ambient is lighter on its feet.
        let float = CABasicAnimation(keyPath: "position.y")
        float.byValue = mode == .anc ? 1.8 : 3.5
        float.duration = mode == .anc ? 3.4 : 2.3
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if mode != .off { imageLayer.add(float, forKey: "float") }

        let amber = cgColor(Console.amber)
        switch mode {
        case .ambient:
            // Arcs travel inward to each cup; count and brightness follow the level.
            let count = 1 + ambientLevel / 5
            let peak = Float(0.3 + 0.45 * Double(ambientLevel) / 20)
            // Sound arrives from outside: from the left into the near cup, from the right into the far one.
            for (side, cup) in [(-1.0, artInView(Art.nearCup.center)), (1.0, artInView(Art.farCup))] {
                for i in 0..<count {
                    let arc = CAShapeLayer()
                    arc.fillColor = nil
                    arc.strokeColor = amber
                    arc.lineWidth = 1.6
                    arc.lineCap = .round
                    arc.opacity = 0
                    let start = side < 0 ? CGFloat.pi * 0.78 : -CGFloat.pi * 0.22
                    func path(_ r: CGFloat) -> CGPath {
                        let p = CGMutablePath()
                        p.addArc(center: cup, radius: r, startAngle: start, endAngle: start + .pi * 0.44, clockwise: false)
                        return p
                    }
                    let near = 30 * artScale / 0.354, far = 50 * artScale / 0.354
                    arc.path = path(near)
                    let travel = CABasicAnimation(keyPath: "path")
                    travel.fromValue = path(far)
                    travel.toValue = path(near)
                    let fade = CAKeyframeAnimation(keyPath: "opacity")
                    fade.values = [0, peak, 0]
                    fade.keyTimes = [0, 0.5, 1]
                    let group = CAAnimationGroup()
                    group.animations = [travel, fade]
                    group.duration = 1.7
                    group.repeatCount = .infinity
                    group.beginTime = CACurrentMediaTime() + 1.7 * Double(i) / Double(count)
                    arc.add(group, forKey: "wave")
                    effects.addSublayer(arc)
                }
            }
        case .anc:
            // A slow ring settling around the headphones: the world sealed out.
            let ring = CAShapeLayer()
            ring.fillColor = nil
            ring.strokeColor = cgColor(Console.legend)
            ring.lineWidth = 1
            ring.opacity = 0
            func oval(_ r: CGFloat) -> CGPath {
                CGPath(ellipseIn: CGRect(x: bounds.midX - r, y: bounds.midY - r * 0.86, width: r * 2, height: r * 1.72), transform: nil)
            }
            ring.path = oval(58)
            let settle = CABasicAnimation(keyPath: "path")
            settle.fromValue = oval(72)
            settle.toValue = oval(58)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.12, 0]
            let group = CAAnimationGroup()
            group.animations = [settle, fade]
            group.duration = 4
            group.repeatCount = .infinity
            ring.add(group, forKey: "seal")
            effects.addSublayer(ring)
        default:
            break
        }
    }

    /// A soft highlight sweeping across the matte cup every few seconds, clipped to the cup.
    private func addSheen() {
        sheen.frame = CGRect(origin: .zero, size: Self.artBox)
        sheen.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.14).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        sheen.locations = [-0.4, -0.25, -0.1]  // rests off the cup between sweeps
        sheen.startPoint = CGPoint(x: 0, y: 0.8)
        sheen.endPoint = CGPoint(x: 1, y: 0.2)
        let cup = art(Art.nearCup.center), s = artScale
        let mask = CAShapeLayer()
        var transform = CGAffineTransform(translationX: cup.x, y: cup.y)
            .rotated(by: CGFloat(-Art.nearCup.rotation) * .pi / 180)
        mask.path = CGPath(ellipseIn: CGRect(x: -Art.nearCup.rx * s, y: -Art.nearCup.ry * s,
                                             width: 2 * Art.nearCup.rx * s, height: 2 * Art.nearCup.ry * s),
                           transform: &transform)
        sheen.mask = mask
        let sweep = CAKeyframeAnimation(keyPath: "locations")
        sweep.values = [[-0.4, -0.25, -0.1], [-0.4, -0.25, -0.1], [1.1, 1.25, 1.4], [1.1, 1.25, 1.4]]
        sweep.keyTimes = [0, 0.62, 0.82, 1]
        sweep.duration = 6.5
        sweep.repeatCount = .infinity
        sweep.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .linear)]
        sheen.add(sweep, forKey: "sweep")
        imageLayer.addSublayer(sheen)
    }

    /// A small physical "pop" when the listening mode changes.
    private func pop() {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1, 1.045, 0.99, 1]
        bounce.keyTimes = [0, 0.35, 0.7, 1]
        bounce.duration = 0.45
        imageLayer.add(bounce, forKey: "pop")
    }

    /// Five clicks: the headphones bob to a beat and notes float up for three seconds.
    private func party() {
        let bob = CAKeyframeAnimation(keyPath: "transform")
        bob.values = (0..<9).map { i in
            let angle = (i % 2 == 0 ? 1.0 : -1.0) * 0.08
            return NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 0, 1),
                                                              CATransform3DMakeTranslation(0, i % 2 == 0 ? 6 : 0, 0)))
        } + [NSValue(caTransform3D: CATransform3DIdentity)]
        bob.duration = 3
        imageLayer.add(bob, forKey: "party")

        let symbols = ["music.note", "music.quarternote.3", "music.note"]
        for (i, name) in symbols.enumerated() {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)
                    .applying(.init(paletteColors: [NSColor(Console.amber)]))) else { continue }
            let note = CALayer()
            note.contents = base
            note.contentsScale = window?.backingScaleFactor ?? 2
            note.frame = CGRect(x: bounds.midX - 7 + CGFloat(i - 1) * 42, y: bounds.midY + 10, width: 14, height: 16)
            note.opacity = 0
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.byValue = 50
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 1.2
            group.repeatCount = 2.5
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.35
            group.isRemovedOnCompletion = true
            note.add(group, forKey: "note")
            effects.addSublayer(note)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { note.removeFromSuperlayer() }
        }
    }
}
