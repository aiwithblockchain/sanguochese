//
//  LegalityTests.swift
//  SgEngineTests
//
//  白盒：走法生成、合法性过滤、几何分叉、主帅互照。
//

import XCTest
@testable import SgEngine

final class LegalityTests: XCTestCase {

    // MARK: - 坐标与接线

    func testPosPalaceAndBorder() {
        let kingHome = SgPos(nation: .wei, file: 5, rank: 1)
        XCTAssertTrue(kingHome.isInPalace)
        XCTAssertFalse(kingHome.isAtBorder)

        let border = SgPos(nation: .wei, file: 5, rank: 5)
        XCTAssertTrue(border.isAtBorder)
        XCTAssertFalse(border.isInPalace)

        let palaceCorner = SgPos(nation: .shu, file: 4, rank: 3)
        XCTAssertTrue(palaceCorner.isInPalace)
    }

    func testRoutingFlipMapping() {
        XCTAssertEqual(SgRouting.route(myFile: 1, target: .shu), 9)
        XCTAssertEqual(SgRouting.route(myFile: 9, target: .shu), 1)
        XCTAssertEqual(SgRouting.route(myFile: 5, target: .shu), 5)
    }

    func testNationCycle() {
        XCTAssertEqual(SgNation.wei.next(), .shu)
        XCTAssertEqual(SgNation.shu.next(), .wu)
        XCTAssertEqual(SgNation.wu.next(), .wei)
        XCTAssertEqual(SgNation.wei.opponents().sorted { $0.rawValue < $1.rawValue }, [.shu, .wu])
    }

    // MARK: - 初始布局

    func testInitialLayoutPerNation() {
        let board = SgLayout.initialBoard()
        for nation in SgNation.allCases {
            let positions = board.positions(of: nation)
            XCTAssertEqual(positions.count, 16, "\(nation.displayName) 应有 16 枚棋子")

            let backRow: [SgPieceType] = [.rook, .knight, .bishop, .advisor, .king,
                                          .advisor, .bishop, .knight, .rook]
            for (idx, type) in backRow.enumerated() {
                let p = board.piece(at: SgPos(nation: nation, file: idx + 1, rank: 1))
                XCTAssertNotNil(p, "底线 \(idx+1) 路应有棋子")
                XCTAssertEqual(p?.type, type)
                XCTAssertEqual(p?.nation, nation)
            }
            XCTAssertEqual(board.piece(at: SgPos(nation: nation, file: 2, rank: 3))?.type, .cannon)
            XCTAssertEqual(board.piece(at: SgPos(nation: nation, file: 8, rank: 3))?.type, .cannon)
            for file in [1, 3, 5, 7, 9] {
                XCTAssertEqual(board.piece(at: SgPos(nation: nation, file: file, rank: 4))?.type, .pawn)
            }
        }
        XCTAssertEqual(board.sideToMove, .wei)
        XCTAssertEqual(board.aliveNations.count, 3)
    }

    func testInitialKingPositions() {
        let board = SgLayout.initialBoard()
        for nation in SgNation.allCases {
            let kp = board.kingPos(of: nation)
            XCTAssertNotNil(kp)
            XCTAssertEqual(kp?.file, 5)
            XCTAssertEqual(kp?.rank, 1)
            XCTAssertEqual(kp?.nation, nation)
        }
    }

    // MARK: - 传统走法（己方领土内）

    func testRookInitialMoves() {
        let board = SgLayout.initialBoard()
        let rookPos = SgPos(nation: .wei, file: 1, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: rookPos)!, at: rookPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 1, rank: 4)))
    }

    func testCannonInitialMoves() {
        let board = SgLayout.initialBoard()
        let cannonPos = SgPos(nation: .wei, file: 2, rank: 3)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: cannonPos)!, at: cannonPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 2, rank: 2)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 2, rank: 1)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 7, rank: 3)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 8, rank: 3)))
    }

    func testKnightInitialMoves() {
        let board = SgLayout.initialBoard()
        let knightPos = SgPos(nation: .wei, file: 2, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: knightPos)!, at: knightPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 3)))
    }

    func testBishopInitialMoves() {
        let board = SgLayout.initialBoard()
        let bishopPos = SgPos(nation: .wei, file: 3, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: bishopPos)!, at: bishopPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)))
    }

    func testAdvisorInitialMoves() {
        let board = SgLayout.initialBoard()
        let advPos = SgPos(nation: .wei, file: 4, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: advPos)!, at: advPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 3, rank: 2)))
    }

    func testKingInitialMoves() {
        let board = SgLayout.initialBoard()
        let kingPos = SgPos(nation: .wei, file: 5, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: kingPos)!, at: kingPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 4, rank: 1)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 6, rank: 1)))
    }

    func testPawnInitialMoves() {
        let board = SgLayout.initialBoard()
        let pawnPos = SgPos(nation: .wei, file: 1, rank: 4)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pawnPos)!, at: pawnPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 5)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 2, rank: 4)))
    }

    // MARK: - 国界分叉

    func testRookBorderForking() {
        let board = SgBoard()
        let rookPos = SgPos(nation: .wei, file: 5, rank: 5)
        board.pieces[rookPos] = SgPiece(type: .rook, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: rookPos)!, at: rookPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 5, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 4)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 1)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 5, rank: 1)))
    }

    func testRookBorderForkFlippedFile() {
        let board = SgBoard()
        let rookPos = SgPos(nation: .wei, file: 1, rank: 5)
        board.pieces[rookPos] = SgPiece(type: .rook, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: rookPos)!, at: rookPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 9, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 9, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 9, rank: 1)))
    }

    func testPawnCrossBorderActivatesSideMove() {
        let board = SgBoard()
        let pawnPos = SgPos(nation: .shu, file: 5, rank: 3)
        board.pieces[pawnPos] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pawnPos)!, at: pawnPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 4, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 6, rank: 3)))
    }

    // MARK: - 2 人模式几何分叉

    func testTwoNationModeGeometryForksToSingleEnemy() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let alive = board.aliveNations
        let rays = SgGeometry.outRays(from: SgPos(nation: .wei, file: 5, rank: 5),
                                      owner: .wei, alive: alive)
        XCTAssertEqual(rays.count, 1, "2 人模式国界分叉应只到 1 个敌国")
        XCTAssertTrue(rays[0].contains { $0.nation == .shu })
    }

    // MARK: - 主帅互照

    func testKingsFacingOnEmptyFile() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        XCTAssertTrue(SgLegality.areKingsFacing(
            SgPos(nation: .wei, file: 5, rank: 1),
            SgPos(nation: .shu, file: 5, rank: 1),
            on: board))
        XCTAssertTrue(SgLegality.isKingExposed(side: .wei, on: board))
    }

    func testKingsFacingBlockedByPiece() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 3)] = SgPiece(type: .pawn, nation: .wei)
        XCTAssertFalse(SgLegality.areKingsFacing(
            SgPos(nation: .wei, file: 5, rank: 1),
            SgPos(nation: .shu, file: 5, rank: 1),
            on: board))
        XCTAssertFalse(SgLegality.isKingExposed(side: .wei, on: board))
    }

    func testKingsNotFacingOnDifferentFile() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .king, nation: .shu)
        XCTAssertNil(SgGeometry.cellsBetween(
            kingA: SgPos(nation: .wei, file: 5, rank: 1),
            kingB: SgPos(nation: .shu, file: 6, rank: 1)))
    }

    func testLegalMovesFilterKingExposure() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .wei)
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertTrue(legal.contains { $0.from == SgPos(nation: .wei, file: 5, rank: 4) &&
                                       $0.to == SgPos(nation: .wei, file: 5, rank: 5) })
        XCTAssertFalse(legal.isEmpty)
    }

    // MARK: - 合法走法总数

    func testInitialLegalMoveCount() {
        let board = SgLayout.initialBoard()
        let weiLegal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertFalse(weiLegal.isEmpty)
        let shuLegal = SgLegality.legalMoves(for: .shu, on: board)
        let wuLegal = SgLegality.legalMoves(for: .wu, on: board)
        XCTAssertEqual(weiLegal.count, shuLegal.count)
        XCTAssertEqual(weiLegal.count, wuLegal.count)
    }

    // MARK: - 2 人模式初始局

    func testTwoNationModeInitialBoardHasTwoAliveNations() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        XCTAssertEqual(board.aliveNations, [.wei, .shu])
        XCTAssertEqual(board.mode, .twoNation(human: .wei, ai: .shu))
        XCTAssertTrue(board.positions(of: .wu).isEmpty)
    }
}
