extends SceneTree
## Renders the card pictures (a field or a piece on a plot, like a diorama)
## into phone/art/*.png. The TV and the phone page both use them.
##     xvfb-run -a godot --rendering-driver vulkan --path . --script tools/card_art.gd

const SIZE := 512
const ITEMS := ["timber", "clay", "wool", "grain", "ore", "road", "hamlet", "town", "festival"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://phone/art")
	for item in ITEMS:
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE, SIZE)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_8X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var scene := _scene(item)
		vp.add_child(scene)
		for _f in 12:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://phone/art/%s.png" % item))
		print("art ", item)
		vp.queue_free()
	quit()


func _scene(item: String) -> Node3D:
	var root3d := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.88
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfd8e6")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-35), 0)
	root3d.add_child(sun)
	var mesh := MeshInstance3D.new()
	mesh.material_override = mat
	root3d.add_child(mesh)
	if item in Rules.RESOURCES:
		var built := Art.field(item, Vector2.ZERO, 4242 + Rules.RESOURCES.find(item), -0.5)
		mesh.mesh = built.mesh
		for extra in built.extras:
			if not extra.has_meta("water"):
				extra.material_override = mat
				root3d.add_child(extra)
	else:
		mesh.mesh = Art.plot(77)
		var piece := MeshInstance3D.new()
		piece.material_override = mat
		var color := Color(Rules.COLORS[0])
		match item:
			"road":
				piece.mesh = Art.road(color, 2.2)
				piece.position = Vector3(0, Art.GROUND, 0.1)
				piece.rotation.y = 0.5
			"hamlet":
				piece.mesh = Art.hamlet(color)
				piece.scale = Vector3.ONE * 2.6
				piece.position = Vector3(0, Art.GROUND, 0)
			"town":
				piece.mesh = Art.town(color)
				piece.scale = Vector3.ONE * 2.2
				piece.position = Vector3(0, Art.GROUND, 0.1)
			"festival":
				piece.mesh = Art.festival()
				piece.scale = Vector3.ONE * 1.5
				piece.position = Vector3(0, Art.GROUND, 0)
		root3d.add_child(piece)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	cam.position = Vector3(0, 6.5, 6.5)
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 7.4, 6.2), Vector3(0, 0.45, 0), Vector3.UP)
	return root3d
