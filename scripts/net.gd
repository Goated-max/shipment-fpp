

extends Node
# Free-for-all networking for Shipment FPP.
#  - Android: Bluetooth Classic (RFCOMM) through the ShipmentBt plugin (up to 4 phones).
#  - Desktop/LAN: TCP on port 7788, for testing with two game windows or two PCs.
# The host (player id 1) owns HP, kills, deaths and respawns. Clients send their own
# position and fire claims; the host validates and broadcasts the world at 15 Hz.

signal status(text: String)
signal lobby_changed(names: Array)
signal started
signal host_lost
signal match_ended(name: String)
signal device_found(name: String, addr: String)
signal scan_done
const PORT := 7788
const TICK := 1.0 / 15.0
const MAX_PLAYERS := 4
const KILL_LIMIT := 15
const REGEN_DELAY := 3.5
const COLORS := [Color(0.3, 0.55, 0.3), Color(0.2, 0.4, 0.8), Color(0.8, 0.45, 0.15), Color(0.6, 0.25, 0.6)]

var main: Main
var bt: Object = null
var backend := ""            # "bt" or "tcp"
var active := false
var in_match := false
var is_host := false
var my_id := 0
var my_name := "PLAYER"
var pl: Dictionary = {}      # pid -> player dict (host owns it, clients mirror the world)
var remotes: Dictionary = {} # pid -> RemotePlayer
var pid_of: Dictionary = {}  # link -> pid (host)
var link_of: Dictionary = {} # pid -> link (host)
var host_link := -1
var links: Dictionary = {}   # tcp link -> {"tcp": StreamPeerTCP, "open": bool}
var rbuf: Dictionary = {}    # link -> pending received bytes
var tcp_server: TCPServer = null
var next_link := 100
var _acc := 0.0
var _respawn_lock := 0.0
var _end_t := 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if OS.get_name() == "Android":
        OS.request_permissions()
    if Engine.has_singleton("ShipmentBt"):
        bt = Engine.get_singleton("ShipmentBt")
        bt.connect("peer_connected", _on_bt_connected)
        bt.connect("peer_disconnected", _on_link_down)
        bt.connect("data_received", _on_bt_data)
        bt.connect("bt_error", _on_bt_error)
        bt.connect("device_found", _on_bt_device)
        bt.connect("scan_finished", _on_bt_scan_done)
func has_bt() -> bool:
    return bt != null and bool(bt.call("is_enabled"))

func bt_devices() -> Array:
    if bt == null:
        return []
    return bt.call("paired_devices")

# ---------- session setup ----------
func scan_start() -> bool:
    if bt == null:
        status.emit("Bluetooth plugin missing from this build. Rebuild the APK.")
        return false
    if not bool(bt.call("is_enabled")):
        status.emit("Turn Bluetooth on first.")
        return false
    return bool(bt.call("scan_start"))

func host_bt() -> void:
    if bt == null:
        status.emit("Bluetooth plugin missing from this build. Rebuild the APK.")
        return
    reset()
    is_host = true
    backend = "bt"
    bt.call("host", MAX_PLAYERS - 1)
    status.emit("You are visible for 5 minutes. Friends: tap SCAN FOR GAMES and pick this phone's name.")
    _begin_host()

func join_bt(addr: String) -> void:
    reset()
    backend = "bt"
    active = true
    scan_stop()
    status.emit("Connecting...")
    bt.call("join", addr)

func scan_start() -> bool:
    if bt == null:
        status.emit("Bluetooth is not available on this device.")
        return false
    return bool(bt.call("scan_start"))

func scan_stop() -> void:
    if bt != null:
        bt.call("scan_stop")

func _on_bt_device(nm: String, addr: String) -> void:
    device_found.emit(nm, addr)

func _on_bt_scan_done() -> void:
    scan_done.emit()

func _begin_host() -> void:
    active = true
    is_host = true
    my_id = 1
    pl = {1: _new_player(my_name)}
    _emit_lobby()

func start_match() -> void:
    if not is_host or in_match:
        return
    in_match = true
    _end_t = 0.0
    _reset_scores()
    _bcast({"k": "start"})
    started.emit()

func reset() -> void:
    for lk in links.keys():
        (links[lk]["tcp"] as StreamPeerTCP).disconnect_from_host()
    links.clear()
    if tcp_server != null:
        tcp_server.stop()
        tcp_server = null
    if backend == "bt" and bt != null:
        bt.call("stop")
    backend = ""
    active = false
    in_match = false
    is_host = false
    my_id = 0
    pl = {}
    pid_of = {}
    link_of = {}
    host_link = -1
    rbuf = {}
    _end_t = 0.0
    _respawn_lock = 0.0
    for pid in remotes.keys():
        remotes[pid].queue_free()
    remotes = {}
    if main != null:
        main.set_board("")

# ---------- gameplay requests ----------
func request_hit(target: int, zone: String) -> void:
    if not in_match:
        return
    var dmg := 48.0 if zone == "head" else 24.0
    if is_host:
        _apply_hit(my_id, target, dmg)
    else:
        _send(host_link, {"k": "hit", "t": target, "dmg": dmg})

func request_respawn(p: Vector3) -> void:
    if not active:
        return
    _respawn_lock = 0.6
    if is_host:
        _apply_respawn(my_id, p)
    else:
        _send(host_link, {"k": "resp", "p": p})

func respawn_locked() -> bool:
    return _respawn_lock > 0.0

# ---------- frame loop ----------
func _process(dt: float) -> void:
    if not active:
        return
    if _respawn_lock > 0.0:
        _respawn_lock -= dt
    if is_host and in_match:
        var now := _now()
        if _end_t > 0.0:
            _end_t -= dt
            if _end_t <= 0.0:
                _reset_scores()
        for pid in pl:
            var E: Dictionary = pl[pid]
            if not E["d"] and E["hp"] < 100.0 and now - E["lh"] > REGEN_DELAY:
                E["hp"] = minf(100.0, E["hp"] + 25.0 * dt)
        _update_self()
    _acc += dt
    if _acc >= TICK:
        _acc = 0.0
        if in_match:
            if is_host:
                _send_world()
            else:
                _send_state()

func _update_self() -> void:
    var me := main.player
    if me == null or not pl.has(my_id):
        return
    var E: Dictionary = pl[my_id]
    E["p"] = me.global_position
    E["y"] = me.yaw
    E["pt"] = me.pitch
    E["c"] = me.crouch
    E["s"] = me.sprint
    E["a"] = me.ads

func _send_state() -> void:
    var me := main.player
    if me == null or host_link < 0:
        return
    _send(host_link, {"k": "st", "p": me.global_position, "y": me.yaw, "pt": me.pitch, "c": me.crouch, "s": me.sprint, "a": me.ads})

func _send_world() -> void:
    var w := {"k": "world", "pl": _world_dict()}
    _bcast(w)
    _apply_world(w["pl"])

func _world_dict() -> Dictionary:
    var out := {}
    for pid in pl:
        var E: Dictionary = pl[pid]
        out[pid] = {"n": E["n"], "p": E["p"], "y": E["y"], "pt": E["pt"], "c": E["c"], "s": E["s"], "a": E["a"], "hp": E["hp"], "k": E["k"], "d": E["d"]}
    return out

# Applies a world snapshot locally: updates my own HP/death/kills and the remote figures.
func _apply_world(d: Dictionary) -> void:
    if not is_host:
        pl = d
    for pid in d:
        var E: Dictionary = d[pid]
        if pid == my_id:
            main.sync_local(E["hp"], E["d"], E["k"])
            continue
        if not remotes.has(pid):
            _spawn_remote(pid, E["p"])
        remotes[pid].set_target(E["p"], E["y"], E["pt"], E["a"], E["d"], E["n"], E["k"])
    for pid in remotes.keys():
        if pid == my_id or not d.has(pid):
            remotes[pid].queue_free()
            remotes.erase(pid)
    main.set_board(_board_text(d))

func _spawn_remote(pid: int, p: Vector3) -> void:
    var rp := RemotePlayer.new()
    rp.pid = pid
    main.add_child(rp)
    rp.setup(COLORS[pid % COLORS.size()])
    rp.snap(p)
    remotes[pid] = rp

func _board_text(d: Dictionary) -> String:
    var rows: Array = []
    for pid in d:
        rows.append([d[pid]["k"], d[pid]["n"], pid])
    rows.sort_custom(func(a, b): return a[0] > b[0])
    var s := "SCORE  (first to %d)\n" % KILL_LIMIT
    for r in rows:
        s += "%s  %d%s\n" % [r[1], r[0], "  (you)" if r[2] == my_id else ""]
    return s

# ---------- host-side rules ----------
func _apply_hit(shooter: int, target: int, dmg: float) -> void:
    if not in_match or _end_t > 0.0 or not pl.has(shooter) or not pl.has(target) or shooter == target:
        return
    var S: Dictionary = pl[shooter]
    var T: Dictionary = pl[target]
    if S["d"] or T["d"]:
        return
    T["hp"] = maxf(0.0, T["hp"] - clampf(dmg, 0.0, 60.0))
    T["lh"] = _now()
    if T["hp"] <= 0.0:
        T["d"] = true
        S["k"] += 1
        var p: Vector3 = T["p"]
        _bcast({"k": "kill", "a": shooter, "v": target, "p": p})
        _on_kill(shooter, target, p)
        if S["k"] >= KILL_LIMIT:
            _end_match(shooter)

func _apply_respawn(pid: int, p: Vector3) -> void:
    if not pl.has(pid):
        return
    var E: Dictionary = pl[pid]
    E["d"] = false
    E["hp"] = 100.0
    E["lh"] = _now()
    E["p"] = p

func _end_match(winner: int) -> void:
    _end_t = 8.0
    var nm: String = pl[winner]["n"]
    _bcast({"k": "end", "w": nm})
    match_ended.emit(nm)

func _reset_scores() -> void:
    var now := _now()
    for pid in pl:
        var E: Dictionary = pl[pid]
        E["k"] = 0
        E["hp"] = 100.0
        E["d"] = false
        E["lh"] = now

func _take_state(pid: int, m: Dictionary) -> void:
    var E: Dictionary = pl[pid]
    var p = m.get("p")
    if p is Vector3:
        E["p"] = p
    E["y"] = float(m.get("y", 0.0))
    E["pt"] = float(m.get("pt", 0.0))
    E["c"] = bool(m.get("c", false))
    E["s"] = bool(m.get("s", false))
    E["a"] = bool(m.get("a", false))

func _on_kill(a: int, _v: int, p: Vector3) -> void:
    main.drop_at(p)
    if a == my_id:
        main.on_my_kill()

# ---------- messages ----------
func _on_msg(link: int, m: Dictionary) -> void:
    var k: String = m.get("k", "")
    if is_host:
        if not pid_of.has(link):
            return
        var pid: int = pid_of[link]
        match k:
            "hi":
                var E: Dictionary = pl[pid]
                E["n"] = String(m.get("n", "P")).left(12)
                _emit_lobby()
            "st":
                if in_match and pl.has(pid):
                    _take_state(pid, m)
            "hit":
                _apply_hit(pid, int(m.get("t", 0)), float(m.get("dmg", 0.0)))
            "resp":
                _apply_respawn(pid, m.get("p", Vector3.ZERO))
    else:
        match k:
            "welcome":
                my_id = int(m.get("id", 0))
                status.emit("Joined. Waiting for the host to start...")
            "lobby":
                lobby_changed.emit(m.get("names", []))
            "start":
                in_match = true
                status.emit("Match started!")
                started.emit()
            "world":
                _apply_world(m.get("pl", {}))
            "kill":
                _on_kill(int(m.get("a", 0)), int(m.get("v", 0)), m.get("p", Vector3.ZERO))
            "end":
                match_ended.emit(String(m.get("w", "")))

func _emit_lobby() -> void:
    var names: Array = []
    for pid in pl:
        names.append(pl[pid]["n"])
    lobby_changed.emit(names)
    if is_host:
        _bcast({"k": "lobby", "names": names})

# ---------- links ----------
func _on_link_up(link: int) -> void:
    if is_host:
        if pid_of.size() >= MAX_PLAYERS - 1:
            _close_link(link)
            return
        var slot := 2
        while link_of.has(slot):
            slot += 1
        pid_of[link] = slot
        link_of[slot] = link
        pl[slot] = _new_player("P%d" % slot)
        _send(link, {"k": "welcome", "id": slot})
        _emit_lobby()
    else:
        host_link = link
        _send(link, {"k": "hi", "n": my_name})
        status.emit("Connected. Waiting for the host to start...")

func _on_link_down(link: int) -> void:
    rbuf.erase(link)
    if links.has(link):
        (links[link]["tcp"] as StreamPeerTCP).disconnect_from_host()
        links.erase(link)
    if is_host:
        if pid_of.has(link):
            var pid: int = pid_of[link]
            pid_of.erase(link)
            link_of.erase(pid)
            pl.erase(pid)
            _emit_lobby()
    elif link == host_link and active:
        status.emit("Host disconnected.")
        active = false
        host_lost.emit()

func _close_link(link: int) -> void:
    if backend == "bt":
        bt.call("close_peer", link)
    elif links.has(link):
        (links[link]["tcp"] as StreamPeerTCP).disconnect_from_host()
        links.erase(link)

func _on_bt_connected(id: int, _addr: String) -> void:
    _on_link_up(id)

func _on_bt_data(id: int, b64: String) -> void:
    _feed(id, Marshalls.base64_to_raw(b64))

func _on_bt_error(msg: String) -> void:
    status.emit(msg)

# ---------- framing: [u32 length][var_to_bytes payload] ----------
func _send(link: int, msg: Dictionary) -> void:
    var payload: PackedByteArray = var_to_bytes(msg)
    var frame := PackedByteArray()
    frame.resize(4)
    frame.encode_u32(0, payload.size())
    frame.append_array(payload)
    if backend == "bt":
        if bt != null:
            bt.call("send", link, Marshalls.raw_to_base64(frame))
    elif links.has(link):
        var sp: StreamPeerTCP = links[link]["tcp"]
        if sp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            sp.put_data(frame)

func _bcast(msg: Dictionary) -> void:
    if not is_host:
        return
    for lk in pid_of.keys():
        _send(lk, msg)

func _feed(link: int, bytes: PackedByteArray) -> void:
    var buf: PackedByteArray = rbuf.get(link, PackedByteArray())
    buf.append_array(bytes)
    while buf.size() >= 4:
        var n := buf.decode_u32(0)
        if buf.size() < 4 + n:
            break
        var msg = bytes_to_var(buf.slice(4, 4 + n))
        buf = buf.slice(4 + n)
        if msg is Dictionary:
            _on_msg(link, msg)
    rbuf[link] = buf

func _tcp_poll() -> void:
    if tcp_server != null and tcp_server.is_connection_available():
        var acc := tcp_server.take_connection()
        var nl := next_link
        next_link += 1
        links[nl] = {"tcp": acc, "open": true}
        _on_link_up(nl)
    for lk in links.keys():
        if not links.has(lk):
            continue
        var rec: Dictionary = links[lk]
        var sp: StreamPeerTCP = rec["tcp"]
        sp.poll()
        var stt := sp.get_status()
        if not rec["open"]:
            if stt == StreamPeerTCP.STATUS_CONNECTED:
                rec["open"] = true
                _on_link_up(lk)
            elif stt != StreamPeerTCP.STATUS_CONNECTING:
                status.emit("Could not reach the host.")
                _on_link_down(lk)
            continue
        if stt != StreamPeerTCP.STATUS_CONNECTED:
            _on_link_down(lk)
            continue
        var avail := sp.get_available_bytes()
        if avail > 0:
            var r: Array = sp.get_data(avail)
            if r[0] == OK:
                _feed(lk, r[1])

func _new_player(n: String) -> Dictionary:
    return {"n": n, "p": Vector3.ZERO, "y": 0.0, "pt": 0.0, "c": false, "s": false, "a": false, "hp": 100.0, "k": 0, "d": false, "lh": 0.0}

func _now() -> float:
    return Time.get_ticks_msec() / 1000.0

func _lan_ip() -> String:
    for a in IP.get_local_addresses():
        if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
            return a
    return "127.0.0.1"
