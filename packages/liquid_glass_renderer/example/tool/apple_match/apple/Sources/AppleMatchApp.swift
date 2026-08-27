import SwiftUI

@main
struct AppleMatchApp: App {
    private let scene: Scene
    private let probe: String

    init() {
        let sceneURL: URL
        if let path = Arguments.value(after: "--scene") {
            sceneURL = URL(fileURLWithPath: path)
        } else {
            let sceneID = Arguments.value(after: "--scene-id") ?? "toolbar_capsule"
            sceneURL = Bundle.main.url(forResource: sceneID, withExtension: "json")!
        }
        let data = try! Data(contentsOf: sceneURL)
        scene = try! JSONDecoder().decode(Scene.self, from: data)
        probe = Arguments.value(after: "--probe") ?? "A"
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            MatchView(scene: scene, probeID: probe)
                .preferredColorScheme(scene.appearance == "dark" ? .dark : .light)
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct MatchView: View {
    let scene: Scene
    let probeID: String

    private var probe: Scene.Probe {
        scene.probes.first(where: { $0.id == probeID })!
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProbeBackground(spec: probe.background)
                .frame(
                    width: scene.canvas.logicalWidth,
                    height: scene.canvas.logicalHeight
                )

            if scene.profile == "tab_bar_holdout" {
                TabView {
                    ProbeBackground(spec: probe.background)
                        .ignoresSafeArea()
                        .tabItem { Label("First", systemImage: "circle.fill") }
                    ProbeBackground(spec: probe.background)
                        .ignoresSafeArea()
                        .tabItem { Label("Second", systemImage: "square.fill") }
                    ProbeBackground(spec: probe.background)
                        .ignoresSafeArea()
                        .tabItem { Label("Third", systemImage: "triangle.fill") }
                }
                .frame(
                    width: scene.canvas.logicalWidth,
                    height: scene.canvas.logicalHeight
                )
                .accessibilityIdentifier("official-glass-tab-bar")
            } else if scene.profile == "loupe" {
                LoupeProbeView()
                    .frame(
                        width: scene.canvas.logicalWidth,
                        height: scene.canvas.logicalHeight
                    )
                    .accessibilityIdentifier("loupe-field")
            } else if scene.profile == "material_shape", #available(iOS 26.0, *) {
                Color.clear
                    .frame(
                        width: scene.shape.width,
                        height: scene.shape.height
                    )
                    .glassEffect(
                        .regular,
                        in: ReferenceGlassShape(
                            kind: scene.shape.kind,
                            cornerRadius: scene.shape.cornerRadius
                        )
                    )
                    .position(
                        x: scene.shape.x + scene.shape.width / 2,
                        y: scene.shape.y + scene.shape.height / 2
                    )
                    .accessibilityIdentifier("official-glass-shape")
            } else if #available(iOS 26.0, *) {
                Button(action: {}) {
                    Color.clear
                        .frame(
                            width: scene.shape.width - scene.shape.appleContentInsetX,
                            height: scene.shape.height - scene.shape.appleContentInsetY
                        )
                }
                .buttonStyle(.glass)
                .position(
                    x: scene.shape.x + scene.shape.width / 2,
                    y: scene.shape.y + scene.shape.height / 2
                )
                .accessibilityIdentifier("official-glass-control")
            }
        }
        .ignoresSafeArea()
    }
}

struct ReferenceGlassShape: Shape {
    let kind: String
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        switch kind {
        case "circle":
            Circle().path(in: rect)
        case "roundedSuperellipse":
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            ).path(in: rect)
        default:
            Capsule(style: .continuous).path(in: rect)
        }
    }
}

// A clear, invisible text surface whose only job is to host the system
// text-selection loupe above a scripted long-press. The callout menu is
// suppressed so the loupe is the sole overlay on the probe background.
final class LoupeTextView: UITextView {
    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool {
        false
    }

    // The blinking caret lands at the whitespace line start, outside the
    // scored crop, and its blink phase differs between frames. Hide it so
    // the loupe is the only dynamic overlay.
    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }
}

struct LoupeProbeView: UIViewRepresentable {
    func makeUIView(context: Context) -> LoupeTextView {
        let field = LoupeTextView()
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = .clear
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.isScrollEnabled = false
        // Whitespace content lets the caret settle anywhere while magnifying
        // nothing but the probe background behind the field.
        field.text = String(repeating: " \n", count: 80)
        // An empty input view suppresses the software keyboard.
        field.inputView = UIView()
        field.inputAccessoryView = UIView()
        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: LoupeTextView, context: Context) {}
}

struct ProbeBackground: View {
    let spec: Scene.Probe.Background

    var body: some View {
        if spec.kind == "solid" {
            Color(srgbHex: spec.color!)
        } else if spec.kind == "tileGrid" {
            Canvas { context, size in
                let cell = Double(spec.cellSize!)
                let gutter = Double(spec.gutter!)
                let pattern = spec.pattern!
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(srgbHex: spec.gutterColor!))
                )
                for row in 0..<Int(ceil(size.height / cell)) {
                    let patternRow = pattern[row % pattern.count]
                    for column in 0..<Int(ceil(size.width / cell)) {
                        let offset = patternRow.index(
                            patternRow.startIndex,
                            offsetBy: column % patternRow.count
                        )
                        let code = String(patternRow[offset])
                        context.fill(
                            Path(
                                CGRect(
                                    x: Double(column) * cell,
                                    y: Double(row) * cell,
                                    width: cell - gutter,
                                    height: cell - gutter
                                )
                            ),
                            with: .color(Color(srgbHex: spec.palette![code]!))
                        )
                    }
                }
            }
        } else {
            Canvas { context, size in
                let cell = Double(spec.cellSize!)
                let gutter = Double(spec.gutter!)
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(srgbHex: spec.gutterColor!))
                )
                for row in 0..<Int(ceil(size.height / cell)) {
                    for column in 0..<Int(ceil(size.width / cell)) {
                        let color = rgbwColor(column: column, row: row)
                        context.fill(
                            Path(
                                CGRect(
                                    x: Double(column) * cell,
                                    y: Double(row) * cell,
                                    width: cell - gutter,
                                    height: cell - gutter
                                )
                            ),
                            with: .color(color)
                        )
                    }
                }
            }
        }
    }

    private func rgbwColor(column: Int, row: Int) -> Color {
        let markerRow = row - spec.markerRow!
        let markerColumn = column - spec.markerColumn!
        if markerRow >= 0,
           markerRow < spec.marker!.count,
           markerColumn >= 0,
           markerColumn < spec.marker![markerRow].count
        {
            let line = spec.marker![markerRow]
            let index = line.index(line.startIndex, offsetBy: markerColumn)
            return color(for: line[index])
        }
        let index: Int
        if spec.layout == "primary" {
            index = (column + 2 * row + row / 4) % 4
        } else {
            index = (3 * column + row + column / 5) % 4
        }
        return Color(srgbHex: spec.colors![index])
    }

    private func color(for code: Character) -> Color {
        let index = ["R", "G", "B", "W"].firstIndex(of: String(code))!
        return Color(srgbHex: spec.colors![index])
    }
}

extension Color {
    init(srgbHex: String) {
        let value = UInt64(srgbHex.dropFirst(), radix: 16)!
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
