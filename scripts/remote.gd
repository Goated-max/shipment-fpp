class_name RemotePlayer
extends Node3D
# A networked opponent: simple figure plus name/kill label, smoothed toward the last received state.

var pid := 0
var sliding := false
var alive := true
var target := Vector3.ZERO
var tyaw := 0.0
var tpitch := 0.0
var head: Node3D

func setup(col: Color) -> void:
    var body := _mat(col)
    var dark := _mat(col.darkened(0.45))
    var skin := _mat(Color(0.82, 0.62, 0.48))
    var gun := _mat(Color(0.09, 0.1, 0.11))
    _box(self, Vector3(0.44, 0.56, 0.26), Vector3(0, 1.15, 0), body)
    _box(self, Vector3(0.38, 0.2, 0.24), Vector3(0, 0.8, 0), dark)
    for sgn in [-1.0, 1.0]:
        _box(self, Vector3(0.16, 0.72, 0.17), Vector3(0.1 * sgn, 0.36, 0), body)
        _box(self, Vector3(0.12, 0.5, 0.13), Vector3(0.29 * sgn, 1.13, 0), body)
    _box(self, Vector3(0.07, 0.07, 0.6), Vector3(0.22, 1.1, -0.35), gun)
    head = Node3D.new()
    head.position = Vector3(0, 1.62, 0)
    add_child(head)
    _box(head, Vector3(0.25, 0.27, 0.25), Vector3.ZERO, skin)
    _box(head, Vector3(0.27, 0.12, 0.27), Vector3(0, 0.12, 0), dark)
    _box(head, Vector3(0.22, 0.06, 0.04), Vector3(0, 0.02, -0.13), _mat(Color(0.9, 0.2, 0.15)))


func snap(p: Vector3) -> void:
    global_position = p
    target = p

func set_target(p: Vector3, y: float, pt: float, a: bool, dead: bool, nm: String, k: int, sl := false) -> void:
    target = p
    tyaw = y
    tpitch = pt
    alive = not dead
    visible = alive
    sliding = sl

func _process(dt: float) -> void:
    var k := 1.0 - exp(-14.0 * dt)
    if global_position.distance_to(target) > 6.0:
        global_position = target
    else:
        global_position = global_position.lerp(target, k)
    rotation.y = lerp_angle(rotation.y, tyaw, k)
    rotation.x = lerpf(rotation.x, -1.1 if sliding else 0.0, k)
    head.rotation.x = lerpf(head.rotation.x, tpitch, k)

func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    return m

func _box(par: Node3D, sz: Vector3, pos: Vector3, m: Material) -> void:
    var mi := MeshInstance3D.new()
    var b := BoxMesh.new()
    b.size = sz
    mi.mesh = b
    mi.material_override = m
    mi.position = pos
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)
