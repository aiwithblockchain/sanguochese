//
//  SgBoard.swift
//  sanguochese
//
//  三国象棋 - 棋盘状态
//
//  三方各 9×5 = 45 格，共 135 格。
//  棋盘用 [SgPos: SgPiece] 字典表示，便于非矩形几何。
//

import Foundation

/// 棋盘状态：所有棋子的位置 + 当前回合方 + 游戏阶段。
public final class SgBoard {

    /// 格子 → 棋子。空格子不在字典中。
    /// 设为 public var 以便 SgLayout 摆子与测试直接构造局面；
    /// 正式对局由 apply/undo 维护，外部直接写入仅用于初始化与测试。
    public var pieces: [SgPos: SgPiece] = [:]

    /// 当前轮到哪一方走子
    public var sideToMove: SgNation = .wei

    /// 存活的国家（未被灭国）
    public private(set) var aliveNations: Set<SgNation> = [.wei, .shu, .wu]

    /// 已被灭国的国家 → 收编它的胜利方
    public private(set) var annexed: [SgNation: SgNation] = [:]

    public init() {}

    /// 从另一个棋盘复制
    public init(copy other: SgBoard) {
        self.pieces = other.pieces
        self.sideToMove = other.sideToMove
        self.aliveNations = other.aliveNations
        self.annexed = other.annexed
    }

    // MARK: - 查询

    /// 某格上的棋子（nil 表示空）
    public func piece(at pos: SgPos) -> SgPiece? {
        return pieces[pos]
    }

    /// 某国的主帅位置（找不到则该方已灭国）
    public func kingPos(of nation: SgNation) -> SgPos? {
        for (pos, p) in pieces where p.type == .king && p.nation == nation {
            return pos
        }
        return nil
    }

    /// 某国全部棋子位置
    public func positions(of nation: SgNation) -> [SgPos] {
        return pieces.compactMap { pos, p in p.nation == nation ? pos : nil }
    }

    /// 某国是否存活
    public func isAlive(_ nation: SgNation) -> Bool { aliveNations.contains(nation) }

    // MARK: - 走子（不含合法性校验，由上层保证）

    /// 执行一步走法，返回被吃的棋子（若有）。
    @discardableResult
    public func apply(_ move: SgMove) -> SgPiece? {
        guard let mover = pieces[move.from] else { return nil }
        let captured = pieces[move.to]
        pieces[move.to] = mover
        pieces[move.from] = nil
        return captured
    }

    /// 撤销一步走法（恢复被吃棋子）
    public func undo(_ move: SgMove, captured: SgPiece?) {
        let mover = pieces[move.to]!
        pieces[move.from] = mover
        pieces[move.to] = captured
    }

    // MARK: - 灭国/吞并（P4 阶段完善，此处先留接口）

    /// 标记一国灭国，其棋子归胜利方。
    /// 兵卒前进方向重定义由走法生成层根据归属动态计算。
    public func annex(defeated: SgNation, by victor: SgNation) {
        aliveNations.remove(defeated)
        annexed[defeated] = victor
        // 改色：败方所有棋子归胜方
        for pos in positions(of: defeated) {
            pieces[pos]?.nation = victor
        }
    }

    /// 清空一国所有棋子（消极判负：无过河棋）
    public func clearAll(of nation: SgNation) {
        aliveNations.remove(nation)
        for pos in positions(of: nation) {
            pieces[pos] = nil
        }
    }
}
