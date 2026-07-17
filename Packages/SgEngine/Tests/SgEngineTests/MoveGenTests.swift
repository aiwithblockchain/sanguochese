//
//  MoveGenTests.swift
//  SgEngineTests
//
//  白盒：每种棋子的伪合法走法生成正确性。
//  目标：蹩腿、塞象眼、炮架子、九宫约束、兵过河横走、国界分叉吃子。
//

import XCTest
@testable import SgEngine

final class MoveGenTests: XCTestCase {

    // MARK: - 车

    func testRookSlidingStopsAtFirstPiece() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .rook, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)),
                       "遇友方应停，不能跳过")
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 4)))
    }

    func testRookCapturesEnemyAndStops() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .shu)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .rook, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)), "应能吃敌兵")
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 4)), "吃后应停")
    }

    func testRookCrossBorderCapture() {
        let board = SgBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .shu)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .rook, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 4), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 3)), "应能过界吃敌兵")
    }

    // MARK: - 炮

    func testCannonMovesLikeRookWhenNoScreen() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .cannon, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .cannon, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 5)))
    }

    func testCannonCannotCaptureWithoutScreen() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .cannon, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .shu)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .cannon, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)),
                       "炮无炮架子不能吃子")
    }

    func testCannonCapturesOverScreen() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .cannon, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .shu)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .cannon, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 4)), "应能翻山吃敌兵")
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)), "翻山后空格不可走")
    }

    func testCannonStopsAtSecondPieceAfterScreen() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .cannon, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .wei)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .cannon, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 5, rank: 4)),
                       "炮架子后是友方子，不能吃")
    }

    // MARK: - 马

    func testKnightMovesAll8TargetsWhenOpen() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .knight, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .knight, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 3), on: board)
        let targets = Set(moves.map { $0.to })
        // 标准 8 个日字目标
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 4, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 6, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 4)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 7, rank: 4)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 7, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 4, rank: 1)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 6, rank: 1)))
    }

    func testKnightBlockedByLegPiece() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .knight, nation: .wei)
        // 蹩腿：在 (wei,5,4) 放一子，阻挡前进方向的马腿
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .knight, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 3), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 4, rank: 5)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 6, rank: 5)))
    }

    // MARK: - 象

    func testBishopBlockedByEyePiece() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .bishop, nation: .wei)
        // 塞象眼：(wei,4,2) 有子
        board.pieces[SgPos(nation: .wei, file: 4, rank: 2)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .bishop, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 3, rank: 3)), "塞象眼应不可走")
    }

    func testBishopStaysInOwnTerritory() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 5)] = SgPiece(type: .bishop, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .bishop, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 5), on: board)
        XCTAssertTrue(moves.allSatisfy { $0.to.nation == .wei }, "象不应过国界")
    }

    // MARK: - 士

    func testAdvisorStaysInPalace() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 2)] = SgPiece(type: .advisor, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .advisor, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 2), on: board)
        XCTAssertTrue(moves.allSatisfy { $0.to.isInPalace }, "士不应出九宫")
    }

    // MARK: - 帅

    func testKingStaysInPalace() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .king, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 1), on: board)
        XCTAssertTrue(moves.allSatisfy { $0.to.isInPalace }, "帅不应出九宫")
        let targets = Set(moves.map { $0.to })
        // 帅在 (wei,5,1) 可走 (wei,4,1)/(wei,5,2)/(wei,6,1)，均在九宫内
        XCTAssertEqual(targets, Set([
            SgPos(nation: .wei, file: 4, rank: 1),
            SgPos(nation: .wei, file: 5, rank: 2),
            SgPos(nation: .wei, file: 6, rank: 1)
        ]))
    }

    // MARK: - 兵

    func testPawnBeforeCrossingOnlyMovesForward() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .pawn, nation: .wei),
                                       at: SgPos(nation: .wei, file: 5, rank: 4), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 5)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 4, rank: 4)), "未过河不可横走")
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 6, rank: 4)))
    }

    func testPawnAfterCrossingCanMoveSideways() {
        let board = SgBoard()
        board.setAliveNationsForTesting([.wei, .shu])
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: SgPiece(type: .pawn, nation: .wei),
                                       at: SgPos(nation: .shu, file: 5, rank: 3), on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 2)), "应可前进")
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 4, rank: 3)), "过河兵应可横走")
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 6, rank: 3)))
    }

    // MARK: - pseudoCaptures 只含吃子

    func testPseudoCapturesOnlyContainsCaptures() {
        let board = SgLayout.initialBoard()
        let caps = SgMoveGen.pseudoCaptures(for: .wei, on: board)
        XCTAssertTrue(caps.allSatisfy { board.piece(at: $0.to) != nil },
                      "pseudoCaptures 应只含吃子走法")
    }
}
