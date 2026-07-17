//
//  SgLegality.swift
//  sanguochese
//
//  三国象棋 · 合法性校验 + 三方主帅互照
//  P1-7 合法性校验 + P1-8 三方主帅互照
//
//  职责：
//    1. 过滤伪合法走法中"走完后己方主帅被任一敌方主帅照面"的走法。
//    2. 检测三方主帅互照（借刀杀人）：若一方无合法走法能同时解除两方照面，判灭国。
//

import Foundation

public enum SgLegality {

    /// 生成某方的所有合法走法（已过滤"走完后己方主帅被将军"）。
    public static func legalMoves(for side: SgNation, on board: SgBoard) -> [SgMove] {
        let pseudo = SgMoveGen.pseudoLegalMoves(for: side, on: board)
        return pseudo.filter { move in
            // 模拟走子，检查走完后己方主帅是否被任一敌方攻击（含飞将）
            let captured = board.apply(move)
            let ok = !isInCheck(side: side, on: board)
            board.undo(move, captured: captured)
            return ok
        }
    }

    /// 生成某方的所有合法**吃子**走法（用于 quiescence 搜索）。
    /// 已过滤将军。
    public static func legalCaptures(for side: SgNation, on board: SgBoard) -> [SgMove] {
        let pseudo = SgMoveGen.pseudoCaptures(for: side, on: board)
        return pseudo.filter { move in
            let captured = board.apply(move)
            let ok = !isInCheck(side: side, on: board)
            board.undo(move, captured: captured)
            return ok
        }
    }

    /// 判断 side 的主帅是否与任一敌方主帅无遮挡相对（飞将）。
    /// 若 side 已无主帅（已灭国），返回 false。
    public static func isKingExposed(side: SgNation, on board: SgBoard) -> Bool {
        guard let myKing = board.kingPos(of: side) else { return false }
        for enemy in side.opponents() {
            guard let enemyKing = board.kingPos(of: enemy) else { continue }
            if areKingsFacing(myKing, enemyKing, on: board) {
                return true
            }
        }
        return false
    }

    /// 两帅是否在同一连通纵线上且中间无棋子（照面）。
    public static func areKingsFacing(_ a: SgPos, _ b: SgPos, on board: SgBoard) -> Bool {
        guard let cells = SgGeometry.cellsBetween(kingA: a, kingB: b) else { return false }
        return cells.allSatisfy { board.piece(at: $0) == nil }
    }

    /// 判断 side 是否处于被将军状态（主帅被任一敌方棋子攻击，或被飞将）。
    /// 这是真正的将军检测：车/炮射线 + 马跳跃 + 兵推进 + 飞将。
    public static func isInCheck(side: SgNation, on board: SgBoard) -> Bool {
        guard let myKing = board.kingPos(of: side) else { return false }
        // 1. 飞将：两帅无遮挡相对
        if isKingExposed(side: side, on: board) { return true }
        // 2. 任意敌方棋子攻击主帅
        for enemy in board.aliveNations where enemy != side {
            if isSquareAttacked(myKing, by: enemy, on: board) { return true }
        }
        return false
    }

    /// 判断 `target` 格是否被 `attacker` 方的任意棋子攻击（不含飞将，不含对方主帅自身）。
    /// 用于将军检测：从 target 沿射线扫描车/炮，逐子检测马/兵。
    /// 优化：马/兵不调用完整走法生成，直接内联检测以减少分配。
    static func isSquareAttacked(_ target: SgPos, by attacker: SgNation, on board: SgBoard) -> Bool {
        let allNations = board.aliveNations

        // 1. 车 / 炮：从 target 沿 4 向射线扫描
        //    射线以 target 所在国为基准生成（覆盖 target 的纵向线含国界分叉 + 横向线）
        let fileRays: [[SgPos]] =
            SgGeometry.outRays(from: target, owner: target.nation, alive: allNations) +
            SgGeometry.inRays(from: target, owner: target.nation, alive: allNations)
        let rankRays: [[SgPos]] =
            [SgGeometry.leftRay(from: target), SgGeometry.rightRay(from: target)]

        for ray in fileRays + rankRays {
            var seenScreen = false
            for cell in ray {
                guard let p = board.piece(at: cell) else { continue }
                if !seenScreen {
                    // 第一枚棋子：若是敌方车，则 target 被车攻击
                    if p.nation == attacker && p.type == .rook { return true }
                    // 任何棋子都可作为炮架子
                    seenScreen = true
                } else {
                    // 第二枚棋子：若是敌方炮，则 target 被炮攻击
                    if p.nation == attacker && p.type == .cannon { return true }
                    // 第三枚及以后不再可能构成炮攻击
                    break
                }
            }
        }

        // 2. 马 / 兵：逐子检测，但避免生成完整走法列表（减少临时分配）。
        //    对每枚 attacker's 马/兵，直接检查 target 是否在其攻击范围内。
        for (pos, piece) in board.pieces where piece.nation == attacker {
            switch piece.type {
            case .knight:
                // 马：target 必须在 pos 的 knightTargets 中（且腿格不蹩）
                let candidates = SgMoveGen.knightTargets(from: pos, owner: attacker, alive: allNations)
                for (t, leg) in candidates where t == target {
                    if let l = leg, board.piece(at: l) != nil { continue }
                    return true
                }
            case .pawn:
                // 兵：target 必须在 pos 的 pawnMoves 中
                // 收编兵卒走法也走 pawnMoves，直接调用并查找即可。
                // 兵最多 3 个目标，生成代价极低。
                let moves = SgMoveGen.pawnMoves(at: pos, owner: attacker, on: board)
                if moves.contains(where: { $0.to == target }) { return true }
            default:
                break
            }
        }
        return false
    }

    /// 判断 side 是否无合法走法（将死/困毙）。
    /// 在三国象棋中：无合法走法 = 灭国。
    public static func hasNoLegalMoves(side: SgNation, on board: SgBoard) -> Bool {
        return legalMoves(for: side, on: board).isEmpty
    }

    /// 借刀杀人判定：side 是否同时被两方主帅照面，且无一手能同时解除。
    /// 返回 true 表示 side 应被判灭国。
    public static func isDoubleCheckedToDeath(side: SgNation, on board: SgBoard) -> Bool {
        guard let myKing = board.kingPos(of: side) else { return false }
        let facingEnemies = side.opponents().filter { enemy in
            guard let ek = board.kingPos(of: enemy) else { return false }
            return areKingsFacing(myKing, ek, on: board)
        }
        // 必须同时被两方照面
        guard facingEnemies.count == 2 else { return false }
        // 是否存在一手能同时解除两方照面
        return legalMoves(for: side, on: board).isEmpty
    }
}
