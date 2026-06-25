//
//  TnEval.swift
//  sanguochese
//
//  2 人标准中国象棋 · 评估函数
//
//  综合三项：
//    1. 子力价值
//    2. 位置加成（每种棋子一张位置表，按 (file, rank) 查分）
//    3. 主帅安全（被将军扣分）
//  机动性默认关闭（开销过大，传统象棋引擎大多不用）。
//
//  位置表以红方视角存储（rank 0 在下），黑方查询时做 rank 翻转 (9 - rank)。
//  分数单位：厘兵（pawn=100）。
//

import Foundation

public enum TnEvaluator {

    // MARK: - 子力价值

    static let kingValue   = 10_000
    static let rookValue   = 900
    static let cannonValue = 450
    static let knightValue = 400
    static let bishopValue = 200
    static let advisorValue = 200
    static let pawnValue   = 100

    static let kingSafetyWeight = 80
    /// 机动性权重：默认 0（关闭）。
    static var mobilityWeight: Int = 0

    // MARK: - 位置表（红方视角，rank 0 在下）

    /// 兵卒位置表（红方视角，9 列 × 10 行）。
    /// 过河后大幅加分，深入敌阵递增。
    static let pawnTable: [[Int]] = [
        // rank 0..9，每行 9 个 file
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 0（己方底线，不可能）
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 1
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 2
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 3（兵初始）
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 4（未过河）
        [ 20,  30,  40,  50,  60,  50,  40,  30,  20],  // rank 5（刚过河）
        [ 30,  40,  50,  70,  80,  70,  50,  40,  30],  // rank 6
        [ 40,  50,  60,  90, 100,  90,  60,  50,  40],  // rank 7
        [ 50,  60,  70, 110, 120, 110,  70,  60,  50],  // rank 8
        [ 60,  70,  80, 130, 140, 130,  80,  70,  60],  // rank 9（敌底线）
    ]

    /// 车位置表
    static let rookTable: [[Int]] = [
        [206, 208, 207, 213, 214, 213, 207, 208, 206],  // rank 0
        [206, 212, 209, 216, 233, 216, 209, 212, 206],  // rank 1
        [206, 208, 207, 214, 216, 214, 207, 208, 206],  // rank 2
        [206, 213, 213, 216, 216, 216, 213, 213, 206],  // rank 3
        [208, 211, 211, 214, 215, 214, 211, 211, 208],  // rank 4
        [208, 212, 212, 214, 215, 214, 212, 212, 208],  // rank 5
        [208, 211, 211, 214, 215, 214, 211, 211, 208],  // rank 6
        [206, 213, 213, 216, 216, 216, 213, 213, 206],  // rank 7
        [206, 208, 207, 214, 216, 214, 207, 208, 206],  // rank 8
        [206, 212, 209, 216, 233, 216, 209, 212, 206],  // rank 9
    ]

    /// 马位置表
    static let knightTable: [[Int]] = [
        [ 90,  90,  90,  96,  90,  96,  90,  90,  90],
        [ 90,  96, 103,  97,  94,  97, 103,  96,  90],
        [ 92,  98,  99, 103,  99, 103,  99,  98,  92],
        [ 93, 108, 100, 107, 100, 107, 100, 108,  93],
        [ 90, 100,  99, 103, 104, 103,  99, 100,  90],
        [ 90,  98, 101, 102, 103, 102, 101,  98,  90],
        [ 92,  94,  98,  95,  98,  95,  98,  94,  92],
        [ 93,  92,  94,  95,  92,  95,  94,  92,  93],
        [ 85,  90,  92,  93,  78,  93,  92,  90,  85],
        [ 90,  90,  98,  87,  90,  87,  98,  90,  90],
    ]

    /// 炮位置表
    static let cannonTable: [[Int]] = [
        [100, 100,  96,  91,  90,  91,  96, 100, 100],
        [ 98,  98,  96,  92,  89,  92,  96,  98,  98],
        [ 97,  97,  96,  91,  92,  91,  96,  97,  97],
        [ 96,  99,  99,  98,  87,  98,  99,  99,  96],
        [ 96,  96,  96,  93,  92,  93,  96,  96,  96],
        [ 95,  96,  99,  96, 100,  96,  99,  96,  95],
        [ 96,  96,  96,  96,  99,  96,  96,  96,  96],
        [ 97,  96, 100,  99, 101,  99, 100,  96,  97],
        [ 96,  97,  98,  98,  98,  98,  98,  97,  96],
        [ 96, 108,  98,  98,  98,  98,  98, 108,  96],
    ]

    /// 相/象位置表
    static let bishopTable: [[Int]] = [
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
    ]

    /// 仕/士位置表
    static let advisorTable: [[Int]] = [
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
        [ 20,  20,  20,  20,  20,  20,  20,  20,  20],
    ]

    /// 帅/将位置表
    static let kingTable: [[Int]] = [
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],
    ]

    // MARK: - 评估

    /// 评估当前局面，返回红方视角的分数（正=红优）。
    /// 不修改 board。
    public static func evaluate(_ board: TnBoard) -> Int {
        var red = score(for: .red, on: board)
        var black = score(for: .black, on: board)
        // 主帅安全：被将军扣分
        if TnLegality.isInCheck(color: .red, on: board) { red -= kingSafetyWeight }
        if TnLegality.isInCheck(color: .black, on: board) { black -= kingSafetyWeight }
        return red - black
    }

    /// 单方综合得分
    static func score(for color: TnColor, on board: TnBoard) -> Int {
        var total = 0
        for (pos, piece) in board.pieces where piece.color == color {
            total += materialValue(of: piece.type)
            total += positionBonus(piece: piece, at: pos)
        }
        if mobilityWeight > 0 {
            total += TnMoveGen.pseudoLegalMoves(for: color, on: board).count * mobilityWeight
        }
        return total
    }

    // MARK: - 子力

    static func materialValue(of type: TnPieceType) -> Int {
        switch type {
        case .king:    return kingValue
        case .rook:    return rookValue
        case .cannon:  return cannonValue
        case .knight:  return knightValue
        case .bishop:  return bishopValue
        case .advisor: return advisorValue
        case .pawn:    return pawnValue
        }
    }

    // MARK: - 位置加成

    /// 查位置表。红方直接查，黑方做 rank 翻转 (9 - rank)。
    static func positionBonus(piece: TnPiece, at pos: TnPos) -> Int {
        let table: [[Int]]
        switch piece.type {
        case .pawn:    table = pawnTable
        case .rook:    table = rookTable
        case .knight:  table = knightTable
        case .cannon:  table = cannonTable
        case .bishop:  table = bishopTable
        case .advisor: table = advisorTable
        case .king:    table = kingTable
        }
        let rank = piece.color == .red ? pos.rank : 9 - pos.rank
        return table[rank][pos.file]
    }
}
