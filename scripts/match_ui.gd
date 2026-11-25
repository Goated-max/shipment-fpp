class_name MatchUI
extends CanvasLayer
# Match timer, killfeed, score popups and the end-of-match summary.

var main: Main
var timer_lbl: Label
var feed_box: VBoxContainer
var popup_lbl: Label
var popup_t := 0.0
var summary: Control
var sum_title: Label
var sum_body: Label

func _ready() -> void:
    layer = 11
    process_mode = Node.PROCESS_MODE_ALWAYS
    var root := Control.new()
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    timer_lbl = _label(root, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(1, 1, 1, 0.9))
    _place(timer_lbl, [0.5, 0.0, 0.5, 0.0], [-170, 80, 170, 112])

    feed_box = VBoxContainer.new()
    feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    feed_box.add_theme_constant_override("separation", 2)
    root.add_child(feed_box)
    _place(feed_box, [1.0, 0.0, 1.0, 0.0], [-340, 56, -10, 56])

    popup_lbl = _label(root, HORIZONTAL_ALIGNMENT_CENTER, 22, Color(1, 0.85, 0.3))
    _place(popup_lbl, [0.5, 0.5, 0.5, 0.5], [-220, 60, 220, 92])
    popup_lbl.modulate.a = 0.0

    summary = _build_summary(root)

func _place(c: Control, anchors: Array, offsets: Array) -> void:
    c.anchor_left = anchors[0]
    c.anchor_top = anchors[1]
    c.anchor_right = anchors[2]
    c.anchor_bottom = anchors[3]
    c.offset_left = offsets[0]
    c.offset_top = offsets[1]
    c.offset_right = offsets[2]
    c.offset_bottom = offsets[3]

func _label(par: Control, align: int, fs: int, col: Color) -> Label:
    var l := Label.new()
    l.horizontal_alignment = align
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    l.add_theme_color_override("font_shadow_color", Color.BLACK)
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 1)
    par.add_child(l)
    return l

func _build_summary(root: Control) -> Control:
    var sv := Control.new()
    sv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    sv.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(sv)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.72)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    sv.add_child(dim)
    var cc := CenterContainer.new()
    cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    sv.add_child(cc)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 16)
    cc.add_child(vb)
    sum_title = _label(vb, HORIZONTAL_ALIGNMENT_CENTER, 40, Color(1, 0.7, 0))
    sum_body = _label(vb, HORIZONTAL_ALIGNMENT_CENTER, 22, Color(1, 1, 1, 0.92))
    sum_body.custom_minimum_size = Vector2(340, 0)
    var b := Button.new()
    b.text = "PLAY AGAIN"
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size = Vector2(320, 60)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(func() -> void: main.reset_match())
    vb.add_child(b)
    sv.hide()
    return sv

func set_timer(t: float, _kills: int, goal: int) -> void:
    var s := int(ceilf(t))
    timer_lbl.text = "%d:%02d    GOAL %d" % [s / 60, s % 60, goal]

func feed(text: String, col := Color(1, 0.8, 0.3)) -> void:
    var l := _label(feed_box, HORIZONTAL_ALIGNMENT_RIGHT, 15, col)
    if feed_box.get_child_count() > 5:
        var old := feed_box.get_child(0)
        feed_box.remove_child(old)
        old.queue_free()
    var tw := l.create_tween()
    tw.tween_interval(3.0)
    tw.tween_property(l, "modulate:a", 0.0, 0.6)
    tw.tween_callback(l.queue_free)

func clear_feed() -> void:
    for c in feed_box.get_children():
        feed_box.remove_child(c)
        c.queue_free()

func popup(text: String) -> void:
    popup_lbl.text = text
    popup_lbl.modulate.a = 1.0
    popup_t = 1.2

func show_summary(reason: String, k: int, d: int, h: int, s: int, t: String) -> void:
    sum_title.text = reason
    sum_body.text = "KILLS      %d\nDEATHS      %d\nHEADSHOTS      %d\nSCORE      %d\nTIME      %s" % [k, d, h, s, t]
    summary.show()

func hide_summary() -> void:
    summary.hide()

func _process(dt: float) -> void:
    if popup_t > 0.0:
        popup_t -= dt
        popup_lbl.modulate.a = clampf(popup_t / 0.4, 0.0, 1.0)
