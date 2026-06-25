//
//  SgGameMode.swift
//  sanguochese
//
//  三国象棋 - 对局模式
//
//  A-2 重构：将 1v1 标准象棋模式合并回 Sg* 引擎，
//  通过枚举区分三方对局与两方对局，避免维护两套引擎。
//

import Foundation

/// 对局模式。
public enum SgGameMode {
    /// 三国对局（魏 / 蜀 / 吴 三方）
    case threeNation
    /// 两方对局（1v1，模拟标准象棋）。human 与 ai 为参与的两方，
    /// 第三方不存活、不摆子、不参与回合轮转。
    case twoNation(human: SgNation, ai: SgNation)

    /// 是否为两方模式
    public var isTwoNation: Bool {
        if case .twoNation = self { return true }
        return false
    }
}
