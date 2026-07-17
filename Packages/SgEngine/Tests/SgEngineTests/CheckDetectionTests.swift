//
//  CheckDetectionTests.swift
//  SgEngineTests
//
//  白盒：将军检测 isInCheck / isSquareAttacked / isKingExposed 的正确性。
//  目标：覆盖车/炮/马/兵将军、飞将、解将、双将，以及与 legalMoves 的一致性。
//  这是定位"AI 弱智 + 慢"核心 bug 的关键测试集。
//

import XCTest
@testable import SgEngine

final class CheckDetectionTests: XCTestCase {

    // MARK: - isKingExposed（飞将）

    func testKingExposedWhenTwoKingsFaceNoBlock() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isKingExposed(side: .wei, on: board), "两帅无遮挡相对应飞将")
        XCTAssertTrue(SgLegality.isKingExposed(side: .shu, on: board))
    }

    func testKingNotExposedWhenBlocked() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertFalse(SgLegality.isKingExposed(side: .wei, on: board), "中间有子不应飞将")
    }

    // MARK: - isInCheck（真将军）

    func testRookCheckFromSameFile() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "魏车应将军蜀帅")
        XCTAssertFalse(SgLegality.isInCheck(side: .wei, on: board))
    }

    func testRookCheckFromSameRank() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "横向车应将军")
    }

    func testCannonCheckWithScreen() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .cannon, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "炮翻山应将军")
    }

    func testCannonNoCheckWithoutScreen() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .cannon, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertFalse(SgLegality.isInCheck(side: .shu, on: board), "炮无炮架子不应将军")
    }

    func testKnightCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        // 魏马在 (shu,6,3)，可跳到 (shu,5,1) 吃帅（腿在 shu,6,2）
        board.pieces[SgPos(nation: .shu, file: 6, rank: 3)] = SgPiece(type: .knight, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "马应将军")
    }

    func testKnightNoCheckWhenLegBlocked() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 3)] = SgPiece(type: .knight, nation: .wei)
        // 蹩马腿
        board.pieces[SgPos(nation: .shu, file: 6, rank: 2)] = SgPiece(type: .pawn, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertFalse(SgLegality.isInCheck(side: .shu, on: board), "蹩腿马不应将军")
    }

    func testPawnCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        // 魏过河兵在 (shu,5,2)，可前进吃帅
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .pawn, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "过河兵应将军")
    }

    func testPawnSidewaysCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        // 魏过河兵在 (shu,4,1)，可横走到 (shu,5,1) 吃帅
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .pawn, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isInCheck(side: .shu, on: board), "过河兵横走应将军")
    }

    // MARK: - isSquareAttacked

    func testIsSquareAttackedByRook() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        XCTAssertTrue(SgLegality.isSquareAttacked(SgPos(nation: .shu, file: 5, rank: 1),
                                                  by: .wei, on: board))
    }

    // MARK: - legalMoves 过滤一致性

    func testLegalMovesFiltersMovesLeavingKingInCheck() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        // 蜀帅只能走，走到 (shu,5,2) 会被车将军，应被过滤
        let legal = SgLegality.legalMoves(for: .shu, on: board)
        let targets = Set(legal.map { $0.to })
        XCTAssertFalse(targets.contains(SgPos(nation: .shu, file: 5, rank: 2)),
                       "走进将军位置的走法应被过滤")
    }

    // MARK: - 关键回归：inCheckPenalty 是否被 eval 使用
    // 此测试用于暴露 Bug A：inCheckPenalty 定义但未使用

    func testEvalPenalizesBeingInCheck() {
        let board1 = SgBoard()
        board1.mode = .twoNation(human: .wei, ai: .shu)
        board1.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board1.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board1.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board1.setAliveNationsForTesting([.wei, .shu])
        // 蜀被将军

        let board2 = SgBoard()
        board2.mode = .twoNation(human: .wei, ai: .shu)
        board2.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board2.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board2.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .shu)
        board2.setAliveNationsForTesting([.wei, .shu])
        // 蜀未被将军（车是自己的）

        let eval1 = SgEvaluator.evaluate(board1)
        let eval2 = SgEvaluator.evaluate(board2)
        // 若 inCheckPenalty 生效，被将军的蜀方分数应明显低于未被将军的蜀方
        XCTAssertLessThan(eval1[.shu], eval2[.shu] - 100,
                          "被将军方应受明显惩罚（inCheckPenalty 应生效），实际: \(eval1[.shu]) vs \(eval2[.shu])")
    }
}
