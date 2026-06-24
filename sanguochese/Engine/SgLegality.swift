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

    /// 生成某方的所有合法走法（已过滤主帅互照）。
    public static func legalMoves(for side: SgNation, on board: SgBoard) -> [SgMove] {
        let pseudo = SgMoveGen.pseudoLegalMoves(for: side, on: board)
        return pseudo.filter { move in
            // 模拟走子，检查走完后己方主帅是否被任一敌方主帅照面
            let captured = board.apply(move)
            let ok = !isKingExposed(side: side, on: board)
            board.undo(move, captured: captured)
            return ok
        }
    }

    /// 判断 side 的主帅是否与任一敌方主帅无遮挡相对（照面）。
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

    /// 检查 side 是否处于"被照面"状态（类似传统象棋的"被将军"）。
    public static func isInCheck(side: SgNation, on board: SgBoard) -> Bool {
        return isKingExposed(side: side, on: board)
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
