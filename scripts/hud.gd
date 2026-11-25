class_name Hud
extends CanvasLayer

signal respawn_requested

const IDS := ["jump", "slide", "fire", "fire2", "ads", "reload", "radar", "ammo", "hpw", "kills", "stance"]
const BTN_IDS := ["jump", "slide", "fire", "fire2", "ads", "reload"]
const NAMES := {"jump": "JUMP", "slide": "SLIDE", "fire": "FIRE", "fire2": "FIRE 2", "ads": "ADS", "reload": "RELOAD", "radar": "RADAR", "ammo": "AMMO", "hpw": "HEALTH", "kills": "KILLS", "stance": "STANCE"}
const GLYPH := {"jump": "JUMP", "slide": "SLIDE", "fire": "FIRE", "fire2": "FIRE", "ads": "ADS", "reload": "RLD"}
# id: [width, height, x-anchor (l/r/c), x-offset, y-anchor (t/b/c), y-offset]
const DEF := {
    "radar": [150, 150, "l", 20, "t", 20],
    "fire": [130, 130, "r", 180, "b", 190],
    "fire2": [90, 90, "l", 36, "t", 200],
    "ads": [84, 84, "r", 330, "b", 230],
    "reload": [80, 80, "r", 36, "b", 290],
    "jump": [100, 100, "r", 36, "b", 150],
    "slide": [100, 100, "r", 160, "b", 70],
    "ammo": [190, 44, "r", 30, "b", 10],
    "hpw": [240, 28, "c", 0, "t", 46],
    "kills": [200, 30, "c", 0, "t", 10],
    "stance": [140, 30, "c", 0, "b", 16],
}
const LAYOUT_PATH := "user://hud_layout.cfg"
const R := 70.0

# ---------- small custom-drawn widgets ----------
class TouchBtn extends Control:
    var label := ""
    var down := false
    func set_down(v: bool) -> void:
        if v != down:
            down = v
            queue_redraw()
    func _draw() -> void:
        var c := size * 0.5
        var r := minf(size.x, size.y) * 0.5
        draw_circle(c, r, Color(1, 0.7, 0, 0.55) if down else Color(1, 1, 1, 0.16))
        draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.0)
        var f := ThemeDB.fallback_font
        var fs := int(r * 0.4)
        var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
        draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

class Radar extends Control:
    # Empty sweeping radar frame (no enemy blips).
    var a := 0.0
    func _process(dt: float) -> void:
        a += dt * 2.1
        queue_redraw()
    func _draw() -> void:
        var c := size * 0.5
        var r := size.x * 0.5
        draw_circle(c, r, Color(0.04, 0.12, 0.08, 0.45))
        draw_line(Vector2(c.x, 0), Vector2(c.x, size.y), Color(1, 1, 1, 0.22), 1.0)
        draw_line(Vector2(0, c.y), Vector2(size.x, c.y), Color(1, 1, 1, 0.22), 1.0)
        draw_arc(c, r * 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)
        var pts := PackedVector2Array([c])
        for i in 9:
            var ang := a + float(i) / 8.0
            pts.append(c + Vector2(cos(ang), sin(ang)) * (r - 2.0))
        draw_colored_polygon(pts, Color(0.35, 1.0, 0.6, 0.25))
        draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.75), 2.0)

class Crosshair extends Control:
    var gap := 12.0
    func _draw() -> void:
        var c := size * 0.5
        draw_rect(Rect2(c.x - 1, c.y - gap - 9, 2, 9), Color.WHITE)
        draw_rect(Rect2(c.x - 1, c.y + gap, 2, 9), Color.WHITE)
        draw_rect(Rect2(c.x - gap - 9, c.y - 1, 9, 2), Color.WHITE)
        draw_rect(Rect2(c.x + gap, c.y - 1, 9, 2), Color.WHITE)
        draw_circle(c, 2.5, Color.WHITE)

class Hitmark extends Control:
    var col := Color.WHITE
    func _draw() -> void:
        var c := size * 0.5
        draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), col, 3.0)
        draw_line(c + Vector2(-10, 10), c + Vector2(10, -10), col, 3.0)

class Stick extends Control:
    var on := false
    var origin := Vector2.ZERO
    var knob := Vector2.ZERO
    func _draw() -> void:
        if not on:
            return
        draw_circle(origin, 60.0, Color(1, 1, 1, 0.08))
        draw_arc(origin, 60.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 2.0)
        draw_circle(origin + knob, 25.0, Color(1, 1, 1, 0.35))
        draw_arc(origin + knob, 25.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 2.0)

# ---------- state shared with the player ----------
var player: Player
var mv := Vector2.ZERO
var look := Vector2.ZERO
var lock := false
var firing := false
var sprint_key := false
var sens := 1.0
var hp := 100.0
var stance := "STAND"
var xh_gap := 12.0
var xh_alpha := 1.0
var ev := {"jump": false, "slide": false, "ads": false, "reload": false}

var root: Control
var els := {}
var btns := {}
var outlines := {}
var layout := {}
var fire_state := {"fire": false, "fire2": false}
var touches := {}
var editing := false
var from_menu := false
var sel := ""
var drag_idx := -1
var drag_off := Vector2.ZERO
var stick_idx := -1
var look_idx := -1
var stick_origin := Vector2.ZERO
var tm := 0.0
var flash_v := 0.0
var hit_t := 0.0
var pick_t := 0.0
var _upd := false

var stick: Stick
var xh: Crosshair
var hm: Hitmark
var vig: TextureRect
var lock_lbl: Label
var ammo_lbl: Label
var kills_lbl: Label
var hpn_lbl: Label
var hp_fill: ColorRect
var stance_lbl: Label
var pick_lbl: Label
var edit_btn: Button
var panel: PanelContainer
var sel_lbl: Label
var size_sl: HSlider
var menu: ColorRect
var death: ColorRect
var dk_lbl: Label
var board: Label
var dirhit: DirHit
var lobby: Lobby

# cached values so UI nodes are only touched when something changed
var _c_hp := -1.0
var _c_hpn := -1
var _c_vig := -1.0
var _c_gap := -1.0
var _c_alpha := -1.0
var _c_stance := ""

func _ready() -> void:
    layer = 10
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = Control.new()
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_overlays()
    _build_elements()
    _build_editor()
    _build_menu_death()
    lobby = Lobby.new()
    lobby.hud = self
    root.add_child(lobby)
    _load_layout()
    _apply_all()
    get_viewport().size_changed.connect(_apply_all)
    get_tree().paused = true   # waiting on the menu

# ---------- builders ----------
func _vp() -> Vector2:
    return get_viewport().get_visible_rect().size

func _sb(c: Color, r: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = c
    s.set_corner_radius_all(r)
    return s

func _lbl(par: Control, text: String, fs: int, al: HorizontalAlignment, col := Color.WHITE) -> Label:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = al
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    l.add_theme_color_override("font_shadow_color", Color.BLACK)
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 1)
    par.add_child(l)
    return l

func _reg(id: String, c: Control) -> void:
    var d: Array = DEF[id]
    c.size = Vector2(d[0], d[1])
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(c)
    els[id] = c
    var o := ReferenceRect.new()
    o.editor_only = false
    o.border_color = Color(1, 0.7, 0)
    o.border_width = 1.0
    o.mouse_filter = Control.MOUSE_FILTER_IGNORE
    c.add_child(o)
    o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    o.hide()
    outlines[id] = o

func _build_overlays() -> void:
    var gr := Gradient.new()
    gr.offsets = PackedFloat32Array([0.5, 1.0])
    gr.colors = PackedColorArray([Color(0.82, 0, 0, 0), Color(0.82, 0, 0, 0.85)])
    var gt := GradientTexture2D.new()
    gt.gradient = gr
    gt.fill = GradientTexture2D.FILL_RADIAL
    gt.fill_from = Vector2(0.5, 0.5)
    gt.fill_to = Vector2(1.0, 0.5)
    gt.width = 128
    gt.height = 128
    vig = TextureRect.new()
    vig.texture = gt
    vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    vig.stretch_mode = TextureRect.STRETCH_SCALE
    vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vig.modulate.a = 0.0
    root.add_child(vig)
    vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    xh = Crosshair.new()
    xh.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(xh)
    xh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hm = Hitmark.new()
    hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hm.modulate.a = 0.0
    root.add_child(hm)
    hm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dirhit = DirHit.new()
    dirhit.hud = self
    root.add_child(dirhit)
    dirhit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_elements() -> void:
    for id in BTN_IDS:
        var b := TouchBtn.new()
        b.label = GLYPH[id]
        _reg(id, b)
        btns[id] = b
    _reg("radar", Radar.new())
    var am := Panel.new()
    _reg("ammo", am)
    am.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.4), 22))
    ammo_lbl = _lbl(am, "30 / 120", 22, HORIZONTAL_ALIGNMENT_CENTER)
    ammo_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var hw := Control.new()
    _reg("hpw", hw)
    hpn_lbl = _lbl(hw, "100", 18, HORIZONTAL_ALIGNMENT_LEFT)
    hpn_lbl.position = Vector2(0, 0)
    hpn_lbl.size = Vector2(44, 28)
    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.45)
    bg.position = Vector2(48, 10)
    bg.size = Vector2(190, 8)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hw.add_child(bg)
    hp_fill = ColorRect.new()
    hp_fill.size = Vector2(190, 8)
    hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.add_child(hp_fill)
    var kc := Control.new()
    _reg("kills", kc)
    kills_lbl = _lbl(kc, "KILLS 0", 20, HORIZONTAL_ALIGNMENT_CENTER)
    kills_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var sc := Control.new()
    _reg("stance", sc)
    stance_lbl = _lbl(sc, "STAND", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.8))
    stance_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    stick = Stick.new()
    stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(stick)
    stick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    lock_lbl = _lbl(root, "^ SPRINT LOCK", 16, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.7, 0))
    lock_lbl.size = Vector2(160, 28)
    lock_lbl.hide()
    pick_lbl = _lbl(root, "+30 AMMO", 22, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.82, 0.29))
    pick_lbl.size = Vector2(240, 30)
    pick_lbl.modulate.a = 0.0
    board = _lbl(root, "", 16, HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.9))
    board.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    board.size = Vector2(240, 150)
    board.hide()

func _build_editor() -> void:
    edit_btn = Button.new()
    edit_btn.text = "EDIT HUD"
    edit_btn.focus_mode = Control.FOCUS_NONE
    edit_btn.size = Vector2(110, 38)
    root.add_child(edit_btn)
    edit_btn.pressed.connect(_start_edit.bind(false))
    edit_btn.hide()
    panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(260, 0)
    root.add_child(panel)
    var vb := VBoxContainer.new()
    panel.add_child(vb)
    var t := Label.new()
    t.text = "HUD LAYOUT (game paused)\nDrag any outlined element. Tap one, then use the slider to resize."
    t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    t.custom_minimum_size = Vector2(250, 0)
    vb.add_child(t)
    sel_lbl = Label.new()
    sel_lbl.text = "Selected: NONE"
    vb.add_child(sel_lbl)
    size_sl = HSlider.new()
    size_sl.min_value = 0.5
    size_sl.max_value = 2.0
    size_sl.step = 0.05
    size_sl.value = 1.0
    size_sl.custom_minimum_size = Vector2(0, 34)
    vb.add_child(size_sl)
    size_sl.value_changed.connect(_on_size)
    size_sl.drag_ended.connect(func(_c: bool) -> void: _save_layout())
    var rb := Button.new()
    rb.text = "RESET DEFAULT"
    rb.focus_mode = Control.FOCUS_NONE
    rb.custom_minimum_size = Vector2(0, 46)
    rb.pressed.connect(_reset_layout)
    vb.add_child(rb)
    var db := Button.new()
    db.text = "DONE / SAVE"
    db.focus_mode = Control.FOCUS_NONE
    db.custom_minimum_size = Vector2(0, 46)
    db.pressed.connect(_stop_edit)
    vb.add_child(db)
    panel.hide()

func _overlay(c: Color) -> ColorRect:
    var o := ColorRect.new()
    o.color = c
    o.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(o)
    o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return o

func _center(par: Control) -> VBoxContainer:
    var cc := CenterContainer.new()
    par.add_child(cc)
    cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var vb := VBoxContainer.new()
    vb.alignment = BoxContainer.ALIGNMENT_CENTER
    vb.add_theme_constant_override("separation", 14)
    cc.add_child(vb)
    return vb

func _button_in(box: Control, text: String, cb: Callable) -> void:
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size = Vector2(320, 56)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(cb)
    box.add_child(b)

func _build_menu_death() -> void:
    death = _overlay(Color(0.24, 0.0, 0.0, 0.6))
    var dc := _center(death)
    _lbl(dc, "ELIMINATED", 56, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.23, 0.23))
    dk_lbl = _lbl(dc, "KILLS 0", 24, HORIZONTAL_ALIGNMENT_CENTER)
    _button_in(dc, "RESPAWN", _on_respawn)
    death.hide()
    menu = _overlay(Color(0.03, 0.07, 0.13, 0.92))
    var mc := _center(menu)
    _lbl(mc, "SHIPMENT FPP", 52, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.7, 0))
    _lbl(mc, "Left thumb moves (push past the ring for SPRINT LOCK), right thumb looks.\nHolding FIRE blocks sprint and keeps ADS.\nDesktop: WASD, Shift sprint, Space jump, C slide, R reload, arrows look.", 18, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.75))
    _lbl(mc, "Camera sensitivity", 18, HORIZONTAL_ALIGNMENT_CENTER)
    var ss := HSlider.new()
    ss.min_value = 0.3
    ss.max_value = 2.5
    ss.step = 0.05
    ss.value = 1.0
    ss.custom_minimum_size = Vector2(320, 36)
    ss.value_changed.connect(func(v: float) -> void: sens = v)
    mc.add_child(ss)
    _button_in(mc, "DEPLOY", _deploy)
    _button_in(mc, "CUSTOMIZE HUD LAYOUT", _start_edit.bind(true))
    _button_in(mc, "MULTIPLAYER (BLUETOOTH)", _open_lobby)

# ---------- layout (position + scale per element, saved to user://) ----------
func _rect(id: String) -> Rect2:
    var c: Control = els[id]
    return Rect2(c.position, c.size * c.scale)

func _default_pos(id: String) -> Vector2:
    var d: Array = DEF[id]
    var vp := _vp()
    var w: float = d[0]
    var h: float = d[1]
    var x: float
    var y: float
    match d[2]:
        "l": x = d[3]
        "r": x = vp.x - float(d[3]) - w
        _: x = vp.x * 0.5 - w * 0.5 + float(d[3])
    match d[4]:
        "t": y = d[5]
        "b": y = vp.y - float(d[5]) - h
        _: y = vp.y * 0.5 - h * 0.5 + float(d[5])
    return Vector2(x, y)

func _place(id: String, pos: Vector2, s: float) -> void:
    var c: Control = els[id]
    var vp := _vp()
    s = clampf(s, 0.5, 2.0)
    var sz := c.size * s
    pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - sz.x))
    pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - sz.y))
    c.scale = Vector2(s, s)
    c.position = pos
    layout[id] = {"x": pos.x, "y": pos.y, "s": s}

func _apply_all() -> void:
    var vp := _vp()
    for id in IDS:
        if layout.has(id):
            var l: Dictionary = layout[id]
            _place(id, Vector2(l["x"], l["y"]), l["s"])
        else:
            var c: Control = els[id]
            c.scale = Vector2.ONE
            c.position = _default_pos(id)
    edit_btn.position = Vector2(vp.x - 122.0, 10.0)
    panel.position = Vector2(vp.x - 280.0, 56.0)
    pick_lbl.position = Vector2(vp.x * 0.5 - 120.0, vp.y * 0.62)
    board.position = Vector2(vp.x - 260.0, 100.0)

func _load_layout() -> void:
    var cf := ConfigFile.new()
    if cf.load(LAYOUT_PATH) != OK:
        return
    for id in IDS:
        if cf.has_section(id):
            layout[id] = {"x": float(cf.get_value(id, "x", 0.0)), "y": float(cf.get_value(id, "y", 0.0)), "s": clampf(float(cf.get_value(id, "s", 1.0)), 0.5, 2.0)}

func _save_layout() -> void:
    var cf := ConfigFile.new()
    for id in layout:
        var l: Dictionary = layout[id]
        cf.set_value(id, "x", l["x"])
        cf.set_value(id, "y", l["y"])
        cf.set_value(id, "s", l["s"])
    cf.save(LAYOUT_PATH)

func _reset_layout() -> void:
    layout.clear()
    _save_layout()
    _apply_all()
    if sel != "":
        _select(sel)

# ---------- edit mode (game is paused while editing) ----------
func _start_edit(from_main_menu: bool) -> void:
    editing = true
    from_menu = from_main_menu
    _clear_input()
    menu.hide()
    edit_btn.hide()
    panel.show()
    board.hide()
    sel = ""
    sel_lbl.text = "Selected: NONE"
    for id in IDS:
        (outlines[id] as ReferenceRect).show()
        (outlines[id] as ReferenceRect).border_width = 1.0
    get_tree().paused = true

func _stop_edit() -> void:
    editing = false
    board.visible = board.text != ""
    panel.hide()
    sel = ""
    for id in IDS:
        (outlines[id] as ReferenceRect).hide()
    _save_layout()
    if from_menu:
        menu.show()
    else:
        edit_btn.show()
        get_tree().paused = false

func _select(id: String) -> void:
    sel = id
    for k in IDS:
        (outlines[k] as ReferenceRect).border_width = 4.0 if k == id else 1.0
    sel_lbl.text = "Selected: " + String(NAMES[id])
    _upd = true
    size_sl.value = (els[id] as Control).scale.x
    _upd = false

func _on_size(v: float) -> void:
    if _upd or sel == "":
        return
    _place(sel, (els[sel] as Control).position, v)

func _deploy() -> void:
    menu.hide()
    edit_btn.show()
    get_tree().paused = false

func _on_respawn() -> void:
    death.hide()
    respawn_requested.emit()

# ---------- API used by gameplay code ----------
func take(k: String) -> bool:
    var v: bool = ev[k]
    ev[k] = false
    return v

func set_ammo(m: int, r: int) -> void:
    ammo_lbl.text = "%d / %d" % [m, r]

func set_kills(k: int) -> void:
    kills_lbl.text = "KILLS %d" % k

func hitmark(red: bool) -> void:
    hm.col = Color(1, 0.16, 0.16) if red else Color.WHITE
    hm.queue_redraw()
    hit_t = 0.22
    hm.modulate.a = 1.0

func pick(text: String) -> void:
    pick_lbl.text = text
    pick_t = 1.2
    pick_lbl.modulate.a = 1.0

func flash(v: float) -> void:
    flash_v = v

func show_death(k: int) -> void:
    dk_lbl.text = "KILLS %d" % k
    death.show()
    _clear_input()

func _clear_input() -> void:
    mv = Vector2.ZERO
    look = Vector2.ZERO
    lock = false
    firing = false
    fire_state["fire"] = false
    fire_state["fire2"] = false
    for id in BTN_IDS:
        (btns[id] as TouchBtn).set_down(false)
    for k in ev:
        ev[k] = false
    touches.clear()
    stick_idx = -1
    look_idx = -1
    drag_idx = -1
    stick.on = false
    stick.queue_redraw()
    lock_lbl.hide()

# ---------- input ----------
func _over_ui(pos: Vector2) -> bool:
    if edit_btn.visible and edit_btn.get_global_rect().has_point(pos):
        return true
    if panel.visible and panel.get_global_rect().has_point(pos):
        return true
    return false

func _input(e: InputEvent) -> void:
    if player == null or player.dead:
        return
    if get_tree().paused and not editing:
        return
    var te := e as InputEventScreenTouch
    var de := e as InputEventScreenDrag
    var ke := e as InputEventKey
    if te:
        if te.pressed:
            _down(te.index, te.position)
        else:
            _up(te.index)
    elif de:
        _move(de.index, de.position, de.relative)
    elif ke and ke.pressed and not ke.echo and not editing:
        match ke.keycode:
            KEY_SPACE: ev["jump"] = true
            KEY_C, KEY_CTRL: ev["slide"] = true
            KEY_R: ev["reload"] = true

func _press(id: String, on: bool) -> void:
    (btns[id] as TouchBtn).set_down(on)
    if id == "fire" or id == "fire2":
        fire_state[id] = on
        firing = fire_state["fire"] or fire_state["fire2"]
        if firing:
            lock = false
    elif on:
        ev[id] = true

func _down(idx: int, pos: Vector2) -> void:
    if _over_ui(pos):
        return
    if editing:
        for id in IDS:
            if _rect(id).has_point(pos):
                _select(id)
                drag_idx = idx
                drag_off = pos - (els[id] as Control).position
                return
        return
    for id in BTN_IDS:
        if _rect(id).has_point(pos):
            touches[idx] = id
            _press(id, true)
            if id == "fire" and look_idx == -1:
                look_idx = idx
            return
    if pos.x < _vp().x * 0.45:
        if stick_idx == -1:
            stick_idx = idx
            stick_origin = pos
            stick.on = true
            stick.origin = pos
            stick.knob = Vector2.ZERO
            stick.queue_redraw()
    elif look_idx == -1:
        look_idx = idx

func _move(idx: int, pos: Vector2, rel: Vector2) -> void:
    if editing:
        if idx == drag_idx and sel != "":
            _place(sel, pos - drag_off, (els[sel] as Control).scale.x)
        return
    if idx == stick_idx:
        var d := pos - stick_origin
        var l := d.length()
        var kv := d / maxf(l, 0.001) * minf(l, R)
        var m := Vector2(kv.x / R, -kv.y / R)
        if m.length() < 0.12:
            m = Vector2.ZERO
        mv = m
        var up := -d.y
        var aligned := absf(d.x) < R * 0.9
        if firing:
            lock = false
        elif up > R * 1.35 and aligned:
            lock = true
        elif lock and m.y < 0.35:
            lock = false
        stick.knob = kv
        stick.queue_redraw()
        var show_lock := (not firing) and ((up > R * 0.55 and aligned) or lock)
        lock_lbl.visible = show_lock
        lock_lbl.position = stick_origin + Vector2(-80.0, -R - 52.0)
        lock_lbl.add_theme_color_override("font_color", Color(1, 0.7, 0) if lock else Color(1, 1, 1, 0.85))
    elif idx == look_idx:
        look += rel

func _up(idx: int) -> void:
    if idx == drag_idx:
        drag_idx = -1
        _save_layout()
    if idx == stick_idx:
        stick_idx = -1
        mv = Vector2.ZERO
        lock = false
        stick.on = false
        stick.queue_redraw()
        lock_lbl.hide()
    if idx == look_idx:
        look_idx = -1
    if touches.has(idx):
        _press(touches[idx], false)
        touches.erase(idx)

# ---------- per-frame (all UI writes are change-checked) ----------
func _process(dt: float) -> void:
    tm += dt
    if not get_tree().paused:
        sprint_key = Input.is_key_pressed(KEY_SHIFT)
        if stick_idx == -1:
            var kx := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
            var ky := int(Input.is_key_pressed(KEY_W)) - int(Input.is_key_pressed(KEY_S))
            mv = Vector2(kx, ky).normalized() if (kx != 0 or ky != 0) else Vector2.ZERO
        var lx := int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT))
        var ly := int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP))
        if lx != 0 or ly != 0:
            look += Vector2(lx, ly) * 420.0 * dt
    if hit_t > 0.0:
        hit_t -= dt
        hm.modulate.a = maxf(0.0, hit_t / 0.22)
    if pick_t > 0.0:
        pick_t -= dt
        pick_lbl.modulate.a = clampf(pick_t * 2.0, 0.0, 1.0)
    flash_v = maxf(0.0, flash_v - dt * 2.2)
    var lv := 0.0
    if hp < 50.0:
        lv = (1.0 - hp / 50.0) * (0.5 + 0.3 * sin(tm * 7.0))
    var va := roundf(minf(1.0, lv + flash_v) * 100.0) / 100.0
    if va != _c_vig:
        _c_vig = va
        vig.modulate.a = va
    var hn := ceili(hp)
    if hn != _c_hpn:
        _c_hpn = hn
        hpn_lbl.text = str(hn)
    var hw := roundf(hp * 10.0) / 10.0
    if hw != _c_hp:
        _c_hp = hw
        hp_fill.size.x = 190.0 * hw / 100.0
        hp_fill.color = Color(0.88, 0.16, 0.16) if hp < 50.0 else Color.WHITE
    if stance != _c_stance:
        _c_stance = stance
        stance_lbl.text = stance
    var g := snappedf(xh_gap, 0.1)
    if g != _c_gap or xh_alpha != _c_alpha:
        _c_gap = g
        _c_alpha = xh_alpha
        xh.gap = g
        xh.modulate.a = xh_alpha
        xh.queue_redraw()

func set_board(t: String) -> void:
    board.text = t
    board.visible = t != "" and not editing

func start_match() -> void:
    lobby.hide()
    _deploy()

func _open_lobby() -> void:
    menu.hide()
    lobby.open()


func dir_hit(src: Vector3) -> void:
    dirhit.add(src)

# Red triangles on a ring around the crosshair, pointing toward where damage came from.
class DirHit extends Control:
    var hud: Hud
    var items: Array = []

    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE

    func add(src: Vector3) -> void:
        items.append([src, 1.3])
        if items.size() > 4:
            items.pop_front()

    func _process(dt: float) -> void:
        if items.is_empty():
            return
        for it in items:
            it[1] -= dt
        items = items.filter(func(it): return it[1] > 0.0)
        queue_redraw()

    func _draw() -> void:
        var pl: Player = hud.player
        if pl == null:
            return
        var c := size * 0.5
        var r := minf(size.x, size.y) * 0.4
        var fwd := Vector2(-sin(pl.yaw), -cos(pl.yaw))
        for it in items:
            var d: Vector3 = it[0] - pl.global_position
            var dir := Vector2(d.x, d.z)
            if dir.length() < 0.01:
                continue
            var a := fwd.angle_to(dir.normalized())
            var sd := Vector2(sin(a), -cos(a))
            var col := Color(1.0, 0.15, 0.15, clampf(it[1] / 0.4, 0.0, 1.0) * 0.9)
            var tip := c + sd * (r + 18.0)
            var base := c + sd * r
            var perp := Vector2(-sd.y, sd.x) * 14.0
            draw_colored_polygon(PackedVector2Array([tip, base + perp, base - perp]), col)
