//
//  MakeUnmakeTests.swift
//  SgEngineTests
//
//  白盒：make/unmake 增量走子还原正确性。
//

import XCTest
@testable import SgEngine

final class MakeUnmakeTests: XCTestCase {

    /// make 后 unmake，board 应完全回到初始状态（所有合法走法遍历）
    func testMakeUnmakeRestoresBoardExactly() {
        let board = SgLayout.initialBoard()
        let before = SgBoard(copy: board)
        let moves = SgLegality.legalMoves(for: .wei, on: board)
        for move in moves {
            let rec = board.make(move)
            board.unmake(rec)
            XCTAssertEqual(board.pieces, before.pieces, "make/unmake 后 pieces 应一致（move: \(move)）")
            XCTAssertEqual(board.sideToMove, before.sideToMove, "sideToMove 应还原")
            XCTAssertEqual(board.zobrist, before.zobrist, "zobrist 应还原")
            XCTAssertEqual(board.aliveNations, before.aliveNations)
        }
    }

    /// 连续 make 多步再逐个 unmake，应回到初始状态
    func testSequentialMakeUnmake() {
        let board = SgLayout.initialBoard()
        let before = SgBoard(copy: board)
        var records: [SgBoard.SgMoveRecord] = []
        for _ in 0..<5 {
            let side = board.sideToMove
            let moves = SgLegality.legalMoves(for: side, on: board)
            guard let m = moves.first else { break }
            records.append(board.make(m))
        }
        for rec in records.reversed() {
            board.unmake(rec)
        }
        XCTAssertEqual(board.pieces, before.pieces)
        XCTAssertEqual(board.sideToMove, before.sideToMove)
        XCTAssertEqual(board.zobrist, before.zobrist)
    }

    /// make 吃子后 unmake，被吃棋子应恢复
    func testMakeUnmakeRestoresCapturedPiece() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()
        let before = SgBoard(copy: board)

        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                          to: SgPos(nation: .shu, file: 5, rank: 2))
        let rec = board.make(move)
        XCTAssertNotNil(rec.captured, "应吃到蜀兵")
        board.unmake(rec)

        XCTAssertEqual(board.pieces, before.pieces, "被吃棋子应恢复")
        XCTAssertEqual(board.zobrist, before.zobrist)
    }

    /// apply + undo 应正确还原（旧 API 兼容）
    func testApplyAndUndo() {
        let board = SgLayout.initialBoard()
        let from = SgPos(nation: .wei, file: 1, rank: 4)
        let to = SgPos(nation: .wei, file: 1, rank: 5)
        let move = SgMove(from: from, to: to)
        let captured = board.apply(move)
        XCTAssertNil(captured)
        XCTAssertEqual(board.piece(at: to)?.type, .pawn)
        XCTAssertNil(board.piece(at: from))
        board.undo(move, captured: captured)
        XCTAssertEqual(board.piece(at: from)?.type, .pawn)
        XCTAssertNil(board.piece(at: to))
    }

    /// apply 吃子应返回被吃棋子并占据目标格
    func testApplyCapture() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 5)] = SgPiece(type: .rook, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 5)] = SgPiece(type: .pawn, nation: .shu)
        let move = SgMove(from: SgPos(nation: .wei, file: 5, rank: 5),
                          to: SgPos(nation: .shu, file: 5, rank: 5))
        let captured = board.apply(move)
        XCTAssertEqual(captured?.type, .pawn)
        XCTAssertEqual(captured?.nation, .shu)
        XCTAssertEqual(board.piece(at: SgPos(nation: .shu, file: 5, rank: 5))?.nation, .wei)
    }
}
