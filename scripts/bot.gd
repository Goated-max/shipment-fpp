class_name Bot
extends CharacterBody3D

# Behaviour profiles. close/far: strafe distances, engage: range to start shooting,
# speed: chase speed, strafe: circling speed, rate/burst: fire cadence, spread: accuracy scale.
const ROLES := {
    "rusher": {"name": "RUSHER", "close": 3.5, "far": 7.0, "engage": 14.0, "speed": 4.4, "strafe": 2.9, "rate": 0.11, "burst": 6, "spread": 1.3},
    "strafer": {"name": "STRAFER", "close": 13.0, "far": 21.0, "engage": 26.0, "speed": 3.0, "strafe": 2.0, "rate": 0.2, "burst": 3, "spread": 0.8},
    "soldier": {"name": "SOLDIER", "close": 9.0, "far": 17.0, "engage": 22.0, "speed": 3.6, "strafe": 2.3, "rate": 0.16, "burst": 4, "spread": 1.0},
}
var role: Dictionary = ROLES["soldier"]
var role_name := "SOLDIER"

var main: Main
var hp := 96.0
var alive := false
var state := 0          # 0 patrol, 1 chase, 2 strafe + shoot
var see := false
var lt := 0.0
var react := 0.0
var cd := 0.0
var n := 0
var lost := 0.0
var last := Vector2.ZERO
var sd := 1.0
var st := 1.0
var ph := 0.0
var aim := 0.0
var sk := 0.0
var sx := 0.0
var sz := 0.0
var yaw := 0.0
var dead_t := 0.0
var tgt := Vector2.ZERO
var model: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var muzzle: Marker3D

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    floor_snap_length = 0.35
    var cs := CollisionShape3D.new()
    var sh := CapsuleShape3D.new()
    sh.radius = 0.4
    sh.height = 1.8
    cs.shape = sh
    cs.position.y = 0.9
    add_child(cs)
    model = Node3D.new()
    add_child(model)
    var skin := _mat(Color(0.82, 0.62, 0.48))
    var oliv := _mat(Color(0.29, 0.36, 0.16))
    var dark := _mat(Color(0.18, 0.23, 0.1))
    var gunm := _mat(Color(0.09, 0.1, 0.11))
    var vest := _mat(Color(0.12, 0.14, 0.17))
    var visor := _mat(Color(0.9, 0.2, 0.15))
    _part(model, Vector3(0.44, 0.56, 0.26), Vector3(0, 1.15, 0), oliv, true)
    _part(model, Vector3(0.46, 0.34, 0.3), Vector3(0, 1.2, 0), vest, false)
    _part(model, Vector3(0.38, 0.2, 0.24), Vector3(0, 0.8, 0), dark, true)
    _part(model, Vector3(0.25, 0.27, 0.25), Vector3(0, 1.62, 0), skin, true)
    _part(model, Vector3(0.27, 0.12, 0.27), Vector3(0, 1.75, 0), dark, false)
    _part(model, Vector3(0.22, 0.06, 0.04), Vector3(0, 1.64, -0.13), visor, false)
    for sgn in [-1.0, 1.0]:
        var lp := Node3D.new()
        lp.position = Vector3(0.1 * sgn, 0.72, 0)
        model.add_child(lp)
        _part(lp, Vector3(0.16, 0.72, 0.17), Vector3(0, -0.36, 0), oliv, true)
        _part(lp, Vector3(0.18, 0.12, 0.26), Vector3(0, -0.66, -0.03), gunm, false)
        legs.append(lp)
        var ap := Node3D.new()
        ap.position = Vector3(0.29 * sgn, 1.38, 0)
        model.add_child(ap)
        _part(ap, Vector3(0.12, 0.5, 0.13), Vector3(0, -0.24, 0), oliv, true)
        arms.append(ap)
    # rifle held by the right arm (arms[1])
    _part(arms[1], Vector3(0.07, 0.5, 0.09), Vector3(0, -0.55, 0), gunm, false)
    muzzle = Marker3D.new()
    muzzle.position = Vector3(0, -0.82, 0)
    arms[1].add_child(muzzle)

func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    return m

func _part(par: Node3D, sz: Vector3, pos: Vector3, m: Material, shadow: bool) -> void:
    var mi := MeshInstance3D.new()
    var b := BoxMesh.new()
    b.size = sz
    mi.mesh = b
    mi.material_override = m
    mi.position = pos
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)

func spawn(s: Vector2) -> void:
    var y: float = main.ground_height(s.x, s.y)
    global_position = Vector3(s.x, y + 0.05, s.y)
    velocity = Vector3.ZERO
    hp = 96.0
    alive = true
    dead_t = 0.0
    visible = true
    model.rotation = Vector3.ZERO
    state = 0
    see = false
    lost = 0.0
    last = s
    react = 0.5
    cd = 1.0
    _pick_wp()

func _pick_wp() -> void:
    var tries := 0
    while tries < 6:
        tries += 1
        tgt = main.active_patrol[randi() % main.active_patrol.size()]
        if tgt.distance_to(Vector2(global_position.x, global_position.z)) > 8.0:
            return

func alert() -> void:
    var pp := main.player.global_position
    last = Vector2(pp.x, pp.z)
    lost = 0.0
    if state == 0:
        state = 1

func die() -> void:
    alive = false
    dead_t = 0.0
    velocity = Vector3.ZERO

func _physics_process(dt: float) -> void:
    if not alive:
        dead_t += dt
        model.rotation.x = -1.5 * minf(1.0, dead_t * 3.0)
        if dead_t > 1.4:
            visible = false
        if dead_t > 3.5:
            spawn(main.spawn_point(self))
        return
    var pl := main.player
    var pp := pl.global_position
    var p := global_position
    var dv := Vector2(pp.x - p.x, pp.z - p.z)
    var d := maxf(dv.length(), 0.001)
    # line of sight, re-checked about 5x per second
    lt -= dt
    if lt <= 0.0:
        lt = 0.2 + randf() * 0.1
        see = false
        if d < 40.0 and pl.hp > 0.0:
            var o := p + Vector3(0, 1.6, 0)
            var tp := pp + Vector3(0, 1.2, 0)
            var ln := o.distance_to(tp)
            var r: Dictionary = main.world_ray(o, tp)
            if r.is_empty():
                see = true
            else:
                var rp: Vector3 = r["position"]
                see = o.distance_to(rp) > ln - 0.4
    var was := state
    if see and d < 30.0:
        state = 2 if d < float(role["engage"]) else 1
        last = Vector2(pp.x, pp.z)
        lost = 0.0
    elif state > 0:
        lost += dt
        if lost > 4.0:
            state = 0
    if was != 2 and state == 2:
        react = 0.45 + randf() * 0.4
    var aimed := state == 2 and see
    var mvd := Vector2.ZERO
    var sp := 0.0
    var hf := false
    var fdir := Vector2.ZERO
    var here := Vector2(p.x, p.z)
    if state == 0:
        var e := tgt - here
        var ed := e.length()
        if ed < 1.5:
            _pick_wp()
        else:
            mvd = e / ed
            sp = 2.6
            hf = true
            fdir = mvd
    else:
        var tpos := Vector2(pp.x, pp.z) if see else last
        var e2 := tpos - here
        var ed2 := maxf(e2.length(), 0.001)
        var u := e2 / ed2
        var tov := dv / d
        hf = true
        if aimed:
            st -= dt
            if st <= 0.0:
                sd = -sd
                st = 1.0 + randf() * 1.6
            var rad := 0.0
            if d < float(role["close"]):
                rad = -1.0
            elif d > float(role["far"]):
                rad = 0.7
            mvd = Vector2(-u.y * sd + u.x * rad, u.x * sd + u.y * rad)
            sp = float(role["strafe"])
            fdir = tov
        else:
            if ed2 > 1.2:
                mvd = u
                sp = float(role["speed"])
            fdir = tov if see else u
    var ml := mvd.length()
    if ml > 0.0 and sp > 0.0:
        velocity.x = mvd.x / ml * sp
        velocity.z = mvd.y / ml * sp
    else:
        velocity.x = 0.0
        velocity.z = 0.0
    if is_on_floor():
        velocity.y = -1.0
    else:
        velocity.y -= 28.0 * dt
    move_and_slide()
    # stuck detection (once a second)
    sk += dt
    if sk > 1.0:
        if sp > 0.0 and Vector2(p.x - sx, p.z - sz).length() < 0.5:
            sd = -sd
            if state == 0:
                _pick_wp()
            elif not aimed:
                state = 0
        sk = 0.0
        sx = p.x
        sz = p.z
    # facing + limb animation
    var ty := atan2(-fdir.x, -fdir.y) if hf else yaw
    yaw = lerp_angle(yaw, ty, 1.0 - exp(-8.0 * dt))
    model.rotation.y = yaw
    ph += sp * dt * 3.2
    var mvf := 1.0 if sp > 0.0 else 0.0
    var sw := sin(ph)
    aim = lerpf(aim, 1.0 if aimed else 0.0, 1.0 - exp(-10.0 * dt))
    legs[0].rotation.x = sw * 0.7 * mvf
    legs[1].rotation.x = -sw * 0.7 * mvf
    arms[0].rotation.x = lerpf(-sw * 0.6 * mvf, 1.45, aim)
    arms[1].rotation.x = lerpf(sw * 0.6 * mvf, 1.45, aim)
    react -= dt
    cd -= dt
    if aimed and react <= 0.0 and cd <= 0.0 and aim > 0.7 and pl.hp > 0.0:
        _fire(d)

func _fire(d: float) -> void:
    main.bot_fired(global_position)
    var pl := main.player
    var o := muzzle.global_position
    var c := pl.global_position + Vector3(0, 1.1, 0)
    var dir := (c - o).normalized()
    var e := (0.025 + d * 0.0016) * float(role["spread"])
    dir += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * e
    dir = dir.normalized()
    var far := 120.0
    var r: Dictionary = main.world_ray(o, o + dir * far)
    var wd := far
    if not r.is_empty():
        var rp: Vector3 = r["position"]
        wd = o.distance_to(rp)
    var tt := (c - o).dot(dir)
    var hit := tt > 0.0 and tt < wd and (o + dir * tt).distance_to(c) < 0.45
    if not hit and not r.is_empty():
        main.impact(r["position"], r["normal"])
    main.spawn_tracer(o, o + dir * (tt if hit else wd))
    main.play("bshot", clampf(1.0 - d / 45.0, 0.1, 0.7))
    n += 1
    cd = (0.7 + randf() * 0.5) if n % int(role["burst"]) == 0 else float(role["rate"])
    if hit:
        pl.hurt(6.0, global_position)


func set_role(id: String) -> void:
    role = ROLES[id]
    role_name = role["name"]
