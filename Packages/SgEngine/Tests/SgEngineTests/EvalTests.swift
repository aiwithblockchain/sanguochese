//
//  EvalTests.swift
//  SgEngineTests
//
//  白盒：评估函数、PST 对称性与方向性。
//

import XCTest
@testable import SgEngine

final class EvalTests: XCTestCase {

    // MARK: - 评估函数基础

    func testEvaluateReturnsAllAliveNations() {
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(Set(eval.scores.keys), [.wei, .shu, .wu])
    }

    func testInitialEvalIsSymmetricAcrossNations() {
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(eval[.wei], eval[.shu])
        XCTAssertEqual(eval[.shu], eval[.wu])
    }

    func testMaterialAdvantageYieldsHigherScore() {
        let board = SgLayout.initialBoard()
        board.pieces[SgPos(nation: .shu, file: 1, rank: 5)] = SgPiece(type: .rook, nation: .wei)
        let eval = SgEvaluator.evaluate(board)
        XCTAssertGreaterThan(eval[.wei], eval[.shu])
        XCTAssertGreaterThan(eval[.wei], eval[.wu])
    }

    func testRelativeScoreForTwoNation() {
        let board = SgLayout.initialBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        let eval = SgEvaluator.evaluate(board)
        let rel = eval.relative(for: .wei, alive: [.wei, .shu])
        XCTAssertEqual(rel, eval[.wei] - eval[.shu])
    }

    // MARK: - PST 对称性

    /// 初始局面 PST 评估应对称（三方等价）
    func testPSTInitialSymmetry() {
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(eval[.wei], eval[.shu], "魏蜀 PST 评估应相等")
        XCTAssertEqual(eval[.shu], eval[.wu], "蜀吴 PST 评估应相等")
    }

    // MARK: - PST 方向性

    /// 车在己方底线 vs 车在敌方底线，PST 加成应不同
    func testRookPSTDiffersByPosition() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.setAliveNationsForTesting([.wei, .shu])

        let rook = SgPiece(type: .rook, nation: .wei)
        let ownPos = SgPos(nation: .wei, file: 1, rank: 1)
        let enemyPos = SgPos(nation: .shu, file: 9, rank: 1)

        let ownBonus = SgEvaluator.positionBonus(piece: rook, at: ownPos, side: .wei)
        let enemyBonus = SgEvaluator.positionBonus(piece: rook, at: enemyPos, side: .wei)
        XCTAssertNotEqual(ownBonus, enemyBonus, "车在不同位置 PST 加成应不同")
    }

    /// 兵过河后加成应递增（越深入敌后越高）
    func testPawnPSTIncreasesWithAdvance() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.setAliveNationsForTesting([.wei, .shu])

        let pawn = SgPiece(type: .pawn, nation: .wei)
        let ownPos = SgPos(nation: .wei, file: 5, rank: 4)
        let justCrossed = SgPos(nation: .shu, file: 5, rank: 5)
        let deep = SgPos(nation: .shu, file: 5, rank: 2)

        let b0 = SgEvaluator.positionBonus(piece: pawn, at: ownPos, side: .wei)
        let b1 = SgEvaluator.positionBonus(piece: pawn, at: justCrossed, side: .wei)
        let b2 = SgEvaluator.positionBonus(piece: pawn, at: deep, side: .wei)
        XCTAssertGreaterThan(b1, b0, "过河兵加成应高于未过河")
        XCTAssertGreaterThan(b2, b1, "越深入敌后加成应越高")
    }

    /// 过河兵（在敌国领土）应比未过河兵得分高
    func testPawnTableGivesBonusForCrossedPawn() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        let ownPawn = SgPiece(type: .pawn, nation: .wei)
        let ownPos = SgPos(nation: .wei, file: 5, rank: 4)
        let crossedPawn = SgPiece(type: .pawn, nation: .wei)
        let crossedPos = SgPos(nation: .shu, file: 5, rank: 5)
        let ownBonus = SgEvaluator.positionBonus(piece: ownPawn, at: ownPos, side: .wei)
        let crossedBonus = SgEvaluator.positionBonus(piece: crossedPawn, at: crossedPos, side: .wei)
        XCTAssertGreaterThan(crossedBonus, ownBonus,
                             "过河兵位置加成应高于未过河兵")
    }

    // MARK: - 逻辑坐标映射

    func testLogicalPosMapping() {
        let ownPiece = SgPiece(type: .rook, nation: .wei)
        let ownPos = SgPos(nation: .wei, file: 1, rank: 1)
        let ownLP = SgEvaluator.logicalPos(piece: ownPiece, at: ownPos, side: .wei)
        XCTAssertEqual(ownLP.file, 0)
        XCTAssertEqual(ownLP.rank, 0)

        let enemyPiece = SgPiece(type: .rook, nation: .wei)
        let enemyPos = SgPos(nation: .shu, file: 1, rank: 1)
        let enemyLP = SgEvaluator.logicalPos(piece: enemyPiece, at: enemyPos, side: .wei)
        XCTAssertEqual(enemyLP.file, 8)
        XCTAssertEqual(enemyLP.rank, 9)
    }
}
