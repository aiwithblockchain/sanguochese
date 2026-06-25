//
//  SgMoveGen.swift
//  sanguochese
//
//  三国象棋 · 走法生成
//  P1-5 传统走法生成 + P1-6 分叉走法生成
//
//  两层解耦：
//    1. 传统走法生成器 —— 每种棋子的传统中国象棋走法
//    2. 分叉路由层    —— 过国界时沿两个方向各生成一份
//
//  统一原则：面向任一国时，走法与传统象棋完全一致。
//  区别仅在国界处的方向选择（OUT/IN 射线分叉成 2 条）。
//
//  关键：所有几何原语以 `owner`（棋子归属国）为基准计算前进/后退方向。
//  棋子在己方领土与敌国领土时，"前进"方向不同（见 SgGeometry）。
//

import Foundation

public enum SgMoveGen {

    /// 生成某方在当前局面下的所有伪合法走法（含吃子）。
    /// 主帅互照/被将军过滤由上层 SgLegality 完成。
    public static func pseudoLegalMoves(for side: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        for (pos, piece) in board.pieces where piece.nation == side {
            moves.append(contentsOf: movesFor(piece: piece, at: pos, on: board))
        }
        return moves
    }

    /// 生成某方所有伪合法**吃子**走法（仅吃子，用于 quiescence 搜索）。
    /// 仍需上层过滤主帅互照。
    public static func pseudoCaptures(for side: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        for (pos, piece) in board.pieces where piece.nation == side {
            let all = movesFor(piece: piece, at: pos, on: board)
            for m in all where board.piece(at: m.to) != nil {
                moves.append(m)
            }
        }
        return moves
    }

    /// 单枚棋子的所有伪合法走法。
    public static func movesFor(piece: SgPiece, at pos: SgPos, on board: SgBoard) -> [SgMove] {
        switch piece.type {
        case .rook:    return rookMoves(at: pos, owner: piece.nation, on: board)
        case .cannon:  return cannonMoves(at: pos, owner: piece.nation, on: board)
        case .knight:  return knightMoves(at: pos, owner: piece.nation, on: board)
        case .bishop:  return bishopMoves(at: pos, owner: piece.nation, on: board)
        case .advisor: return advisorMoves(at: pos, owner: piece.nation, on: board)
        case .king:    return kingMoves(at: pos, owner: piece.nation, on: board)
        case .pawn:    return pawnMoves(at: pos, owner: piece.nation, on: board)
        }
    }

    // MARK: - 车

    /// 车：沿四向射线直走，遇敌可吃、遇友停、不越子。
    /// OUT 与 IN 方向在国界处都会分叉成 2 条射线。
    static func rookMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        // OUT（前进，分叉）
        for ray in SgGeometry.outRays(from: pos, owner: owner) {
            moves.append(contentsOf: slidingMoves(on: ray, from: pos, owner: owner, board: board))
        }
        // IN（后退，分叉）
        for ray in SgGeometry.inRays(from: pos, owner: owner) {
            moves.append(contentsOf: slidingMoves(on: ray, from: pos, owner: owner, board: board))
        }
        // LEFT / RIGHT（横向，不过国界）
        for ray in [SgGeometry.leftRay(from: pos), SgGeometry.rightRay(from: pos)] {
            moves.append(contentsOf: slidingMoves(on: ray, from: pos, owner: owner, board: board))
        }
        return moves
    }

    /// 沿一条射线滑动：空格可走，遇敌可吃并停，遇友停。
    static func slidingMoves(on ray: [SgPos], from origin: SgPos, owner: SgNation, board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        for cell in ray {
            guard let occupant = board.piece(at: cell) else {
                moves.append(SgMove(from: origin, to: cell))
                continue
            }
            if occupant.nation != owner {
                moves.append(SgMove(from: origin, to: cell))  // 吃子
            }
            break  // 遇子即停（无论敌友）
        }
        return moves
    }

    // MARK: - 炮

    /// 炮：移动同车（不越子）；吃子需翻过恰好一枚棋子（炮架子）。
    /// 每个分叉方向独立判炮架子。
    static func cannonMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        let rays: [[SgPos]] =
            SgGeometry.outRays(from: pos, owner: owner) +
            SgGeometry.inRays(from: pos, owner: owner) +
            [SgGeometry.leftRay(from: pos), SgGeometry.rightRay(from: pos)]
        for ray in rays {
            moves.append(contentsOf: cannonRayMoves(on: ray, from: pos, owner: owner, board: board))
        }
        return moves
    }

    /// 炮沿一条射线的走法：未翻山前空格可走；翻过恰好一子后，下一枚敌子可吃。
    static func cannonRayMoves(on ray: [SgPos], from origin: SgPos, owner: SgNation, board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        var jumped = false
        for cell in ray {
            guard let occupant = board.piece(at: cell) else {
                if !jumped { moves.append(SgMove(from: origin, to: cell)) }
                continue
            }
            if !jumped {
                jumped = true  // 这枚棋子作为炮架子
            } else {
                if occupant.nation != owner {
                    moves.append(SgMove(from: origin, to: cell))  // 翻山吃子
                }
                break
            }
        }
        return moves
    }

    // MARK: - 马

    /// 马：走"日"字，蹩腿判定直走一步的邻点。
    /// 蹩腿按所选方向独立判定（三国象棋独有：往 A 蹩、往 B 不蹩）。
    static func knightMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        let candidates: [(target: SgPos, leg: SgPos?)] = knightTargets(from: pos, owner: owner)
        for (target, leg) in candidates {
            // 蹩腿：腿格上有任何棋子则不能跳
            if let leg = leg, board.piece(at: leg) != nil { continue }
            if let occupant = board.piece(at: target), occupant.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }
        return moves
    }

    /// 马的 8 个日字目标及其蹩腿格。
    /// 蹩腿格 = 直走一步的邻点（OUT/IN/LEFT/RIGHT 各一）。
    /// 目标 = 从腿再走一步同方向 + 一步垂直方向（即"日"字：2 步主方向 + 1 步垂直）。
    /// 过国界时 OUT/IN 邻点会分叉，每个分叉邻点作为独立的马腿。
    static func knightTargets(from pos: SgPos, owner: SgNation) -> [(target: SgPos, leg: SgPos?)] {
        // 4 个直走邻点（马腿候选）。OUT/IN 在国界处可能分叉成多个。
        let outSteps = SgGeometry.stepOut(from: pos, owner: owner)   // 0/1/2 个
        let inSteps: [SgPos] = {
            if let s = SgGeometry.stepIn(from: pos, owner: owner) { return [s] }
            return []
        }()
        let leftStep  = SgGeometry.stepLeft(from: pos)
        let rightStep = SgGeometry.stepRight(from: pos)

        var results: [(target: SgPos, leg: SgPos?)] = []

        // 以"OUT 邻点"为腿：从腿再 OUT 一步，然后 LEFT/RIGHT 一步 → 2 个日字目标
        for leg in outSteps {
            for mid in SgGeometry.stepOut(from: leg, owner: owner) {
                if let t = SgGeometry.stepLeft(from: mid) {
                    results.append((t, leg))
                }
                if let t = SgGeometry.stepRight(from: mid) {
                    results.append((t, leg))
                }
            }
        }
        // 以"IN 邻点"为腿：从腿再 IN 一步，然后 LEFT/RIGHT 一步 → 2 个日字目标
        for leg in inSteps {
            if let mid = SgGeometry.stepIn(from: leg, owner: owner) {
                if let t = SgGeometry.stepLeft(from: mid) {
                    results.append((t, leg))
                }
                if let t = SgGeometry.stepRight(from: mid) {
                    results.append((t, leg))
                }
            }
        }
        // 以"LEFT 邻点"为腿：从腿再 LEFT 一步，然后 OUT/IN 一步 → 2 个日字目标
        if let leg = leftStep {
            if let mid = SgGeometry.stepLeft(from: leg) {
                for t in SgGeometry.stepOut(from: mid, owner: owner) {
                    results.append((t, leg))
                }
                if let t = SgGeometry.stepIn(from: mid, owner: owner) {
                    results.append((t, leg))
                }
            }
        }
        // 以"RIGHT 邻点"为腿：从腿再 RIGHT 一步，然后 OUT/IN 一步 → 2 个日字目标
        if let leg = rightStep {
            if let mid = SgGeometry.stepRight(from: leg) {
                for t in SgGeometry.stepOut(from: mid, owner: owner) {
                    results.append((t, leg))
                }
                if let t = SgGeometry.stepIn(from: mid, owner: owner) {
                    results.append((t, leg))
                }
            }
        }
        // 去重（同一目标可能由不同腿到达，保留首个）
        var seen: Set<SgPos> = []
        return results.filter { seen.insert($0.target).inserted }
    }

    // MARK: - 象 / 相

    /// 象：走"田"字（斜向 2 格），塞象眼不可走，不过国界。
    /// 象永远在己方领土内活动（canCrossBorder == false）。
    static func bishopMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        // 象只在己方领土，用简单的 (drank, dfile) ±2 即可
        let dirs = [(-2, -2), (-2, 2), (2, -2), (2, 2)]
        for (dr, df) in dirs {
            let eyeRank = pos.rank + dr / 2
            let eyeFile = pos.file + df / 2
            let targetRank = pos.rank + dr
            let targetFile = pos.file + df
            guard (1...5).contains(eyeRank), (1...9).contains(eyeFile),
                  (1...5).contains(targetRank), (1...9).contains(targetFile) else { continue }
            let eye = SgPos(nation: pos.nation, file: eyeFile, rank: eyeRank)
            let target = SgPos(nation: pos.nation, file: targetFile, rank: targetRank)
            if board.piece(at: eye) != nil { continue }  // 塞象眼
            if let occ = board.piece(at: target), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }
        return moves
    }

    // MARK: - 士

    /// 士：九宫内斜走一步，不出九宫。士永远在己方领土内。
    static func advisorMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        let deltas = [(-1, -1), (-1, 1), (1, -1), (1, 1)]  // (drank, dfile)
        for (dr, df) in deltas {
            let nr = pos.rank + dr
            let nf = pos.file + df
            guard (1...5).contains(nr), (1...9).contains(nf) else { continue }
            let target = SgPos(nation: pos.nation, file: nf, rank: nr)
            guard target.isInPalace else { continue }
            if let occ = board.piece(at: target), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }
        return moves
    }

    // MARK: - 帅 / 将

    /// 帅：九宫内直走一步。主帅互照过滤由 SgLegality 处理。
    /// 帅永远在己方领土九宫内（rank 1...3），OUT 不会触达国界，不分叉。
    static func kingMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []
        let candidates: [SgPos?] = [
            SgGeometry.stepIn(from: pos, owner: owner),
            SgGeometry.stepOut(from: pos, owner: owner).first,  // 九宫内 OUT 不分叉
            SgGeometry.stepLeft(from: pos),
            SgGeometry.stepRight(from: pos),
        ]
        for c in candidates {
            guard let target = c else { continue }
            guard target.isInPalace else { continue }
            if let occ = board.piece(at: target), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }
        return moves
    }

    // MARK: - 兵 / 卒

    /// 兵：过国界前只前进；过国界后激活横走。
    /// 前进方向 = OUT（以 owner 为基准）。过国界后 OUT 变为在敌国坐标系中朝其底线。
    ///
    /// P4-3：兵卒在亡国地盘上（pos.nation 被 owner 吞并）时，前进方向重定义 ——
    /// 朝亡国国界（rank 递增）推进，到国界后分叉到剩余敌对国，不再沿亡国原方向。
    static func pawnMoves(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        // P4-3：亡国地盘上的收编兵卒
        if let conqueror = board.annexed[pos.nation], conqueror == owner {
            return pawnMovesOnConqueredTerritory(at: pos, owner: owner, on: board)
        }

        var moves: [SgMove] = []
        let crossed = pos.nation != owner

        // 前进（OUT 方向，可能分叉）
        for target in SgGeometry.stepOut(from: pos, owner: owner) {
            if let occ = board.piece(at: target), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }

        if crossed {
            // 过河兵：可横走（LEFT / RIGHT，在当前所在国坐标系内）
            for target in [SgGeometry.stepLeft(from: pos), SgGeometry.stepRight(from: pos)] {
                guard let t = target else { continue }
                if let occ = board.piece(at: t), occ.nation == owner { continue }
                moves.append(SgMove(from: pos, to: t))
            }
        }
        return moves
    }

    /// P4-3：亡国地盘上的收编兵卒走法。
    /// 前进 = 朝亡国国界（rank 递增）；在国界处分叉到剩余敌对国（alive 且 ≠ owner）。
    /// 已过河（不在 owner 原始本土）→ 可横走。
    private static func pawnMovesOnConqueredTerritory(at pos: SgPos, owner: SgNation, on board: SgBoard) -> [SgMove] {
        var moves: [SgMove] = []

        let forwardSteps: [SgPos]
        if pos.rank < 5 {
            // 朝亡国国界前进一步
            forwardSteps = [SgPos(nation: pos.nation, file: pos.file, rank: pos.rank + 1)]
        } else {
            // 已在亡国国界：分叉到剩余敌对国（翻转对接 file → 10−file，落到敌国 rank 5）
            let remainingEnemies = board.aliveNations.filter { $0 != owner }
            forwardSteps = remainingEnemies.map { SgPos(nation: $0, file: 10 - pos.file, rank: 5) }
        }
        for target in forwardSteps {
            if let occ = board.piece(at: target), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: target))
        }

        // 横走（已过河）
        for target in [SgGeometry.stepLeft(from: pos), SgGeometry.stepRight(from: pos)] {
            guard let t = target else { continue }
            if let occ = board.piece(at: t), occ.nation == owner { continue }
            moves.append(SgMove(from: pos, to: t))
        }
        return moves
    }
}
