//
//  SgPos.swift
//  sanguochese
//
//  三国象棋 - 棋盘坐标系统
//
//  每方地盘 9 路 × 5 行 + 九宫。
//  坐标 = (国家, 线 file 1...9, 行 rank 1...5)
//  rank=1 为己方底线（帅所在行），rank=5 为国界边。
//

import Foundation

/// 棋盘上的一个格子坐标。
///
/// 三方各 9×5 = 45 格，共 135 格。
/// 九宫范围：file ∈ 4...6, rank ∈ 1...3。
public struct SgPos: Hashable, Equatable, Codable {
    public let nation: SgNation
    public let file: Int   // 1...9  纵向路线
    public let rank: Int   // 1...5  行（1=底线，5=国界边）

    public init(nation: SgNation, file: Int, rank: Int) {
        precondition((1...9).contains(file), "file must be 1...9, got \(file)")
        precondition((1...5).contains(rank), "rank must be 1...5, got \(rank)")
        self.nation = nation
        self.file = file
        self.rank = rank
    }

    /// 是否在九宫内（士、帅的活动范围）
    public var isInPalace: Bool {
        return (4...6).contains(file) && (1...3).contains(rank)
    }

    /// 是否在国界边（rank == 5，即己方最靠近中央的一行）
    public var isAtBorder: Bool {
        return rank == 5
    }

    /// 稳定的字符串表示，便于调试与 FEN
    public var description: String {
        return "\(nation.displayName)\(file)\(rank)"
    }
}

/// 接线表 σ：翻转对接 i → (10 − i)。
///
/// 我方第 i 路在国界处分叉，进攻 target 国时，接入对方第 (10−i) 路。
/// 翻转对接复现传统象棋"两方相对而立、左右镜像"的几何，
/// 保证进攻任意一方时与传统象棋一模一样。
public enum SgRouting {
    /// 我方线 file 进攻 target 时，对接到对方的线号。
    public static func route(myFile: Int, target: SgNation) -> Int {
        return 10 - myFile
    }
}
