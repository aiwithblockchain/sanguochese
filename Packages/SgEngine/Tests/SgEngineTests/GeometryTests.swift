//
//  GeometryTests.swift
//  SgEngineTests
//
//  白盒：棋盘几何原语 stepOut/stepIn/stepLeft/stepRight、
//  outRays/inRays/leftRay/rightRay、cellsBetween 的正确性。
//  目标：覆盖国界分叉、2人/3人模式分叉数差异、翻转对接。
//

import XCTest
@testable import SgEngine

final class GeometryTests: XCTestCase {

    // MARK: - 单步

    func testStepOutInOwnTerritory() {
        let pos = SgPos(nation: .wei, file: 5, rank: 1)
        let out = SgGeometry.stepOut(from: pos, owner: .wei)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first, SgPos(nation: .wei, file: 5, rank: 2))
    }

    func testStepInInOwnTerritory() {
        let pos = SgPos(nation: .wei, file: 5, rank: 3)
        let s = SgGeometry.stepIn(from: pos, owner: .wei)
        XCTAssertEqual(s, SgPos(nation: .wei, file: 5, rank: 2))
    }

    func testStepInAtOwnBottomReturnsNil() {
        let pos = SgPos(nation: .wei, file: 5, rank: 1)
        XCTAssertNil(SgGeometry.stepIn(from: pos, owner: .wei))
    }

    func testStepOutInEnemyTerritoryDecreasesRank() {
        let pos = SgPos(nation: .shu, file: 5, rank: 3)
        let out = SgGeometry.stepOut(from: pos, owner: .wei)
        XCTAssertEqual(out, [SgPos(nation: .shu, file: 5, rank: 2)])
    }

    func testStepOutAtEnemyBottomReturnsEmpty() {
        let pos = SgPos(nation: .shu, file: 5, rank: 1)
        let out = SgGeometry.stepOut(from: pos, owner: .wei)
        XCTAssertTrue(out.isEmpty)
    }

    func testStepInInEnemyTerritoryIncreasesRank() {
        let pos = SgPos(nation: .shu, file: 5, rank: 3)
        let s = SgGeometry.stepIn(from: pos, owner: .wei)
        XCTAssertEqual(s, SgPos(nation: .shu, file: 5, rank: 4))
    }

    func testStepInAtEnemyBorderReturnsNil() {
        let pos = SgPos(nation: .shu, file: 5, rank: 5)
        XCTAssertNil(SgGeometry.stepIn(from: pos, owner: .wei))
    }

    func testStepLeftRightBounds() {
        let leftEdge = SgPos(nation: .wei, file: 1, rank: 3)
        XCTAssertNil(SgGeometry.stepLeft(from: leftEdge))
        XCTAssertNotNil(SgGeometry.stepRight(from: leftEdge))

        let rightEdge = SgPos(nation: .wei, file: 9, rank: 3)
        XCTAssertNil(SgGeometry.stepRight(from: rightEdge))
        XCTAssertNotNil(SgGeometry.stepLeft(from: rightEdge))
    }

    // MARK: - 国界分叉（stepOut）

    func testStepOutForksAtBorder3Nation() {
        let pos = SgPos(nation: .wei, file: 5, rank: 5)
        let out = SgGeometry.stepOut(from: pos, owner: .wei, alive: [.wei, .shu, .wu])
        XCTAssertEqual(Set(out), Set([
            SgPos(nation: .shu, file: 5, rank: 5),
            SgPos(nation: .wu, file: 5, rank: 5)
        ]))
    }

    func testStepOutForksAtBorder2Nation() {
        let pos = SgPos(nation: .wei, file: 5, rank: 5)
        let out = SgGeometry.stepOut(from: pos, owner: .wei, alive: [.wei, .shu])
        XCTAssertEqual(out, [SgPos(nation: .shu, file: 5, rank: 5)])
    }

    func testStepOutForkFileFlip() {
        // file 1 → 敌国 file 9；file 9 → 敌国 file 1
        let pos = SgPos(nation: .wei, file: 1, rank: 5)
        let out = SgGeometry.stepOut(from: pos, owner: .wei, alive: [.wei, .shu, .wu])
        XCTAssertTrue(out.contains(SgPos(nation: .shu, file: 9, rank: 5)))
        XCTAssertTrue(out.contains(SgPos(nation: .wu, file: 9, rank: 5)))
    }

    // MARK: - 射线

    func testOutRaysFromOwnTerritoryForks() {
        let pos = SgPos(nation: .wei, file: 5, rank: 1)
        let rays = SgGeometry.outRays(from: pos, owner: .wei, alive: [.wei, .shu, .wu])
        XCTAssertEqual(rays.count, 2, "3 人模式应分叉到 2 个敌国")
        // 每条射线应包含己方 rank 2..5 + 敌国 rank 5..1
        let firstRay = rays[0]
        XCTAssertEqual(firstRay.count, 9)
        XCTAssertEqual(firstRay.first, SgPos(nation: .wei, file: 5, rank: 2))
        XCTAssertEqual(firstRay.last, SgPos(nation: .shu, file: 5, rank: 1))
    }

    func testOutRays2NationSingleFork() {
        let pos = SgPos(nation: .wei, file: 5, rank: 1)
        let rays = SgGeometry.outRays(from: pos, owner: .wei, alive: [.wei, .shu])
        XCTAssertEqual(rays.count, 1, "2 人模式只分叉到 1 个敌国")
    }

    func testOutRaysFromEnemyTerritoryNoFork() {
        let pos = SgPos(nation: .shu, file: 5, rank: 4)
        let rays = SgGeometry.outRays(from: pos, owner: .wei, alive: [.wei, .shu, .wu])
        XCTAssertEqual(rays.count, 1)
        XCTAssertEqual(rays[0], [SgPos(nation: .shu, file: 5, rank: 3),
                                 SgPos(nation: .shu, file: 5, rank: 2),
                                 SgPos(nation: .shu, file: 5, rank: 1)])
    }

    func testInRaysFromEnemyTerritoryForks() {
        let pos = SgPos(nation: .shu, file: 5, rank: 1)
        let rays = SgGeometry.inRays(from: pos, owner: .wei, alive: [.wei, .shu, .wu])
        XCTAssertEqual(rays.count, 2, "从敌国底线后退应分叉到 2 国")
    }

    func testLeftRayRightRayDoNotCrossBorder() {
        let pos = SgPos(nation: .wei, file: 5, rank: 3)
        let left = SgGeometry.leftRay(from: pos)
        let right = SgGeometry.rightRay(from: pos)
        XCTAssertEqual(left.count, 4)
        XCTAssertEqual(right.count, 4)
        XCTAssertTrue(left.allSatisfy { $0.nation == .wei })
        XCTAssertTrue(right.allSatisfy { $0.nation == .wei })
    }

    // MARK: - cellsBetween（飞将）

    func testCellsBetweenSameNationReturnsNil() {
        let a = SgPos(nation: .wei, file: 5, rank: 1)
        let b = SgPos(nation: .wei, file: 5, rank: 3)
        XCTAssertNil(SgGeometry.cellsBetween(kingA: a, kingB: b))
    }

    func testCellsBetweenNonMatchingFileReturnsNil() {
        let a = SgPos(nation: .wei, file: 5, rank: 1)
        let b = SgPos(nation: .shu, file: 4, rank: 1)
        XCTAssertNil(SgGeometry.cellsBetween(kingA: a, kingB: b))
    }

    func testCellsBetweenMatchingFileReturnsCells() {
        let a = SgPos(nation: .wei, file: 5, rank: 1)
        let b = SgPos(nation: .shu, file: 5, rank: 1)
        let cells = SgGeometry.cellsBetween(kingA: a, kingB: b)
        XCTAssertNotNil(cells)
        XCTAssertEqual(cells?.first, SgPos(nation: .wei, file: 5, rank: 2))
    }
}
