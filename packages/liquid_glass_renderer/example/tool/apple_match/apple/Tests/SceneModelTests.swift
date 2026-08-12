import Foundation

@main
enum SceneModelTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("expected scene path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let scene = try JSONDecoder().decode(Scene.self, from: data)
        try expect(scene.canvas.logicalWidth == 402, "logical width")
        try expect(scene.canvas.logicalHeight == 874, "logical height")
        try expect(scene.canvas.scale == 3, "scale")
        try expect(scene.probes.map(\.id) == ["A", "B", "C", "D"], "probe order")
        try expect(scene.shape.width == 225.333, "shape width")
        try expect(scene.shape.cornerRadius == scene.shape.height / 2, "capsule radius")
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
