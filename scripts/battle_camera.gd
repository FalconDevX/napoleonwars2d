class_name BattleCamera
extends Camera2D
## Kamera RTS: kółko = zoom do kursora, WASD/strzałki lub środkowy przycisk = przesuwanie.

var min_zoom := 0.12
const MAX_ZOOM := 6.0
const PAN_SPEED := 800.0

var map_size := Vector2(6000, 4000)
var target_zoom := 0.32
var zoom_anchor := Vector2.ZERO
var mid_drag := false
var _shake := 0.0


func shake(world_pos: Vector2, power: float) -> void:
	## Wstrząs od wystrzału/wybuchu/szarży — tylko gdy dzieje się to w kadrze i z bliska.
	var vs := get_viewport_rect().size
	var half := vs * 0.5 / zoom.x
	var d := (world_pos - position).abs()
	if d.x > half.x * 1.1 or d.y > half.y * 1.1:
		return
	_shake = minf(maxf(_shake, power * clampf(zoom.x * 1.2, 0.0, 1.6)), 7.0)


func set_zoom_instant(z: float) -> void:
	target_zoom = z
	zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = minf(target_zoom * 1.2, MAX_ZOOM)
			zoom_anchor = mb.position
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = maxf(target_zoom / 1.2, min_zoom)
			zoom_anchor = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			mid_drag = mb.pressed
	elif event is InputEventMouseMotion and mid_drag:
		position -= (event as InputEventMouseMotion).relative / zoom.x


func _process(delta: float) -> void:
	var vs := get_viewport_rect().size
	if _shake > 0.02:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake / maxf(zoom.x, 0.05)
		_shake *= exp(-9.0 * delta)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
		_shake = 0.0
	if absf(zoom.x - target_zoom) > 0.0001:
		var before := _screen_to_world(zoom_anchor, vs)
		var nz := exp(lerpf(log(zoom.x), log(target_zoom), 1.0 - exp(-14.0 * delta)))
		zoom = Vector2(nz, nz)
		position += before - _screen_to_world(zoom_anchor, vs)

	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	position += dir.normalized() * PAN_SPEED * delta / zoom.x
	position = position.clamp(Vector2.ZERO, map_size)


func _screen_to_world(sp: Vector2, vs: Vector2) -> Vector2:
	return position + (sp - vs * 0.5) / zoom.x
