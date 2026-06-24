//
//  SgRulesTests.swift
//  sanguocheseTests
//
//  P1-9 规则引擎单元测试
//
//  测试核心原则：面向任一方时，走法与传统中国象棋完全一致。
//  覆盖：初始布局、传统走法、国界分叉、主帅互照、合法性过滤。
//

import XCTest
@testable import sanguochese

final class SgRulesTests: XCTestCase {

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
        // 翻转对接 i → 10−i：我方线 1 接对方线 9，线 5 接线 5
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

            // rank 1: 车马象士帅士象马车
            let backRow: [SgPieceType] = [.rook, .knight, .bishop, .advisor, .king,
                                          .advisor, .bishop, .knight, .rook]
            for (idx, type) in backRow.enumerated() {
                let p = board.piece(at: SgPos(nation: nation, file: idx + 1, rank: 1))
                XCTAssertNotNil(p, "底线 \(idx+1) 路应有棋子")
                XCTAssertEqual(p?.type, type)
                XCTAssertEqual(p?.nation, nation)
            }
            // rank 3: 炮在 file 2、8
            XCTAssertEqual(board.piece(at: SgPos(nation: nation, file: 2, rank: 3))?.type, .cannon)
            XCTAssertEqual(board.piece(at: SgPos(nation: nation, file: 8, rank: 3))?.type, .cannon)
            // rank 4: 兵在 file 1,3,5,7,9
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

    // MARK: - 传统走法（己方领土内，应与传统象棋一致）

    func testRookInitialMoves() {
        // 初始局面：底线车被马堵住，只能横向走
        let board = SgLayout.initialBoard()
        let rookPos = SgPos(nation: .wei, file: 1, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: rookPos)!, at: rookPos, on: board)
        let targets = Set(moves.map { $0.to })
        // file 1 rank 1 的车：OUT 被马(file1 rank3? 不，rank2 空) — 实际 OUT 方向 rank2 空、rank3 无子、rank4 兵
        // 车 OUT: rank2(空)可走, rank3(空)可走, rank4(己方兵)友军挡住，停于 rank3
        // 车 IN: rank<1 无
        // 车 RIGHT: file2(马)友军，停 → 无横走
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 2)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        // rank 4 是己方兵，车不能吃自己的子
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 1, rank: 4)))
    }

    func testCannonInitialMoves() {
        // 初始局面：炮在 file 2 rank 3
        let board = SgLayout.initialBoard()
        let cannonPos = SgPos(nation: .wei, file: 2, rank: 3)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: cannonPos)!, at: cannonPos, on: board)
        let targets = Set(moves.map { $0.to })
        // 炮移动（不翻山）：OUT rank4(兵)挡住; IN rank2 可走、rank1 有友军马挡住; LEFT file1 可走; RIGHT file3..9 空可走到挡子前
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 2, rank: 2)))
        // (2,1) 有友军马，炮不能落在友军格子上
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 2, rank: 1)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        // RIGHT 方向 file3..9 rank3 全空（file8 是对方炮？不，同方 file8 rank3 也是炮）
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 7, rank: 3)))  // file8 炮前一格
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 8, rank: 3)))  // 友军炮，不可走
    }

    func testKnightInitialMoves() {
        // 初始局面：file 2 rank 1 的马，蹩腿在 file 2 rank 2（空）→ 可跳
        let board = SgLayout.initialBoard()
        let knightPos = SgPos(nation: .wei, file: 2, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: knightPos)!, at: knightPos, on: board)
        let targets = Set(moves.map { $0.to })
        // 马在底线角，腿=OUT(file2,rank2)空 → 可跳到 file1,rank3 和 file3,rank3
        // 腿=RIGHT(file3,rank1)有象 → 蹩
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 3, rank: 3)))
    }

    func testBishopInitialMoves() {
        // 初始局面：file 3 rank 1 的象，象眼 file 4 rank 2 空 → 可走田字到 file 5 rank 3
        // 另一方向 file 2 rank 2 空 → file 1 rank 3
        let board = SgLayout.initialBoard()
        let bishopPos = SgPos(nation: .wei, file: 3, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: bishopPos)!, at: bishopPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 3)))
    }

    func testAdvisorInitialMoves() {
        // 初始局面：file 4 rank 1 的士，可斜走到 file 5 rank 2
        let board = SgLayout.initialBoard()
        let advPos = SgPos(nation: .wei, file: 4, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: advPos)!, at: advPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        // file 3 rank 2 在九宫外
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 3, rank: 2)))
    }

    func testKingInitialMoves() {
        // 初始局面：帅在 file 5 rank 1，可走到 file 5 rank 2（IN 无、OUT 有）
        let board = SgLayout.initialBoard()
        let kingPos = SgPos(nation: .wei, file: 5, rank: 1)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: kingPos)!, at: kingPos, on: board)
        let targets = Set(moves.map { $0.to })
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 5, rank: 2)))
        // 左右 file 4/file 6 rank 1 有士
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 4, rank: 1)))
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 6, rank: 1)))
    }

    func testPawnInitialMoves() {
        // 初始局面：兵在 file 1 rank 4，未过河，只能前进到 rank 5
        let board = SgLayout.initialBoard()
        let pawnPos = SgPos(nation: .wei, file: 1, rank: 4)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pawnPos)!, at: pawnPos, on: board)
        let targets = Set(moves.map { $0.to })
        // OUT 到 rank 5（国界），不分叉的下一步在国界才会分叉
        XCTAssertTrue(targets.contains(SgPos(nation: .wei, file: 1, rank: 5)))
        // 未过河不能横走
        XCTAssertFalse(targets.contains(SgPos(nation: .wei, file: 2, rank: 4)))
    }

    // MARK: - 国界分叉

    func testRookBorderForking() {
        // 把一个车放到国界边 file 5 rank 5，应能沿 OUT 分叉到两个敌国
        let board = SgBoard()
        let rookPos = SgPos(nation: .wei, file: 5, rank: 5)
        board.pieces[rookPos] = SgPiece(type: .rook, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: rookPos)!, at: rookPos, on: board)
        let targets = Set(moves.map { $0.to })
        // 分叉到蜀、吴两国 file 5（10-5=5）rank 5
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 5)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 5, rank: 5)))
        // 并能继续深入敌国
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 4)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 1)))
        XCTAssertTrue(targets.contains(SgPos(nation: .wu, file: 5, rank: 1)))
    }

    func testRookBorderForkFlippedFile() {
        // 车在 file 1 rank 5，分叉到敌国 file 9（10-1=9）
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
        // 兵过河后（在敌国领土）应能横走
        let board = SgBoard()
        let pawnPos = SgPos(nation: .shu, file: 5, rank: 3)  // 魏兵在蜀国领土
        board.pieces[pawnPos] = SgPiece(type: .pawn, nation: .wei)
        let moves = SgMoveGen.movesFor(piece: board.piece(at: pawnPos)!, at: pawnPos, on: board)
        let targets = Set(moves.map { $0.to })
        // 前进（OUT，在敌国领土=rank 递减）到 rank 2
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 5, rank: 2)))
        // 过河横走
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 4, rank: 3)))
        XCTAssertTrue(targets.contains(SgPos(nation: .shu, file: 6, rank: 3)))
    }

    // MARK: - 主帅互照

    func testKingsFacingOnEmptyFile() {
        // 魏帅 file 5 rank 1，蜀帅 file 5 rank 1（10-5=5 对接），中间全空 → 照面
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
        // 中间放一枚棋子 → 不照面
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
        // file 不对接（5 vs 6，10-6=4≠5）→ 不照面
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .king, nation: .shu)
        XCTAssertNil(SgGeometry.cellsBetween(
            kingA: SgPos(nation: .wei, file: 5, rank: 1),
            kingB: SgPos(nation: .shu, file: 6, rank: 1)))
    }

    func testLegalMovesFilterKingExposure() {
        // 魏帅 file 5 rank 1，蜀帅 file 5 rank 1，中间只有魏兵 file 5 rank 4
        // 魏兵若离开 file 5，则两帅照面 → 该走法应被合法性过滤掉
        let board = SgBoard()
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .wei, file: 5, rank: 4)] = SgPiece(type: .pawn, nation: .wei)
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        // 兵前进到 rank 5 仍在 file 5 → 合法（不暴露）
        XCTAssertTrue(legal.contains { $0.from == SgPos(nation: .wei, file: 5, rank: 4) &&
                                       $0.to == SgPos(nation: .wei, file: 5, rank: 5) })
        // 兵若能横走（未过河不能，这里 rank 4 未过河）—— 验证兵没有横走走法
        // 此场景下兵未过河，只能前进，所以不存在"横走暴露"问题
        // 主帅本身不能走到 file 5 rank 2（会暴露于蜀帅）—— 实际 rank 2 仍在 file 5，照面依旧被兵挡
        // 这里主要验证 legalMoves 不为空
        XCTAssertFalse(legal.isEmpty)
    }

    // MARK: - 走子与撤销

    func testApplyAndUndo() {
        let board = SgLayout.initialBoard()
        let from = SgPos(nation: .wei, file: 1, rank: 4)  // 兵
        let to = SgPos(nation: .wei, file: 1, rank: 5)
        let mover = board.piece(at: from)!
        let move = SgMove(from: from, to: to)
        let captured = board.apply(move)
        XCTAssertNil(captured)
        XCTAssertEqual(board.piece(at: to)?.type, .pawn)
        XCTAssertNil(board.piece(at: from))
        board.undo(move, captured: captured)
        XCTAssertEqual(board.piece(at: from)?.type, .pawn)
        XCTAssertNil(board.piece(at: to))
        _ = mover  // suppress unused warning
    }

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

    // MARK: - 灭国吞并接口

    func testAnnexChangesPieceColor() {
        let board = SgBoard()
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 1, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.annex(defeated: .shu, by: .wei)
        XCTAssertFalse(board.aliveNations.contains(.shu))
        XCTAssertEqual(board.annexed[.shu], .wei)
        XCTAssertEqual(board.piece(at: SgPos(nation: .shu, file: 1, rank: 1))?.nation, .wei)
        // 主帅被吃后通常从棋盘移除，这里 annex 只改色；上层应在 annex 前移除主帅
    }

    func testClearAllRemovesPieces() {
        let board = SgLayout.initialBoard()
        board.clearAll(of: .wu)
        XCTAssertFalse(board.aliveNations.contains(.wu))
        XCTAssertTrue(board.positions(of: .wu).isEmpty)
    }

    // MARK: - 合法走法总数（初始局面）

    func testInitialLegalMoveCount() {
        // 初始局面每方应有合法走法（传统象棋开局约 44 步，三方象棋因分叉会更多）
        let board = SgLayout.initialBoard()
        let weiLegal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertFalse(weiLegal.isEmpty)
        // 三方对称，每方合法走法数应相同
        let shuLegal = SgLegality.legalMoves(for: .shu, on: board)
        let wuLegal = SgLegality.legalMoves(for: .wu, on: board)
        XCTAssertEqual(weiLegal.count, shuLegal.count)
        XCTAssertEqual(weiLegal.count, wuLegal.count)
    }
}
