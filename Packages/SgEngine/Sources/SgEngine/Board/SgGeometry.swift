//
//  SgGeometry.swift
//  sanguochese
//
//  三国象棋 · 棋盘几何与射线生成
//  P1-1/P1-3 坐标系统 · 国界分叉路由
//
//  本文件实现"9 条线在国界处二叉分叉"的几何，
//  为走法生成提供射线（ray）与单步（step）原语。
//
//  方向定义（以棋子归属国 owner 为基准）：
//    OUT  = 前进（朝敌方底线方向）
//    IN   = 后退（朝己方底线 / 朝来路国界方向）
//    LEFT = file 递减（横向，在当前所在国坐标系内）
//    RIGHT= file 递增（横向，在当前所在国坐标系内）
//
//  关键性质：
//    1. 棋子在己方领土（pos.nation == owner）时：
//       OUT = rank 递增（朝国界），到达 rank 5 后分叉到 2 个敌国。
//       IN  = rank 递减（朝己方底线），rank 1 为底线，不再分叉。
//    2. 棋子在敌国领土（pos.nation != owner）时：
//       OUT = rank 递减（朝敌国底线），不再分叉（rank 1 为敌底线）。
//       IN  = rank 递增（朝敌国国界），到达 rank 5 后分叉到 2 个国家
//             （其中一个可能是己方——相当于撤回本国）。
//
//  这保证了"面向任一国时，走法与传统象棋完全一致"：
//  在任一领土内，前进方向只有一个（朝该国底线），后退方向只有一个（朝该国国界），
//  分叉只发生在国界处。
//

import Foundation

public enum SgGeometry {

    // MARK: - 单步移动

    /// 向前（OUT）走一步。返回 1 或 2 个结果（在国界处分叉成 2 条）。
    /// - 在己方领土：rank 递增；rank==5 时分叉到存活敌国。
    /// - 在敌国领土：rank 递减（朝敌底线）；rank==1 时无法继续。
    /// - alive：当前存活国家集合，用于过滤国界分叉目标（2 人模式只分叉到 1 个敌国）。
    public static func stepOut(from pos: SgPos, owner: SgNation, alive: Set<SgNation> = Set(SgNation.allCases)) -> [SgPos] {
        if pos.nation == owner {
            // 己方领土：前进 = rank 递增
            if pos.rank < 5 {
                return [SgPos(nation: pos.nation, file: pos.file, rank: pos.rank + 1)]
            }
            // rank == 5：过国界，分叉到存活的敌国
            return pos.nation.opponents().filter { alive.contains($0) }.map { enemy in
                SgPos(nation: enemy, file: 10 - pos.file, rank: 5)
            }
        } else {
            // 敌国领土：前进 = rank 递减（朝敌国底线）
            guard pos.rank > 1 else { return [] }
            return [SgPos(nation: pos.nation, file: pos.file, rank: pos.rank - 1)]
        }
    }

    /// 向后（IN）走一步。返回 0 或 1 个结果。
    /// - 在己方领土：rank 递减（朝己方底线）。
    /// - 在敌国领土：rank 递增（朝敌国国界）；rank==5 时无法继续（需分叉，由 inRays 处理）。
    public static func stepIn(from pos: SgPos, owner: SgNation) -> SgPos? {
        if pos.nation == owner {
            // 己方领土：后退 = rank 递减
            guard pos.rank > 1 else { return nil }
            return SgPos(nation: pos.nation, file: pos.file, rank: pos.rank - 1)
        } else {
            // 敌国领土：后退 = rank 递增（朝敌国国界）
            guard pos.rank < 5 else { return nil }
            return SgPos(nation: pos.nation, file: pos.file, rank: pos.rank + 1)
        }
    }

    /// 向左走一步（file 递减，在当前所在国坐标系内）。
    public static func stepLeft(from pos: SgPos) -> SgPos? {
        guard pos.file > 1 else { return nil }
        return SgPos(nation: pos.nation, file: pos.file - 1, rank: pos.rank)
    }

    /// 向右走一步（file 递增，在当前所在国坐标系内）。
    public static func stepRight(from pos: SgPos) -> SgPos? {
        guard pos.file < 9 else { return nil }
        return SgPos(nation: pos.nation, file: pos.file + 1, rank: pos.rank)
    }

    // MARK: - 射线生成（用于车、炮等滑行棋子）

    /// OUT（前进）方向的射线。可能分叉成多条（在国界处）。
    /// - 己方领土：rank+1...5 → 分叉到存活敌国（各 rank 5→1）。
    /// - 敌国领土：rank-1...1，单条射线，不分叉。
    /// - alive：当前存活国家集合，过滤分叉目标。
    public static func outRays(from pos: SgPos, owner: SgNation, alive: Set<SgNation> = Set(SgNation.allCases)) -> [[SgPos]] {
        if pos.nation == owner {
            // 己方领土：前进到国界后分叉
            var rays: [[SgPos]] = []
            let ownPart: [SgPos] = pos.rank < 5
                ? (pos.rank + 1 ... 5).map { r in
                    SgPos(nation: pos.nation, file: pos.file, rank: r)
                }
                : []
            for enemy in pos.nation.opponents() where alive.contains(enemy) {
                let enemyFile = 10 - pos.file
                let enemyPart: [SgPos] = stride(from: 5, through: 1, by: -1).map { r in
                    SgPos(nation: enemy, file: enemyFile, rank: r)
                }
                rays.append(ownPart + enemyPart)
            }
            return rays
        } else {
            // 敌国领土：朝敌底线前进，不分叉
            guard pos.rank > 1 else { return [] }
            let ray: [SgPos] = stride(from: pos.rank - 1, through: 1, by: -1).map { r in
                SgPos(nation: pos.nation, file: pos.file, rank: r)
            }
            return [ray]
        }
    }

    /// IN（后退）方向的射线。可能分叉成多条（在敌国国界处）。
    /// - 己方领土：rank-1...1，单条射线，不分叉。
    /// - 敌国领土：rank+1...5 → 分叉到存活国家（各 rank 5→1）。
    /// - alive：当前存活国家集合，过滤分叉目标。
    public static func inRays(from pos: SgPos, owner: SgNation, alive: Set<SgNation> = Set(SgNation.allCases)) -> [[SgPos]] {
        if pos.nation == owner {
            // 己方领土：朝己方底线，不分叉
            guard pos.rank > 1 else { return [] }
            let ray: [SgPos] = stride(from: pos.rank - 1, through: 1, by: -1).map { r in
                SgPos(nation: pos.nation, file: pos.file, rank: r)
            }
            return [ray]
        } else {
            // 敌国领土：朝敌国国界后退，到国界后分叉
            var rays: [[SgPos]] = []
            let enemyPart: [SgPos] = pos.rank < 5
                ? (pos.rank + 1 ... 5).map { r in
                    SgPos(nation: pos.nation, file: pos.file, rank: r)
                }
                : []
            // 分叉到当前所在国的存活对手国（其中一个可能是 owner——撤回本国）
            for other in pos.nation.opponents() where alive.contains(other) {
                let otherFile = 10 - pos.file
                let otherPart: [SgPos] = stride(from: 5, through: 1, by: -1).map { r in
                    SgPos(nation: other, file: otherFile, rank: r)
                }
                rays.append(enemyPart + otherPart)
            }
            return rays
        }
    }

    /// LEFT 方向的射线（file 递减，不过国界，与 owner 无关）。
    public static func leftRay(from pos: SgPos) -> [SgPos] {
        guard pos.file > 1 else { return [] }
        return stride(from: pos.file - 1, through: 1, by: -1).map { f in
            SgPos(nation: pos.nation, file: f, rank: pos.rank)
        }
    }

    /// RIGHT 方向的射线（file 递增，不过国界，与 owner 无关）。
    public static func rightRay(from pos: SgPos) -> [SgPos] {
        guard pos.file < 9 else { return [] }
        return stride(from: pos.file + 1, through: 9, by: 1).map { f in
            SgPos(nation: pos.nation, file: f, rank: pos.rank)
        }
    }

    // MARK: - 主帅互照：两帅之间的格子序列

    /// 若两个主帅在同一连通纵线上（file 经翻转对接），返回它们之间的所有格子。
    /// 否则返回 nil。格子序列不含两端的主帅位置。
    /// 主帅永远在己方领土的九宫内（rank 1...3），所以此函数只处理
    /// "kingA 在 A 国、kingB 在 B 国"的跨国土场景。
    public static func cellsBetween(kingA: SgPos, kingB: SgPos) -> [SgPos]? {
        guard kingA.nation != kingB.nation else { return nil }
        // 翻转对接：A 的 file i 接 B 的 file (10-i)
        guard kingA.file == 10 - kingB.file else { return nil }
        var cells: [SgPos] = []
        // A 领土：rank+1 ... 5
        if kingA.rank < 5 {
            for r in (kingA.rank + 1) ... 5 {
                cells.append(SgPos(nation: kingA.nation, file: kingA.file, rank: r))
            }
        }
        // B 领土：rank 5 ... rank+1（递减）
        if kingB.rank < 5 {
            for r in stride(from: 5, through: kingB.rank + 1, by: -1) {
                cells.append(SgPos(nation: kingB.nation, file: kingB.file, rank: r))
            }
        }
        return cells
    }
}
