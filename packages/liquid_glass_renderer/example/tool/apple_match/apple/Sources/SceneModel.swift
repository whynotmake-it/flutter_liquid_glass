import Foundation

struct Scene: Decodable {
    struct GlassTintSpec: Decodable {
        let color: String
        let opacity: Double
    }

    struct CanvasSpec: Decodable {
        let logicalWidth: Double
        let logicalHeight: Double
        let scale: Int
    }

    struct ShapeSpec: Decodable {
        let kind: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let cornerRadius: Double
        let appleContentInsetX: Double
        let appleContentInsetY: Double
    }

    struct Probe: Decodable {
        struct Background: Decodable {
            let kind: String
            let color: String?
            let startColor: String?
            let endColor: String?
            let axis: String?
            let cellSize: Int?
            let gutter: Int?
            let gutterColor: String?
            let layout: String?
            let colors: [String]?
            let markerColumn: Int?
            let markerRow: Int?
            let marker: [String]?
            let palette: [String: String]?
            let pattern: [String]?
        }

        let id: String
        let background: Background
    }

    let canvas: CanvasSpec
    let shape: ShapeSpec
    let id: String
    let profile: String
    let appearance: String
    let glassTint: GlassTintSpec?
    let probes: [Probe]
}

enum Arguments {
    static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
