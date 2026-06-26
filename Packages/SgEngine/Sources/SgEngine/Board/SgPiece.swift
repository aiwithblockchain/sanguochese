//
//  SgPiece.swift
//  sanguochese
//
//  三国象棋 - 棋子模型
//

import Foundation

/// 棋子种类（与传统象棋一致）。
public enum SgPieceType: Int, CaseIterable, Codable {
    case king     = 0   // 帅/将
    case advisor  = 1   // 士
    case bishop   = 2   // 象/相
    case knight   = 3   // 马
    case cannon   = 4   // 炮
    case rook     = 5   // 车
    case pawn     = 6   // 兵/卒

    /// 中文名
    public var displayName: String {
        switch self {
        case .king:    return "帅"
        case .advisor: return "士"
        case .bishop:  return "象"
        case .knight:  return "马"
        case .cannon:  return "炮"
        case .rook:    return "车"
        case .pawn:    return "兵"
        }
    }

    /// 子力价值（参考传统象棋经验值，后续可调）
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

    /// 是否可以越过国界（象/士/帅永远留在己方地盘）
    public var canCrossBorder: Bool {
        switch self {
        case .king, .advisor, .bishop:
            return false
        case .knight, .cannon, .rook, .pawn:
            return true
        }
    }
}

/// 一枚棋子 = 种类 + 归属国家。
///
/// 棋子的"颜色"即其归属国家。吞并后败方棋子改色归胜方，
/// 即修改 `nation` 字段。
public struct SgPiece: Hashable, Equatable, Codable {
    public let type: SgPieceType
    public var nation: SgNation   // var：吞并时改色

    public init(type: SgPieceType, nation: SgNation) {
        self.type = type
        self.nation = nation
    }

    /// 显示用字符串（国家+棋种）
    public var displayName: String {
        return "\(nation.displayName)\(type.displayName)"
    }
}
