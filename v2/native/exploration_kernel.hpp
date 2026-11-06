// Monotonic discovery between restores. Only integer tile-center tests; no view.
#pragma once
#include "movement_kernel.hpp"
#include <tuple>

namespace atd {
struct Discovery { I owner, q, r; };
class Exploration {
    I radius = -1, side = 0;
    std::map<I, std::vector<uint8_t>> known;
    struct Candidate { size_t index; I q, r; };
    std::map<std::tuple<I, I, I, I>, std::vector<Candidate>> fringes;
public:
    std::vector<Discovery> additions;
    void prepare(I map_radius) {
        additions.clear();
        if (radius != map_radius) {
            radius = map_radius; side = radius * 2 + 1; known.clear(); fringes.clear();
        }
    }
    void observe(I owner, I q, I r, I reach) {
        auto &tiles = known[owner];
        if (tiles.empty()) tiles.resize(static_cast<size_t>(side * side));
        auto round = [](I value) { I n = (std::llabs(value) + 512) / 1024; return value < 0 ? -n : n; };
        I cq = round(q), cr = round(r), cs = round(-q - r);
        I qe = std::llabs(cq * 1024 - q), re = std::llabs(cr * 1024 - r), se = std::llabs(cs * 1024 + q + r);
        if (qe > re && qe > se) cq = -cr - cs;
        else if (re > se) cr = -cq - cs;
        auto key = std::make_tuple(owner, reach, cq, cr);
        auto found = fringes.find(key);
        if (found == fringes.end()) {
            // Every sub-tile observer is within one tile of its hex center.
            // Shared envelopes discard discoveries monotonically until restore.
            if (fringes.size() >= 512) fringes.clear();
            auto &candidates = fringes[key];
            I envelope = reach + 1024;
            I span = (envelope * 1183 + 1048575) / 1048576;
            for (I tq = std::max(-radius, cq - span); tq <= std::min(radius, cq + span); ++tq) {
                for (I tr = std::max(-radius, cr - span); tr <= std::min(radius, cr + span); ++tr) {
                    if (std::llabs(tq + tr) > radius || metric((cq - tq) * 1024, (cr - tr) * 1024) > envelope * envelope) continue;
                    size_t index = static_cast<size_t>((tq + radius) * side + tr + radius);
                    if (!tiles[index]) candidates.push_back({index, tq * 1024, tr * 1024});
                }
            }
            found = fringes.find(key);
        }
        auto &candidates = found->second;
        size_t remaining = 0;
        for (const auto &candidate : candidates) {
            if (tiles[candidate.index]) continue;
            if (metric(q - candidate.q, r - candidate.r) <= reach * reach) {
                tiles[candidate.index] = 1; additions.push_back({owner, candidate.q / 1024, candidate.r / 1024});
            } else candidates[remaining++] = candidate;
        }
        candidates.resize(remaining);
    }
};
} // namespace atd
