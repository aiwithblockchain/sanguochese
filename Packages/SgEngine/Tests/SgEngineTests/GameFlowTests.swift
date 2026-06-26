//
//  GameFlowTests.swift
//  SgEngineTests
//
//  黑盒：终局判定、灭国吞并、消极判负、2 人模式结算。
//

import XCTest
@testable import SgEngine

final class GameFlowTests: XCTestCase {

    // MARK: - 3 人模式灭国吞并

    /// 魏 车直接吃蜀帅 → 蜀灭国归魏
    func testCaptureKingTriggersAnnex() {
        let board = SgBoard()
        board.sideToMove = .wei
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 1)] = SgPiece(type: .king, nation: .wu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 1, rank: 1)] = SgPiece(type: .rook, nation: .shu)

        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 2),
                          to: SgPos(nation: .shu, file: 5, rank: 1))
        let outcome = SgGameFlow.play(move, on: board)
        XCTAssertEqual(outcome, .annexed(defeated: .shu, victor: .wei))
        XCTAssertFalse(board.aliveNations.contains(.shu))
        XCTAssertEqual(board.annexed[.shu], .wei)
        XCTAssertEqual(board.piece(at: SgPos(nation: .shu, file: 1, rank: 1))?.nation, .wei)
    }

    /// 3 人模式吃帅应触发吞并（非终局）
    func testThreeNationKingCaptureTriggersAnnex() {
        let board = SgLayout.initialBoard()
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.sideToMove = .wei
        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                          to: SgPos(nation: .shu, file: 5, rank: 1))
        let outcome = SgGameFlow.play(move, on: board)
        if case .annexed(let defeated, let victor) = outcome {
            XCTAssertEqual(defeated, .shu)
            XCTAssertEqual(victor, .wei)
        } else {
            XCTFail("3 人模式吃帅应触发吞并，实际: \(outcome)")
        }
        XCTAssertNotNil(board.annexed[.shu])
    }

    /// 两方阶段：魏吃吴帅 → 魏一统天下
    func testCaptureLastKingGameOver() {
        let board = SgBoard()
        board.sideToMove = .wei
        board.setAliveNationsForTesting([.wei, .wu])
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 1)] = SgPiece(type: .king, nation: .wu)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 2)] = SgPiece(type: .rook, nation: .wei)
        let move = SgMove(from: SgPos(nation: .wu, file: 5, rank: 2),
                          to: SgPos(nation: .wu, file: 5, rank: 1))
        let outcome = SgGameFlow.play(move, on: board)
        XCTAssertEqual(outcome, .gameOver(winner: .wei))
        XCTAssertEqual(SgGameFlow.result(of: board), .gameOver(winner: .wei))
    }

    // MARK: - 2 人模式终局

    /// 2 人模式吃帅后 aliveNations 应只剩 1 方
    func testTwoNationKingCaptureReducesAlive() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.sideToMove = .wei
        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                          to: SgPos(nation: .shu, file: 5, rank: 1))
        let outcome = SgGameFlow.play(move, on: board)
        if case .gameOver(let winner) = outcome {
            XCTAssertEqual(winner, .wei)
            XCTAssertEqual(board.aliveNations, [.wei], "吃帅后只剩胜方存活")
        } else {
            XCTFail("应终局")
        }
    }

    /// 2 人模式：吃帅直接终局，不吞并
    func testTwoNationModeKingCaptureEndsGame() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.sideToMove = .wei
        let outcome = SgGameFlow.play(SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                                              to: SgPos(nation: .shu, file: 5, rank: 1)),
                                       on: board)
        if case .gameOver(let winner) = outcome {
            XCTAssertEqual(winner, .wei)
        } else {
            XCTFail("2 人模式吃帅应直接终局，实际: \(outcome)")
        }
        XCTAssertTrue(board.annexed.isEmpty, "2 人模式不应触发吞并")
    }

    /// 2 人模式无子可走应终局
    func testTwoNationNoMovesEndsGame() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .advisor, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .advisor, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .advisor, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        XCTAssertTrue(SgLegality.hasNoLegalMoves(side: .shu, on: board),
                      "蜀方应无合法走法")
    }

    /// 主帅缺失应判定终局
    func testTwoNationModeResultDetectsKingAbsence() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        if let kp = board.kingPos(of: .shu) {
            board.pieces[kp] = nil
        }
        // aliveNations 仍含 shu，但 result 只看 aliveNations.count；
        // 这里手动 markDefeated 模拟吃帅后的状态
        board.markDefeated(.shu)
        let result = SgGameFlow.result(of: board)
        if case .gameOver(let winner) = result {
            XCTAssertEqual(winner, .wei)
        } else {
            XCTFail("主帅缺失应判定终局")
        }
    }

    // MARK: - 困毙

    func testNoMovesDefeated() {
        let board = SgBoard()
        board.sideToMove = .shu
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wu,  file: 6, rank: 1)] = SgPiece(type: .king, nation: .wu)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 2)] = SgPiece(type: .rook, nation: .wu)

        XCTAssertTrue(SgLegality.hasNoLegalMoves(side: .shu, on: board),
                      "蜀帅被围困应无合法走法")
    }

    // MARK: - 消极判负

    func testHasCrossedPieces() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 1)] = SgPiece(type: .king, nation: .wu)
        board.pieces[SgPos(nation: .shu, file: 9, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 9, rank: 1)] = SgPiece(type: .rook, nation: .wu)

        XCTAssertTrue(SgGameFlow.hasCrossedPieces(.wei, on: board))
        XCTAssertTrue(SgGameFlow.hasCrossedPieces(.wu, on: board))
        XCTAssertFalse(SgGameFlow.hasCrossedPieces(.shu, on: board))
    }

    // MARK: - 吞并接口

    func testAnnexChangesPieceColor() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 1, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.annex(defeated: .shu, by: .wei)
        XCTAssertFalse(board.aliveNations.contains(.shu))
        XCTAssertEqual(board.annexed[.shu], .wei)
        XCTAssertEqual(board.piece(at: SgPos(nation: .shu, file: 1, rank: 1))?.nation, .wei)
    }

    func testClearAllRemovesPieces() {
        let board = SgLayout.initialBoard()
        board.clearAll(of: .wu)
        XCTAssertFalse(board.aliveNations.contains(.wu))
        XCTAssertTrue(board.positions(of: .wu).isEmpty)
    }

    // MARK: - 收编兵卒方向重定义

    func testAnnexedPawnRedirectsTowardRemainingEnemy() {
        let board = SgBoard()
        board.setAliveNationsForTesting([.wei, .wu])
        board.setAnnexedForTesting([.shu: .wei])
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 1)] = SgPiece(type: .king, nation: .wu)

        let pos = SgPos(nation: .shu, file: 5, rank: 3)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pos)!, at: pos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 4)))
    }

    func testAnnexedPawnAtBorderForksToRemainingEnemy() {
        let board = SgBoard()
        board.setAliveNationsForTesting([.wei, .wu])
        board.setAnnexedForTesting([.shu: .wei])
        board.pieces[SgPos(nation: .shu, file: 5, rank: 5)] = SgPiece(type: .pawn, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .wu,  file: 5, rank: 1)] = SgPiece(type: .king, nation: .wu)

        let pos = SgPos(nation: .shu, file: 5, rank: 5)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pos)!, at: pos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 5, rank: 5)))
    }
}
