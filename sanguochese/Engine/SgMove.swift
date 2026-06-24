//
//  SgMove.swift
//  sanguochese
//
//  三国象棋 - 走法表示
//

import Foundation

/// 一步走法：起点 → 终点。
///
/// 终点可能落在己方地盘（不过国界），也可能落在敌国地盘（过国界后）。
/// 过国界时，终点坐标直接用目标国的坐标表示——
/// 路由层已通过 SgRouting.route 把"我方线 i"映射为"对方线 (10−i)"。
public struct SgMove: Hashable, Equatable, Codable {
    public let from: SgPos
    public let to:   SgPos

    /// 是否跨越国界（起点与终点国家不同）
    public var crossesBorder: Bool {
        return from.nation != to.nation
    }

    public init(from: SgPos, to: SgPos) {
        self.from = from
        self.to = to
    }

    public var description: String {
        return "\(from.description)→\(to.description)"
    }
}
