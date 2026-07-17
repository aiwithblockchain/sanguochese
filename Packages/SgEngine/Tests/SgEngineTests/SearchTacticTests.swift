//
//  SearchTacticTests.swift
//  SgEngineTests
//
//  黑盒：搜索战术正确性。聚焦"AI 弱智"问题——
//  解将、解将还吃、避免送将、必胜局面、优先吃高价值。
//  这些测试用于暴露 eval 不惩罚将军导致的战术缺陷。
//

import XCTest
@testable import SgEngine

final class SearchTacticTests: XCTestCase {

    // MARK: - 解将

    /// 被将军时必须找到一步解围走法
    func testMustEscapeCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 2)] = SgPiece(type: .advisor, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board))
        let result = SgSearch.chooseMove(for: .shu, on: board, difficulty: .hard)
        guard let move = result.move else { XCTFail("应找到解围走法"); return }
        let cap = board.apply(move)
        let stillInCheck = SgLegality.isInCheck(side: .shu, on: board)
        board.undo(move, captured: cap)
        XCTAssertFalse(stillInCheck, "走完后应解除将军，实际: \(move)")
    }

    // MARK: - 解将还吃（关键战术测试）

    /// 被将军时应优先吃掉攻击子，而不是逃跑
    /// 此测试用于暴露 Bug A/E：eval 不惩罚将军，AI 不懂"解将还吃"
    func testPrefersCaptureToEscape() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        // 魏车在 (shu,4,1) 横向将军，蜀车在 (shu,6,1) 可吃之
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board))
        let result = SgSearch.chooseMove(for: .shu, on: board, difficulty: .hard)
        guard let move = result.move else { XCTFail("应找到走法"); return }
        XCTAssertEqual(move.to, SgPos(nation: .shu, file: 4, rank: 1),
                       "应吃掉将军的车（解将还吃），实际: \(move)")
    }

    // MARK: - 避免送将

    /// 不应主动走进被将军的位置
    func testAvoidsMovingIntoCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        let result = SgSearch.chooseMove(for: .shu, on: board, difficulty: .hard)
        guard let move = result.move else { XCTFail("应返回走法"); return }
        XCTAssertNotEqual(move.to, SgPos(nation: .shu, file: 5, rank: 2),
                          "不应走进被将军的位置")
    }

    // MARK: - 一步杀

    /// 能直接吃帅时应选择吃帅
    func testFindsMateIn1() {
        let board = SgTestFixtures.mateIn1Board()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertEqual(result.move?.to, SgPos(nation: .shu, file: 5, rank: 1),
                       "应选择吃帅走法")
    }

    // MARK: - 优先吃高价值

    /// 同时可吃车和兵时，应优先吃车
    func testPrefersHighValueCapture() {
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
            XCTAssertEqual(m.to.file, 3, "应优先吃车（file 3），实际走到 file \(m.to.file)")
        }
    }

    // MARK: - 不应修改棋盘

    func testSearchDoesNotMutateBoard() {
        let board = SgTestFixtures.mateIn1Board()
        let before = SgBoard(copy: board)
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertEqual(board.pieces, before.pieces)
        XCTAssertEqual(board.sideToMove, before.sideToMove)
        XCTAssertEqual(board.zobrist, before.zobrist)
    }

    // MARK: - 2人模式返回合法走法

    func testTwoNationReturnsLegalMove() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        guard let m = result.move else { XCTFail("应返回走法"); return }
        XCTAssertTrue(SgLegality.legalMoves(for: .wei, on: board).contains(m))
    }
}
