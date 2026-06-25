//
//  TnBoard.swift
//  sanguochese
//
//  2 人标准中国象棋 · 棋盘状态
//
//  9×10 棋盘，红方在下（rank 0..4），黑方在上（rank 5..9）。
//  用 [TnPos: TnPiece] 字典表示，配合 make/unmake 增量走子与增量 Zobrist。
//

import Foundation

/// 走子记录：足够信息以 O(1) 回滚一步（含回合轮转）。
public struct TnMoveRecord {
    public let move: TnMove
    public let captured: TnPiece?
    public let colorBefore: TnColor
}

/// 棋盘状态
public final class TnBoard {

    /// 格子 → 棋子。空格不在字典中。
    public var pieces: [TnPos: TnPiece] = [:]

    /// 当前轮到哪方走子
    public private(set) var sideToMove: TnColor = .red

    /// 增量 Zobrist 哈希
    public private(set) var zobrist: UInt64 = 0

    public init() {}

    /// 从另一个棋盘复制
    public init(copy other: TnBoard) {
        self.pieces = other.pieces
        self.sideToMove = other.sideToMove
        self.zobrist = other.zobrist
    }

    // MARK: - 查询

    public func piece(at pos: TnPos) -> TnPiece? { pieces[pos] }

    /// 某方主帅位置（找不到则已被吃）
    public func kingPos(of color: TnColor) -> TnPos? {
        for (pos, p) in pieces where p.type == .king && p.color == color {
            return pos
        }
        return nil
    }

    /// 某方全部棋子位置
    public func positions(of color: TnColor) -> [TnPos] {
        pieces.compactMap { pos, p in p.color == color ? pos : nil }
    }

    // MARK: - 走子（不含合法性校验，由上层保证）

    /// 执行一步走法，返回被吃的棋子（若有）。仅移动棋子，不轮转回合。
    /// 同步增量更新 zobrist。
    @discardableResult
    public func apply(_ move: TnMove) -> TnPiece? {
        guard let mover = pieces[move.from] else { return nil }
        let captured = pieces[move.to]
        pieces[move.to] = mover
        pieces[move.from] = nil
        let fi = move.from.linearIndex
        let ti = move.to.linearIndex
        let mi = TnZobrist.pieceIndex(mover)
        zobrist ^= TnZobrist.pieceKeys[fi][mi]
        zobrist ^= TnZobrist.pieceKeys[ti][mi]
        if let cap = captured {
            let ci = TnZobrist.pieceIndex(cap)
            zobrist ^= TnZobrist.pieceKeys[ti][ci]
        }
        return captured
    }

    /// 回滚一步 apply（不轮转回合）。
    public func undo(_ move: TnMove, captured: TnPiece?) {
        let mover = pieces[move.to]!
        pieces[move.from] = mover
        pieces[move.to] = captured
        let fi = move.from.linearIndex
        let ti = move.to.linearIndex
        let mi = TnZobrist.pieceIndex(mover)
        zobrist ^= TnZobrist.pieceKeys[fi][mi]
        zobrist ^= TnZobrist.pieceKeys[ti][mi]
        if let cap = captured {
            let ci = TnZobrist.pieceIndex(cap)
            zobrist ^= TnZobrist.pieceKeys[ti][ci]
        }
    }

    // MARK: - make/unmake（搜索专用，含回合轮转）

    /// 执行走子 + 切换回合。返回回滚所需 record。
    @discardableResult
    public func make(_ move: TnMove) -> TnMoveRecord {
        let colorBefore = sideToMove
        let captured = apply(move)
        zobrist ^= TnZobrist.sideKey(colorBefore)
        zobrist ^= TnZobrist.sideKey(sideToMove.opponent)
        sideToMove = sideToMove.opponent
        return TnMoveRecord(move: move, captured: captured, colorBefore: colorBefore)
    }

    /// 回滚一步 make。
    public func unmake(_ record: TnMoveRecord) {
        zobrist ^= TnZobrist.sideKey(record.colorBefore)
        zobrist ^= TnZobrist.sideKey(sideToMove)
        sideToMove = record.colorBefore
        undo(record.move, captured: record.captured)
    }

    // MARK: - 快照（用于 UI 复位 / 测试）

    public func recomputeZobrist() {
        zobrist = TnZobrist.hash(of: self)
    }
}
