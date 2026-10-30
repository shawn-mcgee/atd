"""Copy approved sheets unchanged and record atlas crops; requires Pillow.

Run from the repository root: python tools/prepare-sprites.py
No repainting, resampling, or background removal occurs. Corrections are runtime
metadata. Keep this script and the original sheets to reproduce the mapping.
"""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

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
    ("batch_08_items_and_effects", 4, 4, "hive_core material_crate methane_canister muzzle_00 muzzle_01 impact_kinetic impact_laser flame_00 flame_01 flame_02 repair_sparks_00 repair_sparks_01 smoke_00 smoke_01 alien_hit_00 alien_hit_01"),
]
SIZES = {"engineer": (.8, .9), "marine": (.8, 1.2), "flamer": (.9, 1.2),
         "runner": (.8, 1), "stalker": (1, 1.1), "brute": (1.3, 1.4),
         "scout": (1, 1.6), "jeep": (1.4, 2), "drill": (1.7, 2.2),
         "hive_core": (.48, .55), "wall_arm": (.95, .36),
         "turret_head": (.9, 1.2), "laser_turret_head": (.9, 1.2), "flame_turret_head": (.9, 1.2)}
MUZZLES = {"marine": (.50, .018), "flamer": (.61, .025), "turret_head": (.50, .018),
           "laser_turret_head": (.50, .018), "flame_turret_head": (.50, .025)}
SOUTH = {"runner", "stalker", "brute", "scout", "jeep", "drill"}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries, sheets = {}, {}
    for stem, columns, rows, names in SHEETS:
        source = SOURCE / (stem + ".png")
        image = Image.open(source).convert("RGBA")
        width, height = image.size
        sheets[stem] = {"file": stem + ".png", "size": [width, height],
                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        for index, name in enumerate(names.split()):
            if name.startswith("unused_"):  # Gate art is intentionally replaced in code.
                continue
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
            if name in {"marine", "flamer"}: pivot = [.5, .70]
            if name == "engineer": pivot = [.5, .60]
            if name.endswith("_head"): pivot = [.5, .70]
            if name == "platform":
                size = (1.82, 1.82 * (y1 - y0) / (x1 - x0))
                pivot = [.5, .45]
            if name.endswith("_wreck"): size = SIZES[name.removesuffix("_wreck")]
            if name.startswith("muzzle_") or name.startswith("flame_0"): pivot = [.02, .5]
            entries[name] = {"sheet": stem, "region": [x0, y0, x1 - x0, y1 - y0],
                             "pivot": pivot, "world_size": list(size),
                             "rotation_degrees": 180 if name in SOUTH or name.endswith("_wreck") else 0}
            if name in MUZZLES: entries[name]["muzzle_uv"] = list(MUZZLES[name])
        if not (OUTPUT / source.name).exists() or hashlib.sha256((OUTPUT / source.name).read_bytes()).hexdigest() != sheets[stem]["sha256"]:
            shutil.copyfile(source, OUTPUT / source.name)
        settings = OUTPUT / (source.name + ".import")
        if settings.exists():
            settings.write_text(settings.read_text().replace("mipmaps/generate=false", "mipmaps/generate=true"))
    manifest = {"version": 1, "sheets": sheets, "sprites": entries,
                "notes": "Original pixels unchanged. Aliens and vehicles face south; rotate 180 degrees at draw time. Gate is procedural."}
    (OUTPUT / "atlas.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(entries)} atlas regions from {len(sheets)} unchanged sheets.")


if __name__ == "__main__":
    main()
