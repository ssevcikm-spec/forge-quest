extends Area2D
## Hráč: pohyb klávesnicí, kolize s předměty řeší sama scéna.
##
## Záměrně nepoužívá vstupní akce z project.godot – pohyb se čte přímo
## z kláves, takže se projekt dá celý vygenerovat textem a nic se nerozbije
## chybějící definicí akce.

signal collected(what: String)

const SPEED := 130.0

var velocity := Vector2.ZERO
var level: Node2D
var dotyk_smer: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	shape.shape = rect
	add_child(shape)
	# Mapa (když je) rozhoduje, kudy se dá chodit. Hledá se ve skupině, takže
	# na sobě hráč a mapa nejsou závislí jménem uzlu.
	level = get_tree().get_first_node_in_group("level")


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	dir += dotyk_smer
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
	position = _step(position + velocity * delta)
	# drž hráče v obrazovce
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, 8.0, vp.x - 8.0)
	position.y = clampf(position.y, 8.0, vp.y - 8.0)


func _step(target: Vector2) -> Vector2:
	"""Posun se zdi: když je cíl ve zdi, zkusí se projet po jedné ose (klouzání).
	Bez mapy se chodí volně – hra musí být hratelná i před vygenerováním úrovně."""
	if level == null or not level.has_method("is_walkable_at"):
		return target
	if level.is_walkable_at(target):
		return target
	if level.is_walkable_at(Vector2(target.x, position.y)):
		return Vector2(target.x, position.y)
	if level.is_walkable_at(Vector2(position.x, target.y)):
		return Vector2(position.x, target.y)
	return position

# GameForge: overeno AI
