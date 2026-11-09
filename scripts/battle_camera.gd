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
