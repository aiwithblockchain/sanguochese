//
//  PerformanceTests.swift
//  SgEngineTests
//
//  性能基准：搜索节点数 / 用时，防止性能回退。
//

import XCTest
@testable import SgEngine

final class PerformanceTests: XCTestCase {

    /// hard 深度 4，2 人模式，应在 2 秒内完成
    func testSearchPerformanceWithinBudget() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "hard 难度搜索应在 2 秒内完成，实际 \(elapsed)s")
    }

    /// expert 深度 5 也应在 3 秒内完成（有迭代加深 + 时限保护）
    func testExpertSearchWithinBudget() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "expert 难度搜索应在 3 秒内完成，实际 \(elapsed)s")
    }

    /// 3 人模式搜索也应在时限内
    func testThreeNationSearchWithinBudget() {
        let board = SgLayout.initialBoard()
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "3 人 hard 搜索应在 3 秒内完成，实际 \(elapsed)s")
    }
}
