-- Jagged 5m-wide nest; center is accessible from the southern opening.
forge.build("Primitives/icosphere", {0, 0, 0}, {0, 0, 0}, {3.8, 0.9, 3.8})
for i = 0, 5 do
    local angle = i * math.pi / 3
    forge.build("Primitives/cone", {math.cos(angle) * 1.8, 0.2, math.sin(angle) * 1.8}, {0, i * 60, 12}, {1.1, 3.4, 1.1})
end
forge.build("Primitives/icosphere", {0, 0.6, 0}, {0, 0, 0}, {1.2, 1.6, 1.2})
