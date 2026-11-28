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
const PRIMARIES := ["assault", "smg", "lmg", "sniper", "shotgun", "marksman"]
const WEAPONS := {
    "assault": {"name": "VANGUARD", "cat": "Assault", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.1, -0.21)},
    "smg": {"name": "VIPER", "cat": "SMG", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.1, -0.21)},
    "lmg": {"name": "WARDEN", "cat": "LMG", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.1, -0.21)},
    "sniper": {"name": "LONGSHOT", "cat": "Sniper", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.12, 0.0)},
    "shotgun": {"name": "BREACHER", "cat": "Shotgun", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.1, -0.21)},
    "marksman": {"name": "HAWK", "cat": "Marksman", "mag": 30, "max": 120, "rate": 0.085, "auto": true, "spread": 0.012, "dmg": 1.0, "hip": Vector3(0.2, -0.16, -0.5), "ads": Vector3(0.0, -0.11, -0.088)},
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
static var primary_pick := "assault"   # chosen in the loadout page
var cur := "assault"
var slots := {}
var swap_t := 0.0
var swap_to := ""
var grenades := MAX_GREN
var gren_cd := 0.0
var was_firing := false
var shake_amt := 0.0
var was_air := false
var land_dip := 0.0
var dust: CPUParticles3D

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
    _setup_dust()
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
    _reset_slots()

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
    _rpart("mag", _box(gun, Vector3(0.034, 0.2, 0.05), Vector3(0, -0.17, 0.0), pl))
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
    var pre_vy := velocity.y
    move_and_slide()
    var grounded := is_on_floor()
    if grounded and was_air:
        land_dip = maxf(land_dip, clampf(-pre_vy * 0.03, 0.0, 0.28))
    was_air = not grounded
    # body / camera
    var ch := 1.1 if (crouch or sliding) else 1.8
    shape.height = lerpf(shape.height, ch, 1.0 - exp(-14.0 * dt))
    col.position.y = shape.height * 0.5
    eye = lerpf(eye, 0.5 if sliding else (1.05 if crouch else 1.7), 1.0 - exp(-14.0 * dt))
    head.position.y = eye - land_dip
    land_dip = lerpf(land_dip, 0.0, 1.0 - exp(-9.0 * dt))
    roll = lerpf(roll, (0.2 if sliding else 0.0) * (1.0 - ads_t), 1.0 - exp(-10.0 * dt))
    cam.rotation.z = roll
    head.rotation.x = pitch + recoil_p
    fov = lerpf(fov, 86.0 if sliding else (84.0 if sprint else 75.0), 1.0 - exp(-8.0 * dt))
    var fv := lerpf(fov, _ads_fov(), ads_t)
    if absf(cam.fov - fv) > 0.01:
        cam.fov = fv
    _weapon(dt, sliding)
    # regen + HUD hand-off (HUD only touches nodes when values change)
    if not Net.active and t - last_hit > 3.5 and hp < 100.0:
        hp = minf(100.0, hp + 25.0 * dt)
    hud.hp = hp
    hud.stance = _stance()
    dust.emitting = slide_t > 0.0 and is_on_floor()
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
        _swap_to("pistol" if cur != "pistol" else primary_pick)
    if hud.take("w1"):
        _swap_to(primary_pick)
    if hud.take("w2"):
        _swap_to("pistol")
    if hud.take("gren"):
        _throw_grenade()
    if (sprint and not was_sprint) or reloading:
        ads = false
    was_sprint = sprint
    # firing auto-aims down sights (sprint is already blocked while firing)
    if hud.aim_fire and not reloading and not sprint:
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
    var scoped := cur == "sniper" or cur == "marksman"
    for n in scope_body:
        n.visible = not (scoped and ads_t > 0.6)
    hud.set_scope(scoped and ads_t > 0.9)
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
        y += 0.03 * (1.0 - a)
        z -= 0.05 * (1.0 - a)
        rz += 0.12 * (1.0 - a)
    var rrot := Vector3.ZERO
    if reloading:
        reload_t += dt
        rrot = _reload_pose(clampf(reload_t / 2.0, 0.0, 1.0))
        if reload_t >= 2.0:
            var n := mini(int(WEAPONS[cur]["mag"]) - mag, reserve)
            mag += n
            reserve -= n
            reloading = false
            hud.set_ammo(mag, reserve)
    else:
        _reset_parts()
    rx += rrot.x
    ry += rrot.y
    rz += rrot.z
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
    main.shot_fired(cam.global_position)
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
    position = Vector3(s.x, main.ground_height(s.x, s.y) + 0.2, s.y)
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
    hud._clear_input()
    hud.look = Vector2.ZERO
    hud.mv = Vector2.ZERO
    was_firing = false
    was_air = false
    land_dip = 0.0
    shake_amt = 0.0
    cam.h_offset = 0.0
    cam.v_offset = 0.0
    head.rotation.x = 0.0
    head.position.y = eye
    hud.lock = false
    hud.flash(1.0)
    hud.set_ammo(mag, reserve)


# ---------- weapons: swap, grenades, ammo pickups, screen shake ----------
func _clear_model() -> void:
    rparts.clear()
    rrest.clear()
    scope_body = []
    for c in gun.get_children():
        gun.remove_child(c)
        c.queue_free()

func _build_model(id: String) -> void:
    match id:
        "pistol": _build_pistol_model()
        "smg": _build_smg_model()
        "lmg": _build_lmg_model()
        "sniper": _build_sniper_model()
        "shotgun": _build_shotgun_model()
        "marksman": _build_marksman_model()
        _: _build_rifle_model()

func _build_pistol_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var glove := _mat(Color(0.09, 0.1, 0.12))
    var sleeve := _mat(Color(0.27, 0.33, 0.18))
    _box(gun, Vector3(0.05, 0.065, 0.2), Vector3(0, 0.02, -0.2), gm)
    _box(gun, Vector3(0.048, 0.085, 0.07), Vector3(0, -0.035, -0.17), pl)
    _box(gun, Vector3(0.012, 0.014, 0.1), Vector3(0, 0.07, -0.12), gm)
    _rpart("mag", _box(gun, Vector3(0.044, 0.14, 0.06), Vector3(0, -0.11, -0.05), pl))
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

# Shared hands and forearms for the new models (same layout as the AR).
func _hands(fore_z: float) -> void:
    var glove := _mat(Color(0.09, 0.1, 0.12))
    var sleeve := _mat(Color(0.27, 0.33, 0.18))
    _box(gun, Vector3(0.09, 0.09, 0.16), Vector3(-0.02, -0.07, fore_z), glove)
    _box(gun, Vector3(0.1, 0.1, 0.34), Vector3(-0.09, -0.16, fore_z + 0.24), sleeve)
    _box(gun, Vector3(0.09, 0.1, 0.1), Vector3(0.0, -0.1, 0.12), glove)
    _box(gun, Vector3(0.1, 0.1, 0.3), Vector3(0.08, -0.18, 0.3), sleeve)

# Muzzle point and muzzle flash for the new models.
func _add_muzzle(z: float, y: float) -> void:
    muzzle = Marker3D.new()
    muzzle.position = Vector3(0, y, z)
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

# VIPER SMG: short and compact with a long magazine.
func _build_smg_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    _box(gun, Vector3(0.06, 0.072, 0.24), Vector3(0, 0.03, 0.0), gm)
    _box(gun, Vector3(0.034, 0.034, 0.2), Vector3(0, 0.03, -0.3), pl)
    _box(gun, Vector3(0.05, 0.02, 0.2), Vector3(0, 0.07, -0.12), gm)
    _rpart("mag", _box(gun, Vector3(0.03, 0.22, 0.05), Vector3(0, -0.11, 0.0), pl))
    _box(gun, Vector3(0.04, 0.12, 0.05), Vector3(0, -0.09, 0.14), pl)
    _box(gun, Vector3(0.04, 0.05, 0.14), Vector3(0, 0.0, 0.26), tanm)
    _hands(-0.36)
    _add_muzzle(-0.42, 0.03)

# WARDEN LMG: heavy receiver, shrouded barrel, bipod and side ammo box.
func _build_lmg_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    _box(gun, Vector3(0.09, 0.1, 0.34), Vector3(0, 0.03, 0.0), gm)
    _box(gun, Vector3(0.075, 0.075, 0.3), Vector3(0, 0.03, -0.3), pl)
    _box(gun, Vector3(0.03, 0.03, 0.2), Vector3(0, 0.03, -0.6), gm)
    _box(gun, Vector3(0.012, 0.13, 0.012), Vector3(-0.03, -0.07, -0.56), pl)
    _box(gun, Vector3(0.012, 0.13, 0.012), Vector3(0.03, -0.07, -0.56), pl)
    _rpart("ammo", _box(gun, Vector3(0.1, 0.12, 0.14), Vector3(0.07, -0.01, 0.0), tanm))
    _box(gun, Vector3(0.04, 0.12, 0.05), Vector3(0, -0.1, 0.12), pl)
    _box(gun, Vector3(0.05, 0.08, 0.22), Vector3(0, -0.01, 0.32), pl)
    _hands(-0.42)
    _add_muzzle(-0.72, 0.03)

# See-through lens glass.
func _glass_mat() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(0.3, 0.6, 0.75, 0.2)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.disable_fog = true
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

# Scope body parts (tube, bells, eyepiece, turrets, mounts) that are hidden while looking through the scope.
func _scope_part(n: Node3D) -> void:
    scope_body.append(n)

# Cylinder piece for scope parts. rot is in radians: (PI/2, 0, 0) lays it along Z, (0, 0, PI/2) along X.
func _cyl(pos: Vector3, r: float, h: float, rot: Vector3, m: Material) -> MeshInstance3D:
    var cm := CylinderMesh.new()
    cm.top_radius = r
    cm.bottom_radius = r
    cm.height = h
    cm.radial_segments = 12
    var mi := MeshInstance3D.new()
    mi.mesh = cm
    mi.material_override = m
    mi.position = pos
    mi.rotation = rot
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    gun.add_child(mi)
    return mi

# LONGSHOT sniper: long barrel, a real scope with lenses and turrets, bolt handle.
func _build_sniper_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    _box(gun, Vector3(0.05, 0.07, 0.28), Vector3(0, 0.03, 0.0), gm)              # receiver
    _box(gun, Vector3(0.028, 0.028, 0.7), Vector3(0, 0.035, -0.55), pl)          # long barrel
    _scope_part(_box(gun, Vector3(0.02, 0.05, 0.04), Vector3(0, 0.085, -0.33), gm))  # front scope mount
    _scope_part(_box(gun, Vector3(0.02, 0.05, 0.04), Vector3(0, 0.085, -0.16), gm))  # rear scope mount
    _scope_part(_cyl(Vector3(0, 0.12, -0.26), 0.022, 0.3, Vector3(PI / 2, 0, 0), pl))   # scope tube
    _scope_part(_cyl(Vector3(0, 0.12, -0.4), 0.03, 0.05, Vector3(PI / 2, 0, 0), gm))    # objective bell
    _scope_part(_cyl(Vector3(0, 0.12, -0.12), 0.026, 0.04, Vector3(PI / 2, 0, 0), gm))  # eyepiece
    _scope_part(_cyl(Vector3(0, 0.155, -0.26), 0.012, 0.025, Vector3(0, 0, 0), gm))     # elevation turret
    _scope_part(_cyl(Vector3(0.034, 0.12, -0.26), 0.012, 0.025, Vector3(0, 0, PI / 2), gm))  # windage turret
    _rpart("bolt", _box(gun, Vector3(0.02, 0.02, 0.04), Vector3(0.035, 0.05, 0.04), tanm))  # bolt handle
    _rpart("mag", _box(gun, Vector3(0.036, 0.13, 0.05), Vector3(0, -0.1, 0.0), pl))  # magazine
    _box(gun, Vector3(0.036, 0.12, 0.05), Vector3(0, -0.09, 0.14), pl)           # grip
    _box(gun, Vector3(0.055, 0.1, 0.34), Vector3(0, -0.01, 0.32), tanm)          # stock
    _hands(-0.38)
    _add_muzzle(-0.92, 0.035)

# BREACHER shotgun: wide receiver, fat barrel, tube magazine and pump.
func _build_shotgun_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    _box(gun, Vector3(0.08, 0.09, 0.26), Vector3(0, 0.03, 0.0), gm)
    _box(gun, Vector3(0.05, 0.05, 0.36), Vector3(0, 0.04, -0.31), pl)
    _box(gun, Vector3(0.03, 0.03, 0.42), Vector3(0, -0.01, -0.2), pl)
    _rpart("pump", _box(gun, Vector3(0.07, 0.05, 0.12), Vector3(0, -0.01, -0.36), tanm))
    _rpart("shell", _box(gun, Vector3(0.025, 0.025, 0.07), Vector3(0.2, -0.02, -0.15), tanm))
    _box(gun, Vector3(0.04, 0.13, 0.05), Vector3(0, -0.1, 0.1), pl)
    _box(gun, Vector3(0.05, 0.1, 0.22), Vector3(0, 0.0, 0.33), tanm)
    _hands(-0.36)
    _add_muzzle(-0.5, 0.04)

# HAWK DMR: tan handguard, muzzle brake, flat optic on a rail, angled magazine and cheek-riser stock.
func _build_marksman_model() -> void:
    var gm := _mat(Color(0.19, 0.2, 0.23))
    var pl := _mat(Color(0.09, 0.1, 0.11))
    var tanm := _mat(Color(0.72, 0.6, 0.38))
    _box(gun, Vector3(0.05, 0.075, 0.3), Vector3(0, 0.03, 0.0), gm)              # receiver
    _box(gun, Vector3(0.03, 0.02, 0.22), Vector3(0, 0.075, -0.02), gm)           # top rail
    _scope_part(_box(gun, Vector3(0.036, 0.05, 0.12), Vector3(0, 0.11, -0.1), pl))      # optic body
    _scope_part(_cyl(Vector3(0, 0.11, -0.18), 0.02, 0.05, Vector3(PI / 2, 0, 0), pl))   # sunshade
    _scope_part(_cyl(Vector3(0, 0.11, -0.03), 0.018, 0.03, Vector3(PI / 2, 0, 0), gm))  # eyepiece
    _scope_part(_cyl(Vector3(0, 0.14, -0.1), 0.01, 0.02, Vector3(0, 0, 0), gm))         # turret knob
    _box(gun, Vector3(0.058, 0.058, 0.24), Vector3(0, 0.02, -0.28), tanm)        # tan handguard
    _box(gun, Vector3(0.026, 0.026, 0.36), Vector3(0, 0.03, -0.56), pl)          # medium barrel
    _box(gun, Vector3(0.04, 0.04, 0.07), Vector3(0, 0.03, -0.74), gm)            # muzzle brake
    var mg := _box(gun, Vector3(0.034, 0.17, 0.05), Vector3(0, -0.1, -0.02), pl)  # magazine
    mg.rotation.x = 0.15
    _rpart("mag", mg)
    _rpart("charge", _box(gun, Vector3(0.012, 0.02, 0.04), Vector3(0.0, 0.095, 0.05), gm))  # charging handle
    _box(gun, Vector3(0.038, 0.12, 0.05), Vector3(0, -0.09, 0.13), pl)           # grip
    _box(gun, Vector3(0.05, 0.08, 0.26), Vector3(0, -0.01, 0.3), tanm)           # stock
    _box(gun, Vector3(0.04, 0.03, 0.12), Vector3(0, 0.03, 0.22), gm)             # cheek riser
    _hands(-0.3)
    _add_muzzle(-0.8, 0.03)

# ---------- reload animations: each weapon moves its own named parts (p goes 0 -> 1 over the reload) ----------
var rparts := {}   # part name -> node that moves during a reload
var rrest := {}    # part name -> [position, rotation] at rest
var scope_body: Array = []   # scope parts hidden while aiming through the scope

func _rpart(pname: String, n: Node3D) -> void:
    rparts[pname] = n
    rrest[pname] = [n.position, n.rotation]

func _ss(x: float) -> float:
    return x * x * (3.0 - 2.0 * x)

# Ramps 0 -> 1 across [a, b], holds at 1 until c, then eases back to 0 by d.
func _hold(p: float, a: float, b: float, c: float, d: float) -> float:
    var up := _ss(clampf((p - a) / (b - a), 0.0, 1.0))
    var down := _ss(clampf((p - c) / (d - c), 0.0, 1.0))
    return up * (1.0 - down)

func _reset_parts() -> void:
    for k in rparts:
        var n: Node3D = rparts[k]
        var r: Array = rrest[k]
        n.position = r[0]
        n.rotation = r[1]
        n.visible = k != "shell"

func _move(pname: String, p: float, a: float, b: float, c: float, d: float, off: Vector3) -> void:
    if not rparts.has(pname):
        return
    var r: Array = rrest[pname]
    (rparts[pname] as Node3D).position = r[0] + off * _hold(p, a, b, c, d)

func _turn(pname: String, p: float, a: float, b: float, c: float, d: float, rot: Vector3) -> void:
    if not rparts.has(pname):
        return
    var r: Array = rrest[pname]
    (rparts[pname] as Node3D).rotation = r[1] + rot * _hold(p, a, b, c, d)

# Moves this weapon's parts for progress p and returns the gun-level tilt to add this frame.
func _reload_pose(p: float) -> Vector3:
    match cur:
        "pistol":
            _move("mag", p, 0.0, 0.25, 0.6, 0.9, Vector3(0, -0.2, 0.0))
            return Vector3(0, 0, 0.15 * _hold(p, 0.0, 0.25, 0.6, 0.9))
        "smg":
            _move("mag", p, 0.0, 0.15, 0.5, 0.6, Vector3(0, -0.25, 0.0))
            return Vector3(0.08 * _hold(p, 0.55, 0.65, 0.7, 0.8), 0, 0)
        "lmg":
            _move("ammo", p, 0.0, 0.35, 0.6, 0.95, Vector3(0.25, 0, 0))
            return Vector3(-0.2 * _hold(p, 0.0, 0.35, 0.6, 0.95), 0, 0)
        "sniper":
            _move("mag", p, 0.0, 0.25, 0.7, 0.9, Vector3(0, -0.2, 0.0))
            _move("bolt", p, 0.3, 0.38, 0.42, 0.5, Vector3(0, 0, 0.1))
            return Vector3(-0.08 * _hold(p, 0.3, 0.38, 0.42, 0.5), 0, 0)
        "shotgun":
            if rparts.has("shell"):
                var sh: Node3D = rparts["shell"]
                sh.visible = p >= 0.1 and p < 0.45
                sh.position = (rrest["shell"][0] as Vector3).lerp(Vector3(0, -0.01, -0.12), _ss(clampf((p - 0.1) / 0.3, 0.0, 1.0)))
            _move("pump", p, 0.6, 0.7, 0.75, 0.9, Vector3(0, 0, 0.08))
            var tilt := _hold(p, 0.0, 0.1, 0.45, 0.55)
            return Vector3(0.2 * tilt, 0, 0.1 * tilt)
        "marksman":
            _move("mag", p, 0.0, 0.3, 0.65, 0.95, Vector3(0, -0.2, 0.0))
            _move("charge", p, 0.8, 0.85, 0.9, 0.98, Vector3(0, 0, 0.08))
            return Vector3(0, 0, 0.1 * _hold(p, 0.0, 0.3, 0.65, 0.95))
        _:
            _move("mag", p, 0.0, 0.3, 0.6, 0.9, Vector3(0, -0.22, 0.04))
            _turn("mag", p, 0.0, 0.3, 0.6, 0.9, Vector3(0.2, 0, 0))
            return Vector3(0, 0, 0.25 * _hold(p, 0.0, 0.3, 0.6, 0.9))

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

# Builds a weapon model into a preview holder (used by the loadout page) without touching the live gun.
func build_preview(holder: Node3D, id: String) -> void:
    var s_gun = gun
    var s_parts = rparts
    var s_rest = rrest
    var s_muzzle = muzzle
    var s_flash = flash_mesh
    var s_scope = scope_body
    rparts = {}
    rrest = {}
    scope_body = []
    for c in holder.get_children():
        holder.remove_child(c)
        c.queue_free()
    gun = holder
    _build_model(id)
    gun = s_gun
    rparts = s_parts
    rrest = s_rest
    muzzle = s_muzzle
    flash_mesh = s_flash
    scope_body = s_scope

# Field of view when aiming: scoped weapons zoom in.
func _ads_fov() -> float:
    match cur:
        "sniper":
            return 20.0
        "marksman":
            return 30.0
        _:
            return 52.0

func _reset_slots() -> void:
    swap_t = 0.0
    swap_to = ""
    cur = primary_pick
    slots = {cur: {"mag": int(WEAPONS[cur]["mag"]), "res": int(WEAPONS[cur]["max"])}, "pistol": {"mag": 12, "res": 60}}
    _clear_model()
    _build_model(cur)
    mag = int(WEAPONS[cur]["mag"])
    reserve = int(WEAPONS[cur]["max"])
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


# Dust kicked up behind the player while sliding on the ground.
func _setup_dust() -> void:
    dust = CPUParticles3D.new()
    dust.emitting = false
    dust.amount = 16
    dust.lifetime = 0.6
    dust.direction = Vector3.UP
    dust.spread = 60.0
    dust.initial_velocity_min = 0.6
    dust.initial_velocity_max = 1.6
    dust.gravity = Vector3(0, -1.5, 0)
    dust.scale_amount_min = 0.8
    dust.scale_amount_max = 1.6
    dust.position = Vector3(0, 0.08, 0)
    var sm := SphereMesh.new()
    sm.radius = 0.09
    sm.height = 0.18
    sm.material = _mat(Color(0.75, 0.68, 0.52), true)
    dust.mesh = sm
    add_child(dust)
