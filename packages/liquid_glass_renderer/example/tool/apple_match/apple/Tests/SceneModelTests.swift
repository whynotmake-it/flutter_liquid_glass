import Foundation

@main
enum SceneModelTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("expected scene path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let scene = try JSONDecoder().decode(Scene.self, from: data)
        try expect(scene.canvas.logicalWidth > 0, "logical width")
        try expect(scene.canvas.logicalHeight > 0, "logical height")
        try expect(scene.canvas.scale == 3, "scale")
        try expect(scene.probes.map(\.id) == ["A", "B", "C", "D"], "probe order")
        try expect(
            ["capsule", "circle", "roundedSuperellipse"].contains(scene.shape.kind),
            "shape kind"
        )
        if scene.profile == "material_shape" {
            try expect(scene.probes[0].background.kind == "tileGrid", "coordinate probe")
            try expect(scene.probes[1].background.kind == "tileGrid", "color probe")
            try expect(scene.probes[0].background.pattern != nil, "tile pattern")
            try expect(scene.probes[0].background.palette != nil, "tile palette")
        }
        print("SceneModelTests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() {
            throw TestFailure("failed: \(name)")
        }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
