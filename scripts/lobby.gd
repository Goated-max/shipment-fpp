class_name Lobby
extends Control
# Multiplayer screen: Bluetooth (Android) or LAN (desktop/Wi-Fi), host or join, then START.

var hud: Hud
var status_lbl: Label
var players_lbl: Label
var name_in: LineEdit
var ip_in: LineEdit
var dev_box: VBoxContainer
var bt_host_btn: Button
var bt_join_btn: Button
var start_btn: Button

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
    vb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    sc.add_child(vb)
    _lbl(vb, "MULTIPLAYER  ·  FREE FOR ALL", 26, Color(1, 0.7, 0))
    status_lbl = _lbl(vb, "Bluetooth needs the phones paired in Android settings first. LAN needs the same Wi-Fi.", 15, Color(1, 1, 1, 0.8))
    name_in = LineEdit.new()
    name_in.placeholder_text = "Your name"
    name_in.text = "PLAYER"
    name_in.max_length = 12
    name_in.custom_minimum_size = Vector2(340, 46)
    vb.add_child(name_in)
    bt_host_btn = _btn(vb, "HOST BLUETOOTH", _host_bt)
    bt_join_btn = _btn(vb, "JOIN BLUETOOTH", _show_devices)
    dev_box = VBoxContainer.new()
    dev_box.add_theme_constant_override("separation", 6)
    vb.add_child(dev_box)
    ip_in = LineEdit.new()
    ip_in.placeholder_text = "Host IP for LAN, e.g. 192.168.1.20"
    ip_in.custom_minimum_size = Vector2(340, 46)
    vb.add_child(ip_in)
    _btn(vb, "HOST LAN", _host_lan)
    _btn(vb, "JOIN LAN", _join_lan)
    players_lbl = _lbl(vb, "", 16, Color(1, 1, 1, 0.9))
    start_btn = _btn(vb, "START MATCH", _start)
    start_btn.hide()
    _btn(vb, "BACK", _back)
    bt_host_btn.visible = Net.has_bt()
    bt_join_btn.visible = Net.has_bt()
    Net.status.connect(_on_status)
    Net.lobby_changed.connect(_on_lobby)
    hide()

func open() -> void:
    show()
    start_btn.visible = Net.is_host and Net.active

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

func _host_bt() -> void:
    _name()
    Net.host_bt()
    start_btn.show()

func _show_devices() -> void:
    for c in dev_box.get_children():
        c.queue_free()
    var devs := Net.bt_devices()
    if devs.is_empty():
        _lbl(dev_box, "No paired devices found. Pair the other phone in Android Bluetooth settings first.", 14, Color(1, 1, 1, 0.8))
        return
    for d in devs:
        var parts := String(d).split("|")
        if parts.size() < 2:
            continue
        _btn(dev_box, parts[0], _join_bt.bind(parts[1]))

func _join_bt(addr: String) -> void:
    _name()
    Net.join_bt(addr)
    start_btn.hide()

func _host_lan() -> void:
    _name()
    Net.host_lan()
    start_btn.show()

func _join_lan() -> void:
    _name()
    Net.join_lan(ip_in.text.strip_edges())
    start_btn.hide()

func _start() -> void:
    Net.start_match()

func _back() -> void:
    hide()
    hud.menu.show()

func _on_status(t: String) -> void:
    status_lbl.text = t

func _on_lobby(names: Array) -> void:
    var s := ""
    for n in names:
        s += String(n) + "   "
    players_lbl.text = "Players (%d/4): %s" % [names.size(), s]
