class_name ProductionQueue
extends VBoxContainer

signal requested(order: Dictionary)
var world: WorldState
var target_id := 0
var signature := ""
var cards: Array = []

func refresh() -> void:
	if world == null or not world.structures.has(target_id):
		hide()
		if signature != "": clear()
		return
	var s: Dictionary = world.structures[target_id]
	visible = not s.operators.is_empty() or not s.kits.is_empty() or not s.upgrades.is_empty() or not s.vehicles.is_empty()
	var next_signature := str(target_id)
	for key in ["operators", "kits", "upgrades", "vehicles"]:
		for item in s[key]: next_signature += "%s%s%s%s" % [key, item.get("kind", "operator"), str(float(item.progress) > 0), str(item.get("done", false))]
	if next_signature != signature:
		clear(); signature = next_signature
		for key in ["operators", "kits", "upgrades", "vehicles"]:
			if s[key].is_empty(): continue
			var row := VBoxContainer.new(); add_child(row)
			var title := Label.new(); title.text = "%s  %d / %d" % ["PERSONNEL" if key == "operators" else "KITS" if key == "kits" else "VEHICLES" if key == "vehicles" else "RESEARCH", s[key].size(), world.cfg.personnel.operatorQueueLimit if key == "operators" else world.cfg.personnel.kitQueueLimit if key == "kits" else world.cfg.personnel.vehicleQueueLimit if key == "vehicles" else world.cfg.personnel.upgradeQueueLimit]
			title.add_theme_font_size_override("font_size", 10); row.add_child(title)
			var scroll := ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size.y = 48; scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; row.add_child(scroll)
			var strip := HBoxContainer.new(); strip.add_theme_constant_override("separation", 3); scroll.add_child(strip)
			for index in range(s[key].size()):
				var item: Dictionary = s[key][index]
				var card := QueueChip.new(); card.glyph = CommandSkin.icon(str(item.get("kind", "operator")))
				card.add_theme_constant_override("icon_max_width", 20); card.add_theme_font_size_override("font_size", 11)
				card.tooltip_text = "%s\nClick × to cancel. %s\nVehicle, kit and personnel orders are separate queues." % [str(item.get("kind", "operator")).capitalize(), "Full refund for this order: work has not started." if float(item.progress) == 0 else "No refund: work has started or finished."]
				card.pressed.connect(func(): requested.emit({"action": "cancel_operator" if key == "operators" else "cancel_kit" if key == "kits" else "cancel_vehicle" if key == "vehicles" else "cancel_upgrade", "target": target_id, "index": index}))
				strip.add_child(card); cards.append({"button": card, "key": key, "index": index})
	for entry in cards:
		entry.button.disabled = world.ended or not world.players[s.owner].alive
		var item: Dictionary = s[entry.key][entry.index]
		var seconds: float = world.cfg.personnel.anchorOperatorSeconds if s.kind == "anchor" else world.cfg.personnel.cradleOperatorSeconds
		if entry.key == "kits": seconds = float(world.cfg.personnel.kits[item.kind].seconds)
		if entry.key == "vehicles": seconds = float(world.cfg.units[item.kind].productionSeconds)
		if entry.key == "upgrades": seconds = float(world.cfg.upgrades.fabricatorArmor.engineerWorkSeconds)
		entry.button.progress_label = "READY" if item.get("done", false) else "%d%%" % mini(100, int(float(item.progress) / seconds * 100))
		entry.button.progress_ratio = float(item.progress) / seconds
		entry.button.queue_redraw()

func clear() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	cards.clear(); signature = ""
