//
//  TnMoveGen.swift
//  sanguochese
//
//  2 人标准中国象棋 · 走法生成
//
//  生成各棋子的伪合法走法（不检查照面/将军，由 TnLegality 过滤）。
//  坐标：file 0..8，rank 0..9。红方在下（rank 小），黑方在上（rank 大）。
//

import Foundation

public enum TnMoveGen {

    /// 生成某方所有伪合法走法（含吃子）。
    public static func pseudoLegalMoves(for color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        for (pos, piece) in board.pieces where piece.color == color {
            moves.append(contentsOf: movesFor(piece: piece, at: pos, on: board))
        }
        return moves
    }

    /// 生成某方所有伪合法**吃子**走法（仅吃子，用于 quiescence）。
    public static func pseudoCaptures(for color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        for (pos, piece) in board.pieces where piece.color == color {
            for m in movesFor(piece: piece, at: pos, on: board) where board.piece(at: m.to) != nil {
                moves.append(m)
            }
        }
        return moves
    }

    /// 单枚棋子的所有伪合法走法。
    public static func movesFor(piece: TnPiece, at pos: TnPos, on board: TnBoard) -> [TnMove] {
        switch piece.type {
        case .rook:    return rookMoves(at: pos, color: piece.color, on: board)
        case .cannon:  return cannonMoves(at: pos, color: piece.color, on: board)
        case .knight:  return knightMoves(at: pos, color: piece.color, on: board)
        case .bishop:  return bishopMoves(at: pos, color: piece.color, on: board)
        case .advisor: return advisorMoves(at: pos, color: piece.color, on: board)
        case .king:    return kingMoves(at: pos, color: piece.color, on: board)
        case .pawn:    return pawnMoves(at: pos, color: piece.color, on: board)
        }
    }

    // MARK: - 车

    static func rookMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (df, dr) in dirs {
            var f = pos.file + df
            var r = pos.rank + dr
            while (0...8).contains(f) && (0...9).contains(r) {
                let to = TnPos(file: f, rank: r)
                if let occ = board.piece(at: to) {
                    if occ.color != color { moves.append(TnMove(from: pos, to: to)) }
                    break
                }
                moves.append(TnMove(from: pos, to: to))
                f += df; r += dr
            }
        }
        return moves
    }

    // MARK: - 炮

    static func cannonMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (df, dr) in dirs {
            var f = pos.file + df
            var r = pos.rank + dr
            var jumped = false
            while (0...8).contains(f) && (0...9).contains(r) {
                let to = TnPos(file: f, rank: r)
                if let occ = board.piece(at: to) {
                    if !jumped {
                        jumped = true
                    } else {
                        if occ.color != color { moves.append(TnMove(from: pos, to: to)) }
                        break
                    }
                } else if !jumped {
                    moves.append(TnMove(from: pos, to: to))
                }
                f += df; r += dr
            }
        }
        return moves
    }

    // MARK: - 马（蹩马腿）

    static func knightMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        // 8 个日字目标 + 对应马腿
        let candidates: [(target: (Int, Int), leg: (Int, Int))] = [
            (( 1,  2), ( 0,  1)), ((-1,  2), ( 0,  1)),
            (( 1, -2), ( 0, -1)), ((-1, -2), ( 0, -1)),
            (( 2,  1), ( 1,  0)), (( 2, -1), ( 1,  0)),
            ((-2,  1), (-1,  0)), ((-2, -1), (-1,  0)),
        ]
        for (t, l) in candidates {
            let tf = pos.file + t.0, tr = pos.rank + t.1
            guard (0...8).contains(tf) && (0...9).contains(tr) else { continue }
            let legPos = TnPos(file: pos.file + l.0, rank: pos.rank + l.1)
            if board.piece(at: legPos) != nil { continue }  // 蹩腿
            let to = TnPos(file: tf, rank: tr)
            if let occ = board.piece(at: to), occ.color == color { continue }
            moves.append(TnMove(from: pos, to: to))
        }
        return moves
    }

    // MARK: - 相/象（塞象眼，不过河）

    static func bishopMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let dirs = [(2, 2), (2, -2), (-2, 2), (-2, -2)]
        for (df, dr) in dirs {
            let tf = pos.file + df, tr = pos.rank + dr
            guard (0...8).contains(tf) && (0...9).contains(tr) else { continue }
            // 不过河
            if color == .red && tr > 4 { continue }
            if color == .black && tr < 5 { continue }
            // 塞象眼
            let eye = TnPos(file: pos.file + df / 2, rank: pos.rank + dr / 2)
            if board.piece(at: eye) != nil { continue }
            let to = TnPos(file: tf, rank: tr)
            if let occ = board.piece(at: to), occ.color == color { continue }
            moves.append(TnMove(from: pos, to: to))
        }
        return moves
    }

    // MARK: - 仕/士（九宫斜走一步）

    static func advisorMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let dirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (df, dr) in dirs {
            let tf = pos.file + df, tr = pos.rank + dr
            guard inPalace(file: tf, rank: tr, color: color) else { continue }
            let to = TnPos(file: tf, rank: tr)
            if let occ = board.piece(at: to), occ.color == color { continue }
            moves.append(TnMove(from: pos, to: to))
        }
        return moves
    }

    // MARK: - 帅/将（九宫直走一步 + 飞将照面由 Legality 处理）

    static func kingMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (df, dr) in dirs {
            let tf = pos.file + df, tr = pos.rank + dr
            guard inPalace(file: tf, rank: tr, color: color) else { continue }
            let to = TnPos(file: tf, rank: tr)
            if let occ = board.piece(at: to), occ.color == color { continue }
            moves.append(TnMove(from: pos, to: to))
        }
        return moves
    }

    // MARK: - 兵/卒

    static func pawnMoves(at pos: TnPos, color: TnColor, on board: TnBoard) -> [TnMove] {
        var moves: [TnMove] = []
        let forward = color == .red ? 1 : -1
        // 前进
        let tr = pos.rank + forward
        if (0...9).contains(tr) {
            let to = TnPos(file: pos.file, rank: tr)
            if let occ = board.piece(at: to), occ.color == color {} else {
                moves.append(TnMove(from: pos, to: to))
            }
        }
        // 过河后可左右走
        let crossed = color == .red ? pos.rank >= 5 : pos.rank <= 4
        if crossed {
            for df in [-1, 1] {
                let tf = pos.file + df
                guard (0...8).contains(tf) else { continue }
                let to = TnPos(file: tf, rank: pos.rank)
                if let occ = board.piece(at: to), occ.color == color {} else {
                    moves.append(TnMove(from: pos, to: to))
                }
            }
        }
        return moves
    }

    // MARK: - 九宫判定

    /// 坐标是否在某方九宫内（file 3..5，红 rank 0..2 / 黑 rank 7..9）
    public static func inPalace(file: Int, rank: Int, color: TnColor) -> Bool {
        guard (3...5).contains(file) else { return false }
        return color == .red ? (0...2).contains(rank) : (7...9).contains(rank)
    }

    public static func inPalace(_ pos: TnPos, color: TnColor) -> Bool {
        inPalace(file: pos.file, rank: pos.rank, color: color)
    }
}
