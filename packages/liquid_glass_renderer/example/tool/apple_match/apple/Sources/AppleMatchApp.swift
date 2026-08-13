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

struct ProbeBackground: View {
    let spec: Scene.Probe.Background

    var body: some View {
        if spec.kind == "solid" {
            Color(srgbHex: spec.color!)
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
