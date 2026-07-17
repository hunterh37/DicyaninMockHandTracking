import XCTest
import simd
@testable import DicyaninFruitScene

final class FruitSceneModelTests: XCTestCase {
    private func pinch(_ point: SIMD3<Float>?, isLeft: Bool = false,
                       pinching: Bool = true) -> FruitHandInput {
        FruitHandInput(isLeft: isLeft, pinchPoint: point, isPinching: pinching)
    }

    func testDefaultLayoutFloatsAtScatteredHeightsAndDepths() {
        let model = FruitSceneModel()
        XCTAssertEqual(model.fruits.count, FruitKind.allCases.count)
        for fruit in model.fruits {
            XCTAssertEqual(fruit.position, fruit.home)
            XCTAssertFalse(fruit.isHeld)
        }
        // Heights and depths are scattered, not a flat row.
        XCTAssertGreaterThan(Set(model.fruits.map { $0.home.y }).count, 1)
        XCTAssertGreaterThan(Set(model.fruits.map { $0.home.z }).count, 1)
        // Layout is deterministic: a second model (the other scene) matches.
        let other = FruitSceneModel()
        for (a, b) in zip(model.fruits, other.fruits) {
            XCTAssertEqual(a.home, b.home)
        }
    }

    func testPinchNearFruitGrabsAndFollowsWithOffset() {
        let model = FruitSceneModel()
        let target = model.fruits[0]
        let start = target.position + SIMD3<Float>(0.05, 0.05, 0)
        model.update(hands: [pinch(start)], deltaTime: 1 / 60)
        XCTAssertTrue(model.fruits[0].isHeld)
        XCTAssertEqual(model.fruits[0].heldByLeftHand, false)

        let moved = start + SIMD3<Float>(0, 0.3, 0.1)
        model.update(hands: [pinch(moved)], deltaTime: 1 / 60)
        // Offset captured at grab time is preserved: no snap to the pinch point.
        let expected = moved + (target.position - start)
        XCTAssertLessThan(simd_distance(model.fruits[0].position, expected), 1e-4)
    }

    func testPinchFarFromFruitGrabsNothing() {
        let model = FruitSceneModel()
        model.update(hands: [pinch(SIMD3(0, 0.5, -0.6))], deltaTime: 1 / 60)
        XCTAssertFalse(model.fruits.contains(where: { $0.isHeld }))
    }

    func testReleasedFruitFloatsBackHome() {
        let model = FruitSceneModel()
        let home = model.fruits[1].home
        let start = model.fruits[1].position
        model.update(hands: [pinch(start)], deltaTime: 1 / 60)
        model.update(hands: [pinch(start + SIMD3(0.1, 0.25, 0.05))], deltaTime: 1 / 60)
        XCTAssertTrue(model.fruits[1].isHeld)

        // Open the pinch, then let the hover spring settle it back home.
        model.update(hands: [pinch(start, pinching: false)], deltaTime: 1 / 60)
        XCTAssertFalse(model.fruits[1].isHeld)
        for _ in 0..<600 {
            model.update(hands: [], deltaTime: 1 / 60)
        }
        XCTAssertLessThan(simd_distance(model.fruits[1].position, home), 5e-3)
    }

    func testSecondHandCannotStealHeldFruit() {
        let model = FruitSceneModel()
        let start = model.fruits[2].position
        model.update(hands: [pinch(start, isLeft: false)], deltaTime: 1 / 60)
        XCTAssertEqual(model.fruits[2].heldByLeftHand, false)

        model.update(hands: [pinch(start, isLeft: false),
                             pinch(start, isLeft: true)],
                     deltaTime: 1 / 60)
        XCTAssertEqual(model.fruits[2].heldByLeftHand, false)
    }

    func testMissingHandReleasesItsFruit() {
        let model = FruitSceneModel()
        let start = model.fruits[3].position
        model.update(hands: [pinch(start, isLeft: true)], deltaTime: 1 / 60)
        XCTAssertTrue(model.fruits[3].isHeld)
        model.update(hands: [], deltaTime: 1 / 60)
        XCTAssertFalse(model.fruits[3].isHeld)
    }

    func testFruitStaysInsideBounds() {
        let model = FruitSceneModel()
        let start = model.fruits[0].position
        model.update(hands: [pinch(start)], deltaTime: 1 / 60)
        // Fling far outside the box.
        model.update(hands: [pinch(SIMD3(5, 5, 5))], deltaTime: 1 / 60)
        model.update(hands: [], deltaTime: 1 / 60)
        for _ in 0..<120 {
            model.update(hands: [], deltaTime: 1 / 60)
        }
        let p = model.fruits[0].position
        let lo = model.configuration.boundsMin
        let hi = model.configuration.boundsMax
        XCTAssertTrue(p.x >= lo.x && p.x <= hi.x)
        XCTAssertTrue(p.y >= lo.y && p.y <= hi.y)
        XCTAssertTrue(p.z >= lo.z && p.z <= hi.z)
    }

    func testResetRestoresLayout() {
        let model = FruitSceneModel()
        let start = model.fruits[0].position
        model.update(hands: [pinch(start)], deltaTime: 1 / 60)
        model.update(hands: [pinch(start + SIMD3(0.1, 0.2, 0))], deltaTime: 1 / 60)
        model.reset()
        XCTAssertFalse(model.fruits.contains(where: { $0.isHeld }))
        XCTAssertEqual(model.fruits[0].position, start)
    }
}
