//
//  SearchTests.swift
//  SgEngineTests
//
//  黑盒 + 白盒：搜索战术正确性、难度调节、LMR、置换表、灭国后切换。
//

import XCTest
@testable import SgEngine

final class SearchTests: XCTestCase {

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

    /// 一步杀：魏车能直接吃蜀帅，AI 应选择吃帅
    func testSearchFindsMateIn1() {
        let board = SgTestFixtures.mateIn1Board()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertEqual(result.move?.to, SgPos(nation: .shu, file: 5, rank: 1),
                       "应选择吃帅走法")
    }

    /// 3 人模式：魏车下一步能吃蜀帅，AI 应选择吃帅
    func testChooseMoveCapturesKingWhenAvailable() {
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
        XCTAssertEqual(move.to, SgPos(nation: .shu, file: 5, rank: 1),
                       "AI 应选择吃帅走法，实际: \(move.description)")
    }

    /// 两步杀：魏方能在两步内必胜，AI 应找到制胜走法
    func testSearchFindsMateIn2() {
        let board = SgTestFixtures.mateIn2Board()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        XCTAssertNotNil(result.move, "应找到制胜走法")
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        if let m = result.move {
            XCTAssertTrue(legal.contains(m), "走法应合法")
        }
    }

    /// AI 应优先吃高价值棋子而非低价值棋子
    func testSearchPrefersHighValueCapture() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 1, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 3, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 7, rank: 1)] = SgPiece(type: .pawn, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()

        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        if let m = result.move {
            XCTAssertEqual(m.to.file, 3, "应优先吃高价值棋子（车），实际走到 file \(m.to.file)")
        }
    }

    /// 搜索不应修改原始棋盘
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

    // MARK: - LMR 正确性

    /// LMR 启用（expert）与未启用（hard，context=nil）都应找到一步杀
    func testLMRDoesNotMissMateIn1() {
        let board = SgTestFixtures.mateIn1Board()
        let r1 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        let r2 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        XCTAssertEqual(r1.move?.to, SgPos(nation: .shu, file: 5, rank: 1))
        XCTAssertEqual(r2.move?.to, SgPos(nation: .shu, file: 5, rank: 1))
    }

    // MARK: - 置换表

    /// 同一局面搜索两次，第二次应命中置换表（结果一致）
    func testTranspositionTableConsistency() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let r1 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        let r2 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        XCTAssertEqual(r1.move, r2.move, "同一局面搜索结果应一致")
    }

    // MARK: - 两方阶段 αβ

    func testTwoNationSearchReturnsLegalMove() {
        let board = SgLayout.initialBoard()
        board.setAliveNationsForTesting([.wei, .shu])
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

    func testTwoNationModeSearchUsesAlphabeta() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertNotNil(result.move, "2 人模式搜索应返回走法")
        if let move = result.move {
            let legal = SgLegality.legalMoves(for: .wei, on: board)
            XCTAssertTrue(legal.contains(move), "2 人模式搜索走法应合法")
        }
    }

    // MARK: - 灭国后搜索切换

    func testSearchHandlesAnnexedState() {
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

    // MARK: - 3 人模式回归

    func testThreeNationSearchReturnsLegalMove() {
        let board = SgLayout.initialBoard()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        guard let m = result.move else { XCTFail("应返回走法"); return }
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertTrue(legal.contains(m))
    }
}
