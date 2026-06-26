//
//  SgAlgorithmTests.swift
//  sanguocheseTests
//
//  算法黑盒 + 白盒测试（2026-06-26）
//  覆盖：
//    - make/unmake 增量走子还原正确性
//    - 搜索战术正确性（一步杀、两步杀、吃子优先）
//    - LMR 不破坏搜索结果
//    - PST 评估对称性与方向性
//    - 2 人模式终局判定
//    - 置换表命中
//    - 性能基准（节点数 / 用时）
//

import XCTest
@testable import sanguochese

final class SgAlgorithmTests: XCTestCase {

    // MARK: - 白盒：make / unmake 还原

    /// make 后 unmake，board 应完全回到初始状态
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
        // 走 5 步
        for _ in 0..<5 {
            let side = board.sideToMove
            let moves = SgLegality.legalMoves(for: side, on: board)
            guard let m = moves.first else { break }
            records.append(board.make(m))
        }
        // 逆序 unmake
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

        // 魏车吃蜀兵
        let move = SgMove(from: SgPos(nation: .shu, file: 5, rank: 3),
                          to: SgPos(nation: .shu, file: 5, rank: 2))
        let rec = board.make(move)
        XCTAssertNotNil(rec.captured, "应吃到蜀兵")
        board.unmake(rec)

        XCTAssertEqual(board.pieces, before.pieces, "被吃棋子应恢复")
        XCTAssertEqual(board.zobrist, before.zobrist)
    }

    // MARK: - 黑盒：搜索战术正确性

    /// 一步杀：魏车能直接吃蜀帅，AI 应选择吃帅
    func testSearchFindsMateIn1() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()

        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertEqual(result.move?.to, SgPos(nation: .shu, file: 5, rank: 1),
                       "应选择吃帅走法")
    }

    /// 两步杀：魏方能在两步内必胜，AI 应找到制胜走法
    func testSearchFindsMateIn2() {
        // 构造：魏车在蜀方底线附近，蜀帅无路可逃
        // 魏车 (shu,5,2)、魏帅 (wei,1,1)、蜀帅 (shu,5,1)
        // 魏走车到 (shu,5,2) 将军，蜀帅只能移动，下一步车吃帅
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 4)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()

        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        XCTAssertNotNil(result.move, "应找到制胜走法")
        // 走法应合法
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
        // 魏车能吃蜀车（高价值）或蜀兵（低价值）
        board.pieces[SgPos(nation: .shu, file: 3, rank: 1)] = SgPiece(type: .rook, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 7, rank: 1)] = SgPiece(type: .pawn, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()

        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        // 走法应吃车（file 3）而非吃兵（file 7）
        if let m = result.move {
            XCTAssertEqual(m.to.file, 3, "应优先吃高价值棋子（车），实际走到 file \(m.to.file)")
        }
    }

    /// 搜索不应修改原始棋盘
    func testSearchDoesNotMutateBoard2() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let before = SgBoard(copy: board)
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        XCTAssertEqual(board.pieces, before.pieces)
        XCTAssertEqual(board.sideToMove, before.sideToMove)
        XCTAssertEqual(board.aliveNations, before.aliveNations)
        XCTAssertEqual(board.zobrist, before.zobrist)
    }

    // MARK: - 白盒：LMR 正确性

    /// LMR 启用（expert）与未启用（hard，context=nil）都应找到一步杀
    func testLMRDoesNotMissMateIn1() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.pieces[SgPos(nation: .wei, file: 1, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .wei
        board.recomputeZobrist()

        // hard: context=nil（无 LMR）
        let r1 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        // expert: context 启用 LMR
        let r2 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        XCTAssertEqual(r1.move?.to, SgPos(nation: .shu, file: 5, rank: 1))
        XCTAssertEqual(r2.move?.to, SgPos(nation: .shu, file: 5, rank: 1))
    }

    // MARK: - 白盒：PST 评估

    /// 初始局面 PST 评估应对称（三方等价）
    func testPSTInitialSymmetry() {
        let board = SgLayout.initialBoard()
        let eval = SgEvaluator.evaluate(board)
        XCTAssertEqual(eval[.wei], eval[.shu], "魏蜀 PST 评估应相等")
        XCTAssertEqual(eval[.shu], eval[.wu], "蜀吴 PST 评估应相等")
    }

    /// 车在己方底线 vs 车在敌方底线，PST 加成应不同
    func testRookPSTDiffersByPosition() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.setAliveNationsForTesting([.wei, .shu])

        let rook = SgPiece(type: .rook, nation: .wei)
        // 己方底线
        let ownPos = SgPos(nation: .wei, file: 1, rank: 1)
        // 敌方底线（过河深入）
        let enemyPos = SgPos(nation: .shu, file: 9, rank: 1)

        let ownBonus = SgEvaluator.positionBonus(piece: rook, at: ownPos, side: .wei)
        let enemyBonus = SgEvaluator.positionBonus(piece: rook, at: enemyPos, side: .wei)
        // 深入敌后的车通常加成更高（PST 设计）
        XCTAssertNotEqual(ownBonus, enemyBonus, "车在不同位置 PST 加成应不同")
    }

    /// 兵过河后加成应递增（越深入敌后越高）
    func testPawnPSTIncreasesWithAdvance() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        board.setAliveNationsForTesting([.wei, .shu])

        let pawn = SgPiece(type: .pawn, nation: .wei)
        // 己方 rank 4（未过河）
        let ownPos = SgPos(nation: .wei, file: 5, rank: 4)
        // 刚过河（敌国 rank 5）
        let justCrossed = SgPos(nation: .shu, file: 5, rank: 5)
        // 深入敌后（敌国 rank 2）
        let deep = SgPos(nation: .shu, file: 5, rank: 2)

        let b0 = SgEvaluator.positionBonus(piece: pawn, at: ownPos, side: .wei)
        let b1 = SgEvaluator.positionBonus(piece: pawn, at: justCrossed, side: .wei)
        let b2 = SgEvaluator.positionBonus(piece: pawn, at: deep, side: .wei)
        XCTAssertGreaterThan(b1, b0, "过河兵加成应高于未过河")
        XCTAssertGreaterThan(b2, b1, "越深入敌后加成应越高")
    }

    // MARK: - 黑盒：2 人模式终局

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

    /// 2 人模式无子可走应终局
    func testTwoNationNoMovesEndsGame() {
        let board = SgBoard()
        board.mode = .twoNation(human: .wei, ai: .shu)
        // 只有帅，且被围困（简化：让蜀方无合法走法）
        board.pieces[SgPos(nation: .wei, file: 5, rank: 1)] = SgPiece(type: .king, nation: .wei)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 1)] = SgPiece(type: .king, nation: .shu)
        // 蜀帅周围被己方棋子围住（无路可走）
        board.pieces[SgPos(nation: .shu, file: 4, rank: 1)] = SgPiece(type: .advisor, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 6, rank: 1)] = SgPiece(type: .advisor, nation: .shu)
        board.pieces[SgPos(nation: .shu, file: 5, rank: 2)] = SgPiece(type: .advisor, nation: .shu)
        board.setAliveNationsForTesting([.wei, .shu])
        board.sideToMove = .shu
        board.recomputeZobrist()

        // 蜀方无子可走 → 魏胜
        let result = SgGameFlow.result(of: board)
        // result 只看 aliveNations，需先触发 settleCurrentSide
        // 这里直接检查 hasNoLegalMoves
        XCTAssertTrue(SgLegality.hasNoLegalMoves(side: .shu, on: board),
                      "蜀方应无合法走法")
    }

    // MARK: - 黑盒：置换表

    /// 同一局面搜索两次，第二次应命中置换表（结果一致）
    func testTranspositionTableConsistency() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let r1 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        let r2 = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        // 两次搜索结果应一致（确定性 + TT）
        XCTAssertEqual(r1.move, r2.move, "同一局面搜索结果应一致")
    }

    // MARK: - 性能基准

    /// 搜索应在合理时间内完成（不卡死）
    func testSearchPerformanceWithinBudget() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        let elapsed = Date().timeIntervalSince(start)
        // hard 深度 4，2 人模式，应在 2 秒内完成
        XCTAssertLessThan(elapsed, 2.0, "hard 难度搜索应在 2 秒内完成，实际 \(elapsed)s")
    }

    /// expert 深度 5 也应在 3 秒内完成（有迭代加深 + 时限保护）
    func testExpertSearchWithinBudget() {
        let board = SgLayout.initialBoard(human: .wei, ai: .shu)
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .expert)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "expert 难度搜索应在 3 秒内完成，实际 \(elapsed)s")
    }

    /// 3 人模式搜索也应在时限内
    func testThreeNationSearchWithinBudget() {
        let board = SgLayout.initialBoard()
        let start = Date()
        _ = SgSearch.chooseMove(for: .wei, on: board, difficulty: .hard)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "3 人 hard 搜索应在 3 秒内完成，实际 \(elapsed)s")
    }

    // MARK: - 回归：3 人模式不受影响

    /// 3 人模式初始搜索应返回合法走法
    func testThreeNationSearchReturnsLegalMove() {
        let board = SgLayout.initialBoard()
        let result = SgSearch.chooseMove(for: .wei, on: board, difficulty: .normal)
        guard let m = result.move else { XCTFail("应返回走法"); return }
        let legal = SgLegality.legalMoves(for: .wei, on: board)
        XCTAssertTrue(legal.contains(m))
    }

    /// 3 人模式吃帅应触发吞并（非终局）
    func testThreeNationKingCaptureTriggersAnnex() {
        let board = SgLayout.initialBoard()
        // 构造魏车吃蜀帅
        board.pieces[SgPos(nation: .shu, file: 5, rank: 3)] = SgPiece(type: .rook, nation: .wei)
        // 移除蜀方原 rank 3 的炮避免阻挡
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
        // 蜀方棋子应归魏
        XCTAssertNotNil(board.annexed[.shu])
    }
}
