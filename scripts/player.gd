class_name Player
extends CharacterBody3D

const WALK := 5.5
const SPRINT := 7.7
const CROUCH_SPEED := 2.8
const GRAV := 28.0
const JUMP_V := 9.0
const SLIDE_T := 0.95
const SLIDE_V := 11.5
const MAX_GREN := 2
const WEAPONS := {
    "rifle": {"name": "AR", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.1, -0.21)},
    "pistol": {"name": "PISTOL", "mag": 12, "max": 60, "rate": 0.2, "auto": false, "spread": 0.008, "dmg": 1.2, "hip": Vector3(0.17, -0.14, -0.38), "ads": Vector3(0.0, -0.09, -0.2)},
}

var main: Main
var hud: Hud
var head: Node3D
var cam: Camera3D
var col: CollisionShape3D
var shape: CapsuleShape3D
var gun: Node3D
var muzzle: Marker3D
var flash_mesh: MeshInstance3D

var yaw := 0.0
var pitch := 0.0
var crouch := false
var sprint := false
var was_sprint := false
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var eye := 1.7
var fov := 75.0
var roll := 0.0
var hp := 100.0
var last_hit := -9.0
var t := 0.0
var dead := false
var mag := 30
var reserve := 120
var reloading := false
var reload_t := 0.0
var ads := false
var ads_t := 0.0
var sp_t := 0.0
var cd := 0.0
var kick := 0.0
var recoil_p := 0.0
var shots := 0
var idle := 9.0
var bloom := 0.0
var flash_t := 0.0
var cur := "rifle"
var slots := {"rifle": {"mag": 30, "res": 120}, "pistol": {"mag": 12, "res": 60}}
var swap_t := 0.0
var swap_to := ""
var grenades := MAX_GREN
var gren_cd := 0.0
var was_firing := false
var shake_amt := 0.0

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1
    floor_snap_length = 0.35
    shape = CapsuleShape3D.new()
    shape.radius = 0.35
    shape.height = 1.8
    col = CollisionShape3D.new()
    col.shape = shape
    col.position.y = 0.9
    add_child(col)
    head = Node3D.new()
    head.position.y = eye
    add_child(head)
    cam = Camera3D.new()
    cam.fov = fov
    cam.near = 0.05
    cam.far = 160.0
    head.add_child(cam)
    cam.make_current()
    _build_gun()
    hud.set_ammo(mag, reserve)

# ---------- procedural first-person viewmodel ----------
func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.disable_fog = true
    if unshaded:
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m

func _box(par: Node3D, sz: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var b := BoxMesh.new()
    b.size = sz
    mi.mesh = b
    mi.material_override = m
    mi.position = pos
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)
    return mi

func _build_gun() -> void:
    gun = Node3D.new()
    cam.add_child(gun)
    _build_rifle_model()

func _build_rifle_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    var glove := _mat(Color(0.09, 0.1, 0.12))
    var sleeve := _mat(Color(0.27, 0.33, 0.18))
    _box(gun, Vector3(0.056, 0.06, 0.36), Vector3(0, 0.03, 0), gm)
    _box(gun, Vector3(0.05, 0.075, 0.26), Vector3(0, -0.035, 0.04), pl)
    _box(gun, Vector3(0.058, 0.058, 0.3), Vector3(0, 0.02, -0.33), pl)
    _box(gun, Vector3(0.062, 0.014, 0.3), Vector3(0, -0.01, -0.33), tanm)
    _box(gun, Vector3(0.022, 0.022, 0.5), Vector3(0, 0.025, -0.62), gm)
    _box(gun, Vector3(0.046, 0.07, 0.18), Vector3(0, 0.0, 0.28), pl)
    _box(gun, Vector3(0.034, 0.1, 0.045), Vector3(0, -0.1, 0.12), pl)
    _box(gun, Vector3(0.034, 0.2, 0.05), Vector3(0, -0.17, 0.0), pl)
    _box(gun, Vector3(0.04, 0.02, 0.08), Vector3(0, 0.085, -0.12), gm)
    _box(gun, Vector3(0.066, 0.006, 0.06), Vector3(0, 0.125, -0.12), gm)
    _box(gun, Vector3(0.007, 0.007, 0.003), Vector3(0, 0.1, -0.09), _mat(Color(1, 0.16, 0.16), true))
    _box(gun, Vector3(0.09, 0.09, 0.16), Vector3(-0.02, -0.07, -0.42), glove)
    _box(gun, Vector3(0.1, 0.1, 0.34), Vector3(-0.09, -0.16, -0.18), sleeve)
    _box(gun, Vector3(0.09, 0.1, 0.1), Vector3(0.0, -0.1, 0.12), glove)
    _box(gun, Vector3(0.1, 0.1, 0.3), Vector3(0.08, -0.18, 0.3), sleeve)
    muzzle = Marker3D.new()
    muzzle.position = Vector3(0, 0.025, -0.88)
    gun.add_child(muzzle)
    flash_mesh = MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.05
    sm.height = 0.1
    flash_mesh.mesh = sm
    flash_mesh.material_override = _mat(Color(1, 0.75, 0.3), true)
    flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    flash_mesh.visible = false
    muzzle.add_child(flash_mesh)

# ---------- main loop ----------
func _physics_process(dt: float) -> void:
    t += dt
    if dead:
        head.rotation.x = lerpf(head.rotation.x, -1.1, 0.2)
        head.position.y = lerpf(head.position.y, 0.45, 0.2)
        return
    # look
    var k := 0.0042 * hud.sens * (1.0 - 0.3 * ads_t)
    yaw -= hud.look.x * k
    pitch = clampf(pitch - hud.look.y * k, -1.4835, 1.4835)
    hud.look = Vector2.ZERO
    rotation.y = yaw
    # input -> intent
    var firing: bool = hud.firing
    if firing:
        hud.lock = false   # holding fire never keeps sprint lock
    var mv: Vector2 = hud.mv
    var mvmag := minf(1.0, mv.length())
    var wish := basis * Vector3(mv.x, 0.0, -mv.y)
    if wish.length() > 0.001:
        wish = wish.normalized()
    # sprint is blocked entirely while a fire input is held (ADS stays on)
    var wants: bool = (hud.lock or hud.sprint_key) and mv.y > 0.3 and not firing
    if wants:
        crouch = false
    if hud.take("slide"):
        if slide_t > 0.0:
            slide_t = 0.0
        elif sprint and is_on_floor() and mvmag > 0.3:
            slide_t = SLIDE_T
            slide_dir = wish
            crouch = false
        elif is_on_floor():
            crouch = not crouch
    if hud.take("jump") and is_on_floor():
        slide_t = 0.0
        crouch = false
        velocity.y = JUMP_V
    var sliding := slide_t > 0.0
    sprint = wants and not crouch and not sliding
    # horizontal movement
    var hv := Vector2(velocity.x, velocity.z)
    if sliding:
        slide_t -= dt
        var f := maxf(0.0, slide_t / SLIDE_T)
        hv = Vector2(slide_dir.x, slide_dir.z) * (4.0 + (SLIDE_V - 4.0) * f * f)
    else:
        var sp: float
        if crouch:
            sp = CROUCH_SPEED * mvmag
        elif sprint:
            sp = SPRINT
        else:
            sp = WALK * mvmag
        hv = hv.lerp(Vector2(wish.x, wish.z) * sp, 1.0 - exp(-(40.0 if is_on_floor() else 4.0) * dt))
    velocity.x = hv.x
    velocity.z = hv.y
    if is_on_floor() and velocity.y <= 0.0:
        velocity.y = -1.0
    else:
        velocity.y -= GRAV * dt
    move_and_slide()
    # body / camera
    var ch := 1.1 if (crouch or sliding) else 1.8
    if absf(shape.height - ch) > 0.01:
        shape.height = ch
        col.position.y = ch * 0.5
    eye = lerpf(eye, 0.65 if sliding else (1.05 if crouch else 1.7), 1.0 - exp(-14.0 * dt))
    head.position.y = eye
    roll = lerpf(roll, 0.09 if sliding else 0.0, 1.0 - exp(-10.0 * dt))
    cam.rotation.z = roll
    head.rotation.x = pitch + recoil_p
    fov = lerpf(fov, 86.0 if sliding else (84.0 if sprint else 75.0), 1.0 - exp(-8.0 * dt))
    var fv := lerpf(fov, 52.0, ads_t)
    if absf(cam.fov - fv) > 0.01:
        cam.fov = fv
    _weapon(dt, sliding)
    # regen + HUD hand-off (HUD only touches nodes when values change)
    if not Net.active and t - last_hit > 3.5 and hp < 100.0:
        hp = minf(100.0, hp + 25.0 * dt)
    hud.hp = hp
    hud.stance = _stance()
    if shake_amt > 0.001:
        cam.h_offset = randf_range(-1.0, 1.0) * shake_amt
        cam.v_offset = randf_range(-1.0, 1.0) * shake_amt
        shake_amt = lerpf(shake_amt, 0.0, 1.0 - exp(-10.0 * dt))
    elif cam.h_offset != 0.0:
        cam.h_offset = 0.0
        cam.v_offset = 0.0

func _stance() -> String:
    if slide_t > 0.0:
        return "SLIDE"
    if sprint:
        return "SPRINT"
    if crouch:
        return "CROUCH"
    return "STAND"

func _spread() -> float:
    var sp := minf(1.0, Vector2(velocity.x, velocity.z).length() / SPRINT) * 0.012
    var air := 0.0 if is_on_floor() else 0.03
    var c := 0.005 if crouch else 0.0
    return (float(WEAPONS[cur]["spread"]) + sp + air + bloom * 0.03 - c) * (1.0 - 0.92 * ads_t)

# ---------- weapon ----------
func _start_reload() -> void:
    if reloading or mag >= int(WEAPONS[cur]["mag"]) or reserve <= 0:
        return
    reloading = true
    reload_t = 0.0
    ads = false

func _weapon(dt: float, sliding: bool) -> void:
    var firing: bool = hud.firing
    if hud.take("ads") and not reloading:
        ads = not ads
        if ads:
            hud.lock = false
    if hud.take("reload"):
        _start_reload()
    if hud.take("swap"):
        _swap_to("pistol" if cur == "rifle" else "rifle")
    if hud.take("w1"):
        _swap_to("rifle")
    if hud.take("w2"):
        _swap_to("pistol")
    if hud.take("gren"):
        _throw_grenade()
    if (sprint and not was_sprint) or reloading:
        ads = false
    was_sprint = sprint
    # firing auto-aims down sights (sprint is already blocked while firing)
    if firing and not reloading and not sprint:
        ads = true
    cd -= dt
    gren_cd -= dt
    idle += dt
    if idle > 0.1:
        recoil_p = lerpf(recoil_p, 0.0, 1.0 - exp(-6.0 * dt))
        bloom = lerpf(bloom, 0.0, 1.0 - exp(-5.0 * dt))
    if idle > 0.25:
        shots = 0
    ads_t = lerpf(ads_t, 1.0 if ads else 0.0, 1.0 - exp(-12.0 * dt))
    var use_s := sprint and is_on_floor() and not firing and idle > 0.25 and not reloading and not ads
    sp_t = lerpf(sp_t, 1.0 if use_s else 0.0, 1.0 - exp(-(9.0 if use_s else 30.0) * dt))
    var sw_off := 0.0
    if swap_t > 0.0:
        swap_t = minf(1.0, swap_t + dt / 0.38)
        sw_off = sin(swap_t * PI) * 0.5
        if swap_t >= 0.5 and swap_to != "":
            _do_swap_switch()
        if swap_t >= 1.0:
            swap_t = 0.0
    var a := ads_t
    var hip: Vector3 = WEAPONS[cur]["hip"]
    var adsp: Vector3 = WEAPONS[cur]["ads"]
    var x := lerpf(lerpf(hip.x, hip.x - 0.08, sp_t), adsp.x, a)
    var y := lerpf(lerpf(hip.y, hip.y - 0.04, sp_t), adsp.y, a)
    var z := lerpf(lerpf(hip.z, hip.z + 0.08, sp_t), adsp.z, a)
    var rx := 0.45 * sp_t * (1.0 - a)
    var ry := -0.5 * sp_t * (1.0 - a)
    var rz := 0.0
    y += sin(t * 1.4) * 0.002 - sw_off
    kick = lerpf(kick, 0.0, 1.0 - exp(-20.0 * dt))
    z += kick * 0.045 * (1.0 - 0.5 * a)
    rx += kick * 0.035
    if sliding:
        y += 0.03
        z -= 0.05
        rz += 0.12
    var rw := 0.0
    if reloading:
        reload_t += dt
        rw = clampf(minf(reload_t / 0.3, (2.0 - reload_t) / 0.25), 0.0, 1.0)
        if reload_t >= 2.0:
            var n := mini(int(WEAPONS[cur]["mag"]) - mag, reserve)
            mag += n
            reserve -= n
            reloading = false
            hud.set_ammo(mag, reserve)
    x -= 0.05 * rw
    y -= 0.05 * rw
    z += 0.04 * rw
    rz += 0.5 * rw
    rx -= 0.15 * rw
    gun.position = Vector3(x, y, z)
    gun.rotation = Vector3(rx, ry, rz)
    var fire_now: bool = firing and (bool(WEAPONS[cur]["auto"]) or not was_firing)
    was_firing = firing
    if fire_now and not reloading and cd <= 0.0 and swap_t <= 0.0:
        if mag > 0:
            _shoot()
        else:
            cd = 0.3
            _start_reload()
    if flash_t > 0.0:
        flash_t -= dt
        if flash_t <= 0.0:
            flash_mesh.visible = false
    hud.xh_gap = lerpf(hud.xh_gap, 4.0 + _spread() * 900.0, 1.0 - exp(-18.0 * dt))
    hud.xh_alpha = maxf(0.0, 1.0 - a * 1.6)

func _shoot() -> void:
    mag -= 1
    cd = float(WEAPONS[cur]["rate"])
    shots += 1
    idle = 0.0
    hud.set_ammo(mag, reserve)
    var s := _spread()
    var d := cam.global_transform.basis * Vector3((randf() - 0.5) * 2.0 * s, (randf() - 0.5) * 2.0 * s, -1.0).normalized()
    var org := cam.global_position
    var wr: Dictionary = main.world_ray(org, org + d * 120.0)
    var wd := 120.0
    if not wr.is_empty():
        var wp: Vector3 = wr["position"]
        wd = org.distance_to(wp)
    var bh: Dictionary = main.bot_ray(org, d, wd)
    var end := org + d * wd
    if not bh.is_empty():
        var bt: float = bh["t"]
        end = org + d * bt
        main.hit_bot(bh["bot"], bh["zone"], float(WEAPONS[cur]["dmg"]))
    elif not wr.is_empty():
        main.impact(wr["position"], wr["normal"])
    main.spawn_tracer(muzzle.global_position, end)
    main.play("shot", 0.8)
    flash_mesh.visible = true
    flash_t = 0.045
    var aa := 1.0 - 0.55 * ads_t
    kick = minf(1.0, kick + 0.7 * aa)
    recoil_p = minf(0.35, recoil_p + (0.0065 + minf(float(shots), 24.0) * 0.0002) * aa)
    yaw += (randf() - 0.5) * 0.0028 * aa
    bloom = minf(1.0, bloom + 0.18)

# ---------- damage / death / respawn ----------
func hurt(dmg: float, src := Vector3.ZERO) -> void:
    if dead:
        return
    hp -= dmg
    last_hit = t
    hud.flash(0.7)
    if src != Vector3.ZERO:
        hud.dir_hit(src)
    main.play("hurt", 0.8)
    recoil_p += 0.01
    if hp <= 0.0:
        hp = 0.0
        hud.hp = 0.0
        dead = true
        hud.show_death(main.kills)
        main.on_player_death()

func respawn() -> void:
    var s: Vector2 = main.spawn_point(null)
    dead = false
    position = Vector3(s.x, 0.2, s.y)
    velocity = Vector3.ZERO
    yaw = atan2(s.x, s.y)
    pitch = 0.0
    recoil_p = 0.0
    slide_t = 0.0
    crouch = false
    sprint = false
    eye = 1.7
    hp = 100.0
    last_hit = t
    _reset_slots()
    reloading = false
    ads = false
    ads_t = 0.0
    head.rotation.x = 0.0
    head.position.y = eye
    hud.lock = false
    hud.flash(1.0)
    hud.set_ammo(mag, reserve)


# ---------- weapons: swap, grenades, ammo pickups, screen shake ----------
func _clear_model() -> void:
    for c in gun.get_children():
        gun.remove_child(c)
        c.queue_free()

func _build_model(id: String) -> void:
    if id == "pistol":
        _build_pistol_model()
    else:
        _build_rifle_model()

func _build_pistol_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var glove := _mat(Color(0.09, 0.1, 0.12))
    var sleeve := _mat(Color(0.27, 0.33, 0.18))
    _box(gun, Vector3(0.05, 0.065, 0.2), Vector3(0, 0.02, -0.2), gm)
    _box(gun, Vector3(0.048, 0.085, 0.07), Vector3(0, -0.035, -0.17), pl)
    _box(gun, Vector3(0.012, 0.014, 0.1), Vector3(0, 0.07, -0.12), gm)
    _box(gun, Vector3(0.044, 0.14, 0.06), Vector3(0, -0.11, -0.05), pl)
    _box(gun, Vector3(0.12, 0.1, 0.12), Vector3(-0.02, -0.12, 0.02), glove)
    _box(gun, Vector3(0.1, 0.1, 0.3), Vector3(-0.07, -0.2, 0.2), sleeve)
    muzzle = Marker3D.new()
    muzzle.position = Vector3(0, 0.02, -0.33)
    gun.add_child(muzzle)
    flash_mesh = MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.05
    sm.height = 0.1
    flash_mesh.mesh = sm
    flash_mesh.material_override = _mat(Color(1, 0.75, 0.3), true)
    flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    flash_mesh.visible = false
    muzzle.add_child(flash_mesh)

func _swap_to(id: String) -> void:
    if id == cur or swap_t > 0.0 or dead:
        return
    swap_to = id
    swap_t = 0.0001
    reloading = false
    ads = false

func _do_swap_switch() -> void:
    slots[cur] = {"mag": mag, "res": reserve}
    cur = swap_to
    swap_to = ""
    mag = int(slots[cur]["mag"])
    reserve = int(slots[cur]["res"])
    _clear_model()
    _build_model(cur)
    hud.set_weapon(WEAPONS[cur]["name"])
    hud.set_ammo(mag, reserve)

func _reset_slots() -> void:
    swap_t = 0.0
    swap_to = ""
    slots = {"rifle": {"mag": 30, "res": 120}, "pistol": {"mag": 12, "res": 60}}
    if cur != "rifle":
        cur = "rifle"
        _clear_model()
        _build_rifle_model()
    mag = 30
    reserve = 120
    reloading = false
    gren_cd = 0.0
    grenades = MAX_GREN
    hud.set_weapon(WEAPONS[cur]["name"])
    hud.set_grenades(grenades)
    hud.set_ammo(mag, reserve)

func _throw_grenade() -> void:
    if grenades <= 0 or gren_cd > 0.0 or dead or swap_t > 0.0:
        return
    grenades -= 1
    gren_cd = 1.2
    hud.set_grenades(grenades)
    var dir := -cam.global_transform.basis.z
    var g := Grenade.new()
    g.main = main
    main.add_child(g)
    g.launch(cam.global_position + dir * 0.6, dir * 15.0 + Vector3(0, 4.0, 0) + velocity * 0.4)

# Adds up to 30 rounds to the active weapon's reserve; returns how many were added.
func ammo_pickup() -> int:
    var mx: int = WEAPONS[cur]["max"]
    var got: int = maxi(0, mini(30, mx - reserve))
    reserve += got
    return got

func shake(a: float) -> void:
    shake_amt = maxf(shake_amt, a)
