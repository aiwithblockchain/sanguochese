//
//  SgAITests.swift
//  sanguocheseTests
//
//  P5 AI 引擎单元测试
//  覆盖：评估函数、搜索（Paranoid/αβ）、难度调节、灭国后切换。
//

import XCTest
@testable import sanguochese

final class SgAITests: XCTestCase {

    // MARK: - 评估函数

    func testEvaluateReturnsAllAliveNations() {
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(Set(eval.scores.keys), [.wei, .shu, .wu])
    }

    func testInitialEvalIsSymmetricAcrossNations() {
        // 三方初始布局对称，评估应完全相等
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(eval[.wei], eval[.shu])
        XCTAssertEqual(eval[.shu], eval[.wu])
    }

    func testMaterialAdvantageYieldsHigherScore() {
        // 给魏方多一枚车，魏分应高于其他两方
        let board = SgLayout.initialBoard()
        board.pieces[SgPos(nation: .shu, file: 1, rank: 5)] = SgPiece(type: .rook, nation: .wei)
        let eval = SgEvaluator.evaluate(board)
        XCTAssertGreaterThan(eval[.wei], eval[.shu])
        XCTAssertGreaterThan(eval[.wei], eval[.wu])
    }

    func testRelativeScoreForTwoNation() {
        // 灭吴后两方阶段：相对分 = mine - enemy
        let board = SgLayout.initialBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        let eval = SgEvaluator.evaluate(board)
        let rel = eval.relative(for: .wei, alive: [.wei, .shu])
        XCTAssertEqual(rel, eval[.wei] - eval[.shu])
    }

    // MARK: - 搜索基本行为

    func testChooseMoveReturnsLegalMove() {
        let board = SgLayout.initialBoard()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        guard let move = result.move else {
            XCTFail("应返回一步走法"); return
        }
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertTrue(legal.contains(move), "AI 返回的走法必须合法")
    }

    func testChooseMoveCapturesKingWhenAvailable() {
        // 构造局面：魏车下一步能吃蜀帅
        // 魏王在 (wei,1,1)、吴王在 (wu,1,1)：file 1 → 对方 file 9，不照面
        // 蜀王在 (shu,5,1)，魏车在 (shu,5,3)，中间 (shu,5,2) 空 → 车可吃帅
        let board = SgBoard()
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wu, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wu)
        board.sideToMove = .wei

        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        guard let move = result.move else {
            XCTFail("应返回走法"); return
        }
        // 走法应吃掉蜀帅（终点为蜀帅位置）
        XCTAssertEqual(move.to, SgPos(nation: .shu, file: 5, rank: 1),
                       "AI 应选择吃帅走法，实际: \(move.description)")
    }

    func testSearchDoesNotMutateBoard() {
        let board = SgLayout.initialBoard()
        let before = SgBoard(copy: board)
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        XCTAssertEqual(board.pieces, before.pieces)
        XCTAssertEqual(board.sideToMove, before.sideToMove)
        XCTAssertEqual(board.aliveNations, before.aliveNations)
        XCTAssertEqual(board.annexed, before.annexed)
    }

    // MARK: - 难度调节

    func testDifficultyDepths() {
        XCTAssertEqual(SgDifficulty.easy.depth, 2)
        XCTAssertEqual(SgDifficulty.normal.depth, 3)
        XCTAssertEqual(SgDifficulty.hard.depth, 4)
        XCTAssertEqual(SgDifficulty.expert.depth, 5)
    }

    func testEasyHasRandomChance() {
        XCTAssertGreaterThan(SgDifficulty.easy.randomChance, 0)
    }

    func testHardHasNoRandom() {
        XCTAssertEqual(SgDifficulty.hard.randomChance, 0)
    }

    // MARK: - 两方阶段 αβ

    func testTwoNationSearchReturnsLegalMove() {
        let board = SgLayout.initialBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        // 移除吴方所有棋子以匹配存活集合
        for pos in board.positions(of: .wu) {
            board.pieces[pos] = nil
        }
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        guard let move = result.move else {
            XCTFail("两方阶段应返回走法"); return
        }
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertTrue(legal.contains(move))
    }

    // MARK: - 灭国后搜索切换

    func testSearchHandlesAnnexedState() {
        // 构造已灭吴的两方局面，魏蜀帅不在同一直线上避免照面。
        // 魏帅 (wei,1,1) → 进攻蜀时接 (shu,9,1)，与蜀帅 (shu,5,1) 不照面。
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 2, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 2, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.setAnnexedForTesting([.wu: .wei])
        board.sideToMove = .wei
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        XCTAssertNotNil(result.move, "两方阶段搜索应返回走法")
    }
}
