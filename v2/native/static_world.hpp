// Exact axial circle/hex clearance, matching core/navigation.gd and geometry.gd.
#pragma once
#include "movement_kernel.hpp"
#include <set>

namespace atd {
inline Point sub(Point a, Point b) { return {a.q - b.q, a.r - b.r}; }
inline I cross(Point a, Point b) { return a.q * b.r - a.r * b.q; }
inline I segment_distance(Point point, Point a, Point b) {
    Point v = sub(b, a), w = sub(point, a);
    I length = metric(v.q, v.r);
    if (!length) return metric(w.q, w.r);
    I dot = 2 * w.q * v.q + w.q * v.r + w.r * v.q + 2 * w.r * v.r;
    I t = std::clamp<I>(dot * 1048576 / (2 * length), 0, 1048576);
    return metric(w.q - v.q * t / 1048576, w.r - v.r * t / 1048576);
}
inline bool intersects(Point a, Point b, Point c, Point d) {
    Point ab = sub(b, a), cd = sub(d, c);
    I ac = cross(ab, sub(c, a)), ad = cross(ab, sub(d, a));
    I ca = cross(cd, sub(a, c)), cb = cross(cd, sub(b, c));
    if ((ac > 0 && ad > 0) || (ac < 0 && ad < 0) || (ca > 0 && cb > 0) || (ca < 0 && cb < 0)) return false;
    return std::max(a.q, b.q) >= std::min(c.q, d.q) && std::max(c.q, d.q) >= std::min(a.q, b.q)
        && std::max(a.r, b.r) >= std::min(c.r, d.r) && std::max(c.r, d.r) >= std::min(a.r, b.r);
}
inline bool inside_hex(Point point, Point cell) {
    I q = point.q - cell.q * 3072, r = point.r - cell.r * 3072;
    return std::llabs(2 * q + r) <= 3072 && std::llabs(q + 2 * r) <= 3072 && std::llabs(q - r) <= 3072;
}
inline bool clear_hex(Point a, Point b, I size, Point cell) {
    a = {a.q * 3, a.r * 3}; b = {b.q * 3, b.r * 3};
    if (inside_hex(a, cell) || inside_hex(b, cell)) return false;
    static constexpr I offsets[6][2] = {{1,1},{-1,2},{-2,1},{-1,-1},{1,-2},{2,-1}};
    Point corners[6];
    for (size_t i = 0; i < 6; ++i) corners[i] = {cell.q * 3072 + offsets[i][0] * 1024, cell.r * 3072 + offsets[i][1] * 1024};
    I limit = (size * 3 + 2) * (size * 3 + 2);
    for (size_t i = 0; i < 6; ++i) {
        Point c = corners[i], d = corners[(i + 1) % 6];
        if (intersects(a, b, c, d) || segment_distance(a, c, d) <= limit || segment_distance(b, c, d) <= limit || segment_distance(c, a, b) <= limit) return false;
    }
    return true;
}
inline I round_cell(I n) { I value = (std::llabs(n) + 512) / 1024; return n < 0 ? -value : value; }
inline Point cell_at(Point p) {
    I q = round_cell(p.q), r = round_cell(p.r), s = round_cell(-p.q - p.r);
    I qe = std::llabs(q * 1024 - p.q), re = std::llabs(r * 1024 - p.r), se = std::llabs(s * 1024 + p.q + p.r);
    if (qe > re && qe > se) q = -r - s;
    else if (re > se) r = -q - s;
    return {q, r};
}
inline bool inside_map(Point cell, I radius) { return std::max({std::llabs(cell.q), std::llabs(cell.r), std::llabs(cell.q + cell.r)}) <= radius; }
struct Circle { Point point; I radius; };
class StaticWorld {
public:
    I radius = 0, revision = 0;
    std::set<Cell> hexes;
    std::vector<Circle> circles;
    bool clear(Point a, Point b, I size) const {
        I pad = (size + 1023) / 1024 + 1, inner = (radius - pad) * 1024;
        bool interior = inside_map(a, inner) && inside_map(b, inner);
        if (!interior || !hexes.empty()) {
            Point start = cell_at(a), end = cell_at(b);
            if (!interior && (!inside_map(start, radius) || !inside_map(end, radius))) return false;
            I minq = std::min(start.q, end.q) - pad, maxq = std::max(start.q, end.q) + pad;
            I minr = std::min(start.r, end.r) - pad, maxr = std::max(start.r, end.r) + pad;
            if (interior && static_cast<I>(hexes.size()) < (maxq - minq + 1) * (maxr - minr + 1)) {
                for (const auto &cell : hexes) {
                    if (cell.first >= minq && cell.first <= maxq && cell.second >= minr && cell.second <= maxr && !clear_hex(a, b, size, {cell.first, cell.second})) return false;
                }
            } else {
                for (I q = minq; q <= maxq; ++q) for (I r = minr; r <= maxr; ++r) {
                    if ((!inside_map({q, r}, radius) || hexes.count({q, r})) && !clear_hex(a, b, size, {q, r})) return false;
                }
            }
        }
        Point v = sub(b, a);
        for (const Circle &circle : circles) {
            I extent = (size + circle.radius + 2) * 1183 / 1024 + 2;
            if (circle.point.q < std::min(a.q, b.q) - extent || circle.point.q > std::max(a.q, b.q) + extent || circle.point.r < std::min(a.r, b.r) - extent || circle.point.r > std::max(a.r, b.r) + extent) continue;
            Point p = sub(circle.point, a);
            I limit = size + circle.radius + 2, start = metric(p.q, p.r), closest = segment_distance(circle.point, a, b);
            if (closest > limit * limit) continue;
            if (start < limit * limit && metric(p.q - v.q, p.r - v.r) > start && closest >= start) continue;
            return false;
        }
        return true;
    }
};
} // namespace atd
