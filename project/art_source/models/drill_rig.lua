-- Ground origin, -Z front; 2.4m wide, ~5m long tunneling vehicle.
forge.build("Primitives/block_bevel", {0, 0.7, 0}, {0, 0, 0}, {1.8, 0.6, 2.6})
forge.build("Primitives/block_bevel", {0, 1.2, -0.4}, {0, 0, 0}, {1.4, 0.7, 1.1})
for _, x in ipairs({-1, 1}) do
    for _, z in ipairs({-0.9, 0.9}) do
        forge.build("Primitives/cylinder", {x, 0.45, z}, {0, 0, 90}, {0.9, 0.4, 0.9})
    end
end
forge.build("Primitives/cone", {0, 0.85, 1.9}, {90, 0, 0}, {1.2, 1.6, 1.2})
forge.build("Vehicles/detail_antenna", {0.5, 1.65, -0.7})
