//
//  TnZobrist.swift
//  sanguochese
//
//  2 人标准中国象棋 · Zobrist 哈希
//
//  90 格 × 14 种棋子（2 色 × 7 型）+ 1 个 side key。
//  pieceIndex: color.rawValue * 7 + type.rawValue（0..13）
//

import Foundation

public enum TnZobrist {

    /// 90 × 14 棋子键
    static let pieceKeys: [[UInt64]] = generatePieceKeys()
    /// 2 个 side 键
    static let sideKeys: [UInt64] = generateSideKeys()

    private static func generatePieceKeys() -> [[UInt64]] {
        var rng = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
        var keys: [[UInt64]] = []
        for _ in 0..<90 {
            var row: [UInt64] = []
            for _ in 0..<14 {
                row.append(rng.next())
            }
            keys.append(row)
        }
        return keys
    }

    private static func generateSideKeys() -> [UInt64] {
        var rng = SplitMix64(seed: 0xC2B2_FEAE_5DB1_D6A4)
        return [rng.next(), rng.next()]
    }

    /// 棋子索引：0..13
    public static func pieceIndex(_ piece: TnPiece) -> Int {
        piece.color.rawValue * 7 + piece.type.rawValue
    }

    public static func sideKey(_ color: TnColor) -> UInt64 {
        sideKeys[color.rawValue]
    }

    /// 全量重算（初始化 / 快照恢复后用）
    public static func hash(of board: TnBoard) -> UInt64 {
        var h: UInt64 = 0
        for (pos, piece) in board.pieces {
            h ^= pieceKeys[pos.linearIndex][pieceIndex(piece)]
        }
        h ^= sideKey(board.sideToMove)
        return h
    }
}

/// 简单确定性 PRNG（SplitMix64），用于生成固定 Zobrist 键。
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_4276_4EE9_1B09
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
