//
//  TnLegality.swift
//  sanguochese
//
//  2 人标准中国象棋 · 合法性校验
//
//  职责：
//    1. 过滤伪合法走法中"走完后己方主帅被将军"的走法。
//    2. 飞将照面判定（两帅同列且中间无子）。
//    3. 将死/困毙判定。
//

import Foundation

public enum TnLegality {

    /// 生成某方所有合法走法（已过滤将军 + 飞将）。
    public static func legalMoves(for color: TnColor, on board: TnBoard) -> [TnMove] {
        let pseudo = TnMoveGen.pseudoLegalMoves(for: color, on: board)
        return pseudo.filter { move in
            let captured = board.apply(move)
            let ok = !isInCheck(color: color, on: board)
            board.undo(move, captured: captured)
            return ok
        }
    }

    /// 生成某方所有合法**吃子**走法（用于 quiescence）。
    public static func legalCaptures(for color: TnColor, on board: TnBoard) -> [TnMove] {
        let pseudo = TnMoveGen.pseudoCaptures(for: color, on: board)
        return pseudo.filter { move in
            let captured = board.apply(move)
            let ok = !isInCheck(color: color, on: board)
            board.undo(move, captured: captured)
            return ok
        }
    }

    /// color 方主帅是否被将军（被任一敌方棋子攻击，或与敌方主帅飞将照面）。
    public static func isInCheck(color: TnColor, on board: TnBoard) -> Bool {
        guard let myKing = board.kingPos(of: color) else { return false }
        let enemy = color.opponent
        // 1. 飞将照面：两帅同列且中间无子
        if let enemyKing = board.kingPos(of: enemy),
           enemyKing.file == myKing.file {
            let lo = min(myKing.rank, enemyKing.rank) + 1
            let hi = max(myKing.rank, enemyKing.rank) - 1
            var blocked = false
            for r in lo...hi {
                if board.piece(at: TnPos(file: myKing.file, rank: r)) != nil {
                    blocked = true; break
                }
            }
            if !blocked { return true }
        }
        // 2. 被敌方任一棋子攻击
        for (pos, piece) in board.pieces where piece.color == enemy {
            let moves = TnMoveGen.movesFor(piece: piece, at: pos, on: board)
            if moves.contains(where: { $0.to == myKing }) { return true }
        }
        return false
    }

    /// color 方是否无合法走法（将死/困毙）。
    public static func hasNoLegalMoves(color: TnColor, on board: TnBoard) -> Bool {
        legalMoves(for: color, on: board).isEmpty
    }
}
