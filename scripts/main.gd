class_name Main
extends Node3D

const SPAWNS: Array[Vector2] = [
    Vector2(-28, -26), Vector2(28, -26), Vector2(-28, 26), Vector2(28, 26),
    Vector2(-10, -4), Vector2(10, 4), Vector2(-20, -6), Vector2(20, 6),
    Vector2(0, -12), Vector2(0, 12), Vector2(-12, -30), Vector2(12, -30), Vector2(-30, -6),
]

var player: Player
var hud: Hud
var bots: Array[Bot] = []
var pickups: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var tr_i := 0
var kills := 0
var rayq := PhysicsRayQueryParameters3D.new()   # reused for every world raycast
var sounds := {}
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_i := 0
var drop_res := {}

func _ready() -> void:
    Net.main = self
    _env()
    ArenaBuilder.build(self)
    _make_sounds()
    _make_tracers()
    _make_impacts()
    hud = Hud.new()
    add_child(hud)
    player = Player.new()
    player.main = self
    player.hud = hud
    add_child(player)
    player.position = Vector3(0, 0.2, 28)
    hud.player = player
    hud.respawn_requested.connect(_on_respawn)
    Net.started.connect(start_mp)
    Net.host_lost.connect(_on_host_lost)
    Net.match_ended.connect(_on_match_ended)
    # Offline practice: 3 bots. Bots are removed when a networked match starts.
    for i in 3:
        var b := Bot.new()
        b.main = self
        add_child(b)
        bots.append(b)
        b.spawn(spawn_point(b))

func _env() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.29, 0.66, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.82, 0.86, 0.95)
    env.ambient_light_energy = 0.9
    env.fog_enabled = true
    env.fog_light_color = Color(0.91, 0.85, 0.71)
    env.fog_density = 0.011
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, 35, 0)
    sun.light_energy = 1.2
    sun.light_color = Color(1, 0.89, 0.7)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 60.0
    add_child(sun)

# ---------- networked match flow ----------
func start_mp() -> void:
    for b in bots:
        b.queue_free()
    bots.clear()
    kills = 0
    hud.set_kills(0)
    player.respawn()
    hud.start_match()

func _on_respawn() -> void:
    player.respawn()
    Net.request_respawn(player.global_position)

func _on_match_ended(nm: String) -> void:
    hud.pick("%s WINS" % nm)

func _on_host_lost() -> void:
    hud.pick("HOST LEFT")
    await get_tree().create_timer(2.0, true).timeout
    Net.reset()
    get_tree().reload_current_scene()

# Called by Net with the host's authoritative values for my player.
func sync_local(hp_v: float, dead_v: bool, k: int, att: int = -1) -> void:
    if k != kills:
        kills = k
        hud.set_kills(k)
    if Net.respawn_locked():
        return
    if hp_v < player.hp and not dead_v:
        hud.flash(0.7)
        if att >= 0 and Net.remotes.has(att):
            hud.dir_hit(Net.remotes[att].global_position)
    player.hp = hp_v
    if dead_v and not player.dead:
        player.dead = true
        player.hp = 0.0
        hud.show_death(k)
    elif not dead_v and player.dead:
        player.respawn()

func set_board(t: String) -> void:
    hud.set_board(t)

func on_my_kill() -> void:
    hud.hitmark(true)
    play("kill")

# ---------- sound ----------
func _make_sounds() -> void:
    sounds = {
        "shot": Sfx.make(150.0, 42.0, 0.14, 0.6, 0.7),
        "hit": Sfx.make(260.0, 90.0, 0.08, 0.5, 0.5),
        "hitm": Sfx.make(1400.0, 900.0, 0.05, 0.1, 0.4),
        "kill": Sfx.make(900.0, 420.0, 0.18, 0.2, 0.5),
        "pick": Sfx.make(500.0, 1100.0, 0.12, 0.0, 0.4),
        "hurt": Sfx.make(110.0, 60.0, 0.18, 0.4, 0.6),
        "bshot": Sfx.make(130.0, 50.0, 0.09, 0.6, 0.4),
    }
    for i in 8:
        var ap := AudioStreamPlayer.new()
        add_child(ap)
        sfx_pool.append(ap)

func play(n: String, vol := 1.0) -> void:
    var ap := sfx_pool[sfx_i % sfx_pool.size()]
    sfx_i += 1
    ap.stream = sounds[n]
    ap.volume_db = linear_to_db(clampf(vol, 0.01, 1.0))
    ap.play()

# ---------- raycasts (no per-call allocations) ----------
func world_ray(a: Vector3, b: Vector3) -> Dictionary:
    rayq.from = a
    rayq.to = b
    rayq.collision_mask = 1
    return get_world_3d().direct_space_state.intersect_ray(rayq)

func _sph(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
    var oc := c - o
    var t := oc.dot(d)
    if t < 0.0:
        return -1.0
    var h := r * r - (oc.length_squared() - t * t)
    if h < 0.0:
        return -1.0
    return t - sqrt(h)

func _hit_figure(o: Vector3, d: Vector3, p: Vector3, maxt: float) -> Dictionary:
    var out := {}
    var t := _sph(o, d, p + Vector3(0, 1.62, 0), 0.2)
    if t >= 0.0 and t < maxt:
        out = {"zone": "head", "t": t}
        maxt = t
    for y in [0.35, 0.75, 1.15]:
        t = _sph(o, d, p + Vector3(0, y, 0), 0.3)
        if t >= 0.0 and t < maxt:
            out = {"zone": "body", "t": t}
            maxt = t
    return out

# Analytic hit test against bots and networked opponents.
func bot_ray(o: Vector3, d: Vector3, maxt: float) -> Dictionary:
    var best := {}
    var bt := maxt
    for b in bots:
        if b.alive:
            var r := _hit_figure(o, d, b.global_position, bt)
            if not r.is_empty():
                bt = r["t"]
                best = {"bot": b, "zone": r["zone"], "t": bt}
    for pid in Net.remotes:
        var rp: RemotePlayer = Net.remotes[pid]
        if rp.alive:
            var r2 := _hit_figure(o, d, rp.global_position, bt)
            if not r2.is_empty():
                bt = r2["t"]
                best = {"bot": rp, "zone": r2["zone"], "t": bt}
    return best

func hit_bot(b, zone: String) -> void:
    if b is RemotePlayer:
        hud.hitmark(zone == "head")
        play("hitm", 0.8)
        Net.request_hit(b.pid, zone)
        return
    var head := zone == "head"
    b.hp -= (48.0 if head else 24.0)
    if b.hp <= 0.0:
        b.die()
        kills += 1
        hud.set_kills(kills)
        drop_at(b.global_position)
        hud.hitmark(true)
        play("kill")
    else:
        hud.hitmark(head)
        play("hitm", 0.8)
        b.alert()

func spawn_point(me) -> Vector2:
    var pp := Vector2(0, 28)
    if player:
        pp = Vector2(player.global_position.x, player.global_position.z)
    var others: Array[Vector2] = []
    for b in bots:
        if b != me and b.alive:
            others.append(Vector2(b.global_position.x, b.global_position.z))
    for pid in Net.remotes:
        var r: RemotePlayer = Net.remotes[pid]
        if r.alive:
            others.append(Vector2(r.global_position.x, r.global_position.z))
    var best := SPAWNS[0]
    var bd := -1.0
    var pts: Array[Vector2] = []
    pts.append_array(SPAWNS)
    pts.shuffle()
    for s in pts:
        var dp := s.distance_to(pp)
        var db := 99.0
        for o in others:
            db = minf(db, s.distance_to(o))
        if dp >= 20.0 and db >= 8.0:
            return s
        var sc := minf(dp, db * 2.0)
        if sc > bd:
            bd = sc
            best = s
    return best

# ---------- tracers (pooled) ----------
func _make_tracers() -> void:
    var bm := BoxMesh.new()
    bm.size = Vector3(0.012, 0.012, 1.0)
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(1, 0.67, 0.2)
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.disable_fog = true
    for i in 12:
        var mi := MeshInstance3D.new()
        mi.mesh = bm
        mi.material_override = m
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mi.visible = false
        add_child(mi)
        tracers.append({"n": mi, "life": 0.0})

func spawn_tracer(a: Vector3, b: Vector3) -> void:
    var d := b - a
    var l := d.length()
    if l < 0.05:
        return
    var tr: Dictionary = tracers[tr_i % tracers.size()]
    tr_i += 1
    var mi: MeshInstance3D = tr["n"]
    mi.visible = true
    mi.global_position = (a + b) * 0.5
    var up := Vector3.UP if absf(d.y / l) < 0.99 else Vector3.RIGHT
    mi.look_at(b, up)
    mi.scale = Vector3(1, 1, l)
    tr["life"] = 0.06

func _process(dt: float) -> void:
    for tr in tracers:
        var life: float = tr["life"]
        if life > 0.0:
            life -= dt
            tr["life"] = life
            if life <= 0.0:
                (tr["n"] as MeshInstance3D).visible = false

# ---------- ammo pickups dropped on kills ----------
func _m(c: Color, unshaded := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    if unshaded:
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m

func _dbox(par: Node3D, sz: Vector3, pos: Vector3, key: String) -> void:
    var mi := MeshInstance3D.new()
    mi.mesh = drop_res["box"]
    mi.scale = sz
    mi.position = pos
    mi.material_override = drop_res[key]
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    par.add_child(mi)

func drop_at(p: Vector3) -> void:
    if drop_res.is_empty():
        var bm := BoxMesh.new()
        bm.size = Vector3.ONE
        drop_res = {"box": bm, "body": _m(Color(0.29, 0.36, 0.16)), "dark": _m(Color(0.18, 0.23, 0.1)), "gun": _m(Color(0.09, 0.1, 0.11)), "yel": _m(Color(1, 0.82, 0.29), true)}
    var g := Node3D.new()
    _dbox(g, Vector3(0.36, 0.2, 0.24), Vector3(0, 0, 0), "body")
    _dbox(g, Vector3(0.38, 0.04, 0.26), Vector3(0, 0.11, 0), "dark")
    _dbox(g, Vector3(0.12, 0.07, 0.27), Vector3(0, 0.13, 0), "yel")
    _dbox(g, Vector3(0.05, 0.16, 0.07), Vector3(-0.09, 0.2, 0.04), "gun")
    _dbox(g, Vector3(0.05, 0.16, 0.07), Vector3(0.09, 0.2, 0.04), "gun")
    var y0 := p.y
    var r := world_ray(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0)
    if not r.is_empty():
        var rp: Vector3 = r["position"]
        y0 = rp.y
    g.position = Vector3(p.x, y0 + 0.35, p.z)
    add_child(g)
    pickups.append({"node": g, "y0": y0, "age": 0.0})
    if pickups.size() > 8:
        var old: Dictionary = pickups.pop_front()
        (old["node"] as Node3D).queue_free()

func _physics_process(dt: float) -> void:
    if player == null or player.dead:
        return
    var pp := player.global_position
    for i in range(pickups.size() - 1, -1, -1):
        var k: Dictionary = pickups[i]
        var g: Node3D = k["node"]
        var age: float = k["age"] + dt
        var y0: float = k["y0"]
        k["age"] = age
        g.rotation.y += 2.5 * dt
        g.position.y = y0 + 0.35 + sin(age * 3.0) * 0.08
        g.visible = age < 17.0 or sin(age * 14.0) > 0.0
        if age > 20.0:
            g.queue_free()
            pickups.remove_at(i)
        elif Vector2(pp.x - g.position.x, pp.z - g.position.z).length() < 1.6 and absf(pp.y - y0) < 1.8:
            var got := maxi(0, mini(30, 180 - player.reserve))
            player.reserve += got
            hud.set_ammo(player.mag, player.reserve)
            hud.pick("+%d AMMO" % got if got > 0 else "AMMO FULL")
            play("pick", 0.5)
            g.queue_free()
            pickups.remove_at(i)


# ---------- bullet holes and sparks ----------
var _hole_mesh: QuadMesh
var _hole_mat: StandardMaterial3D
var _spark_mesh: BoxMesh
var _holes: Array[MeshInstance3D] = []
var _hole_i := 0

func _make_impacts() -> void:
    var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for y in 64:
        for x in 64:
            var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
            if d < 0.5:
                img.set_pixel(x, y, Color(0.04, 0.04, 0.04, 1.0))
            elif d < 0.8:
                img.set_pixel(x, y, Color(0.1, 0.1, 0.1, 0.75))
    _hole_mat = StandardMaterial3D.new()
    _hole_mat.albedo_texture = ImageTexture.create_from_image(img)
    _hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _hole_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    _hole_mesh = QuadMesh.new()
    _hole_mesh.size = Vector2(0.24, 0.24)
    for i in 40:
        var mi := MeshInstance3D.new()
        mi.mesh = _hole_mesh
        mi.material_override = _hole_mat
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mi.visible = false
        add_child(mi)
        _holes.append(mi)
    var sm := StandardMaterial3D.new()
    sm.albedo_color = Color(1.0, 0.75, 0.3)
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.disable_fog = true
    _spark_mesh = BoxMesh.new()
    _spark_mesh.size = Vector3(0.05, 0.05, 0.05)
    _spark_mesh.material = sm

# Called when a bullet hits the world: p = hit point, n = surface normal.
func impact(p: Vector3, n: Vector3) -> void:
    var h := _holes[_hole_i % _holes.size()]
    _hole_i += 1
    h.visible = true
    var off := p + n * 0.03
    h.global_position = off
    h.look_at(off - n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)
    h.rotate_object_local(Vector3(0, 0, 1), randf() * TAU)
    h.scale = Vector3.ONE * randf_range(0.8, 1.25)
    _spark(p, n)

func _spark(p: Vector3, n: Vector3) -> void:
    var cp := CPUParticles3D.new()
    cp.one_shot = true
    cp.explosiveness = 1.0
    cp.amount = 14
    cp.lifetime = 0.35
    cp.direction = n
    cp.spread = 60.0
    cp.initial_velocity_min = 2.5
    cp.initial_velocity_max = 5.5
    cp.gravity = Vector3(0, -12, 0)
    cp.scale_amount_min = 0.6
    cp.scale_amount_max = 1.2
    cp.mesh = _spark_mesh
    add_child(cp)
    cp.global_position = p + n * 0.05
    cp.emitting = true
    get_tree().create_timer(0.7).timeout.connect(cp.queue_free)
