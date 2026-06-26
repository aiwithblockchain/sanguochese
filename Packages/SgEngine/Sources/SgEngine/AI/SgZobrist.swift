//
//  SgZobrist.swift
//  sanguochese
//
//  三国象棋 · Zobrist 哈希 (P7-1)
//
//  为置换表提供稳定的 64-bit 局面哈希。
//  组成：
//    - 每个格子 × 每种棋子（类型×归属国）的随机数
//    - 当前回合方的随机数
//    - 存活国家集合的随机数（每个国家一个 bit key，组合异或）
//
//  增量更新：apply/undo 时异或对应 key 即可。
//  此处提供全量计算接口；搜索层在快照恢复后重算。
//

import Foundation

public enum SgZobrist {

    /// 位置索引：nation(0..2) * 45 + (file-1) * 5 + (rank-1)
    static func posIndex(_ pos: SgPos) -> Int {
        return pos.nation.rawValue * 45 + (pos.file - 1) * 5 + (pos.rank - 1)
    }

    /// 棋子索引：type(0..6) * 3 + nation(0..2)
    static func pieceIndex(_ piece: SgPiece) -> Int {
        return piece.type.rawValue * 3 + piece.nation.rawValue
    }

    /// 135 格 × 21 种棋子
    static let pieceKeys: [[UInt64]] = {
        var rng = SeededRNG(seed: 0x1234_5678_9ABC_DEF0)
        var keys: [[UInt64]] = []
        for _ in 0..<135 {
            var row: [UInt64] = []
            for _ in 0..<21 {
                row.append(rng.next())
            }
            keys.append(row)
        }
        return keys
    }()

    /// 回合方 key
    static let sideKeys: [UInt64] = {
        var rng = SeededRNG(seed: 0xA1B2_C3D4_E5F6_0718)
        return (0..<3).map { _ in rng.next() }
    }()

    /// 存活国家 key（每个国家一个，组合异或）
    static let aliveKeys: [UInt64] = {
        var rng = SeededRNG(seed: 0xFEDC_BA98_7654_3210)
        return (0..<3).map { _ in rng.next() }
    }()

    /// 计算局面的 Zobrist 哈希
    public static func hash(of board: SgBoard) -> UInt64 {
        var h: UInt64 = 0
        for (pos, piece) in board.pieces {
            h ^= pieceKeys[posIndex(pos)][pieceIndex(piece)]
        }
        h ^= sideKeys[board.sideToMove.rawValue]
        for nation in board.aliveNations {
            h ^= aliveKeys[nation.rawValue]
        }
        return h
    }
}

/// 确定性伪随机数生成器（SplitMix64），保证跨次运行 key 一致。
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
