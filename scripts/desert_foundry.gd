class_name DesertFoundryBuilder
extends Node3D
# DESERT FOUNDRY: a 96 x 96 sun-baked smelting and rail yard, built entirely in code.
# This script sits on a Node3D map root. It builds the whole map in _ready().
# Groups: Perimeter, CoolingGate, LoadingDock, CenterSmelter (SlagBridge, FoundryTrench),
# WestRail, EastKiln (FurnaceTanks, SlagShed), Connectors (NorthCross, SouthCross).

const MAP_NAME := "DESERT FOUNDRY"
const HALF := 48.0
const EMBED := 1.0   # ground-standing pieces sink this far into the dunes so no gaps show

const SPAWN_POINTS: Array[Vector2] = [
    Vector2(-22, -42), Vector2(-6, -44), Vector2(10, -44), Vector2(24, -42),
    Vector2(-22, 42), Vector2(-8, 43), Vector2(20, 42), Vector2(-6, 36),
    Vector2(-24, -2), Vector2(34, 4), Vector2(28, -14), Vector2(-22, -22),
    Vector2(22, 22), Vector2(-30, 30), Vector2(30, -34), Vector2(-30, -34),
]

const PATROL_WAYPOINTS: Array[Vector2] = [
    Vector2(-22, -30), Vector2(-34, -6), Vector2(-32, 12), Vector2(-22, 26),
    Vector2(-6, 30), Vector2(8, 30), Vector2(22, 26), Vector2(34, 8),
    Vector2(34, -4), Vector2(28, -14), Vector2(20, -24), Vector2(-20, -24),
    Vector2(0, -30), Vector2(0, 14), Vector2(6, -8), Vector2(-8, -8),
    Vector2(0, 22), Vector2(-10, 36), Vector2(10, 38), Vector2(-28, 38),
    Vector2(20, -8), Vector2(-30, -34),
]

var m_sand: StandardMaterial3D
var m_concrete: StandardMaterial3D
var m_rust: StandardMaterial3D
var m_steel: StandardMaterial3D
var m_hazard: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_teal: StandardMaterial3D

# Rolling dunes: about +/-0.6 m over the whole yard, never steeper than a few degrees.
static func ground(x: float, z: float) -> float:
    return 0.35 * sin(x * 0.055) * cos(z * 0.047) + 0.18 * sin((x + z) * 0.11) + 0.10 * cos(x * 0.13 - z * 0.09)

# Which named callout a world position is in (used for the live HUD location name).
static func get_callout_name(p: Vector3) -> String:
    var x := p.x
    var z := p.z
    if z <= -34.0:
        return "COOLING GATE"
    if z >= 34.0:
        return "LOADING DOCK"
    if x >= 22.0 and x <= 38.0 and z >= -21.0 and z <= -9.0:
        return "SLAG SHED"
    if x >= 18.0 and x <= 46.0 and z >= 4.0 and z <= 26.0:
        return "FURNACE TANKS"
    if absf(x) <= 14.0 and absf(z) <= 16.0:
        if absf(x) <= 12.5 and absf(z) <= 5.0:
            return "SLAG BRIDGE"
        return "FOUNDRY TRENCH"
    if z >= -26.0 and z <= -18.0:
        return "NORTH CROSS"
    if z >= 18.0 and z <= 26.0:
        return "SOUTH CROSS"
    if x < -18.0:
        return "WEST RAIL"
    if x > 18.0:
        return "EAST KILN"
    return ""

func _ready() -> void:
    _make_materials()
    _build_ground()
    _build_perimeter()
    _build_cooling_gate()
    _build_loading_dock()
    _build_center_smelter()
    _build_west_rail()
    _build_east_kiln()
    _build_connectors()

# ---------- helpers ----------
func _group(group_name: String) -> Node3D:
    var g := Node3D.new()
    g.name = group_name
    add_child(g)
    return g

func _sub(par: Node3D, sub_name: String) -> Node3D:
    var n := Node3D.new()
    n.name = sub_name
    par.add_child(n)
    return n

func _mat(c: Color, tex: Texture2D = null) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.95
    if tex != null:
        m.albedo_texture = tex
    return m

func _noise_tex(base: Color, spread: float) -> ImageTexture:
    var size := 128
    var img := Image.create(size, size, false, Image.FORMAT_RGB8)
    for y in size:
        for x in size:
            var k := 1.0 + randf_range(-spread, spread)
            img.set_pixel(x, y, Color(clampf(base.r * k, 0.0, 1.0), clampf(base.g * k, 0.0, 1.0), clampf(base.b * k, 0.0, 1.0)))
    return ImageTexture.create_from_image(img)

func _make_materials() -> void:
    m_sand = _mat(Color(0.80, 0.72, 0.58), _noise_tex(Color(0.80, 0.72, 0.58), 0.07))
    m_concrete = _mat(Color(0.74, 0.70, 0.64), _noise_tex(Color(0.74, 0.70, 0.64), 0.09))
    m_rust = _mat(Color(0.58, 0.30, 0.16))
    m_steel = _mat(Color(0.40, 0.42, 0.44))
    m_hazard = _mat(Color(0.94, 0.74, 0.12))
    m_wood = _mat(Color(0.62, 0.44, 0.24))
    m_teal = _mat(Color(0.22, 0.40, 0.40))

# Solid box at an absolute position (collision + mesh).
func _solid(par: Node3D, pos: Vector3, sz: Vector3, yaw: float, m: Material) -> void:
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = pos
    body.rotation.y = yaw
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = sz
    cs.shape = sh
    body.add_child(cs)
    var bm := BoxMesh.new()
    bm.size = sz
    bm.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = bm
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if maxf(sz.x, sz.z) >= 2.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    body.add_child(mi)
    par.add_child(body)

# Box standing on the dunes: h is its height above the ground at (x, z). Sinks EMBED into the ground.
func _gbox(par: Node3D, x: float, z: float, w: float, h: float, d: float, yaw: float, m: Material) -> void:
    var total := h + EMBED
    var y := ground(x, z) - EMBED + total * 0.5
    _solid(par, Vector3(x, y, z), Vector3(w, total, d), yaw, m)

func _tank(par: Node3D, x: float, z: float, r: float, h: float, m: Material) -> void:
    var total := h + EMBED
    var y := ground(x, z) - EMBED + total * 0.5
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = Vector3(x, y, z)
    var cs := CollisionShape3D.new()
    var sh := CylinderShape3D.new()
    sh.radius = r
    sh.height = total
    cs.shape = sh
    body.add_child(cs)
    var cm := CylinderMesh.new()
    cm.top_radius = r
    cm.bottom_radius = r
    cm.height = total
    cm.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = cm
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    body.add_child(mi)
    par.add_child(body)

# Walkable ramp between two points. Top surface passes through both ends.
func _ramp(par: Node3D, a: Vector2, ya: float, b: Vector2, yb: float, width: float, m: Material) -> void:
    var pa := Vector3(a.x, ya, a.y)
    var pb := Vector3(b.x, yb, b.y)
    var dir := pb - pa
    var length := dir.length()
    var fwd := dir / length
    var side := Vector3(-fwd.z, 0.0, fwd.x).normalized()
    var up := side.cross(fwd).normalized()
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    body.transform = Transform3D(Basis(fwd, up, side), (pa + pb) * 0.5 - up * 0.15)
    var sz := Vector3(length + 0.4, 0.3, width)
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = sz
    cs.shape = sh
    body.add_child(cs)
    var bm := BoxMesh.new()
    bm.size = sz
    bm.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = bm
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    body.add_child(mi)
    par.add_child(body)

# Open-ended cargo container: two side walls and a roof, open at both ends. Length runs along local X.
func _container(par: Node3D, x: float, z: float, yaw: float, m: Material) -> void:
    var L := 12.0
    var W := 2.4
    var H := 2.6
    var s := sin(yaw)
    var c := cos(yaw)
    for side in [-1.0, 1.0]:
        var lz: float = side * (W * 0.5 - 0.1)
        _gbox(par, x + lz * s, z + lz * c, L, H, 0.2, yaw, m)
    _solid(par, Vector3(x, ground(x, z) + H - 0.15, z), Vector3(L, 0.3, W), yaw, m)

func _crate_stack(par: Node3D, x: float, z: float) -> void:
    _gbox(par, x, z, 1.2, 1.2, 1.2, 0.1, m_wood)
    _solid(par, Vector3(x + 0.1, ground(x, z) + 1.8, z), Vector3(1.2, 1.2, 1.2), 0.3, m_wood)

# Flat painted marking on the ground (visual only, no collision).
func _flat(par: Node3D, x: float, z: float, w: float, d: float, yaw: float) -> void:
    var bm := BoxMesh.new()
    bm.size = Vector3(w, 0.03, d)
    bm.material = m_hazard
    var mi := MeshInstance3D.new()
    mi.mesh = bm
    mi.position = Vector3(x, ground(x, z) + 0.02, z)
    mi.rotation.y = yaw
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)

# ---------- ground ----------
func _gv(x: float, z: float) -> Vector3:
    return Vector3(x, ground(x, z), z)

func _build_ground() -> void:
    var n := 97
    var data := PackedFloat32Array()
    data.resize(n * n)
    for j in n:
        for i in n:
            data[j * n + i] = ground(-HALF + i, -HALF + j)
    var hm := HeightMapShape3D.new()
    hm.map_width = n
    hm.map_depth = n
    hm.map_data = data
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    var cs := CollisionShape3D.new()
    cs.shape = hm
    body.add_child(cs)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(m_sand)
    for j in n - 1:
        for i in n - 1:
            var x0 := -HALF + i
            var z0 := -HALF + j
            var a := _gv(x0, z0)
            var b := _gv(x0 + 1.0, z0)
            var c := _gv(x0 + 1.0, z0 + 1.0)
            var d := _gv(x0, z0 + 1.0)
            for v in [a, b, c, a, c, d]:
                st.set_uv(Vector2(v.x, v.z) * 0.2)
                st.add_vertex(v)
    st.generate_normals()
    st.index()
    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    body.add_child(mi)
    add_child(body)

# ---------- perimeter (6.5 m walls) ----------
func _build_perimeter() -> void:
    var g := _group("Perimeter")
    _gbox(g, 0.0, -48.5, 98.0, 6.5, 1.0, 0.0, m_concrete)
    _gbox(g, 0.0, 48.5, 98.0, 6.5, 1.0, 0.0, m_concrete)
    _gbox(g, -48.5, 0.0, 1.0, 6.5, 98.0, 0.0, m_concrete)
    _gbox(g, 48.5, 0.0, 1.0, 6.5, 98.0, 0.0, m_concrete)

# ---------- COOLING GATE (north spawn base, z -46 to -34) ----------
func _build_cooling_gate() -> void:
    var g := _group("CoolingGate")
    _gbox(g, 0.0, -41.0, 4.0, 3.2, 3.0, 0.0, m_concrete)     # guard shack 4 x 3 x 3.2
    for p in [Vector3(-14, -36, 0.0), Vector3(14, -36, 0.0), Vector3(-26, -38, 0.3),
              Vector3(26, -38, -0.3), Vector3(-8, -30, 0.0), Vector3(8, -30, 0.0)]:
        _gbox(g, p.x, p.y, 4.0, 1.1, 0.8, p.z, m_concrete)  # jersey barriers 1.1 m high
    _crate_stack(g, -24.0, -43.0)
    _crate_stack(g, 22.0, -43.0)
    _gbox(g, -4.0, -46.0, 1.2, 1.2, 1.2, 0.2, m_wood)

# ---------- LOADING DOCK (south spawn base, z +34 to +46) ----------
func _build_loading_dock() -> void:
    var g := _group("LoadingDock")
    for px in [-11.5, 11.5]:
        for pz in [35.0, 43.5]:
            _gbox(g, px, pz, 0.5, 4.2, 0.5, 0.0, m_steel)
    _solid(g, Vector3(0.0, ground(0.0, 39.0) + 4.2, 39.0), Vector3(24.0, 0.4, 10.0), 0.0, m_steel)  # covered bay
    for i in 6:
        _flat(g, -9.0 + i * 3.6, 36.0, 1.6, 0.25, 0.8)     # yellow hazard stripes
    _gbox(g, 0.0, 41.0, 6.0, 0.8, 3.0, 0.0, m_steel)     # flatbed trailer deck, 0.8 m high
    _ramp(g, Vector2(0.0, 37.0), ground(0.0, 37.0), Vector2(0.0, 39.5), ground(0.0, 41.0) + 0.8, 3.0, m_steel)
    for c in [Vector2(-20, 36), Vector2(20, 36), Vector2(0, 45)]:
        _gbox(g, c.x, c.y, 1.2, 1.2, 1.2, 0.2, m_wood)
        _gbox(g, c.x + 1.3, c.y + 0.2, 1.2, 1.2, 1.2, -0.3, m_wood)
        _gbox(g, c.x + 0.5, c.y + 1.3, 1.2, 1.2, 1.2, 0.5, m_wood)

# ---------- CENTER SMELTER: SLAG BRIDGE and FOUNDRY TRENCH ----------
func _build_center_smelter() -> void:
    var g := _group("CenterSmelter")
    var sb := _sub(g, "SlagBridge")
    var gy0 := ground(0.0, 0.0)
    var top := gy0 + 1.5
    _solid(sb, Vector3(0.0, gy0 - 0.25, 0.0), Vector3(12.0, 3.5, 10.0), 0.0, m_concrete)  # 12 x 10 platform, 1.5 m high
    _solid(sb, Vector3(0.0, top - 0.05, 0.0), Vector3(12.0, 0.1, 10.0), 0.0, m_steel)       # steel top plate
    _ramp(sb, Vector2(-12.5, 0.0), ground(-12.5, 0.0), Vector2(-6.0, 0.0), top, 4.5, m_concrete)  # West ramp, 4.5 m wide
    _ramp(sb, Vector2(12.5, 0.0), ground(12.5, 0.0), Vector2(6.0, 0.0), top, 4.5, m_concrete)     # East ramp
    _solid(sb, Vector3(0.0, top + 0.55, -4.0), Vector3(3.0, 1.1, 0.8), 0.0, m_concrete)           # head-glitch block, North edge
    _solid(sb, Vector3(0.0, top + 0.55, 4.0), Vector3(3.0, 1.1, 0.8), 0.0, m_concrete)            # head-glitch block, South edge
    var ft := _sub(g, "FoundryTrench")
    _gbox(ft, -12.0, -12.0, 4.0, 0.95, 0.6, 0.7, m_hazard)   # hazard barriers, 0.95 m
    _gbox(ft, 12.0, 12.0, 4.0, 0.95, 0.6, 0.7, m_hazard)
    _gbox(ft, -11.0, 11.0, 2.5, 1.1, 1.2, 0.0, m_concrete)   # low concrete cover
    _gbox(ft, 11.0, -11.0, 2.5, 1.1, 1.2, 0.0, m_concrete)

# ---------- WEST RAIL ----------
func _build_west_rail() -> void:
    var g := _group("WestRail")
    _container(g, -34.0, -12.0, 0.0, m_rust)
    _container(g, -27.0, 6.0, 0.15, m_rust)
    for p in [Vector2(-40, -20), Vector2(-40, 20), Vector2(-26, -20), Vector2(-26, 20)]:
        _gbox(g, p.x, p.y, 1.0, 7.0, 1.0, 0.0, m_steel)       # gantry pillars 1 x 1 x 7 m
    _solid(g, Vector3(-33.0, ground(-33.0, -20.0) + 7.0, -20.0), Vector3(14.0, 0.8, 1.0), 0.0, m_hazard)  # gantry beam at 7 m
    _solid(g, Vector3(-33.0, ground(-33.0, 20.0) + 7.0, 20.0), Vector3(14.0, 0.8, 1.0), 0.0, m_hazard)
    _crate_stack(g, -22.0, -6.0)
    _crate_stack(g, -30.0, 24.0)

# ---------- EAST KILN ----------
func _build_east_kiln() -> void:
    var g := _group("EastKiln")
    var ft := _sub(g, "FurnaceTanks")
    for p in [Vector2(24.0, 12.0), Vector2(28.6, 12.0), Vector2(26.3, 16.5)]:
        _tank(ft, p.x, p.y, 2.2, 4.2, m_teal)                 # tight cylindrical tanks, radius 2.2, height 4.2
    _gbox(ft, 26.5, 8.5, 8.0, 1.1, 0.6, 0.0, m_concrete)      # retaining walls
    _gbox(ft, 26.5, 20.5, 8.0, 1.1, 0.6, 0.0, m_concrete)
    _gbox(ft, 33.0, 14.0, 1.2, 1.2, 1.2, 0.2, m_hazard)       # hazard crates
    _gbox(ft, 33.0, 22.0, 1.2, 1.2, 1.2, -0.2, m_hazard)
    _build_shed(_sub(g, "SlagShed"))

# SLAG SHED: 16 x 12 footprint centred on (30, -15), 3.6 m walls, doorways 3.2 m wide,
# and a 1.1 m sill window on the west wall facing SLAG BRIDGE. No roof (open interior).
func _build_shed(par: Node3D) -> void:
    var m := m_concrete
    _gbox(par, 30.0, -21.2, 16.4, 3.6, 0.4, 0.0, m)          # north wall (solid)
    _gbox(par, 38.0, -18.8, 0.4, 3.6, 4.4, 0.0, m)           # east wall, north piece
    _gbox(par, 38.0, -11.2, 0.4, 3.6, 4.4, 0.0, m)           # east wall, south piece (doorway between)
    _gbox(par, 22.0, -19.5, 0.4, 3.6, 3.0, 0.0, m)           # west wall, north piece
    _gbox(par, 22.0, -10.5, 0.4, 3.6, 3.0, 0.0, m)           # west wall, south piece
    _gbox(par, 22.0, -15.0, 0.4, 1.1, 6.0, 0.0, m)           # window sill, 1.1 m high
    _solid(par, Vector3(22.0, ground(22.0, -15.0) + 3.2, -15.0), Vector3(0.4, 0.8, 6.0), 0.0, m)  # window lintel
    _gbox(par, 25.2, -9.0, 6.4, 3.6, 0.4, 0.0, m)            # south wall, west piece
    _gbox(par, 34.8, -9.0, 6.4, 3.6, 0.4, 0.0, m)            # south wall, east piece (doorway between)
    _gbox(par, 26.0, -18.0, 1.2, 1.2, 1.2, 0.2, m_wood)      # interior crate cover
    _gbox(par, 34.0, -11.6, 1.2, 1.2, 1.2, -0.2, m_wood)
    _gbox(par, 33.0, -18.4, 1.2, 1.2, 1.2, 0.5, m_wood)

# ---------- CONNECTORS: NORTH CROSS (z -22) and SOUTH CROSS (z +22) ----------
func _build_connectors() -> void:
    var g := _group("Connectors")
    var n := _sub(g, "NorthCross")
    _container(n, -10.0, -23.5, 0.3, m_rust)
    _container(n, 10.0, -23.5, -0.3, m_rust)
    _gbox(n, -18.0, -22.0, 3.0, 1.1, 0.8, 0.0, m_concrete)   # chest-high cover
    _gbox(n, 0.0, -19.5, 3.0, 1.1, 0.8, 0.0, m_concrete)
    var s := _sub(g, "SouthCross")
    _container(s, -10.0, 23.5, -0.3, m_rust)
    _container(s, 10.0, 23.5, 0.3, m_rust)
    _gbox(s, -18.0, 22.0, 3.0, 1.1, 0.8, 0.0, m_concrete)
    _gbox(s, 0.0, 19.5, 3.0, 1.1, 0.8, 0.0, m_concrete)
    _gbox(s, 18.0, 22.0, 3.0, 1.1, 0.8, 0.0, m_concrete)
