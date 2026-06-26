//
//  SgTranspositionTable.swift
//  sanguochese
//
//  三国象棋 · 置换表 (P7-1)
//
//  基于 Zobrist 哈希的固定大小置换表，存储：
//    - 深度
//    - 分数
//    - 标志（EXACT / LOWER_BOUND / UPPER_BOUND）
//    - 最佳走法（用于走法排序启发）
//
//  采用"始终替换"策略（简单、缓存友好），
//  容量 1<<20 = 1M 条目，约 32MB 内存。
//

import Foundation

/// 置换表条目标志
public enum SgTTFlag: Int {
    case exact       = 0   // 精确值
    case lowerBound  = 1   // 下界（≥ score，因 β cutoff）
    case upperBound  = 2   // 上界（≤ score，因未超过 α）
}

/// 置换表条目
public struct SgTTEntry {
    public let key: UInt64        // 完整 key（防冲突）
    public let depth: Int         // 搜索深度
    public let score: Int         // 分数
    public let flag: SgTTFlag
    public let bestMove: SgMove?  // 最佳走法（可能为 nil）

    public init(key: UInt64, depth: Int, score: Int, flag: SgTTFlag, bestMove: SgMove?) {
        self.key = key
        self.depth = depth
        self.score = score
        self.flag = flag
        self.bestMove = bestMove
    }
}

/// 固定大小置换表（线程不安全，搜索在单线程后台任务中使用）
public final class SgTranspositionTable {

    private var entries: [SgTTEntry?]
    private let mask: UInt64
    public var collisions = 0
    public var hits = 0
    public var probes = 0

    /// 容量 = 1 << bitsPower 条目
    public init(bitsPower: Int = 20) {
        let size = 1 << bitsPower
        self.entries = [SgTTEntry?](repeating: nil, count: size)
        self.mask = UInt64(size - 1)
    }

    /// 查询
    public func probe(_ key: UInt64) -> SgTTEntry? {
        probes += 1
        let idx = Int(key & mask)
        guard let e = entries[idx], e.key == key else { return nil }
        hits += 1
        return e
    }

    /// 存储（始终替换）
    public func store(_ entry: SgTTEntry) {
        let idx = Int(entry.key & mask)
        if let existing = entries[idx], existing.key != entry.key {
            collisions += 1
        }
        entries[idx] = entry
    }

    /// 清空
    public func clear() {
        for i in 0..<entries.count { entries[i] = nil }
        collisions = 0
        hits = 0
        probes = 0
    }
}
