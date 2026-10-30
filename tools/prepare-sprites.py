"""Prepare approved sheets and isolate terrain alpha islands; Pillow/NumPy/SciPy required.

Run from the repository root: python tools/prepare-sprites.py
Terrain components are repacked with gutters and fitted copies are morphed;
other sheets remain unchanged. Keep originals to reproduce the extraction.
"""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

def morph_hex(sprite, height):
    """Radially map the complete alpha boundary to an exact pointy-top hex."""
    import numpy as np
    from scipy import ndimage
    pixels = np.array(sprite)
    solid = pixels[:, :, 3] > 40
    yy, xx = np.nonzero(solid)
    sx = (xx + .5) / sprite.width * 2 - 1
    sy = (yy + .5) / sprite.height * 2 - 1
    angles = np.mod(np.arctan2(sy, sx), 2 * np.pi)
    bins = np.floor(angles / (2 * np.pi) * 720).astype(int)
    boundary = np.zeros(720)
    np.maximum.at(boundary, bins, np.hypot(sx, sy))
    valid = np.flatnonzero(boundary)
    boundary = np.interp(np.arange(720), valid, boundary[valid], period=720)
    boundary = ndimage.maximum_filter1d(boundary, 3, mode="wrap")
    _, nearest = ndimage.distance_transform_edt(~solid, return_indices=True)
    filled = pixels[nearest[0], nearest[1]]
    gy, gx = np.mgrid[:height, :256]
    x = (gx + .5) / 256 * 2 - 1
    y = (gy + .5) / height * 2 - 1
    angle = np.mod(np.arctan2(y, x), 2 * np.pi)
    dx, dy = np.cos(angle), np.sin(angle)
    edge = np.minimum(1 / np.maximum(abs(dx), 1e-6), 1 / np.maximum(abs(dy) + .5 * abs(dx), 1e-6))
    fraction = np.minimum(1, np.hypot(x, y) / edge)
    radius = np.interp(angle / (2 * np.pi) * 720, np.arange(720), boundary, period=720) * fraction
    map_x = (dx * radius + 1) * .5 * sprite.width - .5
    map_y = (dy * radius + 1) * .5 * sprite.height - .5
    result = np.empty((height, 256, 4), dtype=np.uint8)
    for channel in range(3):
        result[:, :, channel] = ndimage.map_coordinates(filled[:, :, channel], [map_y, map_x], order=1, mode="nearest")
    # Opaque edge-extended colors; the renderer clips to the exact hex mesh.
    result[:, :, 3] = 255
    return Image.fromarray(result)


def isolate_terrain(image, columns, rows):
    """Extract complete alpha islands across nominal cells, then add wide gutters."""
    import numpy as np
    from scipy import ndimage
    from scipy.optimize import linear_sum_assignment

    pixels = np.array(image)
    labels, total = ndimage.label(pixels[:, :, 3] > 40)
    counts = np.bincount(labels.ravel())
    number = columns * rows
    if total < number:
        raise ValueError("Terrain sprites touch: separate their silhouettes before extraction")
    islands = np.argsort(counts[1:])[-number:] + 1
    centers = np.array(ndimage.center_of_mass(pixels[:, :, 3], labels, islands))
    expected = np.array([((r + .5) * image.height / rows, (c + .5) * image.width / columns)
                         for r in range(rows) for c in range(columns)])
    slots, matches = linear_sum_assignment(((expected[:, None] - centers[None, :]) ** 2).sum(axis=2))
    distance, nearest = ndimage.distance_transform_edt(labels == 0, return_indices=True)
    owners = labels[nearest[0], nearest[1]]
    packed = Image.new("RGBA", (columns * 512, rows * 512))
    for slot, match in zip(slots, matches):
        island = islands[match]
        owned = (owners == island) & (distance <= 3) & (pixels[:, :, 3] > 0)
        yy, xx = np.nonzero(owned)
        x0, x1, y0, y1 = xx.min(), xx.max() + 1, yy.min(), yy.max() + 1
        cutout = pixels[y0:y1, x0:x1].copy()
        cutout[~owned[y0:y1, x0:x1]] = 0
        assert np.count_nonzero(cutout[:, :, 3] > 40) == counts[island], "Lost or borrowed opaque pixels"
        sprite = Image.fromarray(cutout)
        if max(sprite.size) > 448:
            raise ValueError("Terrain island exceeds safe atlas slot; increase slot size")
        # Preserve pixels/aspect; no resizing. 32+ transparent pixels protect mipmaps.
        packed.paste(sprite, ((int(slot) % columns) * 512 + (512 - sprite.width) // 2,
                              (int(slot) // columns) * 512 + (512 - sprite.height) // 2))
    return packed

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "project/art_source/sprites"
OUTPUT = ROOT / "project/assets/sprites"
SHEETS = [
    ("batch_01_characters", 3, 2, "engineer marine flamer runner stalker brute"),
    ("batch_02_vehicles", 3, 2, "scout jeep drill scout_wreck jeep_wreck drill_wreck"),
    ("batch_03_large_buildings", 2, 2, "core generator barracks garage"),
    ("batch_04_utility_buildings", 3, 2, "depot gas_tank repeater floodlight scanner extractor"),
    ("batch_05_turret_components", 3, 2, "turret_base laser_turret_base flame_turret_base turret_head laser_turret_head flame_turret_head"),
    ("batch_06_objectives_and_ramps", 3, 2, "beacon_ruined beacon hive hive_breached ramp natural_ramp"),
    ("batch_07_terrain_and_connections", 4, 4, "ground_a ground_b cliff_top platform materials_full materials_medium materials_low methane_full methane_medium methane_low wall wall_arm unused_gate_frame unused_gate_closed unused_gate_open rubble"),
    ("batch_09_ui_icons", 5, 5, "ui_board ui_unload ui_expedition ui_mining ui_attack ui_defend ui_patrol ui_drill_order ui_repair ui_load ui_stock ui_home ui_escort ui_recharge ui_reload_turret ui_auto_reload ui_repeater ui_gate ui_gate_lock ui_stop ui_destroy ui_cancel_train ui_material ui_methane ui_power"),
    ("batch_08_items_and_effects", 4, 4, "hive_core material_crate methane_canister muzzle_00 muzzle_01 impact_kinetic impact_laser flame_00 flame_01 flame_02 repair_sparks_00 repair_sparks_01 smoke_00 smoke_01 alien_hit_00 alien_hit_01"),
]
SIZES = {"engineer": (.8, .9), "marine": (.8, 1.2), "flamer": (.9, 1.2),
         "runner": (.8, 1), "stalker": (1, 1.1), "brute": (1.3, 1.4),
         "scout": (1, 1.6), "jeep": (1.4, 2), "drill": (1.7, 2.2),
         "hive_core": (.48, .55), "wall_arm": (.95, .36),
         "turret_head": (.9, 1.2), "laser_turret_head": (.9, 1.2), "flame_turret_head": (.9, 1.2)}
MUZZLES = {"marine": (.50, .985), "flamer": (.55, .98), "turret_head": (.50, .018),
           "laser_turret_head": (.50, .018), "flame_turret_head": (.50, .025)}
SOUTH = {"engineer", "marine", "flamer", "runner", "stalker", "brute", "scout", "jeep", "drill"}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries, sheets = {}, {}
    for stem, columns, rows, names in SHEETS:
        source = SOURCE / (stem + ".png")
        image = Image.open(source).convert("RGBA")
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        terrain = stem == "batch_07_terrain_and_connections"
        if terrain:
            image = isolate_terrain(image, columns, rows)
            image.save(OUTPUT / source.name)
        width, height = image.size
        sheets[stem] = {"file": stem + ".png", "size": [width, height],
                        "sha256": hashlib.sha256((OUTPUT / source.name).read_bytes()).hexdigest() if terrain else source_hash,
                        "source_sha256": source_hash}
        for index, name in enumerate(names.split()):
            if name.startswith("unused_"):  # Gate art is intentionally replaced in code.
                continue
            col, row = index % columns, index // columns
            cell = (round(col * width / columns), round(row * height / rows),
                    round((col + 1) * width / columns), round((row + 1) * height / rows))
            # Analyze alpha only; exclude barely visible background haze from bounds.
            alpha = image.getchannel("A").crop(cell)
            bounds = alpha.point(lambda a: 255 if a > 0 and (terrain or a >= 96) else 0).getbbox()
            if bounds is None:
                raise ValueError(f"Empty sprite: {name}")
            x0, y0 = max(cell[0], cell[0] + bounds[0] - 3), max(cell[1], cell[1] + bounds[1] - 3)
            x1, y1 = min(cell[2], cell[0] + bounds[2] + 3), min(cell[3], cell[1] + bounds[3] + 3)
            size = SIZES.get(name, (1.5, 1.5))
            pivot = [.5, .5]
            # Rifle/nozzle extends ahead of the body; pivot stays under the torso.
            if name in {"marine", "flamer"}: pivot = [.5, .38]
            if name == "engineer": pivot = [.5, .38]
            if name.endswith("_head"): pivot = [.5, .70]
            if name == "floodlight": pivot = [.5, .62]
            if stem in {"batch_01_characters", "batch_07_terrain_and_connections"}:
                desired_width = size[0] if stem == "batch_01_characters" else (0.95 if name == "wall_arm" else 1.82)
                size = (desired_width, desired_width * (y1 - y0) / (x1 - x0))
            if name == "cliff_top":
                # Fit the foreshortened top to a whole hex, retain depth below it.
                size = (2.0, 2.5)
                pivot = [.5, .62]
            if name == "platform":
                size = (1.82, 1.82 * (y1 - y0) / (x1 - x0))
                pivot = [.5, .45]
            if name.startswith("materials_"):
                pivot = [.5, .5 + .22 / size[1]]
            if name.endswith("_wreck"): size = SIZES[name.removesuffix("_wreck")]
            if name.startswith("muzzle_") or name.startswith("flame_0"): pivot = [.02, .5]
            entries[name] = {"sheet": stem, "region": [x0, y0, x1 - x0, y1 - y0],
                             "pivot": pivot, "world_size": list(size),
                             "rotation_degrees": 180 if name in SOUTH or name.endswith("_wreck") else 0}
            if name in MUZZLES: entries[name]["muzzle_uv"] = list(MUZZLES[name])
            if name in {"ground_a", "ground_b", "cliff_top"}:
                fitted = morph_hex(image.crop((x0, y0, x1, y1)), 370 if name == "cliff_top" else 296)
                key = name + "_fit"
                filename = key + ".png"
                fitted.save(OUTPUT / filename)
                sheets[key] = {"file": filename, "size": list(fitted.size), "source_sha256": source_hash,
                               "sha256": hashlib.sha256((OUTPUT / filename).read_bytes()).hexdigest()}
                entries[key] = {"sheet": key, "region": [0, 0, *fitted.size], "pivot": [.5, .6 if name == "cliff_top" else .5],
                                "world_size": [1.732050808, 2.5 if name == "cliff_top" else 2], "rotation_degrees": 0}
        if not terrain and (not (OUTPUT / source.name).exists() or hashlib.sha256((OUTPUT / source.name).read_bytes()).hexdigest() != source_hash):
            shutil.copyfile(source, OUTPUT / source.name)
        settings = OUTPUT / (source.name + ".import")
        if settings.exists():
            settings.write_text(settings.read_text().replace("mipmaps/generate=false", "mipmaps/generate=true"))
    manifest = {"version": 1, "sheets": sheets, "sprites": entries,
                "notes": "Original pixels unchanged. Aliens and vehicles face south; rotate 180 degrees at draw time. Gate is procedural."}
    (OUTPUT / "atlas.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(entries)} regions; terrain isolated and fitted copies morphed. Sources unchanged.")


if __name__ == "__main__":
    main()
