//
//  SgDeepSeekBridge.swift
//  sanguochese
//
//  三国象棋 · DeepSeek 解说桥接 (P6-1 / P6-5)
//
//  职责：
//    - 调用 DeepSeek chat completions API 生成角色化解说
//    - 鉴权（Bearer token，apiKey 由外部注入）
//    - 错误处理与降级兜底文案
//    - 简单内存缓存：相同 (role + situationHash + moveText) 直接复用
//
//  LLM 不参与走法决策，只做解说，避免幻觉影响对弈。
//

import Foundation

public final class SgDeepSeekBridge {

    public let apiKey: String
    public let endpoint: URL
    public let model: String

    /// 内存缓存：key = prompt 的稳定哈希
    private var cache: [Int: String] = [:]
    private let cacheQueue = DispatchQueue(label: "sg.deepseek.cache")

    /// 兜底文案池（API 失败时随机选一句）
    private static let fallbackLines: [SgRole: [String]] = [
        .zhugeLiang: ["此步尚可，然需观全局。", "妙哉，进退有度。", "惜哉，此着稍急。"],
        .simaYi:    ["此着隐锋芒，宜静观其变。", "有进无退，需防后路。", "稳健，然隐患未除。"],
        .zhouYu:    ["此步锐气可嘉。", "机不可失，时不再来。", "此着稍显保守。"],
        .caoCao:    "顺我者昌，此步当赏。|岂有此理，此着不妥。|哼，尚可一战。".split(separator: "|").map(String.init),
        .liuBei:    ["此步仁义在前，社稷之福。", "当慎之，勿轻进。", "此着稳健，可安民心。"],
        .sunQuan:   ["此步务实，江东之幸。", "需谋后动。", "此着机敏，可图后效。"],
    ]

    public init(apiKey: String,
                endpoint: URL = URL(string: "https://api.deepseek.com/v1/chat/completions")!,
                model: String = "deepseek-chat") {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }

    /// 是否已配置有效 apiKey
    public var isConfigured: Bool {
        return !apiKey.isEmpty
    }

    /// 异步生成解说。
    /// - Parameters:
    ///   - prompt: 完整 prompt（来自 SgRolePrompt.build）
    ///   - role: 解说角色（用于兜底文案）
    ///   - completion: 主线程回调，返回解说文本
    public func commentate(prompt: String,
                           role: SgRole,
                           completion: @escaping (String) -> Void) {
        let key = stableHash(prompt)
        if let cached = cacheRead(key) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        guard isConfigured else {
            let fallback = Self.fallback(for: role)
            DispatchQueue.main.async { completion(fallback) }
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.8,
            "max_tokens": 120,
            "stream": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(Self.fallback(for: role)) }
            return
        }
        request.httpBody = data

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DispatchQueue.main.async { completion(Self.fallback(for: role)) }
                return
            }
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            self.cacheWrite(key, cleaned)
            DispatchQueue.main.async { completion(cleaned) }
        }
        task.resume()
    }

    // MARK: - 兜底文案

    static func fallback(for role: SgRole) -> String {
        let pool = fallbackLines[role] ?? ["此步值得玩味。"]
        return pool.randomElement() ?? "此步值得玩味。"
    }

    // MARK: - 缓存

    private func cacheRead(_ key: Int) -> String? {
        cacheQueue.sync { cache[key] }
    }

    private func cacheWrite(_ key: Int, _ value: String) {
        cacheQueue.sync { cache[key] = value }
    }

    /// 简单稳定哈希（FNV-1a 32-bit）
    private func stableHash(_ s: String) -> Int {
        var h: UInt32 = 2166136261
        for byte in s.utf8 {
            h ^= UInt32(byte)
            h &*= 16777619
        }
        return Int(h)
    }
}
