// Deterministic integer crowd movement. No Godot, clocks, threads or physics APIs.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <unordered_map>
#include <vector>

namespace atd {
using I = int64_t;
struct Point { I q = 0, r = 0; };
inline I metric(I q, I r) { return q * q + q * r + r * r; }
inline I root(I value) {
    if (value <= 0) return 0;
    I n = static_cast<I>(std::sqrt(static_cast<double>(value)));
    while (n > value / n) --n;
    while (n + 1 <= value / (n + 1)) ++n;
    return n;
}
inline I sign(I n) { return (n > 0) - (n < 0); }
inline Point scaled(I q, I r, I length) {
    I size = root(metric(q, r));
    return size ? Point{q * length / size, r * length / size} : Point{};
}
inline I bucket(I n) { return n >= 0 ? n / 2048 : (n + 1) / 2048 - 1; }
struct Body { I id, owner, radius, q, r, vq, vr; };
using Cell = std::pair<I, I>;
struct Group {
    std::map<Cell, std::vector<size_t>> buckets;
    I radius = 0;
};

class Movement {
    std::vector<Body> bodies;
    std::unordered_map<I, size_t> ids;
    std::map<I, Group> groups;
    const Body *find(I id) const {
        auto it = ids.find(id);
        return it == ids.end() ? nullptr : &bodies[it->second];
    }
    std::vector<size_t> query(I owner, I q, I r, I reach, I cap = 0, I offset = 0) const {
        std::vector<size_t> result;
        auto found = groups.find(owner);
        if (found == groups.end()) return result;
        const Group &group = found->second;
        I radius = reach + group.radius;
        I extent = (radius * 1183 + 1023) / 1024 + 2;
        I cq = bucket(q), cr = bucket(r);
        I minq = bucket(q - extent), maxq = bucket(q + extent);
        I minr = bucket(r - extent), maxr = bucket(r + extent);
        I span = std::max({cq - minq, maxq - cq, cr - minr, maxr - cr});
        I scanned = 0;
        for (I ring = 0; ring <= span; ++ring) {
            for (I bq = std::max(minq, cq - ring); bq <= std::min(maxq, cq + ring); ++bq) {
                for (I br = std::max(minr, cr - ring); br <= std::min(maxr, cr + ring); ++br) {
                    if (std::max(std::llabs(bq - cq), std::llabs(br - cr)) != ring) continue;
                    auto entry = group.buckets.find({bq, br});
                    if (entry == group.buckets.end()) continue;
                    const auto &list = entry->second;
                    for (size_t i = 0; i < list.size(); ++i) {
                        size_t index = list[(i + static_cast<size_t>(offset)) % list.size()];
                        const Body &other = bodies[index];
                        ++scanned;
                        if (metric(q - other.q, r - other.r) <= radius * radius) result.push_back(index);
                        if (cap > 0 && scanned >= cap) return result;
                    }
                }
            }
        }
        return result;
    }
    std::vector<size_t> hostiles(I owner, I q, I r, I reach, I cap = 0, I offset = 0) const {
        std::vector<size_t> result;
        for (const auto &entry : groups) {
            if (entry.first == owner) continue;
            auto more = query(entry.first, q, r, reach, cap > 0 ? std::max<I>(1, cap - result.size()) : 0, offset);
            result.insert(result.end(), more.begin(), more.end());
            if (cap > 0 && static_cast<I>(result.size()) >= cap) break;
        }
        return result;
    }
    static I predicted(I q, I r, I vq, I vr) {
        I length = metric(vq, vr);
        if (!length) return metric(q, r);
        I dot = 2 * q * vq + q * vr + r * vq + 2 * r * vr;
        if (dot <= 0) return metric(q, r);
        if (dot >= 2 * length) return metric(q - vq, r - vr);
        I t = dot * 1048576 / (2 * length);
        return metric(q - vq * t / 1048576, r - vr * t / 1048576);
    }
public:
    std::vector<I> neighbors(I owner, I q, I r, I reach, I cap, I offset) const {
        std::vector<I> result;
        for (size_t index : query(owner, q, r, reach, cap, offset)) result.push_back(bodies[index].id);
        return result;
    }
    void prepare(const I *data, size_t size) {
        bodies.clear(); ids.clear(); groups.clear();
        bodies.reserve(size / 7);
        for (size_t i = 0; i < size; i += 7) {
            Body b{data[i], data[i+1], data[i+2], data[i+3], data[i+4], data[i+5], data[i+6]};
            size_t index = bodies.size();
            bodies.push_back(b); ids[b.id] = index;
            auto &g = groups[b.owner];
            g.radius = std::max(g.radius, b.radius);
            g.buckets[{bucket(b.q), bucket(b.r)}].push_back(index);
        }
    }
    void moved(I id, I q, I r) {
        auto it = ids.find(id);
        if (it == ids.end()) return;
        Body &body = bodies[it->second];
        Cell old{bucket(body.q), bucket(body.r)}, next{bucket(q), bucket(r)};
        body.q = q; body.r = r;
        if (old == next) return;
        auto &g = groups[body.owner];
        auto &list = g.buckets[old];
        list.erase(std::remove(list.begin(), list.end(), it->second), list.end());
        g.buckets[next].push_back(it->second);
    }
    Point preferred(I id, I vq, I vr, I wq, I wr, I speed, I stop, I hz, bool passing) const {
        const Body *ptr = find(id);
        if (!ptr) return {};
        const Body &body = *ptr;
        I length = root(metric(vq, vr));
        if (!length) return {body.q, body.r};
        I horizon = std::max<I>(1, hz / 2), reach = speed * horizon + 1024;
        auto candidates = query(body.owner, body.q, body.r, body.radius + reach, 24, body.id);
        auto enemies = hostiles(body.owner, body.q, body.r, body.radius + reach, 24, body.id);
        candidates.insert(candidates.end(), enemies.begin(), enemies.end());
        struct Entry { I distance, id; size_t index; };
        std::vector<Entry> nearby;
        for (size_t index : candidates) {
            const Body &other = bodies[index];
            if (other.id == body.id) continue;
            I distance = metric(body.q - other.q, body.r - other.r);
            I limit = body.radius + other.radius + reach;
            if (distance < limit * limit) nearby.push_back({distance, other.id, index});
        }
        std::sort(nearby.begin(), nearby.end(), [](const Entry &a, const Entry &b) {
            return a.distance < b.distance || (a.distance == b.distance && a.id < b.id);
        });
        if (nearby.size() > 6) nearby.resize(6);
        I distance = std::min(length * horizon, std::max(length, root(metric(body.q - wq, body.r - wr)) - stop));
        Point prediction = scaled(vq, vr, distance), perpendicular = scaled(-vq - 2 * vr, 2 * vq + vr, length);
        I fq = 0, fr = 0;
        static constexpr I axes[6][2] = {{1,0},{0,1},{-1,1},{-1,0},{0,-1},{1,-1}};
        for (const Entry &entry : nearby) {
            const Body &other = bodies[entry.index];
            if (passing && other.owner == body.owner) continue;
            I q = body.q - other.q, r = body.r - other.r;
            I distance2 = metric(q, r), limit = body.radius + other.radius + 32;
            if (distance2 < limit * limit) {
                I d = root(distance2);
                if (!d) {
                    I axis = (std::min(body.id, other.id) * 17 + std::max(body.id, other.id) * 31) % 6;
                    I direction = body.id < other.id ? 1 : -1;
                    fq += axes[axis][0] * length * direction; fr += axes[axis][1] * length * direction;
                } else {
                    I strength = (limit - d) * length * 2 / limit;
                    fq += q * strength / d; fr += r * strength / d;
                }
                continue;
            }
            I rq = prediction.q - other.vq * horizon, rr = prediction.r - other.vr * horizon;
            if (-2 * q * rq - q * rr - r * rq - 2 * r * rr <= 0) continue;
            I closest = predicted(-q, -r, rq, rr);
            if (closest >= limit * limit) continue;
            I cross = -vq * r + vr * q, side = cross ? -sign(cross) : 1;
            I weight = (limit * limit - closest) * 512 / (limit * limit);
            fq += perpendicular.q * side * weight / 1024; fr += perpendicular.r * side * weight / 1024;
        }
        if (!fq && !fr) return {body.q + vq, body.r + vr};
        I q = vq + fq, r = vr + fr;
        I forward = 2 * q * vq + q * vr + r * vq + 2 * r * vr, minimum = metric(vq, vr);
        if (forward < minimum) {
            q += vq * (minimum - forward) / (2 * minimum);
            r += vr * (minimum - forward) / (2 * minimum);
        }
        Point delta = root(metric(q, r)) > length ? scaled(q, r, length) : Point{q, r};
        return {body.q + delta.q, body.r + delta.r};
    }
    bool contact(I id, I q, I r, I reach) const {
        const Body *ptr = find(id);
        if (!ptr) return false;
        const Body &b = *ptr;
        I vq = q - b.q, vr = r - b.r, length = metric(vq, vr);
        for (size_t index : hostiles(b.owner, b.q, b.r, reach)) {
            const Body &enemy = bodies[index];
            I eq = enemy.q - b.q, er = enemy.r - b.r, limit = b.radius + enemy.radius + 2;
            I start = metric(eq, er), closest = start;
            if (length) {
                I dot = 2 * eq * vq + eq * vr + er * vq + 2 * er * vr;
                I t = std::clamp<I>(dot * 1048576 / (2 * length), 0, 1048576);
                closest = metric(eq - vq * t / 1048576, er - vr * t / 1048576);
            }
            if (closest > limit * limit) continue;
            if (start < limit * limit && metric(eq - vq, er - vr) > start && closest >= start) continue;
            return false;
        }
        return true;
    }
    I pressure(I id, I q, I r) const {
        const Body *ptr = find(id);
        if (!ptr) return 0;
        I score = 0;
        for (const Body &other : bodies) {
            if (other.id == id || other.owner != ptr->owner) continue;
            I limit = ptr->radius + other.radius;
            score += std::max<I>(0, limit * limit - metric(q - other.q, r - other.r)) * 4096 / (limit * limit);
        }
        return score;
    }
};
} // namespace atd
