//
//  SgCoordMapper.swift
//  sanguochese
//
//  三国象棋 · 逻辑坐标 ↔ 屏幕坐标映射 (P2-4)
//
//  三方地盘以 120° 旋转对称围合排列，每方的"国界边"(rank 5)朝向中央。
//  三条国界边拼成一个等边三角形，三角形的中心即棋盘中心。
//
//  局部坐标（每方自己的框架，旋转前）：
//    file 1..9  沿 tangent 方向（横向），file=5 在地盘横向中点
//    rank 1..5  沿 outward 方向（背离中心），rank=1 为底线（帅所在行，最外），
//               rank=5 为国界边（最靠近中心）
//
//  每方由一个朝外角 θ 定义（从棋盘中心指向该方底线方向）：
//    魏 θ =  π/2        （上方）
//    蜀 θ = -π/6        （右下）
//    吴 θ =  7π/6       （左下）
//  三者相差 120°，保证 120° 旋转对称：旋转整体 120° 后魏→蜀→吴→魏 完全重合。
//
//  屏幕坐标以棋盘中心为原点；GameScene 负责平移到场景中心。
//

import Foundation
import CoreGraphics

public struct SgCoordMapper {

    /// 单格边长（屏幕点）
    public let cellSize: CGFloat

    /// 国界边中点到棋盘中心的距离（等边三角形内切半径）
    /// 三条国界边各长 9·cellSize，拼成等边三角形，内切半径 = 边长·√3/6。
    public let apothem: CGFloat

    public init(cellSize: CGFloat) {
        self.cellSize = cellSize
        self.apothem = cellSize * 9.0 * CGFloat(3.0).squareRoot() / 6.0
    }

    // MARK: - 每方朝外角

    /// 某方的朝外角 θ（弧度，从棋盘中心指向该方底线方向）。
    public func outwardAngle(of nation: SgNation) -> CGFloat {
        switch nation {
        case .wei: return .pi / 2
        case .shu: return -.pi / 6
        case .wu:  return 7.0 * .pi / 6.0
        }
    }

    /// outward 单位向量
    private func outwardVec(_ nation: SgNation) -> CGVector {
        let a = outwardAngle(of: nation)
        return CGVector(dx: cos(a), dy: sin(a))
    }

    /// tangent 单位向量（outward 逆时针旋转 90°），保证 120° 旋转对称
    private func tangentVec(_ nation: SgNation) -> CGVector {
        let a = outwardAngle(of: nation)
        return CGVector(dx: -sin(a), dy: cos(a))
    }

    // MARK: - 逻辑坐标 → 屏幕坐标

    /// 某格中心在屏幕坐标系（以棋盘中心为原点）中的位置。
    public func screenPos(for pos: SgPos) -> CGPoint {
        let out = outwardVec(pos.nation)
        let tan = tangentVec(pos.nation)
        // rank=5 在国界边（距中心 apothem），rank=1 在最外（距中心 apothem + 4·cellSize）
        let radial = apothem + CGFloat(5 - pos.rank) * cellSize
        let lateral = CGFloat(pos.file - 5) * cellSize
        let x = radial * out.dx + lateral * tan.dx
        let y = radial * out.dy + lateral * tan.dy
        return CGPoint(x: x, y: y)
    }

    /// 棋盘整体半径（从中心到最外底线的角点），用于布局缩放。
    public var boardRadius: CGFloat {
        // 底线角点：radial = apothem + 4·cellSize，lateral = ±4·cellSize
        let r = apothem + 4 * cellSize
        let l = 4 * cellSize
        return (r * r + l * l).squareRoot()
    }

    // MARK: - 格子多边形（用于绘制/点击命中）

    /// 返回某格的四角屏幕坐标（顺时针），用于绘制格子矩形与命中判定。
    public func cellPolygon(for pos: SgPos) -> [CGPoint] {
        let out = outwardVec(pos.nation)
        let tan = tangentVec(pos.nation)
        // 在局部 (radial, lateral) 平面上，格子四角为：
        //   radial 范围：[apothem + (5-rank)·cs - 0.5cs,  + 0.5cs]
        //   lateral 范围：[(file-5)·cs - 0.5cs, + 0.5cs]
        let cs = cellSize
        let r0 = apothem + CGFloat(5 - pos.rank) * cs - 0.5 * cs
        let r1 = r0 + cs
        let l0 = CGFloat(pos.file - 5) * cs - 0.5 * cs
        let l1 = l0 + cs
        // 四角：(r0,l0)(r0,l1)(r1,l1)(r1,l0)
        func p(_ r: CGFloat, _ l: CGFloat) -> CGPoint {
            CGPoint(x: r * out.dx + l * tan.dx, y: r * out.dy + l * tan.dy)
        }
        return [p(r0, l0), p(r0, l1), p(r1, l1), p(r1, l0)]
    }

    /// 某格中心的多边形（用于点击命中），等价于 cellPolygon 但便于 SKShapeNode 绘制。
    public func cellPath(for pos: SgPos) -> CGPath {
        let pts = cellPolygon(for: pos)
        let path = CGMutablePath()
        path.move(to: pts[0])
        for i in 1..<pts.count { path.addLine(to: pts[i]) }
        path.closeSubpath()
        return path
    }

    // MARK: - 屏幕坐标 → 逻辑坐标（点击命中）

    /// 给定屏幕坐标（以棋盘中心为原点），返回命中的格子，未命中返回 nil。
    public func pos(at point: CGPoint) -> SgPos? {
        // 对每方，把 point 投影到该方局部 (radial, lateral) 坐标，判断是否落在 9×5 内。
        for nation in SgNation.allCases {
            let out = outwardVec(nation)
            let tan = tangentVec(nation)
            let radial = point.x * out.dx + point.y * out.dy
            let lateral = point.x * tan.dx + point.y * tan.dy
            // radial 范围：apothem + (5-rank)·cs ± 0.5cs，rank=1..5
            //   rank=5: radial∈[apothem-0.5cs, apothem+0.5cs]
            //   rank=1: radial∈[apothem+3.5cs, apothem+4.5cs]
            let cs = cellSize
            let radialFromBorder = radial - apothem  // rank=5 → ~0, rank=1 → ~4cs
            // rank = 5 - round((radialFromBorder)/cs)，且需在 [1,5]
            let rankFloat = 5.0 - radialFromBorder / cs
            let fileFloat = 5.0 + lateral / cs
            // 命中判定：落在格子中心 ±0.5cs 内
            let rank = Int((rankFloat + 0.5).rounded(.down))
            let file = Int((fileFloat + 0.5).rounded(.down))
            if (1...5).contains(rank) && (1...9).contains(file) {
                // 再校验确实在该格矩形内（避免边缘溢出误判）
                let pos = SgPos(nation: nation, file: file, rank: rank)
                if cellPolygon(for: pos).contains(point) {
                    return pos
                }
            }
        }
        return nil
    }
}

private extension Array where Element == CGPoint {
    /// 点在多边形内判定（射线法）
    func contains(_ p: CGPoint) -> Bool {
        guard count >= 3 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let pi = self[i], pj = self[j]
            if ((pi.y > p.y) != (pj.y > p.y)),
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
