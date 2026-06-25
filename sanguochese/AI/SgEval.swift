//
//  SgEval.swift
//  sanguochese
//
//  三国象棋 · 评估函数 (P5-1 + A-3 PST)
//
//  返回一个三维向量（三国阶段）或降维后的二维/标量（两方阶段）。
//  综合四项：
//    1. 子力价值（帅∞/车9/炮4.5/马4/象2/士2/兵1，参考传统象棋）
//    2. 位置加成（PST 位置表，9×10 owner 视角；通过 logicalPos 映射）
//    3. 主帅安全（对两方分别计算照面威胁度）
//    4. 机动性（合法走法数，默认关闭）
//  另：吞并威胁（若能一手吃帅，大幅加分）由搜索层在走法生成时标注，
//     评估层只对"主帅暴露"做惩罚。
//
//  A-3：位置表以"owner 视角"存储（owner 半盘对应 rank 0..4，敌半盘对应 rank 5..9）。
//  通过 logicalPos(piece:at:side:) 把 SgPos 映射到 9×10 逻辑坐标。
//

import Foundation

/// 评估向量：每个存活方一个分数。
/// 分数越高表示该方局面越好。
/// 已灭国方不出现在向量中。
public struct SgEval: Equatable {
    public var scores: [SgNation: Int]

    public init(scores: [SgNation: Int] = [:]) {
        self.scores = scores
    }

    public subscript(nation: SgNation) -> Int {
        get { scores[nation] ?? 0 }
        set { scores[nation] = newValue }
    }

    /// 单方视角的相对优势 = self - max(opponents)
    /// 用于两方阶段 αβ 的标量评估。
    public func relative(for side: SgNation, alive: Set<SgNation>) -> Int {
        let mine = self[side]
        let worstEnemy = alive.filter { $0 != side }.map { self[$0] }.max() ?? 0
        return mine - worstEnemy
    }
}

public enum SgEvaluator {

    // MARK: - 子力价值（与 SgPieceType.baseValue 一致，此处显式列出便于调参）

    static let kingValue   = 10_000
    static let rookValue   = 900
    static let cannonValue = 450
    static let knightValue = 400
    static let bishopValue = 200
    static let advisorValue = 200
    static let pawnValue   = 100

    static let kingSafetyWeight = 80
    /// 机动性权重：默认 0（关闭）。机动性需 legalMoves，叶节点开销过大。
    /// 如需启用，由搜索层显式传入。
    static var mobilityWeight: Int = 0

    // MARK: - 位置表（owner 视角，9 列 × 10 行）
    // 表以 owner 视角存储：owner 半盘 = rank 0..4，敌半盘 = rank 5..9。
    // 查表前用 logicalPos() 把 SgPos 映射到 (logicalFile 0..8, logicalRank 0..9)。

    /// 兵卒位置表。过河后（rank≥5）大幅加分，深入敌阵递增。
    static let pawnTable: [[Int]] = [
        [  0,   0,   0,   0,   0,   0,   0,   0,   0],  // rank 0（己方底线）
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

    /// 帅/将位置表（全 0，保留接口）
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

    /// 评估当前局面，返回各存活方的分数向量。
    /// 不修改 board。
    public static func evaluate(_ board: SgBoard) -> SgEval {
        var eval = SgEval()
        for nation in board.aliveNations {
            eval[nation] = score(for: nation, on: board)
        }
        return eval
    }

    /// 单方综合得分
    static func score(for side: SgNation, on board: SgBoard) -> Int {
        var total = 0
        // 1. 子力 + 位置
        for (pos, piece) in board.pieces where piece.nation == side {
            total += materialValue(of: piece.type)
            total += positionBonus(piece: piece, at: pos, side: side)
        }
        // 2. 主帅安全：被照面扣分
        if SgLegality.isKingExposed(side: side, on: board) {
            total -= kingSafetyWeight
        }
        // 3. 机动性：默认关闭（mobilityWeight=0），避免叶节点 legalMoves 开销
        if mobilityWeight > 0 {
            let mobility = SgLegality.legalMoves(for: side, on: board).count
            total += mobility * mobilityWeight
        }
        return total
    }

    // MARK: - 子力

    static func materialValue(of type: SgPieceType) -> Int {
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

    // MARK: - 位置加成（PST）

    /// 把 SgPos 映射到 owner 视角的 9×10 逻辑坐标 (logicalFile 0..8, logicalRank 0..9)。
    /// - 己方半盘（pos.nation == side）：logicalFile = file-1, logicalRank = rank-1
    ///   → owner 半盘对应表的 rank 0..4（底部）。
    /// - 敌方半盘（pos.nation != side）：翻转对接 file → 9-file，rank → 10-rank
    ///   → 敌半盘对应表的 rank 5..9（顶部）。
    /// 这样 owner 视角下"自己的子总在底部、敌方的子总在顶部"，与传统象棋红方视角一致。
    static func logicalPos(piece: SgPiece, at pos: SgPos, side: SgNation) -> (file: Int, rank: Int) {
        if pos.nation == side {
            // 己方半盘：直接映射到 rank 0..4
            return (pos.file - 1, pos.rank - 1)
        } else {
            // 敌方半盘：翻转 file（国界对接 10-file → 9-file 给 0..8），
            // rank 翻转（1..5 → 9..5）
            return (9 - pos.file, 10 - pos.rank)
        }
    }

    /// 查位置表。按 owner 视角映射后查表。
    static func positionBonus(piece: SgPiece, at pos: SgPos, side: SgNation) -> Int {
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
        let (f, r) = logicalPos(piece: piece, at: pos, side: side)
        return table[r][f]
    }
}
