class_name World
extends Node3D
## Builds the Hollowreach overworld: a lit KayKit-style village ringed by forest and
## rocky paths, with a dungeon entrance. Code-driven; keep it light for mobile GPUs.

const TEX_DIR: String = "res://textures/"
const MODEL_DIR: String = "res://models/"

const WORLD_RADIUS: float = 46.0
var village_center: Vector3 = Vector3(0, 0, 0)
var dungeon_pos: Vector3 = Vector3(0, 0, -36)

var npc_specs: Array = []
var enemy_spawns: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _mesh_cache: Dictionary = {}


func build() -> void:
	_rng.seed = 20260606
	_build_environment()
	_build_ground()
	_build_path()
	_build_boundary()
	_build_village()
	_scatter_trees()
	_scatter_rocks()
	_scatter_grass()
	_build_dungeon()
	_define_actors()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.80)
	sky_mat.ground_bottom_color = Color(0.32, 0.30, 0.26)
	sky_mat.ground_horizon_color = Color(0.74, 0.78, 0.76)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.1

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.74, 0.79, 0.82)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.3

	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -125, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 60, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.7, 0.78, 0.95)
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_RADIUS * 2.4, WORLD_RADIUS * 2.4)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	ground.mesh = plane
	ground.material_override = _ground_mat("grass.png", Color(0.55, 0.62, 0.38), 26.0)
	add_child(ground)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)


func _build_path() -> void:
	var path := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.2, dungeon_pos.distance_to(village_center) + 6.0)
	path.mesh = pm
	path.material_override = _ground_mat("dirt_ground.png", Color(0.5, 0.42, 0.3), 6.0)
	path.position = village_center.lerp(dungeon_pos, 0.5) + Vector3(0, 0.02, 0)
	add_child(path)


func _build_boundary() -> void:
	var n := 28
	for i in n:
		var ang := TAU * float(i) / float(n)
		var p := Vector3(cos(ang), 0, sin(ang)) * WORLD_RADIUS
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WORLD_RADIUS * 0.6, 6, 2)
		cs.shape = box
		wall.add_child(cs)
		wall.position = p + Vector3(0, 3, 0)
		wall.rotation.y = atan2(-p.x, -p.z)
		add_child(wall)


func _build_village() -> void:
	var ring := [
		{"id": "building_blacksmith_blue", "ang": 0.35, "r": 11.0},
		{"id": "building_tavern_blue", "ang": 1.25, "r": 12.0},
		{"id": "building_home_B_blue", "ang": 2.1, "r": 11.0},
		{"id": "building_market_blue", "ang": 3.1, "r": 12.5},
		{"id": "building_church_blue", "ang": 4.2, "r": 12.0},
		{"id": "building_home_B_blue", "ang": 5.2, "r": 11.0},
	]
	for spec: Dictionary in ring:
		var ang: float = spec["ang"]
		var r: float = spec["r"]
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var yrot := atan2(-pos.x, -pos.z)
		_place_solid(spec["id"], pos, 3.4, yrot, 2.3, 4.0)

	_place_solid("building_well_blue", Vector3(3.5, 0, 2.5), 2.6, 0.0, 1.1, 2.0)

	var fire := _place("log_large", Vector3(-3.0, 0, 1.5), 1.4, 0.0)
	var ember := OmniLight3D.new()
	ember.light_color = Color(1.0, 0.6, 0.25)
	ember.light_energy = 2.4
	ember.omni_range = 9.0
	ember.position = Vector3(-3.0, 1.2, 1.5)
	add_child(ember)
	_campfire_particles(Vector3(-3.0, 0.4, 1.5))


func _build_dungeon() -> void:
	var dark := MeshInstance3D.new()
	var dm := PlaneMesh.new()
	dm.size = Vector2(22, 20)
	dark.mesh = dm
	dark.material_override = _ground_mat("rock_cliff.png", Color(0.32, 0.3, 0.32), 7.0)
	dark.position = dungeon_pos + Vector3(0, 0.01, -2)
	add_child(dark)

	var arch := _place("arch_gate", dungeon_pos, 1.4, 0.0)
	arch.rotation.y = PI

	var void_quad := MeshInstance3D.new()
	var vq := QuadMesh.new()
	vq.size = Vector2(4.4, 4.6)
	void_quad.mesh = vq
	var vmat := StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.albedo_color = Color(0.02, 0.01, 0.04)
	void_quad.material_override = vmat
	void_quad.position = dungeon_pos + Vector3(0, 2.7, -0.5)
	add_child(void_quad)

	for side: float in [-1.0, 1.0]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(0.55, 0.85, 1.0)
		torch.light_energy = 3.0
		torch.omni_range = 8.0
		torch.position = dungeon_pos + Vector3(2.6 * side, 2.4, 0.2)
		add_child(torch)

	for i in 7:
		var gp := dungeon_pos + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-1, 7))
		_place("grave_B", gp, _rng.randf_range(1.1, 1.6), _rng.randf_range(0, TAU))
	for i in 6:
		var bp := dungeon_pos + Vector3(_rng.randf_range(-8, 8), 0.05, _rng.randf_range(0, 8))
		_place("bone_A", bp, _rng.randf_range(0.8, 1.3), _rng.randf_range(0, TAU))
	for side2: float in [-1.0, 1.0]:
		_place("banner_patternA_red", dungeon_pos + Vector3(3.4 * side2, 0, 0.4), 1.8, 0.0)


func _define_actors() -> void:
	npc_specs = [
		{
			"name": "Doran the Smith",
			"model": MODEL_DIR + "kk_Barbarian.glb",
			"pos": Vector3(cos(0.35) * 11.0, 0, sin(0.35) * 11.0) + Vector3(-2.0, 0, 1.0),
			"color": Color(0.9, 0.5, 0.2),
			"persona": "You are Doran, a nervous, big-hearted village blacksmith in the hamlet of Hollowreach. You dread the dungeon to the north and the skeletons that crawl out of it at night. You speak in short, anxious bursts, fidget with your hammer, and care about keeping the villagers safe. You forge blades but wish you never had to. Keep replies to 1-2 in-character sentences.",
		},
		{
			"name": "Sila the Hermit",
			"model": MODEL_DIR + "kk_Mage.glb",
			"pos": Vector3(cos(4.2) * 12.0, 0, sin(4.2) * 12.0) + Vector3(1.5, 0, -1.0),
			"color": Color(0.5, 0.4, 0.9),
			"persona": "You are Sila, a cryptic old hermit-mage who lives at the edge of Hollowreach. You speak in riddles, half-prophecies and metaphors about the Hollow beneath the dungeon. You are wise but never give a straight answer, often answering a question with a question. You hint that the dungeon's restlessness is tied to something older. Keep replies to 1-2 mysterious in-character sentences.",
		},
	]

	enemy_spawns = []
	var count := 5
	for i in count:
		var ang := TAU * float(i) / float(count) + 0.3
		var r := _rng.randf_range(4.5, 8.0)
		enemy_spawns.append(dungeon_pos + Vector3(cos(ang) * r, 0, sin(ang) * r + 2.0))


func _scatter_trees() -> void:
	var kinds := ["tree_blocks", "tree_blocks_dark", "tree_cone", "tree_cone_dark"]
	for id: String in kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _extract_mesh(id)
		var pts: Array[Transform3D] = []
		var tries := 0
		while pts.size() < 34 and tries < 400:
			tries += 1
			var ang := _rng.randf_range(0, TAU)
			var r := _rng.randf_range(20.0, WORLD_RADIUS - 3.0)
			var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
			if p.distance_to(dungeon_pos) < 11.0:
				continue
			var s := _rng.randf_range(2.2, 3.4)
			var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(Vector3(s, s, s)), p)
			pts.append(t)
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, pts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


func _scatter_rocks() -> void:
	for id: String in ["rock_largeA", "rock_largeC", "stone_largeB"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _extract_mesh(id)
		var pts: Array[Transform3D] = []
		var tries := 0
		while pts.size() < 16 and tries < 200:
			tries += 1
			var ang := _rng.randf_range(0, TAU)
			var r := _rng.randf_range(14.0, WORLD_RADIUS - 4.0)
			var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
			if p.length() < 9.0:
				continue
			var s := _rng.randf_range(1.4, 2.6)
			pts.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(Vector3(s, s, s)), p))
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, pts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _scatter_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _extract_mesh("Grass_1_A_Color1")
	var pts: Array[Transform3D] = []
	for i in 320:
		var ang := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(2.0, WORLD_RADIUS - 6.0)
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if p.distance_to(dungeon_pos) < 9.0:
			continue
		var s := _rng.randf_range(0.8, 1.5)
		pts.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(Vector3(s, s, s)), p))
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, pts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _campfire_particles(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 22
	p.lifetime = 1.4
	p.position = pos
	p.direction = Vector3(0, 1, 0)
	p.spread = 18.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.28
	p.color = Color(1.0, 0.55, 0.18)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mesh.material = mat
	p.mesh = mesh
	add_child(p)


func _place(id: String, pos: Vector3, scl: float, yrot: float) -> Node3D:
	var ps: PackedScene = load(MODEL_DIR + id + ".glb")
	var inst: Node3D = ps.instantiate()
	inst.position = pos
	inst.scale = Vector3(scl, scl, scl)
	inst.rotation.y = yrot
	add_child(inst)
	return inst


func _place_solid(id: String, pos: Vector3, scl: float, yrot: float, radius: float, height: float) -> void:
	_place(id, pos, scl, yrot)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	body.position = pos + Vector3(0, height * 0.5, 0)
	add_child(body)


func _extract_mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var ps: PackedScene = load(MODEL_DIR + id + ".glb")
	var inst: Node3D = ps.instantiate()
	var found: Mesh = _first_mesh(inst)
	_mesh_cache[id] = found
	inst.queue_free()
	return found


func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for c: Node in n.get_children():
		var r: Mesh = _first_mesh(c)
		if r != null:
			return r
	return null


func _ground_mat(tex_file: String, tint: Color, tiles: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex: Texture2D = load(TEX_DIR + tex_file)
	m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_scale = Vector3(tiles, tiles, 1)
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m
