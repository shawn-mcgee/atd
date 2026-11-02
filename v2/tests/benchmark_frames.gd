extends SceneTree
## Rendered CPU/viewport probe. Time never enters simulation decisions.
class ProfileGround:
	extends "res://view/visibility_ground.gd"
	var elapsed := 0
	func refresh(game, observers):
		var t := Time.get_ticks_usec()
		super.refresh(game, observers)
		elapsed += Time.get_ticks_usec()-t
class ProfileOverlay:
	extends "res://view/veil_overlay.gd"
	var elapsed := 0
	func refresh(game, owner, selected, observers=[]):
		var t := Time.get_ticks_usec()
		super.refresh(game, owner, selected, observers)
		elapsed += Time.get_ticks_usec()-t
class ProfileView:
	extends "res://view/prototype.gd"
	var sync_us := 0
	var orders_us := 0
	var hud_us := 0
	func _sync_meshes():
		var t := Time.get_ticks_usec()
		super._sync_meshes()
		sync_us += Time.get_ticks_usec() - t
	func _sync_orders(game):
		var t := Time.get_ticks_usec()
		super._sync_orders(game)
		orders_us += Time.get_ticks_usec() - t
	func _refresh_hud():
		var t := Time.get_ticks_usec()
		super._refresh_hud()
		hud_us += Time.get_ticks_usec() - t
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1280, 800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var view = ProfileView.new()
	root.add_child(view)
	view.set_process(false)
	view.remove_child(view.visibility_ground); view.visibility_ground.free()
	view.visibility_ground = ProfileGround.new(); view.add_child(view.visibility_ground)
	view.remove_child(view.veil_overlay); view.veil_overlay.free()
	view.veil_overlay = ProfileOverlay.new(); view.add_child(view.veil_overlay)
	view._local()
	view.selected.assign([1])
	for i in 30: await process_frame
	for tick in 600: view.session.advance()
	view.session.set_local_control("both")
	view._sync_meshes()
	for mode in ["paused", "running"]:
		view.visibility_ground.elapsed = 0; view.veil_overlay.elapsed = 0
		view.sync_us = 0; view.orders_us = 0; view.hud_us = 0
		var samples: Array = []
		var intervals: Array = []
		var cpu_render := 0.0; var gpu_render := 0.0
		var last_frame := Time.get_ticks_usec()
		var ticks := int(view.session.rollback.simulation.state.tick)
		for i in 120:
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(now - last_frame); last_frame = now
			cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			gpu_render += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			var t := Time.get_ticks_usec()
			view._process(0.0 if mode == "paused" else 1.0 / 60)
			samples.append(Time.get_ticks_usec()-t)
		var total := 0
		for value in samples: total += int(value)
		samples.sort()
		intervals.sort()
		print("ATD_FRAME_BENCHMARK " + JSON.stringify({"mode":mode,"wall_p95_us":intervals[113],"render_cpu_ms":cpu_render/120,"render_gpu_ms":gpu_render/120,"mean_us":total/120,"p95_us":samples[113],"max_us":samples[-1],"sync_us":view.sync_us/120,"orders_us":view.orders_us/120,"hud_us":view.hud_us/120,"ground_us":view.visibility_ground.elapsed/120,"overlay_us":view.veil_overlay.elapsed/120,"ticks":int(view.session.rollback.simulation.state.tick)-ticks,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}))
	quit()
