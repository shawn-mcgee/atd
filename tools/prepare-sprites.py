"""Prepare approved sheets and isolate terrain alpha islands; Pillow/NumPy/SciPy required.

Run from the repository root: python tools/prepare-sprites.py
Use --batch-7 to refresh terrain, walls and gates while retaining resource patches.
Terrain components are repacked with gutters and fitted copies are morphed.
"""
from pathlib import Path
import hashlib
import json
import shutil
import sys
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
    ("batch_07_terrain_and_connections", 4, 4, "ground_a ground_b cliff_top platform materials_full materials_medium materials_low methane_full methane_medium methane_low wall wall_arm gate_frame gate_closed gate_open rubble"),
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


def update_batch7(wall_only=False):
    """Refresh terrain/fortifications without replacing approved resource patches."""
    stem = "batch_07_terrain_and_connections"
    source = SOURCE / (stem + ".png")
    image = Image.open(source).convert("RGBA")
    atlas_path = OUTPUT / (stem + ".png")
    atlas = Image.open(atlas_path).convert("RGBA")
    if atlas.size != (2048, 2048):
        raise ValueError("Selective Batch 7 import requires the prepared 4x4 atlas with 512px slots")
    manifest_path = OUTPUT / "atlas.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    selected = {10: "wall"} if wall_only else {
        0: "ground_a", 1: "ground_b", 2: "cliff_top", 10: "wall",
        12: "gate_frame", 13: "gate_closed", 14: "gate_open"}
    if not wall_only:
        import numpy as np
        from scipy import ndimage
        pixels = np.array(image)
        labels, _ = ndimage.label(pixels[:, :, 3] > 40)
        distance, nearest = ndimage.distance_transform_edt(labels == 0, return_indices=True)
        owners = labels[nearest[0], nearest[1]]
    slots = {}
    for index, name in selected.items():
        col, row = index % 4, index // 4
        cx0, cy0, cx1, cy1 = (round(col * image.width / 4), round(row * image.height / 4),
                                round((col + 1) * image.width / 4), round((row + 1) * image.height / 4))
        cell = image.crop((cx0, cy0, cx1, cy1))
        bounds = cell.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
        if bounds is None:
            raise ValueError(f"The Batch 7 {name} cell is empty")
        slot = Image.new("RGBA", (512, 512))
        if not wall_only:
            counts = np.bincount(labels[cy0:cy1, cx0:cx1].ravel())
            count = 2 if name in {"gate_frame", "gate_open"} else 1
            islands = np.argsort(counts[1:])[-count:] + 1
            owned = np.isin(owners, islands) & (distance <= 3) & (pixels[:, :, 3] > 0)
            yy, xx = np.nonzero(owned)
            x0, y0, x1, y1 = xx.min(), yy.min(), xx.max() + 1, yy.max() + 1
            cutout = pixels[y0:y1, x0:x1].copy()
            cutout[~owned[y0:y1, x0:x1]] = 0
            sprite = Image.fromarray(cutout)
            if max(sprite.size) > 448:
                raise ValueError(f"Batch 7 {name} exceeds its safe atlas slot")
            # Gate states share a vertical anchor; center each panel on the passage axis.
            top = (512 - (cy1 - cy0)) // 2 + y0 - cy0 if name.startswith("gate_") else (512 - sprite.height) // 2
            slot.paste(sprite, ((512 - sprite.width) // 2, top))
        else:
            x0, y0, x1, y1 = bounds
            cutout = cell.crop((max(0, x0 - 3), max(0, y0 - 3), min(cell.width, x1 + 3), min(cell.height, y1 + 3)))
            slot.paste(cutout, ((512 - cutout.width) // 2, (512 - cutout.height) // 2))
        slots[name] = slot
        atlas.paste(slot, (col * 512, row * 512))

    def padded_bounds(slot):
        x0, y0, x1, y1 = slot.getchannel("A").getbbox()
        return max(0, x0 - 3), max(0, y0 - 3), min(512, x1 + 3), min(512, y1 + 3)

    gate_bounds = [padded_bounds(slot) for name, slot in slots.items() if name.startswith("gate_")]
    if gate_bounds:
        gate_bounds = (min(b[0] for b in gate_bounds), min(b[1] for b in gate_bounds),
                       max(b[2] for b in gate_bounds), max(b[3] for b in gate_bounds))
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    for index, name in selected.items():
        x0, y0, x1, y1 = gate_bounds if name.startswith("gate_") else padded_bounds(slots[name])
        size = [1.82, 1.82 * (y1 - y0) / (x1 - x0)]
        pivot = [.5, .5]
        if name == "cliff_top": size, pivot = [2.0, 2.5], [.5, .62]
        if name.startswith("gate_"): size = [1.82 * (x1 - x0) / (y1 - y0), 1.82]
        manifest["sprites"][name] = {"sheet": stem, "region": [index % 4 * 512 + x0, index // 4 * 512 + y0, x1 - x0, y1 - y0],
                                      "pivot": pivot, "world_size": size, "rotation_degrees": 0}
        if name in {"ground_a", "ground_b", "cliff_top"}:
            fitted = morph_hex(slots[name].crop((x0, y0, x1, y1)), 370 if name == "cliff_top" else 296)
            key = name + "_fit"
            fitted.save(OUTPUT / (key + ".png"))
            manifest["sheets"][key].update(source_sha256=source_hash, sha256=hashlib.sha256((OUTPUT / (key + ".png")).read_bytes()).hexdigest())
    if gate_bounds:
        # Distance between lower panel centers in the two registered leaf states.
        middle = round((gate_bounds[1] + gate_bounds[3]) / 2)
        centers = []
        for name in ["gate_closed", "gate_open"]:
            bounds = slots[name].getchannel("A").crop((0, middle, 512, 512)).point(lambda a: 255 if a > 40 else 0).getbbox()
            centers.append(middle + (bounds[1] + bounds[3]) / 2)
        manifest["sprites"]["gate_open"]["slide_distance"] = (centers[1] - centers[0]) * 1.82 / (gate_bounds[3] - gate_bounds[1])
    atlas.save(atlas_path)
    sheet = manifest["sheets"][stem]
    sheet["sha256"] = hashlib.sha256(atlas_path.read_bytes()).hexdigest()
    sheet.setdefault("sprite_source_sha256", {}).update({name: source_hash for name in selected.values()})
    if not wall_only:
        manifest["notes"] = "Resource patches retain approved art. Batch 7 terrain, full-tile walls and registered gate layers use the updated source. South-facing actors rotate 180 degrees at draw time."
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("Prepared " + ", ".join(selected.values()) + "; other runtime cells and source art are unchanged.")


def main():
    if "--wall-only" in sys.argv:
        update_batch7(wall_only=True)
        return
    if "--batch-7" in sys.argv:
        update_batch7()
        return
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries, sheets = {}, {}
    for stem, columns, rows, names in SHEETS:
        if stem == "batch_07_terrain_and_connections":
            update_batch7()
            prepared = json.loads((OUTPUT / "atlas.json").read_text(encoding="utf-8"))
            sheets.update({key: value for key, value in prepared["sheets"].items() if key == stem or key.endswith("_fit")})
            entries.update({key: value for key, value in prepared["sprites"].items() if value["sheet"] == stem or key.endswith("_fit")})
            continue
        source = SOURCE / (stem + ".png")
        image = Image.open(source).convert("RGBA")
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        width, height = image.size
        sheets[stem] = {"file": stem + ".png", "size": [width, height],
                        "sha256": source_hash,
                        "source_sha256": source_hash}
        for index, name in enumerate(names.split()):
            col, row = index % columns, index // columns
            cell = (round(col * width / columns), round(row * height / rows),
                    round((col + 1) * width / columns), round((row + 1) * height / rows))
            # Analyze alpha only; exclude barely visible background haze from bounds.
            alpha = image.getchannel("A").crop(cell)
            bounds = alpha.point(lambda a: 255 if a >= 96 else 0).getbbox()
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
            if stem == "batch_01_characters":
                size = (size[0], size[0] * (y1 - y0) / (x1 - x0))
            if name.endswith("_wreck"): size = SIZES[name.removesuffix("_wreck")]
            if name.startswith("muzzle_") or name.startswith("flame_0"): pivot = [.02, .5]
            entries[name] = {"sheet": stem, "region": [x0, y0, x1 - x0, y1 - y0],
                             "pivot": pivot, "world_size": list(size),
                             "rotation_degrees": 180 if name in SOUTH or name.endswith("_wreck") else 0}
            if name in MUZZLES: entries[name]["muzzle_uv"] = list(MUZZLES[name])
        if not (OUTPUT / source.name).exists() or hashlib.sha256((OUTPUT / source.name).read_bytes()).hexdigest() != source_hash:
            shutil.copyfile(source, OUTPUT / source.name)
        settings = OUTPUT / (source.name + ".import")
        if settings.exists():
            settings.write_text(settings.read_text().replace("mipmaps/generate=false", "mipmaps/generate=true"))
    manifest = {"version": 1, "sheets": sheets, "sprites": entries,
                "notes": "Resource patches retain approved art. Aliens and vehicles face south; rotate 180 degrees at draw time. Gates use registered Batch 7 layers."}
    (OUTPUT / "atlas.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(entries)} regions; terrain isolated and fitted copies morphed. Sources unchanged.")


if __name__ == "__main__":
    main()
