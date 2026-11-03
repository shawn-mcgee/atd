// Monotonic discovery between restores. Only integer tile-center tests; no view.
#pragma once
#include "movement_kernel.hpp"

namespace atd {
struct Discovery { I owner, q, r; };
class Exploration {
    I radius = -1, side = 0;
    std::map<I, std::vector<uint8_t>> known;
public:
    std::vector<Discovery> additions;
    void prepare(I map_radius) {
        additions.clear();
        if (radius != map_radius) {
            radius = map_radius; side = radius * 2 + 1; known.clear();
        }
    }
    void observe(I owner, I q, I r, I reach) {
        auto &tiles = known[owner];
        if (tiles.empty()) tiles.resize(static_cast<size_t>(side * side));
        // Axial component magnitude is at most 2/sqrt(3) times metric length.
        I span = (reach * 1183 + 1048575) / 1048576 + 2;
        I cq = q / 1024, cr = r / 1024;
        for (I tq = std::max(-radius, cq - span); tq <= std::min(radius, cq + span); ++tq) {
            for (I tr = std::max(-radius, cr - span); tr <= std::min(radius, cr + span); ++tr) {
                if (std::llabs(tq + tr) > radius) continue;
                size_t index = static_cast<size_t>((tq + radius) * side + tr + radius);
                if (tiles[index] || metric(q - tq * 1024, r - tr * 1024) > reach * reach) continue;
                tiles[index] = 1; additions.push_back({owner, tq, tr});
            }
        }
    }
};
} // namespace atd
