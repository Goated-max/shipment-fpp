class_name Lobby
extends Control
# Bluetooth lobby: one phone taps HOST GAME, the others tap SCAN FOR GAMES and pick its name.

var hud: Hud
var status_lbl: Label
var players_lbl: Label
var name_in: LineEdit
var list_box: VBoxContainer
var scan_btn: Button
var host_btn: Button
var start_btn: Button
var found := {}
var map_box: VBoxContainer
var map_btns := {}
var scanning := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var bg := ColorRect.new()
    bg.color = Color(0.03, 0.07, 0.13, 0.96)
    bg.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var sc := ScrollContainer.new()
    add_child(sc)
    sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 10)
    vb.custom_minimum_size = Vector2(340, 0)
    vb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    sc.add_child(vb)
    _lbl(vb, "BLUETOOTH MULTIPLAYER", 26, Color(1, 0.7, 0))
    status_lbl = _lbl(vb, "One phone taps HOST GAME. The others tap SCAN FOR GAMES and pick its name.", 15, Color(1, 1, 1, 0.8))
    name_in = LineEdit.new()
    name_in.placeholder_text = "Your name"
    name_in.text = "PLAYER"
    name_in.max_length = 12
    name_in.custom_minimum_size = Vector2(340, 46)
    vb.add_child(name_in)
    host_btn = _btn(vb, "HOST GAME", _host)
    scan_btn = _btn(vb, "SCAN FOR GAMES", _scan)
    list_box = VBoxContainer.new()
    list_box.add_theme_constant_override("separation", 6)
    list_box.custom_minimum_size = Vector2(340, 0)
    vb.add_child(list_box)
    players_lbl = _lbl(vb, "", 16, Color(1, 1, 1, 0.9))
    map_box = VBoxContainer.new()
    map_box.add_theme_constant_override("separation", 6)
    vb.add_child(map_box)
    _lbl(map_box, "MAP (host picks)", 16, Color(1, 1, 1, 0.9))
    _map_btn("shipment", "SHIPMENT")
    _map_btn("desert", "DESERT FOUNDRY")
    map_box.hide()
    start_btn = _btn(vb, "START MATCH", _start)
    start_btn.hide()
    _btn(vb, "BACK", _back)
    Net.status.connect(_on_status)
    Net.lobby_changed.connect(_on_lobby)
    Net.device_found.connect(_on_device)
    Net.scan_done.connect(_on_scan_done)
    hide()

func open() -> void:
    show()
    host_btn.visible = not Net.active
    start_btn.visible = Net.is_host and Net.active
    map_box.visible = Net.is_host and Net.active

func _lbl(par: Control, text: String, fs: int, col: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(340, 0)
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    par.add_child(l)
    return l

func _btn(par: Control, text: String, cb: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size = Vector2(340, 52)
    b.add_theme_font_size_override("font_size", 20)
    b.pressed.connect(cb)
    par.add_child(b)
    return b

func _name() -> void:
    var n := name_in.text.strip_edges()
    Net.my_name = n if n != "" else "PLAYER"

func _host() -> void:
    _name()
    Net.host_bt()
    host_btn.hide()
    start_btn.show()
    map_box.show()

func _map_btn(id: String, text: String) -> void:
    var b := _btn(map_box, text, _pick_map.bind(id))
    map_btns[id] = [b, text]
    _refresh_maps()

func _pick_map(id: String) -> void:
    Net.chosen_map = id
    _refresh_maps()

func _refresh_maps() -> void:
    for k in map_btns:
        var v: Array = map_btns[k]
        (v[0] as Button).text = ("> %s <" % v[1]) if k == Net.chosen_map else String(v[1])

func _scan() -> void:
    if scanning:
        Net.scan_stop()
        _scan_stopped()
        status_lbl.text = "Scan stopped."
        return
    for c in list_box.get_children():
        c.queue_free()
    found.clear()
    if Net.scan_start():
        scanning = true
        scan_btn.text = "SCANNING... (tap to stop)"
        status_lbl.text = "Scanning for nearby phones that are hosting..."

func _scan_stopped() -> void:
    scanning = false
    scan_btn.text = "SCAN FOR GAMES"

func _on_scan_done() -> void:
    _scan_stopped()
    if found.is_empty():
        status_lbl.text = "No games found. Ask the host to tap HOST GAME, then scan again."
    else:
        status_lbl.text = "Tap a game to join."

func _on_device(nm: String, addr: String) -> void:
    if found.has(addr):
        return
    found[addr] = true
    _btn(list_box, "%s   (tap to join)" % nm, _join.bind(addr))

func _join(addr: String) -> void:
    _name()
    if scanning:
        Net.scan_stop()
        _scan_stopped()
    for c in list_box.get_children():
        c.queue_free()
    host_btn.hide()
    scan_btn.hide()
    status_lbl.text = "Connecting..."
    Net.join_bt(addr)

func _start() -> void:
    Net.start_match()

func _back() -> void:
    if scanning:
        Net.scan_stop()
        _scan_stopped()
    hide()
    hud.menu.show()

func _on_status(t: String) -> void:
    status_lbl.text = t

func _on_lobby(names: Array) -> void:
    var s := ""
    for n in names:
        s += String(n) + "   "
    players_lbl.text = "Players (%d/4): %s" % [names.size(), s]
