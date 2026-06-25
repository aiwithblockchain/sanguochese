//
//  TnCoordMapper.swift
//  sanguochese
//
//  2 人标准中国象棋 · 逻辑坐标 ↔ 屏幕坐标映射
//
//  标准 9×10 矩形棋盘：
//    file 0..8（左→右，共 9 列）
//    rank 0..9（下→上，共 10 行）
//    红方在下（rank 0..4），黑方在上（rank 5..9）
//    楚河汉界在 rank 4 与 rank 5 之间
//
//  屏幕坐标以棋盘中心为原点（GameScene 负责平移到场景中心）。
//  红方在下：rank 0 在屏幕下方（y 小），rank 9 在屏幕上方（y 大）。
//
//  视角翻转：若 perspectiveColor == .black，则黑方在下方，
//  整体上下翻转（rank → 9 - rank）。
//

import Foundation
import CoreGraphics

public struct TnCoordMapper {

    /// 单格边长（屏幕点）
    public let cellSize: CGFloat

    /// 视角：该方在屏幕下方。nil = 红方在下（默认）。
    public let perspectiveColor: TnColor?

    public init(cellSize: CGFloat, perspectiveColor: TnColor? = nil) {
        self.cellSize = cellSize
        self.perspectiveColor = perspectiveColor
    }

    /// 是否上下翻转（黑方视角）
    private var flipped: Bool { perspectiveColor == .black }

    /// 把逻辑 rank 转为屏幕行号（0=最下，9=最上）
    private func screenRank(_ rank: Int) -> Int {
        flipped ? (9 - rank) : rank
    }

    /// 某格中心在屏幕坐标系（以棋盘中心为原点）中的位置。
    /// file 0..8 映射到 x = (file - 4) * cellSize（file 4 在中线）
    /// rank 0..9 映射到 y = (screenRank - 4.5) * cellSize（rank 4/5 之间为河界中心）
    public func screenPos(for pos: TnPos) -> CGPoint {
        let x = CGFloat(pos.file - 4) * cellSize
        let y = (CGFloat(screenRank(pos.rank)) - 4.5) * cellSize
        return CGPoint(x: x, y: y)
    }

    /// 棋盘宽度（8 格距 = 9 列）
    public var boardWidth: CGFloat { 8 * cellSize }

    /// 棋盘高度（9 格距 = 10 行）
    public var boardHeight: CGFloat { 9 * cellSize }

    /// 棋盘左下角（相对中心）
    public var origin: CGPoint {
        CGPoint(x: -boardWidth / 2, y: -boardHeight / 2)
    }

    // MARK: - 屏幕坐标 → 逻辑坐标（点击命中）

    /// 给定屏幕坐标（以棋盘中心为原点），返回命中的格子，未命中返回 nil。
    public func pos(at point: CGPoint) -> TnPos? {
        // file = round((x / cellSize) + 4)
        let fileFloat = point.x / cellSize + 4
        let rankFloat = point.y / cellSize + 4.5
        let file = Int((fileFloat + 0.5).rounded(.down))
        let sRank = Int((rankFloat + 0.5).rounded(.down))
        guard (0...8).contains(file), (0...9).contains(sRank) else { return nil }
        let rank = flipped ? (9 - sRank) : sRank
        return TnPos(file: file, rank: rank)
    }
}
