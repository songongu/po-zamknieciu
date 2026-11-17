extends Node
## Proceduralnie generowane dźwięki (bez zewnętrznych plików).

const R := 22050
var s := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1234
	s["drone"] = _wav(_drone(), true)
	s["hum"] = _wav(_hum(), true)
	s["buzz"] = _wav(_buzz(), true)
	s["heart"] = _wav(_heart())
	s["step"] = _wav(_step())
	s["pickup"] = _wav(_bells([523.25, 659.25, 783.99, 1046.5], 0.08, 1.0))
	s["battery"] = _wav(_bells([392.0, 587.33], 0.07, 0.6))
	s["chime"] = _wav(_chime())
	s["screech"] = _wav(_screech())
	s["creak"] = _wav(_creak())
	s["whisper"] = _wav(_whisper())
	s["click"] = _wav(_click())
	s["locked"] = _wav(_locked())
	s["win"] = _wav(_bells([261.63, 329.63, 392.0, 523.25, 659.25, 783.99], 0.15, 2.5))


func _wav(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(buf.size() * 2)
	for i in buf.size():
		b.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = R
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * R))
	return b


func _saw(x: float) -> float:
	return 2.0 * (x - floor(x)) - 1.0


func _drone() -> PackedFloat32Array:
	var b := _buf(8.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / R
		var v := 0.0
		v += sin(TAU * 55.0 * t) * (0.5 + 0.5 * sin(TAU * 0.125 * t)) * 0.25
		v += sin(TAU * 55.375 * t) * 0.2
		v += sin(TAU * 82.5 * t) * 0.12 * (0.5 + 0.5 * sin(TAU * 0.25 * t + 1.0))
		v += sin(TAU * 110.25 * t + sin(TAU * 0.5 * t) * 2.0) * 0.06
		v += sin(TAU * 233.125 * t) * 0.03 * (0.5 + 0.5 * sin(TAU * 0.375 * t))
		lp += (rng.randf() * 2.0 - 1.0 - lp) * 0.02
		v += lp * 0.7 * (0.6 + 0.4 * sin(TAU * 0.125 * t))
		b[i] = v * 0.7
	return b


func _hum() -> PackedFloat32Array:
	var b := _buf(1.0)
	for i in b.size():
		var t := float(i) / R
		var v := sin(TAU * 50.0 * t) * 0.3 + sin(TAU * 100.0 * t) * 0.25 + signf(sin(TAU * 100.0 * t)) * 0.05 + sin(TAU * 150.0 * t) * 0.1
		b[i] = v * 0.5 + (rng.randf() - 0.5) * 0.02
	return b


func _buzz() -> PackedFloat32Array:
	var b := _buf(2.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / R
		var v := _saw(41.0 * t) * 0.35 + sin(TAU * 61.5 * t) * 0.3 + _saw(82.5 * t) * 0.1
		lp += (v - lp) * 0.15
		b[i] = lp * (0.55 + 0.45 * sin(TAU * 3.0 * t)) * 0.9
	return b


func _heart() -> PackedFloat32Array:
	var b := _buf(0.7)
	for i in b.size():
		var t := float(i) / R
		var v := 0.0
		for off in [0.0, 0.22]:
			var tt: float = t - off
			if tt >= 0.0:
				v += sin(TAU * (60.0 - 25.0 * tt) * tt) * exp(-tt * 16.0) * (1.0 if off == 0.0 else 0.7)
		b[i] = v * 0.9
	return b


func _step() -> PackedFloat32Array:
	var b := _buf(0.14)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / R
		lp += (rng.randf() * 2.0 - 1.0 - lp) * 0.18
		b[i] = (lp * 1.6 + sin(TAU * 90.0 * t) * 0.3) * exp(-t * 35.0)
	return b


func _bells(notes: Array, gap: float, length: float) -> PackedFloat32Array:
	var b := _buf(length + gap * notes.size())
	for i in b.size():
		var t := float(i) / R
		var v := 0.0
		for n in notes.size():
			var tt: float = t - n * gap
			if tt >= 0.0:
				var f: float = notes[n]
				v += (sin(TAU * f * tt) + 0.3 * sin(TAU * f * 2.76 * tt)) * exp(-tt * 4.0) * 0.22
		b[i] = v
	return b


func _chime() -> PackedFloat32Array:
	var notes := [659.25, 523.25, 392.0, 523.25]
	var b := _buf(3.2)
	for i in b.size():
		var t := float(i) / R
		var v := 0.0
		for n in notes.size():
			var tt: float = t - n * 0.55
			if tt >= 0.0:
				var f: float = notes[n] * (1.0 + 0.006 * sin(TAU * 5.0 * tt))
				v += (sin(TAU * f * tt) + 0.25 * sin(TAU * f * 2.0 * tt)) * exp(-tt * 2.2) * 0.3
		b[i] = v
	return b


func _screech() -> PackedFloat32Array:
	var b := _buf(1.4)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / R
		var f := 220.0 * pow(8.0, minf(t / 0.5, 1.0)) * (1.0 + 0.08 * sin(TAU * 27.0 * t))
		ph += f / R
		lp += (rng.randf() * 2.0 - 1.0 - lp) * 0.5
		var v := _saw(ph) * 0.6 + _saw(ph * 1.51) * 0.3 + lp * 0.7
		v += sin(TAU * 45.0 * t) * exp(-t * 6.0) * 1.2
		var env := minf(t / 0.015, 1.0) * exp(-t * 1.8)
		b[i] = tanh(v * 2.5) * env * 0.85
	return b


func _creak() -> PackedFloat32Array:
	var b := _buf(0.6)
	var ph := 0.0
	var last := -1.0
	for i in b.size():
		var t := float(i) / R
		var rate := 18.0 + 70.0 * t
		ph += rate / R
		if ph >= 1.0:
			ph -= 1.0
			last = t
		var v := 0.0
		if last >= 0.0:
			var dt := t - last
			v = sin(TAU * (700.0 + rng.randf() * 80.0) * dt) * exp(-dt * 260.0)
		b[i] = v * 0.7 * sin(PI * t / 0.6)
	return b


func _whisper() -> PackedFloat32Array:
	var b := _buf(2.6)
	var lp1 := 0.0
	var lp2 := 0.0
	var syl := [0.6, 1.0, 0.4, 0.9, 0.7, 1.0, 0.5, 0.8, 0.3]
	for i in b.size():
		var t := float(i) / R
		var n := rng.randf() * 2.0 - 1.0
		lp1 += (n - lp1) * 0.5
		lp2 += (n - lp2) * 0.08
		var band := lp1 - lp2
		var k := int(t * 3.4) % syl.size()
		var env := pow(absf(sin(TAU * 1.7 * t)), 2.0) * float(syl[k]) * sin(PI * t / 2.6)
		b[i] = band * env * 1.1
	return b


func _click() -> PackedFloat32Array:
	var b := _buf(0.06)
	for i in b.size():
		var t := float(i) / R
		b[i] = sin(TAU * 2200.0 * t) * exp(-t * 120.0) * 0.6 + (rng.randf() - 0.5) * exp(-t * 200.0)
	return b


func _locked() -> PackedFloat32Array:
	var b := _buf(0.6)
	for i in b.size():
		var t := float(i) / R
		var v := 0.0
		for off in [0.0, 0.12, 0.24]:
			var tt: float = t - off
			if tt >= 0.0:
				v += (sin(TAU * 180.0 * tt) * 0.5 + (rng.randf() - 0.5)) * exp(-tt * 40.0)
		b[i] = v * 0.7
	return b
