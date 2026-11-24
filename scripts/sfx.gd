class_name Sfx
extends RefCounted

# Tiny procedural sound generator (sine sweep + noise, decaying envelope).
static func make(f0: float, f1: float, dur: float, noise: float, vol: float) -> AudioStreamWAV:
    var rate := 22050
    var n := int(dur * rate)
    var data := PackedByteArray()
    data.resize(n * 2)
    var ph := 0.0
    for i in n:
        var k := float(i) / float(n)
        ph += TAU * lerpf(f0, f1, k) / float(rate)
        var env := (1.0 - k) * (1.0 - k)
        var s := (sin(ph) * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise) * env * vol
        data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
    var w := AudioStreamWAV.new()
    w.format = AudioStreamWAV.FORMAT_16_BITS
    w.mix_rate = rate
    w.data = data
    return w
