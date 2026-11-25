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
    _load_map(pick_map_id())
    _make_sounds()
    _make_tracers()
    _make_impacts()
    mui = MatchUI.new()
    mui.main = self
    add_child(mui)
    hud = Hud.new()
    add_child(hud)
    player = Player.new()
    player.main = self
    player.hud = hud
    add_child(player)
    player.position = start_position()
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
        b.set_role(["rusher", "strafer", "soldier"][i])
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
    world_env = we
    we.environment = env
    add_child(we)
    var sun := DirectionalLight3D.new()
    main_sun = sun
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
    _load_map(Net.map_id)
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
        on_player_death()
    elif not dead_v and player.dead:
        player.respawn()

func set_board(t: String) -> void:
    hud.set_board(t)

func on_my_kill() -> void:
    hud.hitmark(true)
    play("kill")
    add_streak()

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
        "boom": Sfx.make(90.0, 25.0, 0.7, 0.8, 0.9),
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

func hit_bot(b, zone: String, mult := 1.0) -> void:
    shots_hit += 1
    if zone == "head":
        headshots += 1
    if b is RemotePlayer:
        hud.hitmark(zone == "head")
        play("hitm", 0.8)
        Net.request_hit(b.pid, zone)
        return
    damage_bot(b, (48.0 if zone == "head" else 24.0) * mult, zone == "head")

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
    var best: Vector2 = active_spawns[0]
    var bd := -1.0
    var pts: Array[Vector2] = []
    pts.append_array(active_spawns)
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
    _match_tick(dt)
    _uav_tick(dt)
    _callout_tick()
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
            var got: int = player.ammo_pickup()
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


# ---------- match: timer, kill goal, score, deaths, summary (offline practice) ----------
const MATCH_TIME := 180.0
const KILL_GOAL := 20
var mui: MatchUI
var score := 0
var deaths := 0
var headshots := 0
var match_t := MATCH_TIME
var match_started := false
var match_over := false

func _match_tick(dt: float) -> void:
    if Net.active or get_tree().paused:
        return
    if not match_started:
        match_started = true
        match_t = MATCH_TIME
    if match_over:
        return
    match_t = maxf(0.0, match_t - dt)
    mui.set_timer(match_t, kills, KILL_GOAL)
    if match_t <= 0.0:
        end_match("TIME UP")

func end_match(reason: String) -> void:
    if match_over:
        return
    match_over = true
    hud._clear_input()
    var secs := int(MATCH_TIME - match_t)
    mui.show_summary(reason, kills, deaths, headshots, score, "%d:%02d" % [secs / 60, secs % 60], accuracy_text())
    get_tree().paused = true

func reset_match() -> void:
    mui.hide_summary()
    mui.clear_feed()
    for g in get_tree().get_nodes_in_group("grenade"):
        g.queue_free()
    for k in pickups:
        (k["node"] as Node3D).queue_free()
    pickups.clear()
    kills = 0
    deaths = 0
    headshots = 0
    score = 0
    shots_fired = 0
    shots_hit = 0
    streak = 0
    uav_t = 0.0
    hud.set_uav(0.0)
    hud.set_kills(0)
    _load_map(pick_map_id())
    for b in bots:
        b.spawn(spawn_point(b))
    player.respawn()
    match_t = MATCH_TIME
    match_over = false
    get_tree().paused = false

func on_player_death() -> void:
    deaths += 1
    streak = 0
    mui.feed("YOU WERE ELIMINATED", Color(1, 0.35, 0.35))

# Killfeed for networked kills (names come from the host's player table).
func net_kill_feed(a: int, v: int) -> void:
    var na: String = "P%d" % a
    var nv: String = "P%d" % v
    if Net.pl.has(a):
        na = Net.pl[a]["n"]
    if Net.pl.has(v):
        nv = Net.pl[v]["n"]
    mui.feed("%s  >  %s" % [na, nv], Color(1, 0.8, 0.3) if a == Net.my_id else Color(0.85, 0.85, 0.85))

# Single place for bot damage: handles kills, score, killfeed and popups.
func damage_bot(b, amount: float, head: bool) -> void:
    if not b.alive:
        return
    b.hp -= amount
    if b.hp <= 0.0:
        b.die()
        kills += 1
        score += 150 if head else 100
        hud.set_kills(kills)
        add_streak()
        drop_at(b.global_position)
        hud.hitmark(true)
        play("kill")
        var nm := "%s %d" % [b.role_name, bots.find(b) + 1]
        mui.feed("YOU  >  %s%s" % [nm, "   HEADSHOT" if head else ""], Color(1, 0.8, 0.3))
        mui.popup("HEADSHOT +150" if head else "ELIMINATED +100")
        if kills >= KILL_GOAL:
            end_match("GOAL REACHED")
    else:
        hud.hitmark(head)
        play("hitm", 0.8)
        b.alert()

# Grenade blast: damages bots by distance, hurts the thrower if close, plus visuals and sound.
func explode(p: Vector3, radius: float, dmg: float, self_r: float, self_dmg: float) -> void:
    if Net.active:
        Net.report_boom(p)
    for b in bots:
        if not b.alive:
            continue
        var d: float = b.global_position.distance_to(p + Vector3(0, 0.9, 0))
        if d < radius:
            damage_bot(b, dmg * (1.0 - d / radius), false)
    var pd: float = player.global_position.distance_to(p + Vector3(0, 0.9, 0))
    if not Net.active and pd < self_r and not player.dead:
        player.hurt(self_dmg * (1.0 - pd / self_r), p)
    _boom(p)
    for i in 3:
        _spark(p, Vector3(randf() - 0.5, 1.0, randf() - 0.5).normalized())
    player.shake(0.3 * clampf(1.0 - pd / 14.0, 0.0, 1.0))
    play("boom", 0.9)

func _boom(p: Vector3) -> void:
    var ex := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 1.0
    sm.height = 2.0
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(1.0, 0.55, 0.15)
    m.emission_enabled = true
    m.emission = Color(1.0, 0.5, 0.1)
    m.emission_energy_multiplier = 2.0
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.material = m
    ex.mesh = sm
    ex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(ex)
    ex.global_position = p
    ex.scale = Vector3.ONE * 0.2
    var tw := ex.create_tween()
    tw.tween_property(ex, "scale", Vector3.ONE * 5.0, 0.18)
    tw.tween_callback(ex.queue_free)


# ---------- step 5: UAV streaks, radar feed, accuracy ----------
const UAV_TIME := 12.0
var streak := 0
var uav_t := 0.0
var shots_fired := 0
var shots_hit := 0

func shot_fired(p: Vector3) -> void:
    shots_fired += 1
    if Net.active:
        Net.report_fire(p)

func accuracy_text() -> String:
    if shots_fired <= 0:
        return "0%"
    return "%d%%" % int(round(100.0 * shots_hit / shots_fired))

# Every 3 kills in a row brings the UAV online for 12 seconds.
func add_streak() -> void:
    streak += 1
    if streak % 3 == 0:
        uav_t = UAV_TIME
        mui.popup("UAV ONLINE")
        mui.feed("UAV ONLINE  (%d kill streak)" % streak, Color(1, 0.7, 0))

func bot_fired(p: Vector3) -> void:
    hud.radar_ping(p)

func _uav_tick(dt: float) -> void:
    if uav_t > 0.0:
        uav_t = maxf(0.0, uav_t - dt)
    hud.set_uav(uav_t)
    hud.radar_feed(_enemy_points())

func _enemy_points() -> Array:
    var out: Array = []
    for b in bots:
        if b.alive:
            out.append(b.global_position)
    for pid in Net.remotes:
        var r: RemotePlayer = Net.remotes[pid]
        if r.alive:
            out.append(r.global_position)
    return out


# ---------- maps: Shipment arena or Desert Foundry, picked at random ----------
var map_root: Node3D
var map_id := "shipment"
var active_spawns: Array[Vector2] = []
var active_patrol: Array[Vector2] = []
var world_env: WorldEnvironment
var main_sun: DirectionalLight3D

func pick_map_id() -> String:
    return "desert" if randf() < 0.5 else "shipment"

func _load_map(id: String) -> void:
    if map_root != null:
        remove_child(map_root)
        map_root.free()
    map_id = id
    active_spawns.clear()
    active_patrol.clear()
    if id == "desert":
        var d := DesertFoundryBuilder.new()
        map_root = d
        add_child(d)
        active_spawns.append_array(DesertFoundryBuilder.SPAWN_POINTS)
        active_patrol.append_array(DesertFoundryBuilder.PATROL_WAYPOINTS)
    else:
        map_root = Node3D.new()
        add_child(map_root)
        ArenaBuilder.build(map_root)
        active_spawns.append_array(SPAWNS)
        active_patrol.append_array(SPAWNS)
    _apply_lighting(id)
    if mui != null:
        mui.popup(DesertFoundryBuilder.MAP_NAME if id == "desert" else "SHIPMENT")

# Warm sun-baked light for the desert; the original blue daylight for Shipment.
func _apply_lighting(id: String) -> void:
    if world_env == null or main_sun == null:
        return
    var e: Environment = world_env.environment
    if id == "desert":
        e.background_color = Color(0.86, 0.72, 0.52)
        e.ambient_light_color = Color(0.95, 0.85, 0.70)
        e.fog_light_color = Color(0.95, 0.82, 0.62)
        e.fog_density = 0.006
        main_sun.light_color = Color(1.0, 0.86, 0.62)
        main_sun.light_energy = 1.5
        main_sun.rotation_degrees = Vector3(-48, 28, 0)
    else:
        e.background_color = Color(0.29, 0.66, 1.0)
        e.ambient_light_color = Color(0.82, 0.86, 0.95)
        e.fog_light_color = Color(0.91, 0.85, 0.71)
        e.fog_density = 0.011
        main_sun.light_color = Color(1, 0.89, 0.7)
        main_sun.light_energy = 1.2
        main_sun.rotation_degrees = Vector3(-55, 35, 0)

func start_position() -> Vector3:
    if map_id == "desert" and not active_spawns.is_empty():
        var s: Vector2 = active_spawns[0]
        return Vector3(s.x, ground_height(s.x, s.y) + 0.2, s.y)
    return Vector3(0, 0.2, 28)

# Height of the walkable ground at (x, z). Shipment is flat.
func ground_height(x: float, z: float) -> float:
    if map_id == "desert":
        return DesertFoundryBuilder.ground(x, z)
    return 0.0

func _callout_tick() -> void:
    if mui == null:
        return
    if map_id == "desert" and player != null:
        mui.set_callout(DesertFoundryBuilder.get_callout_name(player.global_position))
    else:
        mui.set_callout("")
