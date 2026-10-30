extends RefCounted
## Small consistent vector pictograms. Keep gameplay commands in game_hud.gd.
static var cache: Dictionary = {}
const PATHS := {
	"board": "M14 3h6v18h-6 M3 12h12 m-4-4 4 4-4 4",
	"unload": "M10 3H4v18h6 M21 12H9 m4-4-4 4 4 4",
	"expedition": "M12 2v3 m0 14v3 M2 12h3 m14 0h3 M8 16l3-7 5-1-3 7z",
	"mining": "M4 6q8-5 16 2 M12 5 6 21 M4 6l-1 4 m17-2 1 4",
	"attack": "M12 2v5 m0 10v5 M2 12h5 m10 0h5 M8 8h8v8H8z",
	"defend": "M12 3l8 3v6q0 6-8 10-8-4-8-10V6z M8 12l3 3 5-6",
	"patrol": "M4 8h14l-4-4 M20 16H6l4 4 M4 8v6 m16 2v-6",
	"drill_order": "M8 3h8v5l-2 3 2 3-2 3-2 4-2-4-2-3 2-3-2-3z",
	"repair": "M15 3l-3 5 4 3 4-4q2 7-6 7L6 22l-4-4 8-8Q8 3 15 3z",
	"load": "M4 12h16v9H4z M12 2v12 m-4-4 4 4 4-4",
	"stock": "M4 12h16v9H4z M12 14V2 m-4 4 4-4 4 4",
	"home": "M2 11l10-8 10 8 M5 10v11h14V10 M10 21v-7h4v7",
	"escort": "M4 5h5v5H4z M3 14h7v7H3z M16 4v16 m-3-3 3 3 3-3",
	"recharge": "M13 2 5 14h6l-1 8 9-13h-7z",
	"reload_turret": "M19 8a8 8 0 1 0 0 9 M19 3v6h-6 M10 9h4v7h-4z",
	"auto_reload": "M19 8a8 8 0 1 0 0 9 M19 3v6h-6 M12 10v6 m-3-3h6",
	"repeater": "M9 9h6v6H9z M12 2v7 m0 6v7 M2 12h7 m6 0h7",
	"gate": "M3 4h4v17H3z M17 4h4v17h-4z M7 9h10v6H7",
	"gate_lock": "M5 10h14v12H5z M8 10V6a4 4 0 0 1 8 0v4 M12 14v4",
	"stop": "M5 5h14v14H5z",
	"destroy": "M4 6h16 M9 3h6 M6 6l1 15h10l1-15 M10 10v7 m4-7v7",
	"cancel_train": "M5 5l14 14 M19 5 5 19"
}
static func texture(key: String) -> Texture2D:
	if cache.has(key): return cache[key]
	var image := Image.new()
	var path: String = PATHS.get(key, PATHS.stop)
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#d5c498" stroke-width="1.7" stroke-linecap="square" stroke-linejoin="miter"/></svg>' % path)
	cache[key] = ImageTexture.create_from_image(image)
	return cache[key]
