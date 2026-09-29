extends RefCounted
## Opciones de la próxima partida del motor nuevo. Las llena la pantalla
## "Nueva partida" (game/scenes/Setup) y las lee Match al arrancar. Vacías =
## partida por defecto (británicos contra la IA franca).

const DEFAULT_SLOTS := [{"civ": "britones", "team": 0}, {"civ": "francos", "team": 1, "ai": true}]
const DEFAULT_SEED := 1234

## [{civ, team, ai}], el índice es el id del jugador; el 0 es el humano local.
static var slots: Array = []
static var map_seed := DEFAULT_SEED
## 0 = sin tope de población.
static var pop_max := 0
static var lake := true


static func active_slots() -> Array:
	return slots if not slots.is_empty() else DEFAULT_SLOTS


static func reset() -> void:
	slots = []
	map_seed = DEFAULT_SEED
	pop_max = 0
	lake = true
