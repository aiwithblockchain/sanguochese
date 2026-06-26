//
//  SgRolePrompt.swift
//  sanguochese
//
//  三国象棋 · 角色 Prompt 模板 (P6-3)
//
//  三国角色分工（按玩家阵营匹配解说者）：
//    - 玩家是蜀方 → 诸葛亮解说（鼓励 + 教学）
//    - 玩家是魏方 → 司马懿解说（隐忍 + 洞察）  ※ AI 是魏方时由曹操点评
//    - 玩家是吴方 → 周瑜解说（机锋 + 算计）
//  AI 方的走法由其对应君主点评（曹操/刘备/孙权），形成"双方各有一嘴"。
//
//  Prompt 模板包含：当前局面描述、刚走的步、角色人设、输出风格约束。
//

import Foundation
import SgEngine

/// 解说角色
public enum SgRole: String, CaseIterable, Codable {
    case zhugeLiang   // 诸葛亮（蜀方视角）
    case simaYi       // 司马懿（魏方视角）
    case zhouYu       // 周瑜（吴方视角）
    case caoCao       // 曹操（魏方君主，点评魏方走法）
    case liuBei       // 刘备（蜀方君主，点评蜀方走法）
    case sunQuan      // 孙权（吴方君主，点评吴方走法）

    public var displayName: String {
        switch self {
        case .zhugeLiang: return "诸葛亮"
        case .simaYi:     return "司马懿"
        case .zhouYu:     return "周瑜"
        case .caoCao:     return "曹操"
        case .liuBei:     return "刘备"
        case .sunQuan:    return "孙权"
        }
    }

    /// 玩家阵营对应的解说者
    public static func commentator(for humanSide: SgNation) -> SgRole {
        switch humanSide {
        case .shu: return .zhugeLiang
        case .wei: return .simaYi
        case .wu:  return .zhouYu
        }
    }

    /// 某方走法对应的君主点评者
    public static func monarch(of nation: SgNation) -> SgRole {
        switch nation {
        case .wei: return .caoCao
        case .shu: return .liuBei
        case .wu:  return .sunQuan
        }
    }
}

public enum SgRolePrompt {

    /// 构建解说 prompt。
    /// - Parameters:
    ///   - role: 解说角色
    ///   - situation: 局面描述文本（来自 SgBoardDescriber）
    ///   - moveText: 刚走的步描述
    ///   - isPlayerMove: 这步是玩家走的还是 AI 走的
    public static func build(role: SgRole,
                             situation: String,
                             moveText: String,
                             isPlayerMove: Bool) -> String {
        return """
        \(persona(role))

        \(situation)

        \(moveText)

        要求：
        1. 以\(role.displayName)的口吻点评刚才这步棋，\(isPlayerMove ? "玩家" : "AI")所走。
        2. 点评不超过 60 字，言简意赅，符合角色性格。
        3. 可以指出好劣、给出后续建议，但不要列出具体坐标。
        4. 不要重复局面描述中的数字，只做主观点评。
        5. 输出纯文本，不要 markdown、不要引号、不要前缀。
        """
    }

    /// 角色人设
    static func persona(_ role: SgRole) -> String {
        switch role {
        case .zhugeLiang:
            return "你是诸葛亮，羽扇纶巾，运筹帷幄。你辅佐蜀汉，对玩家（蜀方）既有鼓励也有教诲，语气从容睿智，偶有「妙哉」「惜哉」之叹。"
        case .simaYi:
            return "你是司马懿，隐忍深沉，洞察人心。你辅佐曹魏，对玩家（魏方）点评克制而精准，善指出隐患，语气沉静。"
        case .zhouYu:
            return "你是周瑜，雄姿英发，谈笑间樯橹灰飞烟灭。你辅佐东吴，对玩家（吴方）点评锋锐而自信，喜用兵法之语。"
        case .caoCao:
            return "你是曹操，宁我负人毋人负我。点评己方走法时霸气外露，胜则「顺我者昌」，劣则「岂有此理」，语气威压。"
        case .liuBei:
            return "你是刘备，仁义为本，喜怒不形于色。点评己方走法时温厚持重，胜则「社稷之福」，劣则「当慎之」，语气宽和。"
        case .sunQuan:
            return "你是孙权，碧眼紫髯，能屈能伸。点评己方走法时务实而机敏，胜则「江东之幸」，劣则「需谋后动」，语气从容。"
        }
    }
}
