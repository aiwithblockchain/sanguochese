//
//  TnTypes.swift
//  sanguochese
//
//  2 人标准中国象棋 · 核心类型（与三国象棋 Sg* 完全独立）
//
//  坐标约定（0-indexed）：
//    file: 0...8（左→右，共 9 列）
//    rank: 0...9（下→上，共 10 行）
//    红方在下方（rank 0..4），黑方在上方（rank 5..9）
//    楚河汉界在 rank 4 与 rank 5 之间
//    九宫：红方 file 3..5 × rank 0..2；黑方 file 3..5 × rank 7..9
//

import Foundation

/// 棋子颜色
public enum TnColor: Int, CaseIterable, Hashable, Codable {
    case red = 0    // 红（下方，先手）
    case black = 1  // 黑（上方，后手）

    public var opponent: TnColor { self == .red ? .black : .red }

    public var displayName: String { self == .red ? "红" : "黑" }
}

/// 棋子类型
public enum TnPieceType: Int, CaseIterable, Hashable, Codable {
    case king      // 帅/将
    case advisor   // 仕/士
    case bishop    // 相/象
    case knight    // 马
    case rook      // 车
    case cannon    // 炮
    case pawn      // 兵/卒

    /// 中文名（红方视角）
    public var redName: String {
        switch self {
        case .king: return "帅"
        case .advisor: return "仕"
        case .bishop: return "相"
        case .knight: return "马"
        case .rook: return "车"
        case .cannon: return "炮"
        case .pawn: return "兵"
        }
    }

    /// 中文名（黑方视角）
    public var blackName: String {
        switch self {
        case .king: return "将"
        case .advisor: return "士"
        case .bishop: return "象"
        case .knight: return "马"
        case .rook: return "车"
        case .cannon: return "炮"
        case .pawn: return "卒"
        }
    }

    public func name(for color: TnColor) -> String {
        color == .red ? redName : blackName
    }

    /// 子力价值（参考主流象棋引擎，单位厘兵）
    public var baseValue: Int {
        switch self {
        case .king:    return 10_000
        case .rook:    return 900
        case .cannon:  return 450
        case .knight:  return 400
        case .bishop:  return 200
        case .advisor: return 200
        case .pawn:    return 100
        }
    }
}

/// 棋子
public struct TnPiece: Hashable, Codable {
    public let type: TnPieceType
    public let color: TnColor

    public init(type: TnPieceType, color: TnColor) {
        self.type = type
        self.color = color
    }

    public var displayChar: String { type.name(for: color) }
}

/// 坐标：file 0..8，rank 0..9
public struct TnPos: Hashable, Equatable, Codable {
    public let file: Int
    public let rank: Int

    public init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    public var isValid: Bool { (0...8).contains(file) && (0...9).contains(rank) }

    /// 线性索引 0..89（rank*9 + file）
    public var linearIndex: Int { rank * 9 + file }
}

/// 走法
public struct TnMove: Hashable, Equatable, Codable {
    public let from: TnPos
    public let to: TnPos

    public init(from: TnPos, to: TnPos) {
        self.from = from
        self.to = to
    }

    public var description: String {
        "(\(from.file),\(from.rank))→(\(to.file),\(to.rank))"
    }
}
