//
//  SgEval.swift
//  sanguochese
//
//  三国象棋 · 评估函数 (P5-1)
//
//  返回一个三维向量（三国阶段）或降维后的二维/标量（两方阶段）。
//  综合四项：
//    1. 子力价值（帅∞/车9/炮4.5/马4/象2/士2/兵1，参考传统象棋）
//    2. 位置加成（中心线、过河兵、车占肋、马居要位）
//    3. 主帅安全（对两方分别计算照面威胁度）
//    4. 机动性（合法走法数）
//  另：吞并威胁（若能一手吃帅，大幅加分）由搜索层在走法生成时标注，
//     评估层只对"主帅暴露"做惩罚。
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

    /// 位置加成的最大幅度（避免压过子力）
    static let positionWeight = 30
    static let mobilityWeight = 2
    static let kingSafetyWeight = 80

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
        // 3. 机动性：合法走法数 * 小权重
        //    注意：legalMoves 较贵，深度搜索时由调用方决定是否启用。
        //    这里默认启用，保证评估有动态感。
        let mobility = SgLegality.legalMoves(for: side, on: board).count
        total += mobility * mobilityWeight
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

    // MARK: - 位置加成

    /// 简化版位置加成：
    ///   - 过河兵：+15（已进入敌国领土）
    ///   - 车占肋（file 4/5/6 且 rank≥3）：+10
    ///   - 马居中（file 4..6）：+8
    ///   - 炮居中线（file 5）：+6
    ///   - 兵卒过国界后深入：+5
    static func positionBonus(piece: SgPiece, at pos: SgPos, side: SgNation) -> Int {
        switch piece.type {
        case .pawn:
            if pos.nation != side {
                // 过河兵
                return 15
            }
            // 未过河兵：靠前略加
            return max(0, pos.rank - 2) * 3
        case .rook:
            if (4...6).contains(pos.file) && pos.rank >= 3 { return 10 }
            return 0
        case .knight:
            if (4...6).contains(pos.file) { return 8 }
            return 0
        case .cannon:
            if pos.file == 5 { return 6 }
            return 0
        case .king, .advisor, .bishop:
            return 0
        }
    }
}
