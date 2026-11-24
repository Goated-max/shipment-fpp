class_name ArenaBuilder
extends RefCounted

# Shipment / Firing Range style arena (65x65), built entirely in code.

static func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    return m

static func _floor_mat() -> StandardMaterial3D:
    var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
    img.fill(Color(0.56, 0.54, 0.49))
    for i in 128:
        for w in 2:
            img.set_pixel(i, w, Color(0.92, 0.92, 0.92))
            img.set_pixel(i, 127 - w, Color(0.92, 0.92, 0.92))
            img.set_pixel(w, i, Color(0.92, 0.92, 0.92))
            img.set_pixel(127 - w, i, Color(0.92, 0.92, 0.92))
            if i % 16 < 10:
                img.set_pixel(i, 63 + w, Color(0.95, 0.76, 0.19))
                img.set_pixel(63 + w, i, Color(0.95, 0.76, 0.19))
    img.generate_mipmaps()
    var m := _mat(Color.WHITE)
    m.albedo_texture = ImageTexture.create_from_image(img)
    m.uv1_scale = Vector3(8, 8, 1)
    return m

static func _b(p: Node3D, x: float, z: float, w: float, h: float, d: float, rot: float, m: Material, y0 := 0.0) -> void:
    var sb := StaticBody3D.new()
    sb.collision_layer = 1
    sb.collision_mask = 0
    sb.position = Vector3(x, y0 + h * 0.5, z)
    sb.rotation.y = rot
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = Vector3(w, h, d)
    cs.shape = sh
    sb.add_child(cs)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(w, h, d)
    mi.mesh = bm
    mi.material_override = m
    # Only large structures cast shadows (cheaper shadow pass).
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if maxf(w, d) >= 2.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    sb.add_child(mi)
    p.add_child(sb)

# Open-ended container: two side walls + roof, run and slide straight through.
static func _open_container(p: Node3D, x: float, z: float, rot: float, m: Material) -> void:
    var c := cos(rot)
    var s := sin(rot)
    var L := 12.0
    var W := 2.4
    var H := 2.6
    for side in [1.0, -1.0]:
        var lz: float = side * (W * 0.5 - 0.1)
        _b(p, x + lz * s, z + lz * c, L, H, 0.2, rot, m)
    _b(p, x, z, L, 0.3, W, rot, m, H - 0.3)

# Ramp from height 0 (local -x end) to H (local +x end), approximated by a tilted slab.
static func _ramp(p: Node3D, x: float, z: float, rot: float, L: float, W: float, H: float, m: Material) -> void:
    var sb := StaticBody3D.new()
    sb.collision_layer = 1
    sb.collision_mask = 0
    sb.position = Vector3(x, 0.0, z)
    sb.rotation.y = rot
    var ang := atan2(H, L)
    var ln := sqrt(L * L + H * H)
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = Vector3(ln, 0.3, W)
    cs.shape = sh
    cs.rotation.z = ang
    cs.position.y = H * 0.5 - 0.15
    sb.add_child(cs)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(ln, 0.3, W)
    mi.mesh = bm
    mi.material_override = m
    mi.rotation.z = ang
    mi.position.y = H * 0.5 - 0.15
    sb.add_child(mi)
    p.add_child(sb)

static func build(p: Node3D) -> void:
    var wall := _mat(Color(0.72, 0.7, 0.66))
    var conc := _mat(Color(0.73, 0.71, 0.66))
    var wood := _mat(Color(0.65, 0.45, 0.23))
    var haz := _mat(Color(0.95, 0.76, 0.19))
    var red := _mat(Color(0.75, 0.22, 0.17))
    var blue := _mat(Color(0.12, 0.44, 0.82))
    var yel := _mat(Color(0.91, 0.7, 0.1))
    # floor (visual plane + thick collider)
    var fb := StaticBody3D.new()
    fb.collision_layer = 1
    fb.collision_mask = 0
    var fc := CollisionShape3D.new()
    var fs := BoxShape3D.new()
    fs.size = Vector3(65, 1, 65)
    fc.shape = fs
    fc.position.y = -0.5
    fb.add_child(fc)
    var pm := PlaneMesh.new()
    pm.size = Vector2(65, 65)
    var fm := MeshInstance3D.new()
    fm.mesh = pm
    fm.material_override = _floor_mat()
    fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    fb.add_child(fm)
    p.add_child(fb)
    # outer walls
    _b(p, 0, -33, 66, 6, 1, 0, wall)
    _b(p, 0, 33, 66, 6, 1, 0, wall)
    _b(p, -33, 0, 1, 6, 66, 0, wall)
    _b(p, 33, 0, 1, 6, 66, 0, wall)
    # central platform + ramps + head-glitch cover
    _b(p, 0, 0, 10, 1.2, 10, 0, conc)
    _ramp(p, 8, 0, PI, 6, 4, 1.2, haz)
    _ramp(p, -8, 0, 0, 6, 4, 1.2, haz)
    _b(p, 0, -3, 3, 1.1, 0.8, 0, conc, 1.2)
    _b(p, 0, 3, 3, 1.1, 0.8, 0, conc, 1.2)
    # open-ended containers (run and slide through)
    _open_container(p, -14, -14, 0, red)
    _open_container(p, 14, 14, 0, blue)
    _open_container(p, 14, -14, PI / 2, yel)
    _open_container(p, -14, 14, PI / 2, red)
    # angled + closed containers
    _b(p, -24, 2, 12, 2.6, 2.4, 0.55, yel)
    _b(p, 24, -2, 12, 2.6, 2.4, 0.55, red)
    _b(p, 0, -23, 12, 2.6, 2.4, 0, blue)
    _b(p, 0, 23, 12, 2.6, 2.4, 0, yel)
    # flank corridor walls
    _b(p, -28.5, -12, 0.8, 3, 14, 0, wall)
    _b(p, 28.5, 12, 0.8, 3, 14, 0, wall)
    # chest-high concrete blocks + hazard barriers
    for a in [[-10, 6, 0.0], [10, -6, 0.0], [-4, -19, 0.2], [4, 19, 0.2], [-18, 24, PI / 2], [18, -24, PI / 2]]:
        _b(p, a[0], a[1], 3, 1.1, 1, a[2], conc)
    _b(p, -4, 14, 3, 0.9, 0.6, 0, haz)
    _b(p, 4, 14, 3, 0.9, 0.6, 0, haz)
    # wooden crates
    for a in [[-5, -12, 0.3], [-6.4, -12.3, 0.0], [6, 10, 0.0], [7.3, 10.3, 0.2], [22, 12, 0.4], [-22, -8, 0.0], [-22, -9.3, 0.3], [10, -26, 0.0], [-10, 26, 0.5], [26, -14, 0.0]]:
        _b(p, a[0], a[1], 1.2, 1.2, 1.2, a[2], wood)
    _b(p, -5.7, -12.1, 1.2, 1.2, 1.2, 0.1, wood, 1.2)
