extends Area2D
## Hráč: pohyb klávesnicí, kolize s předměty řeší sama scéna.
##
## Záměrně nepoužívá vstupní akce z project.godot – pohyb se čte přímo
## z kláves, takže se projekt dá celý vygenerovat textem a nic se nerozbije
## chybějící definicí akce.

signal collected(what: String)

const SPEED := 130.0

var velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	shape.shape = rect
	add_child(shape)


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	velocity = dir * SPEED
	position += velocity * delta
	# drž hráče v obrazovce
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 8.0, vp.x - 8.0)
	position.y = clampf(position.y, 8.0, vp.y - 8.0)

# GameForge: overeno AI
