//
//  ZobristTests.swift
//  SgEngineTests
//
//  白盒：增量 Zobrist 哈希一致性。
//  目标：apply/undo 后 zobrist 还原、make/unmake 后 zobrist 还原、
//  相同局面相同哈希、不同局面不同哈希、recomputeZobrist 与增量一致。
//

import XCTest
@testable import SgEngine

final class ZobristTests: XCTestCase {

    func testRecomputeEqualsIncrementalAfterApply() {
        let board = SgLayout.initialBoard()
        let moves = SgLegality.legalMoves(for: .wei, on: board)
        for move in moves {
            let before = board.zobrist
            let cap = board.apply(move)
            let incremental = board.zobrist
            board.recomputeZobrist()
            XCTAssertEqual(incremental, board.zobrist,
                           "增量哈希应与全量重算一致（move: \(move)）")
            board.undo(move, captured: cap)
            XCTAssertEqual(board.zobrist, before, "undo 后哈希应还原")
        }
    }

    func testMakeUnmakeRestoresZobrist() {
        let board = SgLayout.initialBoard()
        let before = board.zobrist
        let moves = SgLegality.legalMoves(for: .wei, on: board)
        for move in moves {
            let rec = board.make(move)
            board.unmake(rec)
            XCTAssertEqual(board.zobrist, before, "make/unmake 后哈希应还原（move: \(move)）")
        }
    }

    func testSamePositionSameHash() {
        let b1 = SgLayout.initialBoard()
        let b2 = SgLayout.initialBoard()
        XCTAssertEqual(b1.zobrist, b2.zobrist, "相同初始局面哈希应相同")
    }

    func testDifferentSideToMoveDifferentHash() {
        let b1 = SgLayout.initialBoard()
        let b2 = SgLayout.initialBoard()
        b2.setSideToMove(.shu)
        XCTAssertNotEqual(b1.zobrist, b2.zobrist, "回合方不同哈希应不同")
    }

    func testDifferentPieceDifferentHash() {
        let b1 = SgBoard()
        b1.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        b1.recomputeZobrist()
        let b2 = SgBoard()
        b2.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        b2.recomputeZobrist()
        XCTAssertNotEqual(b1.zobrist, b2.zobrist, "不同棋子哈希应不同")
    }

    func testAnnexChangesZobrist() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 1, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.recomputeZobrist()
        let before = board.zobrist
        board.annex(defeated: .shu, by: .wei)
        XCTAssertNotEqual(board.zobrist, before, "吞并后哈希应变化")
    }

    func testApplyUndoRoundTripPreservesHash() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.recomputeZobrist()
        let before = board.zobrist

        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                          to: SgPos(nation: .shu, file: 5, rank: 2))
        let cap = board.apply(move)
        board.undo(move, captured: cap)
        XCTAssertEqual(board.zobrist, before, "吃子 apply/undo 后哈希应还原")
    }
}
