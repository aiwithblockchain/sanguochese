//
//  SgNation.swift
//  sanguochese
//
//  三国象棋 - 国家枚举
//

import Foundation

/// 三方对弈的国家。
///
/// 120° 旋转对称下，三方地位等价。
/// 回合顺序固定为 魏 → 蜀 → 吴 → 魏 → ...
public enum SgNation: Int, CaseIterable, Hashable, Codable {
    case wei = 0   // 魏
    case shu = 1   // 蜀
    case wu  = 2   // 吴

    /// 中文名称
    public var displayName: String {
        switch self {
        case .wei: return "魏"
        case .shu: return "蜀"
        case .wu:  return "吴"
        }
    }

    /// 回合顺序中的下一个国家
    public func next() -> SgNation {
        SgNation(rawValue: (self.rawValue + 1) % 3)!
    }

    /// 除自己之外的另外两国（分叉的两个方向）
    public func opponents() -> [SgNation] {
        SgNation.allCases.filter { $0 != self }
    }
}
