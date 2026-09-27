# F0 — Registry de datos + World de simulación: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear el núcleo del motor nuevo (`engine/data` + `engine/sim`) y migrar todo el contenido de `data/` a `mods/aoe2_base` en formato de habilidades, sin tocar el juego viejo.

**Architecture:** `engine/data` carga mods (herencia `extends`, parches `patch`, validación estricta por esquema, `content_hash`) y ofrece una vista parcheada por jugador (`PlayerDefs`). `engine/sim` aporta punto fijo, `SpatialHash` y `World` (estado único con componentes por habilidad). Un script Python migra `data/` → `mods/aoe2_base`. Nada de esto se engancha todavía al juego (autoloads intactos); F1 lo conectará.

**Tech Stack:** Godot 4.4 (GDScript, headless), Python 3.12 (solo stdlib: `unittest`, `json`), Git Bash.

**Spec:** `docs/superpowers/specs/2026-09-26-reestructura-aoe2-design.md` (secciones 3, 4, 5.1, 9, 10-F0)

## Global Constraints

- Godot **4.4** (renderer GL Compatibility ya configurado); tests headless con `godot --headless --path . -s <script>`.
- `engine/sim` y `engine/data` **no pueden** usar `Node2D`, `Node3D`, `Sprite2D`, `Sprite3D`, `Time.`, `randf(`, `randi(`, `randomize(`, `OS.get_ticks`, `RandomNumberGenerator`.
- Estado mutable de simulación solo en enteros; posiciones en punto fijo `SCALE = 1000` (1 casilla = 1000).
- `JSON.parse_string` devuelve **float para todo número**: los esquemas `int` aceptan `5.0` y rechazan `5.5`.
- Sin `class_name` en código nuevo: todo se referencia con `preload("res://...")` (los tests headless no dependen de la caché de clases del editor).
- Validación estricta: campo o habilidad desconocidos = error con `archivo: entidad.ruta: problema`. **Sin fallbacks silenciosos.**
- Iteración determinista: toda lista de ids/archivos se ordena antes de recorrerla.
- El juego viejo (`data/`, `core/`, `systems/`, `world/`, autoloads) **no se modifica** en F0.
- Comentarios y mensajes en español, como el resto del repo. Commits terminan con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Enteros que llegan como float** (`"queue": 5` → `5.0`): deben validar; `5.5` debe fallar con "debe ser entero". → Task 3, `test_int_accepts_whole_float_rejects_fraction`.
2. **Acentos y UTF-8** ("Torre Vigía", "Arquería"): la migración no debe romperlos ni escapar a `\u00ed`. → Task 8, `test_write_keeps_utf8`.
3. **JSON con BOM o inválido** (archivos editados en Notepad de Windows): el BOM se ignora; JSON roto da error con línea, no crash. → Task 5, `test_parse_json_text_bom_and_errors`.
4. **Carpeta de mods ausente, vacía o `mod.json` sin id**: error claro, `load_mods` devuelve `false`. → Task 5, `test_missing_and_empty_roots`.
5. **Orden no determinista** (orden de `DirAccess`, inserción en diccionarios, ids reciclados tras `despawn`): hash y listas iguales entre cargas; `ids_with` ordenado. → Task 5 `test_hash_stable`, Task 7 `test_ids_with_sorted_after_despawn`.

---

## File Structure

```
engine/
  data/
    Merge.gd          fusión profunda + acceso por ruta "a.b.c"
    Schemas.gd        esquemas de entidades/habilidades/efectos + validate_entity()
    Patch.gd          selectores (id:/tag:/type:, | y &) + ops set/add/mul/append/remove
    Registry.gd       carga de mods, orden, override/patch, extends, validación, refs, hash
    PlayerDefs.gd     vista parcheada por jugador (civ, techs, disabled, upgrades)
  sim/
    FixedPoint.gd     aritmética de punto fijo determinista
    SpatialHash.gd    consultas por radio en grilla de celdas
    World.gd          entidades + componentes por habilidad + state_hash
mods/aoe2_base/       GENERADO por tools/migrate_data_to_mod.py (se commitea)
tools/
  migrate_data_to_mod.py
  validate_mods.gd    CLI: valida mods y muestra hash
  tests/test_migrate.py
tests/engine/
  TestCase.gd         asserts mínimos
  run_tests.gd        runner (SceneTree)
  run.sh              atajo bash
  test_*.gd           un archivo por módulo
  fixtures/mods_ok/…, fixtures/mods_bad/…, fixtures/mods_empty/…
```

---

### Task 0: Entorno Godot + runner de tests

**Files:**
- Create: `tests/engine/TestCase.gd`, `tests/engine/run_tests.gd`, `tests/engine/run.sh`, `tests/engine/test_harness.gd`

**Interfaces:**
- Produces: base `TestCase` (`assert_eq(actual, expected, msg="")`, `assert_true`, `assert_false`, `assert_has_error(errors: Array, fragment: String)`, `fail(msg)`); los tests hacen `extends "res://tests/engine/TestCase.gd"` y definen métodos `test_*`. Runner: `godot --headless --path . -s tests/engine/run_tests.gd [-- --only=test_x]`.

- [ ] **Step 1: Instalar Godot 4.4**

Godot no está en el PATH de esta máquina. Descargar **Godot 4.4.1 stable (Windows 64-bit, estándar, no .NET)** desde https://godotengine.org/download/archive/4.4.1-stable/ (confirmar con el usuario antes de descargar), descomprimir en `C:\Tools\Godot\` y exportar en Git Bash:

```bash
export GODOT="/c/Tools/Godot/Godot_v4.4.1-stable_win64_console.exe"
"$GODOT" --version
```
Expected: `4.4.1.stable.official...`

- [ ] **Step 2: Escribir `tests/engine/TestCase.gd`**

```gdscript
extends RefCounted
## Base mínima de tests (sin dependencias). Cada método test_* es un caso;
## el runner crea una instancia nueva por caso.

var failures: Array[String] = []
var asserts := 0
var current := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current, msg])


func assert_true(cond: bool, msg: String = "") -> void:
	asserts += 1
	if not cond:
		fail("se esperaba verdadero. " + msg)


func assert_false(cond: bool, msg: String = "") -> void:
	asserts += 1
	if cond:
		fail("se esperaba falso. " + msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	asserts += 1
	if not equal(actual, expected):
		fail("esperado %s, obtenido %s. %s" % [var_to_str(expected), var_to_str(actual), msg])


## Pasa si algún error contiene el fragmento.
func assert_has_error(errors: Array, fragment: String) -> void:
	asserts += 1
	for e in errors:
		if fragment in str(e):
			return
	fail("ningún error contiene '%s'. Errores: %s" % [fragment, str(errors)])


## Igualdad profunda tolerante int/float (JSON.parse_string da float siempre).
static func equal(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var nums := [TYPE_INT, TYPE_FLOAT]
	if ta in nums and tb in nums:
		return float(a) == float(b)
	if ta != tb:
		return false
	if ta == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not equal(a[k], b[k]):
				return false
		return true
	if ta == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not equal(a[i], b[i]):
				return false
		return true
	return a == b
```

- [ ] **Step 3: Escribir `tests/engine/run_tests.gd`**

```gdscript
extends SceneTree
## Corre res://tests/engine/test_*.gd. Sale 0 si todo pasa, 1 si algo falla.
## Uso: godot --headless --path . -s tests/engine/run_tests.gd [-- --only=test_world]

const TEST_DIR := "res://tests/engine"


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--only="):
			only = str(a).get_slice("=", 1)
	var files: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and (only == "" or f.get_basename() == only):
			files.append(f)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	for f in files:
		var script: GDScript = load(TEST_DIR + "/" + f)
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var inst = script.new()
			inst.current = "%s::%s" % [f.get_basename(), mname]
			inst.call(mname)
			total += 1
			if inst.asserts == 0:
				inst.fail("no ejecutó ningún assert (¿error de script?)")
			failed.append_array(inst.failures)
			print(("FAIL " if inst.failures.size() > 0 else "ok   ") + inst.current)
	for e in failed:
		printerr(e)
	print("%d tests, %d fallos" % [total, failed.size()])
	quit(1 if failed.size() > 0 or total == 0 else 0)
```

- [ ] **Step 4: Escribir `tests/engine/run.sh`**

```sh
#!/usr/bin/env sh
# Tests del motor nuevo (engine/). Uso: sh tests/engine/run.sh [test_nombre]
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ "$#" -gt 0 ]; then
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" -- --only="$1"
else
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd"
fi
```

- [ ] **Step 5: Escribir el test de humo `tests/engine/test_harness.gd`**

```gdscript
extends "res://tests/engine/TestCase.gd"


func test_equal_tolerates_int_float() -> void:
	assert_eq(45.0, 45)
	assert_eq({"a": [1, {"b": 2}]}, {"a": [1.0, {"b": 2.0}]})
	assert_false(equal({"a": 1}, {"a": 1, "b": 2}))
	assert_false(equal("1", 1))


func test_assert_has_error_matches_fragment() -> void:
	assert_has_error(["x: campo desconocido"], "desconocido")
```

- [ ] **Step 6: Correr**

Run: `sh tests/engine/run.sh`
Expected: `ok   test_harness::test_equal_tolerates_int_float`, `ok   test_harness::test_assert_has_error_matches_fragment`, `2 tests, 0 fallos`, código 0. (Pueden aparecer avisos de los autoloads viejos: se ignoran.)

- [ ] **Step 7: Commit**

```bash
git add tests/engine
git commit -m "F0: runner de tests headless del motor nuevo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: FixedPoint

**Files:**
- Create: `engine/sim/FixedPoint.gd`
- Test: `tests/engine/test_fixed_point.gd`

**Interfaces:**
- Produces: `const SCALE := 1000`; estáticos `from_tiles(t: int) -> int`, `from_data(v: float) -> int`, `mul(a: int, b: int) -> int`, `div(a: int, b: int) -> int`, `floordiv(a: int, b: int) -> int`, `isqrt(n: int) -> int`, `length(dx: int, dy: int) -> int`, `dist(a: Vector2i, b: Vector2i) -> int`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_fixed_point.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const FP := preload("res://engine/sim/FixedPoint.gd")


func test_from_tiles_and_data() -> void:
	assert_eq(FP.from_tiles(3), 3000)
	assert_eq(FP.from_data(0.96), 960)
	assert_eq(FP.from_data(0.39), 390)
	assert_eq(FP.from_data(-1.2346), -1235)


func test_mul_rounds_half_away_from_zero() -> void:
	assert_eq(FP.mul(1500, 2000), 3000)
	assert_eq(FP.mul(-1500, 2000), -3000)
	assert_eq(FP.mul(1, 500), 1)
	assert_eq(FP.mul(-1, 500), -1)


func test_div() -> void:
	assert_eq(FP.div(1000, 3), 333)
	assert_eq(FP.div(2000, 3), 667)
	assert_eq(FP.div(-2000, 3), -667)
	assert_eq(FP.div(3000, 2000), 1500)


func test_floordiv_negative() -> void:
	assert_eq(FP.floordiv(7, 4), 1)
	assert_eq(FP.floordiv(-1, 4000), -1)
	assert_eq(FP.floordiv(-4000, 4000), -1)
	assert_eq(FP.floordiv(-4001, 4000), -2)


func test_isqrt_and_dist() -> void:
	assert_eq(FP.isqrt(0), 0)
	assert_eq(FP.isqrt(2), 1)
	assert_eq(FP.isqrt(15), 3)
	assert_eq(FP.isqrt(16), 4)
	assert_eq(FP.isqrt(1000000000000), 1000000)
	assert_eq(FP.dist(Vector2i(0, 0), Vector2i(3000, 4000)), 5000)
	assert_eq(FP.dist(Vector2i(1000, 1000), Vector2i(1000, 1000)), 0)
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_fixed_point`
Expected: error de carga `res://engine/sim/FixedPoint.gd` / fallos.

- [ ] **Step 3: Implementar** — `engine/sim/FixedPoint.gd`

```gdscript
extends RefCounted
## Aritmética de punto fijo determinista: 1 casilla = SCALE unidades.
## Todo el estado mutable de la simulación usa estos enteros; los float
## solo aparecen al leer datos (from_data), nunca dentro del tick.

const SCALE := 1000


static func from_tiles(tiles: int) -> int:
	return tiles * SCALE


## Convierte un valor de datos (float de JSON) a punto fijo, redondeando a milésimas.
static func from_data(v: float) -> int:
	return int(round(v * SCALE))


static func mul(a: int, b: int) -> int:
	return _div_round(a * b, SCALE)


static func div(a: int, b: int) -> int:
	assert(b != 0, "FixedPoint.div: división por cero")
	return _div_round(a * SCALE, b)


## División entera redondeando hacia -infinito (celdas con coordenadas negativas).
static func floordiv(a: int, b: int) -> int:
	var q := a / b
	if a % b != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Raíz cuadrada entera (piso) por Newton.
static func isqrt(n: int) -> int:
	if n < 2:
		return maxi(n, 0)
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


static func length(dx: int, dy: int) -> int:
	return isqrt(dx * dx + dy * dy)


static func dist(a: Vector2i, b: Vector2i) -> int:
	return length(b.x - a.x, b.y - a.y)


## n / d redondeando la mitad lejos de cero.
static func _div_round(n: int, d: int) -> int:
	var q := n / d
	var r := n % d
	if absi(r) * 2 >= absi(d):
		q += 1 if (n < 0) == (d < 0) else -1
	return q
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_fixed_point`
Expected: `5 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/sim/FixedPoint.gd tests/engine/test_fixed_point.gd
git commit -m "F0: FixedPoint determinista

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Merge (fusión profunda y rutas)

**Files:**
- Create: `engine/data/Merge.gd`
- Test: `tests/engine/test_merge.gd`

**Interfaces:**
- Produces: estáticos `deep_merge(base: Dictionary, over: Dictionary) -> Dictionary` (copia; dicts se fusionan, todo lo demás se reemplaza), `path_get(d: Dictionary, path: String, default: Variant = null) -> Variant`, `path_has(d, path) -> bool`, `path_set(d, path, value) -> void` (crea intermedios), `path_erase(d, path) -> bool`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_merge.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Merge := preload("res://engine/data/Merge.gd")


func test_deep_merge_merges_dicts_replaces_arrays() -> void:
	var base := {"a": {"x": 1, "y": 2}, "l": [1, 2], "s": "base"}
	var over := {"a": {"y": 3}, "l": [9], "n": true}
	var out := Merge.deep_merge(base, over)
	assert_eq(out, {"a": {"x": 1, "y": 3}, "l": [9], "s": "base", "n": true})
	assert_eq(base, {"a": {"x": 1, "y": 2}, "l": [1, 2], "s": "base"}, "base no se muta")


func test_deep_merge_copies_nested_values() -> void:
	var over := {"a": {"k": [1]}}
	var out := Merge.deep_merge({}, over)
	out["a"]["k"].append(2)
	assert_eq(over, {"a": {"k": [1]}}, "over no se comparte")


func test_path_get_has() -> void:
	var d := {"abilities": {"Attack": {"range": 5.0}}}
	assert_eq(Merge.path_get(d, "abilities.Attack.range"), 5.0)
	assert_eq(Merge.path_get(d, "abilities.Move.speed", -1), -1)
	assert_true(Merge.path_has(d, "abilities.Attack"))
	assert_false(Merge.path_has(d, "abilities.Attack.range.x"))


func test_path_set_creates_intermediates_and_erase() -> void:
	var d := {}
	Merge.path_set(d, "abilities.Attack.damage.edificio", 2)
	assert_eq(d, {"abilities": {"Attack": {"damage": {"edificio": 2}}}})
	assert_true(Merge.path_erase(d, "abilities.Attack.damage.edificio"))
	assert_eq(d, {"abilities": {"Attack": {"damage": {}}}})
	assert_false(Merge.path_erase(d, "no.existe"))
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_merge` → Expected: FAIL (script no existe).

- [ ] **Step 3: Implementar** — `engine/data/Merge.gd`

```gdscript
extends RefCounted
## Fusión profunda y acceso por ruta "a.b.c" para definiciones de datos.


## Copia de base con over encima: los diccionarios se fusionan recursivamente;
## cualquier otro valor (listas incluidas) se reemplaza. No muta las entradas.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		var v: Variant = over[k]
		if v is Dictionary and out.get(k) is Dictionary:
			out[k] = deep_merge(out[k], v)
		elif v is Dictionary or v is Array:
			out[k] = v.duplicate(true)
		else:
			out[k] = v
	return out


static func path_get(d: Dictionary, path: String, default: Variant = null) -> Variant:
	var cur: Variant = d
	for part in path.split("."):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return default
		cur = cur[part]
	return cur


static func path_has(d: Dictionary, path: String) -> bool:
	var cur: Variant = d
	for part in path.split("."):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return false
		cur = cur[part]
	return true


static func path_set(d: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cur: Dictionary = d
	for i in parts.size() - 1:
		var p := parts[i]
		if not (cur.get(p) is Dictionary):
			cur[p] = {}
		cur = cur[p]
	cur[parts[parts.size() - 1]] = value


static func path_erase(d: Dictionary, path: String) -> bool:
	var parts := path.split(".")
	var cur: Variant = d
	for i in parts.size() - 1:
		if not (cur is Dictionary) or not (cur as Dictionary).has(parts[i]):
			return false
		cur = cur[parts[i]]
	if not (cur is Dictionary):
		return false
	return (cur as Dictionary).erase(parts[parts.size() - 1])
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_merge` → Expected: `4 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/data/Merge.gd tests/engine/test_merge.gd
git commit -m "F0: Merge (deep_merge + rutas)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Schemas (validación de entidades, habilidades y efectos)

**Files:**
- Create: `engine/data/Schemas.gd`
- Test: `tests/engine/test_schemas.gd`

**Interfaces:**
- Produces: `const RESOURCES: Array[String] = ["wood","food","gold","stone"]`, `const ENTITY_TYPES`, `const EFFECT_OPS`, `const ABILITIES` (dict nombre → campos); estáticos `validate_entity(e: Dictionary, src: String) -> Array[String]`, `validate_effect(e: Variant) -> String` ("" si válido), `is_num(v) -> bool`, `type_error(v, type: String) -> String`.
- Formato de error: `"<src>: <id>.<ruta>: <problema>"`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_schemas.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Schemas := preload("res://engine/data/Schemas.gd")


func _milicia() -> Dictionary:
	return {
		"id": "milicia", "type": "unit", "name": "Milicia", "_comment": "ok",
		"tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
		"train_time": 21, "pop_cost": 1, "requires": {"age": "alta_edad_media"},
		"abilities": {
			"Hitpoints": {"max": 45},
			"Armor": {"classes": {"melee": 0, "pierce": 1}},
			"Move": {"speed": 0.9},
			"Attack": {"damage": {"melee": 4, "edificio": 2}, "range": 0, "reload": 2.0},
		},
	}


func test_valid_unit_has_no_errors() -> void:
	assert_eq(Schemas.validate_entity(_milicia(), "m.json"), [])


func test_unknown_type_ability_and_field() -> void:
	var e := _milicia()
	e["hp"] = 45
	e["abilities"]["Volar"] = {}
	e["abilities"]["Move"]["turbo"] = 1
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "m.json: milicia.hp: campo desconocido")
	assert_has_error(errs, "milicia.abilities.Volar: habilidad desconocida")
	assert_has_error(errs, "milicia.abilities.Move.turbo: campo desconocido")
	var bad := {"id": "x", "type": "dragon"}
	assert_has_error(Schemas.validate_entity(bad, "x.json"), "tipo desconocido 'dragon'")


func test_missing_required() -> void:
	var e := _milicia()
	e["abilities"]["Attack"].erase("reload")
	e.erase("train_time")
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "milicia.abilities.Attack.reload: falta campo obligatorio")
	assert_has_error(errs, "milicia.train_time: falta campo obligatorio")


func test_abstract_skips_required() -> void:
	var base := {"id": "infanteria_base", "type": "unit", "abstract": true,
		"abilities": {"Garrisonable": {}, "Attack": {"damage": {"melee": 1}}}}
	assert_eq(Schemas.validate_entity(base, "b.json"), [])


func test_int_accepts_whole_float_rejects_fraction() -> void:
	var e := _milicia()
	e["pop_cost"] = 1.0
	assert_eq(Schemas.validate_entity(e, "m.json"), [])
	e["pop_cost"] = 1.5
	assert_has_error(Schemas.validate_entity(e, "m.json"), "milicia.pop_cost: debe ser entero")


func test_res_map_and_requires() -> void:
	var e := _milicia()
	e["cost"] = {"madera": 10}
	e["requires"] = {"edad": "feudal"}
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "recurso desconocido 'madera'")
	assert_has_error(errs, "clave desconocida 'edad'")


func test_effects() -> void:
	assert_eq(Schemas.validate_effect({"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}), "")
	assert_eq(Schemas.validate_effect({"op": "replace_entity", "from": "milicia", "to": "hombre_armas"}), "")
	assert_eq(Schemas.validate_effect({"target": "id:x", "op": "disable"}), "")
	assert_true("op desconocida" in Schemas.validate_effect({"target": "id:x", "op": "explode"}))
	assert_true("value debe ser número" in Schemas.validate_effect({"target": "id:x", "op": "mul", "path": "cost.wood", "value": "mucho"}))
	var tech := {"id": "forja", "type": "tech", "research_time": 50, "at": "herreria",
		"effects": [{"target": "tag:infanteria", "op": "bad"}]}
	assert_has_error(Schemas.validate_entity(tech, "t.json"), "forja.effects: efecto 0: op desconocida")
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_schemas` → Expected: FAIL (script no existe).

- [ ] **Step 3: Implementar** — `engine/data/Schemas.gd`

```gdscript
extends RefCounted
## Esquemas de entidades, habilidades y efectos. validate_entity() devuelve
## errores "archivo: id.ruta: problema". Números de JSON llegan como float.
## Tipos de campo: number, int, string, bool, dict, array, string_list,
## class_map {texto: número}, res_map {recurso: número}, int_pair, requires, effects.

const RESOURCES: Array[String] = ["wood", "food", "gold", "stone"]
const ENTITY_TYPES: Array[String] = ["unit", "building", "resource", "tech", "age", "civ"]
const EFFECT_OPS: Array[String] = ["set", "add", "mul", "append", "remove", "enable", "disable", "replace_entity"]

const COMMON := {
	"id": {"type": "string", "required": true},
	"type": {"type": "string", "required": true},
	"extends": {"type": "string"},
	"abstract": {"type": "bool"},
	"patch": {"type": "bool"},
	"name": {"type": "string"},
	"description": {"type": "string"},
	"hotkey": {"type": "string"},
	"tags": {"type": "string_list"},
	"requires": {"type": "requires"},
	"cost": {"type": "res_map"},
	"graphics": {"type": "dict"},
	"abilities": {"type": "dict"},
}

const BY_TYPE := {
	"unit": {
		"train_time": {"type": "number", "required": true},
		"pop_cost": {"type": "int", "required": true},
		"upgrades_to": {"type": "string"},
	},
	"building": {
		"build_time": {"type": "number", "required": true},
		"footprint": {"type": "int_pair", "required": true},
	},
	"resource": {},
	"tech": {
		"research_time": {"type": "number", "required": true},
		"at": {"type": "string", "required": true},
		"effects": {"type": "effects", "required": true},
		"legacy_effects": {"type": "dict"},
	},
	"age": {
		"index": {"type": "int", "required": true},
		"research_time": {"type": "number", "required": true},
		"prerequisite_buildings": {"type": "dict"},
	},
	"civ": {
		"color": {"type": "string", "required": true},
		"effects": {"type": "effects"},
		"disabled": {"type": "string_list"},
		"unique_units": {"type": "string_list"},
		"unique_techs": {"type": "string_list"},
		"legacy_effects": {"type": "array"},
	},
}

const ABILITIES := {
	"Hitpoints": {"max": {"type": "number", "required": true}, "regen": {"type": "number"}},
	"Armor": {"classes": {"type": "class_map", "required": true}},
	"Move": {"speed": {"type": "number", "required": true}},
	"Vision": {"sight": {"type": "number", "required": true}},
	"Selectable": {"radius": {"type": "number"}},
	"Attack": {
		"damage": {"type": "class_map", "required": true},
		"range": {"type": "number", "required": true},
		"reload": {"type": "number", "required": true},
		"min_range": {"type": "number"},
		"attack_delay": {"type": "number"},
		"accuracy": {"type": "number"},
		"projectile_speed": {"type": "number"},
		"area_radius": {"type": "number"},
	},
	"Gather": {"rates": {"type": "class_map", "required": true}, "capacity": {"type": "number", "required": true}},
	"Build": {"rate": {"type": "number", "required": true}},
	"Repair": {"rate": {"type": "number", "required": true}, "cost_factor": {"type": "number"}},
	"DropSite": {"accepts": {"type": "string_list", "required": true}},
	"ResourceSource": {
		"resource": {"type": "string", "required": true},
		"amount": {"type": "number", "required": true},
		"rate_key": {"type": "string", "required": true},
		"infinite": {"type": "bool"},
		"requires_kill": {"type": "bool"},
		"hostile": {"type": "bool"},
		"tame": {"type": "bool"},
		"flees": {"type": "bool"},
		"water": {"type": "bool"},
	},
	"Farm": {"food": {"type": "number", "required": true}, "rate_key": {"type": "string", "required": true}},
	"Train": {"units": {"type": "string_list", "required": true}, "queue": {"type": "int", "required": true}},
	"Research": {"techs": {"type": "string_list", "required": true}},
	"AgeAdvance": {},
	"Bell": {},
	"RallyPoint": {},
	"Garrison": {
		"capacity": {"type": "int", "required": true},
		"arrows_per_unit": {"type": "number"},
		"heal_rate": {"type": "number"},
	},
	"Garrisonable": {},
	"ProvidesPop": {"amount": {"type": "int", "required": true}},
	"Convert": {
		"range": {"type": "number", "required": true},
		"cooldown": {"type": "number", "required": true},
		"chance": {"type": "number", "required": true},
	},
	"Heal": {"range": {"type": "number", "required": true}, "rate": {"type": "number", "required": true}},
	"Trade": {"gold_base": {"type": "number", "required": true}, "gold_per_tile": {"type": "number", "required": true}},
	"Packable": {"pack_time": {"type": "number", "required": true}, "unpack_time": {"type": "number", "required": true}},
	"Wonder": {"victory_time": {"type": "number", "required": true}},
	"Unique": {"civ": {"type": "string", "required": true}},
}


static func validate_entity(e: Dictionary, src: String) -> Array[String]:
	var errs: Array[String] = []
	var id := str(e.get("id", "?"))
	var t := str(e.get("type", ""))
	if not ENTITY_TYPES.has(t):
		errs.append("%s: %s.type: tipo desconocido '%s'" % [src, id, t])
		return errs
	var abstract := bool(e.get("abstract", false))
	var fields: Dictionary = COMMON.duplicate()
	fields.merge(BY_TYPE[t])
	_check_fields(e, fields, id, src, abstract, errs)
	var abil: Variant = e.get("abilities", {})
	if not (abil is Dictionary):
		return errs
	var names: Array = (abil as Dictionary).keys()
	names.sort()
	for a in names:
		var prefix := "%s.abilities.%s" % [id, a]
		if not ABILITIES.has(a):
			errs.append("%s: %s: habilidad desconocida" % [src, prefix])
			continue
		if not (abil[a] is Dictionary):
			errs.append("%s: %s: debe ser objeto" % [src, prefix])
			continue
		_check_fields(abil[a], ABILITIES[a], prefix, src, abstract, errs)
	return errs


## "" si el efecto es válido; si no, el motivo.
static func validate_effect(e: Variant) -> String:
	if not (e is Dictionary):
		return "debe ser objeto"
	var op := str(e.get("op", ""))
	if not EFFECT_OPS.has(op):
		return "op desconocida '%s'" % op
	if op == "replace_entity":
		return "" if e.get("from") is String and e.get("to") is String else "replace_entity requiere from y to"
	if not (e.get("target") is String):
		return "falta target"
	if op == "enable" or op == "disable":
		return ""
	if not (e.get("path") is String):
		return "falta path"
	if not e.has("value") and op != "remove":
		return "falta value"
	if (op == "add" or op == "mul") and not is_num(e["value"]):
		return "value debe ser número"
	return ""


static func is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## "" si v cumple el tipo; si no, el motivo.
static func type_error(v: Variant, type: String) -> String:
	match type:
		"number":
			return "" if is_num(v) else "debe ser número"
		"int":
			return "" if is_num(v) and float(v) == floorf(float(v)) else "debe ser entero"
		"string":
			return "" if v is String else "debe ser texto"
		"bool":
			return "" if v is bool else "debe ser true/false"
		"dict":
			return "" if v is Dictionary else "debe ser objeto"
		"array":
			return "" if v is Array else "debe ser lista"
		"string_list":
			if not (v is Array):
				return "debe ser lista de textos"
			for x in v:
				if not (x is String):
					return "debe ser lista de textos"
			return ""
		"class_map":
			if not (v is Dictionary):
				return "debe ser objeto {clase: número}"
			for k in v:
				if not is_num(v[k]):
					return "valor de '%s' debe ser número" % k
			return ""
		"res_map":
			if not (v is Dictionary):
				return "debe ser objeto {recurso: número}"
			for k in v:
				if not RESOURCES.has(str(k)):
					return "recurso desconocido '%s'" % k
				if not is_num(v[k]):
					return "valor de '%s' debe ser número" % k
			return ""
		"int_pair":
			if v is Array and v.size() == 2 and type_error(v[0], "int") == "" and type_error(v[1], "int") == "":
				return ""
			return "debe ser [entero, entero]"
		"requires":
			if not (v is Dictionary):
				return "debe ser objeto {age, techs}"
			for k in v:
				if k != "age" and k != "techs":
					return "clave desconocida '%s' (usa age/techs)" % k
			if v.has("age") and not (v["age"] is String):
				return "age debe ser texto"
			if v.has("techs") and type_error(v["techs"], "string_list") != "":
				return "techs debe ser lista de textos"
			return ""
		"effects":
			if not (v is Array):
				return "debe ser lista de efectos"
			for i in v.size():
				var why := validate_effect(v[i])
				if why != "":
					return "efecto %d: %s" % [i, why]
			return ""
	return "tipo de esquema desconocido '%s'" % type


static func _check_fields(obj: Dictionary, fields: Dictionary, prefix: String, src: String, skip_required: bool, errs: Array[String]) -> void:
	var keys: Array = obj.keys()
	keys.sort()
	for k in keys:
		var key := str(k)
		if key.begins_with("_"):
			continue
		if not fields.has(key):
			errs.append("%s: %s.%s: campo desconocido" % [src, prefix, key])
			continue
		var why := type_error(obj[k], str(fields[key]["type"]))
		if why != "":
			errs.append("%s: %s.%s: %s" % [src, prefix, key, why])
	if skip_required:
		return
	var req: Array = fields.keys()
	req.sort()
	for key in req:
		if bool(fields[key].get("required", false)) and not obj.has(key):
			errs.append("%s: %s.%s: falta campo obligatorio" % [src, prefix, key])
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_schemas` → Expected: `7 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/data/Schemas.gd tests/engine/test_schemas.gd
git commit -m "F0: esquemas de entidades, habilidades y efectos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Patch (selectores y operaciones)

**Files:**
- Create: `engine/data/Patch.gd`
- Test: `tests/engine/test_patch.gd`

**Interfaces:**
- Consumes: `Merge.path_get/path_set/path_erase` (Task 2), `Schemas.is_num` (Task 3).
- Produces: estáticos `matches(def: Dictionary, selector: String) -> bool`, `select(defs: Dictionary, selector: String) -> Array[String]` (ordenado), `apply(defs: Dictionary, effect: Dictionary) -> Array[String]` (errores; muta `defs` in place; solo ops `set/add/mul/append/remove`).
- Reglas: si la ruta empieza por `abilities.<X>` y la entidad no tiene `<X>`, se omite esa entidad. `add` sobre hoja inexistente la crea; `mul` sobre hoja inexistente se omite; `append` crea la lista; `remove` con `value` quita de la lista, sin `value` borra la ruta.

- [ ] **Step 1: Test que falla** — `tests/engine/test_patch.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Patch := preload("res://engine/data/Patch.gd")


func _defs() -> Dictionary:
	return {
		"milicia": {"id": "milicia", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 4}}, "Hitpoints": {"max": 45}}},
		"arquero": {"id": "arquero", "type": "unit", "tags": ["arqueros"], "cost": {"wood": 25, "gold": 45},
			"abilities": {"Attack": {"damage": {"pierce": 4}}, "Hitpoints": {"max": 30}}},
		"aldeano": {"id": "aldeano", "type": "unit", "tags": ["aldeano"], "cost": {"food": 50},
			"abilities": {"Hitpoints": {"max": 25}}},
		"casa": {"id": "casa", "type": "building", "tags": ["edificio"], "abilities": {"Hitpoints": {"max": 550}}},
	}


func test_selectors() -> void:
	var d := _defs()
	assert_eq(Patch.select(d, "tag:infanteria|tag:arqueros"), ["arquero", "milicia"])
	assert_eq(Patch.select(d, "type:unit&tag:aldeano"), ["aldeano"])
	assert_eq(Patch.select(d, "id:casa"), ["casa"])
	assert_eq(Patch.select(d, "type:unit"), ["aldeano", "arquero", "milicia"])
	assert_eq(Patch.select(d, "tag:nada"), [])


func test_add_creates_leaf_and_skips_missing_ability() -> void:
	var d := _defs()
	var errs := Patch.apply(d, {"target": "type:unit", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1})
	assert_eq(errs, [])
	assert_eq(d["milicia"]["abilities"]["Attack"]["damage"], {"melee": 5})
	assert_eq(d["arquero"]["abilities"]["Attack"]["damage"], {"pierce": 4, "melee": 1})
	assert_false(d["aldeano"]["abilities"].has("Attack"), "sin Attack no se toca")


func test_mul_skips_missing_leaf() -> void:
	var d := _defs()
	Patch.apply(d, {"target": "type:unit", "op": "mul", "path": "cost.wood", "value": 0.9})
	assert_eq(d["arquero"]["cost"]["wood"], 22.5)
	assert_false(d["milicia"]["cost"].has("wood"))


func test_set_append_remove() -> void:
	var d := _defs()
	Patch.apply(d, {"target": "id:casa", "op": "set", "path": "abilities.Hitpoints.max", "value": 600})
	assert_eq(d["casa"]["abilities"]["Hitpoints"]["max"], 600)
	Patch.apply(d, {"target": "id:casa", "op": "append", "path": "tags", "value": "civil"})
	Patch.apply(d, {"target": "id:casa", "op": "append", "path": "tags", "value": "civil"})
	assert_eq(d["casa"]["tags"], ["edificio", "civil"])
	Patch.apply(d, {"target": "id:casa", "op": "remove", "path": "tags", "value": "edificio"})
	assert_eq(d["casa"]["tags"], ["civil"])
	Patch.apply(d, {"target": "id:milicia", "op": "remove", "path": "cost.gold"})
	assert_eq(d["milicia"]["cost"], {"food": 60})


func test_type_mismatch_reports_error() -> void:
	var d := _defs()
	var errs := Patch.apply(d, {"target": "id:milicia", "op": "add", "path": "tags", "value": 1})
	assert_has_error(errs, "milicia.tags: add sobre un valor no numérico")
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_patch` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/data/Patch.gd`

```gdscript
extends RefCounted
## Selectores y operaciones de parche (tecnologías, civilizaciones, mods).
## Selector: "tag:a|tag:b&type:unit" = OR de grupos AND. Términos id:, tag:, type:.

const Merge := preload("res://engine/data/Merge.gd")
const Schemas := preload("res://engine/data/Schemas.gd")


static func matches(def: Dictionary, selector: String) -> bool:
	for alt in selector.split("|"):
		var ok := true
		for term in alt.split("&"):
			if not _term(def, term.strip_edges()):
				ok = false
				break
		if ok:
			return true
	return false


static func select(defs: Dictionary, selector: String) -> Array[String]:
	var out: Array[String] = []
	for id in defs:
		if matches(defs[id], selector):
			out.append(str(id))
	out.sort()
	return out


## Aplica set/add/mul/append/remove sobre defs (in place). Devuelve errores.
static func apply(defs: Dictionary, effect: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var op := str(effect["op"])
	var path := str(effect["path"])
	var value: Variant = effect.get("value")
	var parts := path.split(".")
	for id in select(defs, str(effect["target"])):
		var def: Dictionary = defs[id]
		if parts[0] == "abilities" and parts.size() >= 2 and not (def.get("abilities", {}) as Dictionary).has(parts[1]):
			continue
		var cur: Variant = Merge.path_get(def, path)
		if op == "set":
			Merge.path_set(def, path, value.duplicate(true) if (value is Dictionary or value is Array) else value)
		elif op == "add":
			if cur == null:
				Merge.path_set(def, path, value)
			elif Schemas.is_num(cur):
				Merge.path_set(def, path, cur + value)
			else:
				errs.append("%s.%s: add sobre un valor no numérico" % [id, path])
		elif op == "mul":
			if cur == null:
				continue
			if Schemas.is_num(cur):
				Merge.path_set(def, path, cur * value)
			else:
				errs.append("%s.%s: mul sobre un valor no numérico" % [id, path])
		elif op == "append":
			if cur == null:
				Merge.path_set(def, path, [value])
			elif cur is Array:
				if not (cur as Array).has(value):
					(cur as Array).append(value)
			else:
				errs.append("%s.%s: append sobre algo que no es lista" % [id, path])
		elif op == "remove":
			if cur is Array and value != null:
				(cur as Array).erase(value)
			elif cur != null:
				Merge.path_erase(def, path)
		else:
			errs.append("%s: op '%s' no se aplica sobre datos" % [id, op])
	return errs


static func _term(def: Dictionary, term: String) -> bool:
	var kind := term.get_slice(":", 0)
	var val := term.get_slice(":", 1)
	match kind:
		"id":
			return str(def.get("id", "")) == val
		"tag":
			return (def.get("tags", []) as Array).has(val)
		"type":
			return str(def.get("type", "")) == val
	return false
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_patch` → Expected: `5 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/data/Patch.gd tests/engine/test_patch.gd
git commit -m "F0: selectores y operaciones de parche

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Registry (mods, herencia, parches, validación, hash)

**Files:**
- Create: `engine/data/Registry.gd`
- Create fixtures: `tests/engine/fixtures/mods_ok/core/{mod.json, base/unidad_base.json, units/soldado.json, buildings/cuartel.json, ages/edad1.json, units/_notas.json}`, `tests/engine/fixtures/mods_ok/addon/{mod.json, units/soldado.json, buildings/torre.json}`, `tests/engine/fixtures/mods_bad/core/{mod.json, units/a.json, units/b.json, units/soldado.json, buildings/cuartel.json, units/parche.json}`, `tests/engine/fixtures/mods_empty/sin_mod/leeme.txt`
- Test: `tests/engine/test_registry.gd`

**Interfaces:**
- Consumes: `Merge.deep_merge` (Task 2), `Schemas.validate_entity`, `Schemas.RESOURCES` (Task 3).
- Produces: `Registry.new()`; `load_mods(root: String = "res://mods", enabled: Array = []) -> bool`; campos `defs: Dictionary` (id → def resuelta, sin abstractos), `abstract_defs`, `mods: Array[Dictionary]` (`{id, version, depends, priority, path}` en orden de carga), `errors: Array[String]`, `warnings: Array[String]`, `content_hash: String` (64 hex, "" si hay errores); `get_def(id) -> Dictionary` (no mutar), `has(id) -> bool`, `ids_of_type(type) -> Array[String]` (ordenado), `source_of(id) -> String`; estáticos `parse_json_text(text) -> Dictionary` (`{ok, data, error}`), `hash_defs(d: Dictionary) -> String`; `const ENTITY_DIRS := ["base","units","buildings","resources","techs","ages","civs"]`.
- Reglas: archivos que empiezan con `_` se ignoran; `"patch": true` fusiona sobre la definición existente (error si no existe); un id repetido en **otro** mod lo sobrescribe (warning), en el **mismo** mod es error; `tags` se unen a lo largo de `extends`; `abstract` no se hereda.

- [ ] **Step 1: Crear fixtures**

`tests/engine/fixtures/mods_ok/core/mod.json`
```json
{"id": "core", "version": "1"}
```
`tests/engine/fixtures/mods_ok/core/base/unidad_base.json`
```json
{"id": "unidad_base", "type": "unit", "abstract": true, "tags": ["unidad"], "pop_cost": 1,
 "abilities": {"Move": {"speed": 1.0}, "Vision": {"sight": 4}}}
```
`tests/engine/fixtures/mods_ok/core/units/soldado.json`
```json
{"id": "soldado", "type": "unit", "extends": "unidad_base", "name": "Soldado", "tags": ["infanteria"],
 "cost": {"food": 60}, "train_time": 21,
 "abilities": {"Hitpoints": {"max": 45}, "Attack": {"damage": {"melee": 4}, "range": 0, "reload": 2.0}}}
```
`tests/engine/fixtures/mods_ok/core/buildings/cuartel.json`
```json
{"id": "cuartel", "type": "building", "name": "Cuartel", "cost": {"wood": 175}, "build_time": 50,
 "footprint": [3, 3], "requires": {"age": "edad1"},
 "abilities": {"Hitpoints": {"max": 1200}, "Train": {"units": ["soldado"], "queue": 5}}}
```
`tests/engine/fixtures/mods_ok/core/ages/edad1.json`
```json
{"id": "edad1", "type": "age", "index": 0, "research_time": 0}
```
`tests/engine/fixtures/mods_ok/core/units/_notas.json` (debe ignorarse; no es una entidad)
```json
{"nota": "archivos con _ se ignoran"}
```
`tests/engine/fixtures/mods_ok/addon/mod.json`
```json
{"id": "addon", "version": "1", "depends": ["core"]}
```
`tests/engine/fixtures/mods_ok/addon/units/soldado.json`
```json
{"id": "soldado", "patch": true, "abilities": {"Hitpoints": {"max": 50}}}
```
`tests/engine/fixtures/mods_ok/addon/buildings/torre.json`
```json
{"id": "torre", "type": "building", "cost": {"stone": 125}, "build_time": 80, "footprint": [1, 1],
 "abilities": {"Hitpoints": {"max": 700}, "Garrison": {"capacity": 5.0}}}
```
`tests/engine/fixtures/mods_bad/core/mod.json`
```json
{"id": "core", "version": "1"}
```
`tests/engine/fixtures/mods_bad/core/units/a.json`
```json
{"id": "a", "type": "unit", "extends": "b", "train_time": 1, "pop_cost": 1}
```
`tests/engine/fixtures/mods_bad/core/units/b.json`
```json
{"id": "b", "type": "unit", "extends": "a", "train_time": 1, "pop_cost": 1}
```
`tests/engine/fixtures/mods_bad/core/units/soldado.json`
```json
{"id": "soldado", "type": "unit", "hp": 45, "train_time": 21, "pop_cost": 1}
```
`tests/engine/fixtures/mods_bad/core/buildings/cuartel.json`
```json
{"id": "cuartel", "type": "building", "build_time": 50, "footprint": [3, 3],
 "abilities": {"Train": {"units": ["fantasma", "cuartel"], "queue": 5}}}
```
`tests/engine/fixtures/mods_bad/core/units/parche.json`
```json
{"id": "nadie", "patch": true, "name": "x"}
```
`tests/engine/fixtures/mods_empty/sin_mod/leeme.txt`
```
Carpeta sin mod.json: el Registry debe reportar "no hay mods".
```

- [ ] **Step 2: Test que falla** — `tests/engine/test_registry.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const OK_ROOT := "res://tests/engine/fixtures/mods_ok"
const BAD_ROOT := "res://tests/engine/fixtures/mods_bad"


func _ok() -> Registry:
	var r := Registry.new()
	r.load_mods(OK_ROOT)
	return r


func test_loads_ok_fixture() -> void:
	var r := _ok()
	assert_eq(r.errors, [])
	assert_eq(r.defs.keys().size(), 4, str(r.defs.keys()))
	assert_true(r.has("soldado") and r.has("cuartel") and r.has("edad1") and r.has("torre"))
	assert_false(r.has("unidad_base"), "abstractos fuera de defs")
	assert_true(r.abstract_defs.has("unidad_base"))


func test_mod_order_respects_depends() -> void:
	var r := _ok()
	assert_eq(r.mods.map(func(m): return m["id"]), ["core", "addon"])


func test_extends_merges_and_unions_tags() -> void:
	var s := _ok().get_def("soldado")
	assert_eq(s["abilities"]["Move"], {"speed": 1.0})
	assert_eq(s["tags"], ["unidad", "infanteria"])
	assert_eq(s["pop_cost"], 1)
	assert_false(s.has("extends"))
	assert_false(s.has("abstract"))


func test_patch_from_dependent_mod() -> void:
	var s := _ok().get_def("soldado")
	assert_eq(s["abilities"]["Hitpoints"], {"max": 50})
	assert_eq(s["abilities"]["Attack"]["damage"], {"melee": 4})
	assert_false(s.has("patch"))


func test_ids_of_type_sorted() -> void:
	assert_eq(_ok().ids_of_type("building"), ["cuartel", "torre"])


func test_hash_stable() -> void:
	var a := _ok()
	var b := _ok()
	assert_eq(a.content_hash.length(), 64)
	assert_eq(a.content_hash, b.content_hash)
	var only_core := Registry.new()
	assert_true(only_core.load_mods(OK_ROOT, ["core"]), str(only_core.errors))
	assert_true(only_core.content_hash != a.content_hash)


func test_enabled_without_dependency_fails() -> void:
	var r := Registry.new()
	assert_false(r.load_mods(OK_ROOT, ["addon"]))
	assert_has_error(r.errors, "mod addon: depende de 'core'")


func test_bad_fixture_reports_everything() -> void:
	var r := Registry.new()
	assert_false(r.load_mods(BAD_ROOT))
	assert_has_error(r.errors, "herencia circular")
	assert_has_error(r.errors, "soldado.hp: campo desconocido")
	assert_has_error(r.errors, "cuartel.abilities.Train.units: 'fantasma' no existe")
	assert_has_error(r.errors, "cuartel.abilities.Train.units: 'cuartel' no es de tipo unit")
	assert_has_error(r.errors, "parche sobre 'nadie', que no existe")
	assert_eq(r.content_hash, "")


func test_missing_and_empty_roots() -> void:
	var r := Registry.new()
	assert_false(r.load_mods("res://tests/engine/fixtures/no_existe"))
	assert_has_error(r.errors, "carpeta de mods no encontrada")
	var e := Registry.new()
	assert_false(e.load_mods("res://tests/engine/fixtures/mods_empty"))
	assert_has_error(e.errors, "no hay mods")


func test_parse_json_text_bom_and_errors() -> void:
	var ok := Registry.parse_json_text("\uFEFF{\"id\": \"x\"}")
	assert_true(ok["ok"])
	assert_eq(ok["data"], {"id": "x"})
	var bad := Registry.parse_json_text("{\n\"id\": ")
	assert_false(bad["ok"])
	assert_true("línea" in str(bad["error"]), str(bad["error"]))
```

- [ ] **Step 3: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_registry` → Expected: FAIL.

- [ ] **Step 4: Implementar** — `engine/data/Registry.gd`

```gdscript
extends RefCounted
## Registry: carga mods (res://mods/<mod>/mod.json), aplica overrides y
## parches, resuelve herencia "extends", valida contra Schemas y calcula
## content_hash. Única fuente de definiciones para sim, render y UI.
## Las definiciones devueltas no deben mutarse (usar PlayerDefs).

const Merge := preload("res://engine/data/Merge.gd")
const Schemas := preload("res://engine/data/Schemas.gd")
const ENTITY_DIRS: Array[String] = ["base", "units", "buildings", "resources", "techs", "ages", "civs"]

var mods: Array[Dictionary] = []
var defs: Dictionary = {}
var abstract_defs: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var content_hash := ""

var _raw: Dictionary = {}
var _src: Dictionary = {}
var _mod_of: Dictionary = {}


func load_mods(root: String = "res://mods", enabled: Array = []) -> bool:
	mods.clear()
	defs.clear()
	abstract_defs.clear()
	errors.clear()
	warnings.clear()
	content_hash = ""
	_raw.clear()
	_src.clear()
	_mod_of.clear()
	var found := _discover(root, enabled)
	if not errors.is_empty():
		return false
	mods = _order(found)
	if not errors.is_empty():
		return false
	for m in mods:
		_load_mod_entities(m)
	var resolved := {}
	for id in _sorted(_raw):
		_resolve(id, resolved, [])
	for id in _sorted(_raw):
		var d: Dictionary = resolved.get(id, {})
		if d.is_empty():
			continue
		if bool(d.get("abstract", false)):
			abstract_defs[id] = d
		else:
			defs[id] = d
	for id in _sorted(abstract_defs):
		errors.append_array(Schemas.validate_entity(abstract_defs[id], _src[id]))
	for id in _sorted(defs):
		errors.append_array(Schemas.validate_entity(defs[id], _src[id]))
	_check_refs()
	if errors.is_empty():
		content_hash = hash_defs(defs)
	return errors.is_empty()


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func has(id: String) -> bool:
	return defs.has(id)


func source_of(id: String) -> String:
	return str(_src.get(id, ""))


func ids_of_type(type: String) -> Array[String]:
	var out: Array[String] = []
	for id in _sorted(defs):
		if str(defs[id].get("type", "")) == type:
			out.append(id)
	return out


## {ok: bool, data: Variant, error: String}. Ignora BOM UTF-8.
static func parse_json_text(text: String) -> Dictionary:
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "data": null, "error": "línea %d: %s" % [j.get_error_line(), j.get_error_message()]}
	return {"ok": true, "data": j.data, "error": ""}


static func hash_defs(d: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(d, "", true, true).to_utf8_buffer())
	return ctx.finish().hex_encode()


# ------------------------------------------------------------------ mods ---

func _discover(root: String, enabled: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		errors.append("%s: carpeta de mods no encontrada" % root)
		return out
	var names: Array = Array(dir.get_directories())
	names.sort()
	for n in names:
		var mpath := "%s/%s/mod.json" % [root, n]
		if not FileAccess.file_exists(mpath):
			continue
		var m: Variant = _read_json(mpath)
		if m == null:
			continue
		if not (m is Dictionary) or not (m.get("id") is String):
			errors.append("%s: mod.json necesita 'id' (texto)" % mpath)
			continue
		if not enabled.is_empty() and not enabled.has(m["id"]):
			continue
		out.append({
			"id": str(m["id"]),
			"version": str(m.get("version", "0")),
			"depends": Array(m.get("depends", [])),
			"priority": int(m.get("priority", 0)),
			"path": "%s/%s" % [root, n],
		})
	if out.is_empty() and errors.is_empty():
		errors.append("%s: no hay mods (ninguna carpeta con mod.json)" % root)
	return out


## Orden topológico por depends; entre listos, menor priority y luego id.
func _order(found: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := {}
	for m in found:
		ids[m["id"]] = true
	for m in found:
		for dep in m["depends"]:
			if not ids.has(dep):
				errors.append("mod %s: depende de '%s', que no está" % [m["id"], dep])
	if not errors.is_empty():
		return out
	var done := {}
	while out.size() < found.size():
		var ready: Array = []
		for m in found:
			if done.has(m["id"]):
				continue
			var ok := true
			for dep in m["depends"]:
				if not done.has(dep):
					ok = false
			if ok:
				ready.append(m)
		if ready.is_empty():
			errors.append("mods con dependencia circular")
			return []
		ready.sort_custom(func(a, b): return a["priority"] < b["priority"] or (a["priority"] == b["priority"] and a["id"] < b["id"]))
		out.append(ready[0])
		done[ready[0]["id"]] = true
	return out


func _load_mod_entities(m: Dictionary) -> void:
	for sub in ENTITY_DIRS:
		for f in _json_files("%s/%s" % [m["path"], sub]):
			var e: Variant = _read_json(f)
			if e == null:
				continue
			if not (e is Dictionary) or not (e.get("id") is String):
				errors.append("%s: la entidad necesita 'id' (texto)" % f)
				continue
			var id := str(e["id"])
			if bool(e.get("patch", false)):
				if not _raw.has(id):
					errors.append("%s: parche sobre '%s', que no existe" % [f, id])
					continue
				var p: Dictionary = (e as Dictionary).duplicate(true)
				p.erase("patch")
				_raw[id] = Merge.deep_merge(_raw[id], p)
				_src[id] = "%s (+%s)" % [_src[id], f]
				continue
			if _raw.has(id):
				if _mod_of[id] == m["id"]:
					errors.append("%s: id '%s' repetido en el mod %s (ya en %s)" % [f, id, m["id"], _src[id]])
					continue
				warnings.append("%s: sobrescribe '%s' de %s" % [f, id, _src[id]])
			_raw[id] = e
			_src[id] = f
			_mod_of[id] = m["id"]


func _json_files(dpath: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dpath)
	if dir == null:
		return out
	var files: Array = Array(dir.get_files())
	files.sort()
	for f in files:
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append("%s/%s" % [dpath, f])
	var subs: Array = Array(dir.get_directories())
	subs.sort()
	for s in subs:
		out.append_array(_json_files("%s/%s" % [dpath, s]))
	return out


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: no se pudo abrir" % path)
		return null
	var r := parse_json_text(f.get_as_text())
	if not r["ok"]:
		errors.append("%s: JSON inválido (%s)" % [path, r["error"]])
		return null
	return r["data"]


# ------------------------------------------------------------- herencia ---

func _resolve(id: String, resolved: Dictionary, stack: Array) -> Dictionary:
	if resolved.has(id):
		return resolved[id]
	if stack.has(id):
		errors.append("%s: herencia circular %s" % [_src[id], " -> ".join(PackedStringArray(stack + [id]))])
		return {}
	var own: Dictionary = _raw[id]
	var out: Dictionary
	if own.has("extends"):
		var parent_id := str(own["extends"])
		if not _raw.has(parent_id):
			errors.append("%s: %s extiende '%s', que no existe" % [_src[id], id, parent_id])
			resolved[id] = {}
			return {}
		var parent := _resolve(parent_id, resolved, stack + [id])
		if parent.is_empty():
			resolved[id] = {}
			return {}
		out = Merge.deep_merge(parent, own)
		var tags: Array = (parent.get("tags", []) as Array).duplicate()
		for t in own.get("tags", []):
			if not tags.has(t):
				tags.append(t)
		out["tags"] = tags
		out.erase("extends")
	else:
		out = own.duplicate(true)
	if bool(own.get("abstract", false)):
		out["abstract"] = true
	else:
		out.erase("abstract")
	resolved[id] = out
	return out


# ---------------------------------------------------------- referencias ---

func _check_refs() -> void:
	for id in _sorted(defs):
		var d: Dictionary = defs[id]
		var ab: Dictionary = d.get("abilities", {}) if d.get("abilities") is Dictionary else {}
		if ab.get("Train") is Dictionary:
			for u in ab["Train"].get("units", []):
				_ref(id, "abilities.Train.units", str(u), "unit")
		if ab.get("Research") is Dictionary:
			for t in ab["Research"].get("techs", []):
				_ref(id, "abilities.Research.techs", str(t), "tech")
		if ab.get("DropSite") is Dictionary:
			for r in ab["DropSite"].get("accepts", []):
				if not Schemas.RESOURCES.has(str(r)):
					errors.append("%s: %s.abilities.DropSite.accepts: recurso desconocido '%s'" % [_src[id], id, r])
		var req: Variant = d.get("requires", {})
		if req is Dictionary:
			if req.has("age"):
				_ref(id, "requires.age", str(req["age"]), "age")
			for t in req.get("techs", []):
				_ref(id, "requires.techs", str(t), "tech")
		if d.has("upgrades_to"):
			_ref(id, "upgrades_to", str(d["upgrades_to"]), "unit")
		match str(d.get("type", "")):
			"tech":
				_ref(id, "at", str(d.get("at", "")), "building")
			"civ":
				for x in d.get("disabled", []):
					if not defs.has(str(x)):
						errors.append("%s: %s.disabled: '%s' no existe" % [_src[id], id, x])
				for u in d.get("unique_units", []):
					_ref(id, "unique_units", str(u), "unit")
				for t in d.get("unique_techs", []):
					_ref(id, "unique_techs", str(t), "tech")


func _ref(id: String, field: String, target: String, type: String) -> void:
	if not defs.has(target):
		errors.append("%s: %s.%s: '%s' no existe" % [_src[id], id, field, target])
	elif str(defs[target].get("type", "")) != type:
		errors.append("%s: %s.%s: '%s' no es de tipo %s" % [_src[id], id, field, target, type])


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_registry` → Expected: `10 tests, 0 fallos`.

- [ ] **Step 6: Commit**

```bash
git add engine/data/Registry.gd tests/engine/test_registry.gd tests/engine/fixtures
git commit -m "F0: Registry de mods (herencia, parches, validación, hash)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: PlayerDefs (vista parcheada por jugador)

**Files:**
- Create: `engine/data/PlayerDefs.gd`
- Test: `tests/engine/test_player_defs.gd`

**Interfaces:**
- Consumes: `Patch.select`, `Patch.apply` (Task 4); `Registry.defs` (Task 5).
- Produces: `PlayerDefs.new(registry_defs: Dictionary, civ_id: String)`; campos `civ_id`, `defs` (copia profunda), `disabled: Dictionary` (id → true), `upgrades: Dictionary` (id → id), `researched: Array[String]`; métodos `apply_effects(effects: Array) -> Array[String]`, `research(tech_id: String) -> Array[String]`, `is_available(id: String) -> bool`, `resolve_unit(id: String) -> String`, `get_def(id: String) -> Dictionary`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_player_defs.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")


func _defs() -> Dictionary:
	return {
		"milicia": {"id": "milicia", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 4}}, "Hitpoints": {"max": 45}}},
		"hombre_armas": {"id": "hombre_armas", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 6}}, "Hitpoints": {"max": 55}}},
		"huscarle": {"id": "huscarle", "type": "unit", "tags": ["infanteria"], "abilities": {"Hitpoints": {"max": 60}}},
		"forja": {"id": "forja", "type": "tech", "effects": [
			{"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}]},
		"hombre_armas_up": {"id": "hombre_armas_up", "type": "tech", "effects": [
			{"op": "replace_entity", "from": "milicia", "to": "hombre_armas"}]},
		"godos": {"id": "godos", "type": "civ", "disabled": [], "effects": [
			{"target": "tag:infanteria", "op": "mul", "path": "cost.food", "value": 0.8}]},
		"britones": {"id": "britones", "type": "civ", "disabled": ["huscarle"], "effects": []},
	}


func test_civ_effects_and_disabled() -> void:
	var g := PlayerDefs.new(_defs(), "godos")
	assert_eq(g.get_def("milicia")["cost"]["food"], 48.0)
	assert_true(g.is_available("huscarle"))
	var b := PlayerDefs.new(_defs(), "britones")
	assert_eq(b.get_def("milicia")["cost"]["food"], 60)
	assert_false(b.is_available("huscarle"))
	assert_false(b.is_available("no_existe"))


func test_research_is_per_player() -> void:
	var src := _defs()
	var p0 := PlayerDefs.new(src, "britones")
	var p1 := PlayerDefs.new(src, "britones")
	assert_eq(p0.research("forja"), [])
	assert_eq(p0.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], 5)
	assert_eq(p1.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], 4)
	assert_eq(src["milicia"]["abilities"]["Attack"]["damage"]["melee"], 4, "registry intacto")
	assert_has_error(p0.research("forja"), "forja ya investigada")
	assert_has_error(p0.research("milicia"), "milicia no es una tecnología")


func test_replace_entity_upgrade() -> void:
	var p := PlayerDefs.new(_defs(), "britones")
	assert_eq(p.resolve_unit("milicia"), "milicia")
	p.research("hombre_armas_up")
	assert_eq(p.resolve_unit("milicia"), "hombre_armas")


func test_enable_disable_effects() -> void:
	var p := PlayerDefs.new(_defs(), "britones")
	p.apply_effects([{"target": "id:huscarle", "op": "enable"}])
	assert_true(p.is_available("huscarle"))
	p.apply_effects([{"target": "tag:infanteria", "op": "disable"}])
	assert_false(p.is_available("milicia"))
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_player_defs` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/data/PlayerDefs.gd`

```gdscript
extends RefCounted
## Vista de definiciones de UN jugador: copia del Registry con los efectos de
## su civilización y de sus tecnologías investigadas. Se recalcula al investigar,
## nunca por tick. Las mejoras afectan a las unidades vivas (leen de aquí).

const Patch := preload("res://engine/data/Patch.gd")

var civ_id := ""
var defs: Dictionary = {}
var disabled: Dictionary = {}
var upgrades: Dictionary = {}
var researched: Array[String] = []


func _init(registry_defs: Dictionary, civ: String) -> void:
	civ_id = civ
	defs = registry_defs.duplicate(true)
	var civ_def: Dictionary = defs.get(civ, {})
	for id in civ_def.get("disabled", []):
		disabled[str(id)] = true
	apply_effects(civ_def.get("effects", []))


func apply_effects(effects: Array) -> Array[String]:
	var errs: Array[String] = []
	for e in effects:
		var op := str(e["op"])
		if op == "enable" or op == "disable":
			for id in Patch.select(defs, str(e["target"])):
				if op == "disable":
					disabled[id] = true
				else:
					disabled.erase(id)
		elif op == "replace_entity":
			upgrades[str(e["from"])] = str(e["to"])
		else:
			errs.append_array(Patch.apply(defs, e))
	return errs


func research(tech_id: String) -> Array[String]:
	if researched.has(tech_id):
		return ["%s ya investigada" % tech_id]
	var tech: Dictionary = defs.get(tech_id, {})
	if str(tech.get("type", "")) != "tech":
		return ["%s no es una tecnología" % tech_id]
	researched.append(tech_id)
	return apply_effects(tech.get("effects", []))


func is_available(id: String) -> bool:
	return defs.has(id) and not disabled.has(id)


## Sigue la cadena de mejoras (milicia -> hombre_armas -> ...).
func resolve_unit(id: String) -> String:
	var cur := id
	var guard := 0
	while upgrades.has(cur) and guard < 16:
		cur = upgrades[cur]
		guard += 1
	return cur


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_player_defs` → Expected: `4 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/data/PlayerDefs.gd tests/engine/test_player_defs.gd
git commit -m "F0: PlayerDefs, vista parcheada por jugador

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: SpatialHash + World

**Files:**
- Create: `engine/sim/SpatialHash.gd`, `engine/sim/World.gd`
- Test: `tests/engine/test_world.gd`

**Interfaces:**
- Consumes: `FixedPoint.SCALE`, `FixedPoint.floordiv`, `FixedPoint.dist`, `FixedPoint.from_data` (Task 1).
- Produces:
  - `SpatialHash`: `const CELL := 4000`; `insert(id: int, p: Vector2i)`, `remove(id: int)`, `move(id: int, p: Vector2i)`, `query_radius(center: Vector2i, radius: int) -> Array[int]` (ordenado, incluye distancia == radius), `count() -> int`.
  - `World`: `tick: int`; `entities: Dictionary` (id → `{id, def_id, type, owner, pos: Vector2i}`); `components: Dictionary` (habilidad → {id → componente}); `spatial`; `spawn(def: Dictionary, owner: int, pos: Vector2i) -> int` (ids desde 1, nunca se reciclan); `despawn(id: int)`; `has_ability(id: int, ability: String) -> bool`; `comp(id: int, ability: String) -> Dictionary`; `ids_with(ability: String) -> Array[int]` (ordenado); `set_pos(id: int, p: Vector2i)`; `state_hash() -> String` (SHA-256 hex).
  - Componente = `{"params": <dict de la definición, solo lectura>}` + estado: `Hitpoints` → `hp`, `max` (int); `ResourceSource` → `amount` (punto fijo).

- [ ] **Step 1: Test que falla** — `tests/engine/test_world.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const World := preload("res://engine/sim/World.gd")
const SpatialHash := preload("res://engine/sim/SpatialHash.gd")

const SOLDADO := {"id": "soldado", "type": "unit",
	"abilities": {"Hitpoints": {"max": 45.0}, "Move": {"speed": 0.9}}}
const ARBOL := {"id": "arbol", "type": "resource",
	"abilities": {"ResourceSource": {"resource": "wood", "amount": 100.0, "rate_key": "wood"}}}


func test_spawn_creates_components() -> void:
	var w := World.new()
	var a := w.spawn(SOLDADO, 0, Vector2i(1000, 2000))
	var t := w.spawn(ARBOL, -1, Vector2i(5000, 5000))
	assert_eq([a, t], [1, 2])
	assert_eq(w.entities[a]["def_id"], "soldado")
	assert_eq(w.entities[a]["pos"], Vector2i(1000, 2000))
	var hp := w.comp(a, "Hitpoints")
	assert_eq(typeof(hp["hp"]), TYPE_INT)
	assert_eq(hp["hp"], 45)
	assert_eq(hp["max"], 45)
	assert_eq(w.comp(a, "Move")["params"]["speed"], 0.9)
	assert_eq(w.comp(t, "ResourceSource")["amount"], 100000)
	assert_true(w.has_ability(a, "Move"))
	assert_false(w.has_ability(t, "Move"))


func test_ids_with_sorted_after_despawn() -> void:
	var w := World.new()
	for i in 3:
		w.spawn(SOLDADO, 0, Vector2i(0, 0))
	w.despawn(2)
	var d := w.spawn(SOLDADO, 1, Vector2i(0, 0))
	assert_eq(d, 4, "los ids no se reciclan")
	assert_eq(w.ids_with("Move"), [1, 3, 4])
	assert_false(w.entities.has(2))
	assert_eq(w.comp(2, "Move"), {})


func test_spatial_query_radius_including_negative() -> void:
	var s := SpatialHash.new()
	s.insert(1, Vector2i(0, 0))
	s.insert(2, Vector2i(3000, 4000))
	s.insert(3, Vector2i(10000, 0))
	s.insert(4, Vector2i(-1500, -1500))
	assert_eq(s.query_radius(Vector2i(0, 0), 5000), [1, 2, 4])
	s.move(3, Vector2i(1000, 0))
	assert_eq(s.query_radius(Vector2i(0, 0), 1000), [1, 3])
	s.remove(1)
	assert_eq(s.query_radius(Vector2i(0, 0), 1000), [3])
	assert_eq(s.count(), 3)


func test_set_pos_updates_spatial() -> void:
	var w := World.new()
	var a := w.spawn(SOLDADO, 0, Vector2i(0, 0))
	w.set_pos(a, Vector2i(20000, 20000))
	assert_eq(w.spatial.query_radius(Vector2i(0, 0), 1000), [])
	assert_eq(w.spatial.query_radius(Vector2i(20000, 20000), 0), [a])


func test_state_hash_deterministic() -> void:
	var a := World.new()
	var b := World.new()
	for w in [a, b]:
		w.spawn(SOLDADO, 0, Vector2i(1000, 1000))
		w.spawn(ARBOL, -1, Vector2i(3000, 3000))
	assert_eq(a.state_hash(), b.state_hash())
	assert_eq(a.state_hash().length(), 64)
	b.set_pos(1, Vector2i(1001, 1000))
	assert_true(a.state_hash() != b.state_hash())
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_world` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/sim/SpatialHash.gd`

```gdscript
extends RefCounted
## Grilla de celdas para consultas por radio. Posiciones en punto fijo.

const FP := preload("res://engine/sim/FixedPoint.gd")
const CELL := 4 * FP.SCALE

var _cells: Dictionary = {}
var _pos: Dictionary = {}


static func cell_of(p: Vector2i) -> Vector2i:
	return Vector2i(FP.floordiv(p.x, CELL), FP.floordiv(p.y, CELL))


func insert(id: int, p: Vector2i) -> void:
	_pos[id] = p
	var c := cell_of(p)
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(id)


func remove(id: int) -> void:
	if not _pos.has(id):
		return
	var c := cell_of(_pos[id])
	_cells[c].erase(id)
	if _cells[c].is_empty():
		_cells.erase(c)
	_pos.erase(id)


func move(id: int, p: Vector2i) -> void:
	if _pos.has(id) and cell_of(_pos[id]) == cell_of(p):
		_pos[id] = p
		return
	remove(id)
	insert(id, p)


func query_radius(center: Vector2i, radius: int) -> Array[int]:
	var out: Array[int] = []
	var lo := cell_of(center - Vector2i(radius, radius))
	var hi := cell_of(center + Vector2i(radius, radius))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cy)
			if not _cells.has(c):
				continue
			for id in _cells[c]:
				if FP.dist(center, _pos[id]) <= radius:
					out.append(id)
	out.sort()
	return out


func count() -> int:
	return _pos.size()
```

- [ ] **Step 4: Implementar** — `engine/sim/World.gd`

```gdscript
extends RefCounted
## Estado único de la simulación. Estado mutable solo en enteros; los
## parámetros de cada habilidad ("params") apuntan a la definición y son
## de solo lectura. Iteración siempre por id ascendente.

const FP := preload("res://engine/sim/FixedPoint.gd")
const SpatialHash := preload("res://engine/sim/SpatialHash.gd")

var tick := 0
var entities: Dictionary = {}
var components: Dictionary = {}
var spatial := SpatialHash.new()
var _next_id := 1


func spawn(def: Dictionary, owner: int, pos: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	entities[id] = {"id": id, "def_id": str(def["id"]), "type": str(def["type"]), "owner": owner, "pos": pos}
	var ab: Dictionary = def.get("abilities", {})
	var names: Array = ab.keys()
	names.sort()
	for a in names:
		if not components.has(a):
			components[a] = {}
		components[a][id] = _init_component(str(a), ab[a])
	spatial.insert(id, pos)
	return id


func despawn(id: int) -> void:
	for a in components:
		components[a].erase(id)
	entities.erase(id)
	spatial.remove(id)


func has_ability(id: int, ability: String) -> bool:
	return components.has(ability) and components[ability].has(id)


func comp(id: int, ability: String) -> Dictionary:
	if not has_ability(id, ability):
		return {}
	return components[ability][id]


func ids_with(ability: String) -> Array[int]:
	var out: Array[int] = []
	if components.has(ability):
		out.assign(components[ability].keys())
	out.sort()
	return out


func set_pos(id: int, p: Vector2i) -> void:
	entities[id]["pos"] = p
	spatial.move(id, p)


## Hash SHA-256 del estado relevante para detectar desync.
func state_hash() -> String:
	var ids: Array = entities.keys()
	ids.sort()
	var parts := PackedStringArray([str(tick)])
	for id in ids:
		var e: Dictionary = entities[id]
		var hp := -1
		if has_ability(id, "Hitpoints"):
			hp = components["Hitpoints"][id]["hp"]
		parts.append("%d|%s|%d|%d|%d|%d" % [id, e["def_id"], e["owner"], e["pos"].x, e["pos"].y, hp])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _init_component(ability: String, params: Dictionary) -> Dictionary:
	var c := {"params": params}
	match ability:
		"Hitpoints":
			var mx := int(round(float(params["max"])))
			c["max"] = mx
			c["hp"] = mx
		"ResourceSource":
			c["amount"] = FP.from_data(float(params["amount"]))
	return c
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_world` → Expected: `5 tests, 0 fallos`.

- [ ] **Step 6: Commit**

```bash
git add engine/sim/SpatialHash.gd engine/sim/World.gd tests/engine/test_world.gd
git commit -m "F0: World (estado único) + SpatialHash

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Migrador `data/` → `mods/aoe2_base` (Python)

**Files:**
- Create: `tools/migrate_data_to_mod.py`
- Test: `tools/tests/test_migrate.py`, `tools/tests/__init__.py` (vacío)

**Interfaces:**
- Consumes: formato viejo de `data/units`, `data/buildings`, `data/techs`, `data/factions`, `data/ages/ages.json`, `data/actions.json`, `data/maps/resource_defs.json`.
- Produces: funciones puras `unit_category(u) -> str`, `convert_unit(u, rates, carry, actions, sprites_root=None) -> dict`, `derive_trains(units) -> dict[str, list[str]]`, `convert_building(b, trains, research, sprites_root=None) -> dict`, `tech_effects(ef) -> (list, dict)`, `convert_tech(t, building) -> dict`, `civ_bonus_effects(ef) -> list`, `convert_age(a, index, report) -> dict`, `convert_resource(r, defaults) -> dict`, `bases() -> list`, `write(path, obj)`, `migrate(src, out, sprites_root) -> dict` (reporte). Genera en `out/`: `mod.json`, `base/`, `units/`, `buildings/`, `resources/`, `techs/`, `ages/`, `civs/`, `maps/arabia.json`, `_migration_report.json`.

- [ ] **Step 1: Test que falla** — `tools/tests/test_migrate.py` (y `tools/tests/__init__.py` vacío)

```python
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import migrate_data_to_mod as M  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ACTIONS = {
    "repair": {"rate_hp_per_sec": 15.0, "cost_factor": 0.5},
    "convert": {"range": 8.0, "cooldown_sec": 12, "chance_base": 0.35},
    "heal": {"rate_hp_per_sec": 2.5, "range": 4.0},
    "trade": {"gold_per_trip_base": 20, "bonus_per_tile": 0.3},
}
RATES = {"wood": 0.39, "food_forage": 0.41, "food_farm": 0.32, "food_fish": 0.43, "gold": 0.38, "stone": 0.36}


class TestUnits(unittest.TestCase):
    def test_category(self):
        self.assertEqual(M.unit_category({"trained_at": "cuartel"}), "infanteria")
        self.assertEqual(M.unit_category({"trained_at": "caballeriza"}), "caballeria")
        self.assertEqual(M.unit_category({"trained_at": "castillo", "armor_class": "arquero"}), "arqueros")
        self.assertEqual(M.unit_category({"trained_at": "castillo"}), "infanteria")

    def test_ranged_unit(self):
        u = {"id": "arquero", "name": "Arquero", "hp": 30, "attack": 4, "armor_melee": 0, "armor_pierce": 0,
             "range": 5.0, "sight": 6.0, "speed": 0.96, "cost": {"wood": 25, "gold": 45}, "train_time_sec": 27,
             "pop_cost": 1, "trained_at": "arqueria", "hotkey": "Q", "projectile_speed": 12.0, "fire_cooldown_sec": 2.0}
        e = M.convert_unit(u, RATES, 10, ACTIONS)
        self.assertEqual(e["extends"], "arqueros_base")
        self.assertEqual(e["abilities"]["Attack"],
                         {"damage": {"pierce": 4}, "range": 5.0, "reload": 2.0, "projectile_speed": 12.0})
        self.assertEqual(e["train_time"], 27)
        self.assertNotIn("graphics", e)

    def test_melee_unit_bonus_and_upgrade(self):
        u = {"id": "milicia", "hp": 45, "attack": 4, "armor_melee": 0, "armor_pierce": 1, "range": 1.2,
             "sight": 4.0, "speed": 0.9, "cost": {"food": 60, "gold": 20}, "train_time_sec": 21, "pop_cost": 1,
             "trained_at": "cuartel", "bonus_vs": {"edificio": 2}, "upgrade_to": None}
        e = M.convert_unit(u, RATES, 10, ACTIONS)
        self.assertEqual(e["abilities"]["Attack"], {"damage": {"melee": 4, "edificio": 2}, "range": 0, "reload": 2.0})
        self.assertNotIn("upgrades_to", e)

    def test_villager(self):
        u = {"id": "aldeano", "hp": 25, "attack": 3, "range": 1.0, "sight": 4.0, "speed": 0.8,
             "cost": {"food": 50}, "train_time_sec": 20, "pop_cost": 1, "trained_at": "centro_urbano", "gather_carry": 10}
        ab = M.convert_unit(u, RATES, 10, ACTIONS)["abilities"]
        self.assertEqual(ab["Gather"], {"rates": RATES, "capacity": 10})
        self.assertEqual(ab["Build"], {"rate": 1.0})
        self.assertEqual(ab["Repair"], {"rate": 15.0, "cost_factor": 0.5})

    def test_derive_trains_alias_and_hotkey_order(self):
        units = [{"id": "scout", "trained_at": "caballeriza", "hotkey": "Q"},
                 {"id": "paladin", "trained_at": "caballeriza", "hotkey": "E"},
                 {"id": "jinete", "trained_at": "caballeriza", "hotkey": "W"}]
        self.assertEqual(M.derive_trains(units), {"establo": ["scout", "jinete", "paladin"]})


class TestEffects(unittest.TestCase):
    def test_blacksmith(self):
        eff, legacy = M.tech_effects({"categoria": "infanteria", "attack": 1})
        self.assertEqual(eff, [{"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}])
        self.assertEqual(legacy, {})
        eff, _ = M.tech_effects({"categoria": "arqueros", "attack": 1, "range": 1})
        self.assertEqual([e["path"] for e in eff], ["abilities.Attack.damage.pierce", "abilities.Attack.range"])

    def test_unknown_goes_to_legacy(self):
        eff, legacy = M.tech_effects({"teocracia": True})
        self.assertEqual(eff, [])
        self.assertEqual(legacy, {"teocracia": True})

    def test_civ_discount(self):
        eff = M.civ_bonus_effects({"descuento_madera": 0.1, "descuento_oro": 0.1, "aplica_a": ["arquero", "ballestero"]})
        self.assertEqual(eff, [
            {"target": "id:arquero|id:ballestero", "op": "mul", "path": "cost.wood", "value": 0.9},
            {"target": "id:arquero|id:ballestero", "op": "mul", "path": "cost.gold", "value": 0.9}])

    def test_civ_partial_bonus_not_mapped(self):
        self.assertEqual(M.civ_bonus_effects({"descuento_madera": 0.1, "raro": 1, "aplica_a": ["x"]}), [])


class TestFiles(unittest.TestCase):
    def test_write_keeps_utf8(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x", "torre.json")
            M.write(p, {"name": "Torre Vigía"})
            raw = open(p, "rb").read()
            self.assertIn("Vigía".encode("utf-8"), raw)
            self.assertEqual(json.load(open(p, encoding="utf-8"))["name"], "Torre Vigía")

    def test_migrate_real_data(self):
        with tempfile.TemporaryDirectory() as d:
            report = M.migrate(os.path.join(ROOT, "data"), d, os.path.join(ROOT, "assets", "sprites"))

            def count(sub):
                return len([f for f in os.listdir(os.path.join(d, sub)) if f.endswith(".json")])

            self.assertEqual(count("units"), 25)
            self.assertEqual(count("buildings"), 20)
            self.assertEqual(count("resources"), 8)
            self.assertEqual(count("ages"), 4)
            self.assertEqual(count("civs"), 5)
            self.assertTrue(os.path.exists(os.path.join(d, "mod.json")))
            self.assertTrue(os.path.exists(os.path.join(d, "maps", "arabia.json")))
            establo = json.load(open(os.path.join(d, "buildings", "establo.json"), encoding="utf-8"))
            self.assertIn("scout", establo["abilities"]["Train"]["units"])
            castillo = json.load(open(os.path.join(d, "buildings", "castillo.json"), encoding="utf-8"))
            self.assertIn("trebuchet", castillo["abilities"]["Train"]["units"])
            self.assertIn("dropped_train_refs", report)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Correr y ver que falla**

Run: `python -m unittest discover -s tools/tests -v`
Expected: `ModuleNotFoundError: No module named 'migrate_data_to_mod'`.

- [ ] **Step 3: Implementar** — `tools/migrate_data_to_mod.py`

```python
#!/usr/bin/env python3
"""migrate_data_to_mod.py - Convierte data/ (formato viejo) a mods/aoe2_base (habilidades).

Uso:
  py tools/migrate_data_to_mod.py [--src data] [--out mods/aoe2_base] [--sprites assets/sprites]

Regenera las carpetas de entidades de --out (idempotente). Lo que no se puede
portar automáticamente queda en <out>/_migration_report.json y en los campos
legacy_effects de techs/civs (se portan a mano en F4). Solo stdlib.
"""
import argparse
import glob
import json
import os
import shutil

RESOURCES = ["wood", "food", "gold", "stone"]
ENTITY_DIRS = ["base", "units", "buildings", "resources", "techs", "ages", "civs"]
BUILDING_ALIASES = {"caballeriza": "establo"}
CATEGORY_BY_BUILDING = {
    "cuartel": "infanteria", "arqueria": "arqueros", "establo": "caballeria",
    "taller_asedio": "asedio", "muelle": "barco", "monasterio": "monje",
    "mercado": "comercio", "centro_urbano": "aldeano",
}
CATEGORY_BY_ARMOR_CLASS = {
    "infanteria": "infanteria", "arquero": "arqueros", "caballeria": "caballeria",
    "asedio": "asedio", "ariete": "asedio", "barco": "barco", "comercio": "comercio",
}
RANGED_CATEGORIES = {"arqueros", "barco"}
GARRISONABLE = {"infanteria", "arqueros", "caballeria", "aldeano", "monje"}
DROPSITES = {
    "centro_urbano": RESOURCES, "campamento_maderero": ["wood"],
    "campamento_minero": ["gold", "stone"], "molino": ["food"], "muelle": ["food"],
}
SPRITE_PACKS = {
    "aldeano": "villager", "milicia": "militia", "arquero": "archer", "scout": "scout",
    "monje": "monk", "ariete": "ram", "barco_pesquero": "fishingship", "carreta_comercio": "cart",
}
BUILDING_SPRITES = {
    "centro_urbano": "buildings/tc/b_west_town_center_age3_x1",
    "casa": "buildings/house/b_west_house_age3_x1",
    "cuartel": "buildings/barracks/b_west_barracks_age3_x1",
}
AGE_PREREQS = {"herreria_o_mercado": ["herreria", "mercado"], "castillo_o_monasterio": ["castillo", "monasterio"]}
HOTKEY_ORDER = "QWERTASDFGZXCVB"
HUNTABLE = {"boar", "deer"}
DEFAULT_MELEE_RELOAD = 2.0  # AoE2: recarga cuerpo a cuerpo estándar
TRAIN_QUEUE = 5
TC_POP = 5
FARM_FOOD = 250  # igual que Economy.FARM_FOOD_MAX del juego viejo
UNIT_FIELDS_USED = {
    "id", "name", "hp", "attack", "armor_melee", "armor_pierce", "armor_class", "range", "sight", "speed",
    "cost", "train_time_sec", "pop_cost", "trained_at", "hotkey", "bonus_vs", "projectile_speed",
    "fire_cooldown_sec", "min_range", "splash_radius", "requires_age", "upgrade_to", "gather_carry",
    "packable", "pack_time_sec", "unpack_time_sec", "unique_to", "civ_unica",
}


def load(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def building_id(name):
    return BUILDING_ALIASES.get(name, name)


def unit_category(u):
    at = building_id(u.get("trained_at", ""))
    if at in CATEGORY_BY_BUILDING:
        return CATEGORY_BY_BUILDING[at]
    return CATEGORY_BY_ARMOR_CLASS.get(u.get("armor_class", ""), "infanteria")


def graphics_for_unit(unit_id, sprites_root):
    pack = SPRITE_PACKS.get(unit_id)
    if not pack or not sprites_root:
        return {}
    base = os.path.join(sprites_root, pack)
    if not os.path.isdir(base):
        return {}
    return {a: f"sprite:{pack}/{a}" for a in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base, a))}


def convert_unit(u, rates, carry, actions, sprites_root=None):
    cat = unit_category(u)
    e = {"id": u["id"], "type": "unit", "extends": f"{cat}_base", "name": u.get("name", u["id"])}
    ac = u.get("armor_class")
    if ac and CATEGORY_BY_ARMOR_CLASS.get(ac) != cat:
        e["tags"] = [ac]
    if u.get("requires_age"):
        e["requires"] = {"age": u["requires_age"]}
    e["cost"] = u.get("cost", {})
    e["train_time"] = u["train_time_sec"]
    e["pop_cost"] = u.get("pop_cost", 1)
    if u.get("hotkey"):
        e["hotkey"] = u["hotkey"]
    if u.get("upgrade_to"):
        e["upgrades_to"] = u["upgrade_to"]
    g = graphics_for_unit(u["id"], sprites_root)
    if g:
        e["graphics"] = g
    ab = {
        "Hitpoints": {"max": u["hp"]},
        "Armor": {"classes": {"melee": u.get("armor_melee", 0), "pierce": u.get("armor_pierce", 0)}},
        "Move": {"speed": u["speed"]},
        "Vision": {"sight": u["sight"]},
    }
    if u.get("attack", 0) > 0:
        ranged = "projectile_speed" in u
        dmg = {"pierce" if ranged else "melee": u["attack"]}
        dmg.update(u.get("bonus_vs", {}))
        atk = {"damage": dmg, "range": u["range"] if ranged else 0,
               "reload": u.get("fire_cooldown_sec", DEFAULT_MELEE_RELOAD)}
        if "min_range" in u:
            atk["min_range"] = u["min_range"]
        if "projectile_speed" in u:
            atk["projectile_speed"] = u["projectile_speed"]
        if "splash_radius" in u:
            atk["area_radius"] = u["splash_radius"]
        ab["Attack"] = atk
    if cat == "aldeano":
        ab["Gather"] = {"rates": dict(rates), "capacity": u.get("gather_carry", carry)}
        ab["Build"] = {"rate": 1.0}
        ab["Repair"] = {"rate": actions["repair"]["rate_hp_per_sec"], "cost_factor": actions["repair"]["cost_factor"]}
    if u["id"] == "barco_pesquero":
        ab["Gather"] = {"rates": {"food_fish": rates["food_fish"]}, "capacity": carry}
    if cat == "monje":
        c, h = actions["convert"], actions["heal"]
        ab["Convert"] = {"range": c["range"], "cooldown": c["cooldown_sec"], "chance": c["chance_base"]}
        ab["Heal"] = {"range": h["range"], "rate": h["rate_hp_per_sec"]}
    if cat == "comercio":
        t = actions["trade"]
        ab["Trade"] = {"gold_base": t["gold_per_trip_base"], "gold_per_tile": t["bonus_per_tile"]}
    if u.get("packable"):
        ab["Packable"] = {"pack_time": u["pack_time_sec"], "unpack_time": u["unpack_time_sec"]}
    civ = u.get("unique_to") or u.get("civ_unica")
    if civ:
        ab["Unique"] = {"civ": civ}
    e["abilities"] = ab
    return e


def derive_trains(units):
    out = {}
    for u in units:
        out.setdefault(building_id(u["trained_at"]), []).append(u)
    for b, lst in out.items():
        lst.sort(key=lambda u: (HOTKEY_ORDER.find(u["hotkey"]) if u.get("hotkey") and u["hotkey"] in HOTKEY_ORDER else 99, u["id"]))
        out[b] = [u["id"] for u in lst]
    return out


def convert_building(b, trains, research, sprites_root=None):
    e = {"id": b["id"], "type": "building", "extends": "edificio_base", "name": b.get("name", b["id"]),
         "cost": b.get("cost", {}), "build_time": b["build_time_sec"], "footprint": b["size_tiles"]}
    if b.get("requires_age"):
        e["requires"] = {"age": b["requires_age"]}
    sp = BUILDING_SPRITES.get(b["id"])
    if sp and sprites_root and os.path.isdir(os.path.join(sprites_root, sp)):
        e["graphics"] = {"idle": f"sprite:{sp}"}
    ab = {"Hitpoints": {"max": b["hp"]},
          "Armor": {"classes": {"melee": b.get("armor_melee", 0), "pierce": b.get("armor_pierce", 0)}}}
    if "sight" in b:
        ab["Vision"] = {"sight": b["sight"]}
    if trains:
        ab["Train"] = {"units": list(trains), "queue": TRAIN_QUEUE}
        ab["RallyPoint"] = {}
    if research:
        ab["Research"] = {"techs": list(research)}
    if b["id"] in DROPSITES:
        ab["DropSite"] = {"accepts": list(DROPSITES[b["id"]])}
    if b.get("garrison_max"):
        ab["Garrison"] = {"capacity": b["garrison_max"], "arrows_per_unit": 1}
    if b.get("attack", 0) > 0:
        ab["Attack"] = {"damage": {"pierce": b["attack"]}, "range": b["range"], "reload": DEFAULT_MELEE_RELOAD}
    if "pop_supply" in b:
        ab["ProvidesPop"] = {"amount": b["pop_supply"]}
    if b["id"] == "centro_urbano":
        ab["ProvidesPop"] = {"amount": TC_POP}
        ab["AgeAdvance"] = {}
        ab["Bell"] = {}
    if b["id"] == "granja":
        ab["Farm"] = {"food": FARM_FOOD, "rate_key": "food_farm"}
    if b.get("wonder"):
        ab["Wonder"] = {"victory_time": b.get("victory_time_min", 0) * 60}
    e["abilities"] = ab
    return e


def tech_effects(ef):
    """Efectos del formato viejo -> (efectos portables, legacy sin portar)."""
    if "aplica_a" in ef:
        target = "|".join(f"id:{x}" for x in ef["aplica_a"])
    elif ef.get("categoria") in ("infanteria", "arqueros", "caballeria", "barco"):
        target = f"tag:{ef['categoria']}"
    else:
        target = None
    ranged = ef.get("categoria") in RANGED_CATEGORIES
    paths = {
        "attack": "abilities.Attack.damage." + ("pierce" if ranged else "melee"),
        "armor_melee": "abilities.Armor.classes.melee",
        "armor_pierce": "abilities.Armor.classes.pierce",
        "range": "abilities.Attack.range",
        "hp": "abilities.Hitpoints.max",
        "bonus_vs_edificio": "abilities.Attack.damage.edificio",
    }
    effects, legacy = [], {}
    for k, v in ef.items():
        if k in ("categoria", "aplica_a"):
            continue
        numeric = isinstance(v, (int, float)) and not isinstance(v, bool)
        if k in paths and target and numeric:
            effects.append({"target": target, "op": "add", "path": paths[k], "value": v})
        else:
            legacy[k] = v
    if legacy:
        for k in ("categoria", "aplica_a"):
            if k in ef:
                legacy[k] = ef[k]
    return effects, legacy


def convert_tech(t, building):
    e = {"id": t["id"], "type": "tech", "name": t.get("nombre", t["id"]), "cost": t.get("coste", {}),
         "research_time": t.get("tiempo_sec", 0), "at": building_id(building)}
    if t.get("descripcion"):
        e["description"] = t["descripcion"]
    req = {}
    if t.get("edad"):
        req["age"] = t["edad"]
    if t.get("requiere"):
        req["techs"] = list(t["requiere"])
    if req:
        e["requires"] = req
    effects, legacy = tech_effects(t.get("efectos", {}))
    e["effects"] = effects
    if legacy:
        e["legacy_effects"] = legacy
    return e


def civ_bonus_effects(ef):
    """Bonus de civ portables (descuentos, HP). Si queda algo sin mapear -> []."""
    if "aplica_a" not in ef:
        return []
    target = "|".join(f"id:{x}" for x in ef["aplica_a"])
    out, handled = [], {"aplica_a"}
    for key, path in (("descuento_madera", "cost.wood"), ("descuento_oro", "cost.gold")):
        if key in ef:
            out.append({"target": target, "op": "mul", "path": path, "value": round(1 - ef[key], 6)})
            handled.add(key)
    if "hp_caballeria_bonus" in ef:
        out.append({"target": target, "op": "mul", "path": "abilities.Hitpoints.max",
                    "value": round(1 + ef["hp_caballeria_bonus"], 6)})
        handled.add("hp_caballeria_bonus")
    if set(ef) - handled:
        return []
    return out


def convert_age(a, index, report):
    e = {"id": a["id"], "type": "age", "name": a.get("name", a["id"]), "index": index,
         "cost": a.get("cost", {}), "research_time": a.get("research_time_sec", 0)}
    for r in a.get("requires", []):
        if r in AGE_PREREQS:
            e["prerequisite_buildings"] = {"any_of": AGE_PREREQS[r], "count": 1}
        else:
            report["warnings"].append(f"edad {a['id']}: requisito '{r}' sin mapear")
    return e


def convert_resource(r, defaults):
    rr = {**defaults, **r}
    src = {"resource": rr["resource"], "amount": rr["amount"], "rate_key": rr["gather"]["rate_key"]}
    if rr.get("infinite"):
        src["infinite"] = True
    if r["id"] in HUNTABLE:
        src["requires_kill"] = True
    for flag in ("hostile", "tame", "flees", "water"):
        if rr.get(flag):
            src[flag] = True
    return {"id": r["id"], "type": "resource", "name": rr.get("name", r["id"]), "tags": ["recurso"],
            "abilities": {"ResourceSource": src}}


def bases():
    out = [
        {"id": "unidad_base", "type": "unit", "abstract": True, "tags": ["unidad"], "abilities": {"Selectable": {}}},
        {"id": "edificio_base", "type": "building", "abstract": True, "tags": ["edificio"], "abilities": {"Selectable": {}}},
    ]
    for cat in sorted(set(CATEGORY_BY_BUILDING.values()) | set(CATEGORY_BY_ARMOR_CLASS.values())):
        b = {"id": f"{cat}_base", "type": "unit", "abstract": True, "extends": "unidad_base", "tags": [cat], "abilities": {}}
        if cat in GARRISONABLE:
            b["abilities"]["Garrisonable"] = {}
        out.append(b)
    return out


def migrate(src, out, sprites_root):
    report = {"dropped_train_refs": {}, "legacy_effects": {}, "unported_fields": {}, "warnings": []}
    actions = load(os.path.join(src, "actions.json"))["actions"]
    rates = actions["gather"]["rates_per_sec"]
    carry = actions["gather"]["carry_capacity"]
    units = [load(p) for p in sorted(glob.glob(os.path.join(src, "units", "*.json")))]
    buildings = [load(p) for p in sorted(glob.glob(os.path.join(src, "buildings", "*.json")))]
    factions = [load(p) for p in sorted(glob.glob(os.path.join(src, "factions", "*.json")))]
    tech_files = [load(p) for p in sorted(glob.glob(os.path.join(src, "techs", "*.json")))]
    unit_ids = {u["id"] for u in units}
    building_ids = {b["id"] for b in buildings}

    for sub in ENTITY_DIRS + ["maps"]:
        shutil.rmtree(os.path.join(out, sub), ignore_errors=True)
    write(os.path.join(out, "mod.json"), {"id": "aoe2_base", "version": "0.3.0", "depends": [], "priority": 0})
    for b in bases():
        write(os.path.join(out, "base", b["id"] + ".json"), b)

    # Unidades
    for u in units:
        extra = sorted(set(u) - UNIT_FIELDS_USED)
        if extra:
            report["unported_fields"][u["id"]] = extra
        if building_id(u.get("trained_at", "")) not in building_ids:
            report["warnings"].append(f"unidad {u['id']}: trained_at '{u.get('trained_at')}' no existe")
        write(os.path.join(out, "units", u["id"] + ".json"), convert_unit(u, rates, carry, actions, sprites_root))

    # Tecnologías (archivos de edificio + únicas de civ); la primera definición gana
    techs, research, unique_techs_by_civ = {}, {}, {}

    def add_tech(t, building, civ=None):
        if t["id"] in techs:
            report["warnings"].append(f"tech {t['id']} duplicada: se conserva la primera")
            return
        e = convert_tech(t, building)
        techs[t["id"]] = e
        research.setdefault(e["at"], []).append(t["id"])
        if civ:
            unique_techs_by_civ.setdefault(civ, []).append(t["id"])
        if "legacy_effects" in e:
            report["legacy_effects"][t["id"]] = e["legacy_effects"]

    for tf in tech_files:
        for t in tf["techs"]:
            add_tech(t, tf["building"], tf.get("civ"))
    for f in factions:
        for t in f.get("unique_techs", []):
            add_tech(t, t.get("edificio", "castillo"), f["id"])
    for tid, e in techs.items():
        if e["at"] not in building_ids:
            report["warnings"].append(f"tech {tid}: edificio '{e['at']}' no existe")
        write(os.path.join(out, "techs", tid + ".json"), e)

    # Edificios (Train se deriva de trained_at de las unidades)
    trains = derive_trains(units)
    for b in buildings:
        dropped = [x for x in b.get("trains", []) if x not in trains.get(b["id"], [])]
        if dropped:
            report["dropped_train_refs"][b["id"]] = dropped
        e = convert_building(b, trains.get(b["id"], []), research.get(b["id"], []), sprites_root)
        write(os.path.join(out, "buildings", b["id"] + ".json"), e)

    # Recursos
    rd = load(os.path.join(src, "maps", "resource_defs.json"))
    for r in rd["resources"]:
        write(os.path.join(out, "resources", r["id"] + ".json"), convert_resource(r, rd.get("defaults", {})))

    # Edades
    for i, a in enumerate(load(os.path.join(src, "ages", "ages.json"))["ages"]):
        write(os.path.join(out, "ages", a["id"] + ".json"), convert_age(a, i, report))

    # Civilizaciones
    unique_units_by_civ = {}
    for u in units:
        civ = u.get("unique_to") or u.get("civ_unica")
        if civ:
            unique_units_by_civ.setdefault(civ, set()).add(u["id"])
    for f in factions:
        uu = f.get("unique_unit", {}).get("id")
        if uu in unit_ids:
            unique_units_by_civ.setdefault(f["id"], set()).add(uu)
        elif uu:
            report["warnings"].append(f"civ {f['id']}: unidad única '{uu}' no existe")
    known = unit_ids | set(techs)
    for f in factions:
        cid = f["id"]
        effects, legacy = [], []
        for bonus in f.get("bonus", []):
            mapped = civ_bonus_effects(bonus.get("efecto", {}))
            if mapped:
                effects.extend(mapped)
            else:
                legacy.append(bonus)
        if f.get("team_bonus"):
            legacy.append({"team_bonus": f["team_bonus"]})
        disabled = set()
        for other, ids in unique_units_by_civ.items():
            if other != cid:
                disabled |= ids
        for other, ids in unique_techs_by_civ.items():
            if other != cid:
                disabled |= set(ids)
        for _building, entries in f.get("tech_tree", {}).items():
            if isinstance(entries, dict):
                for x, ok in entries.items():
                    if ok is False and x in known:
                        disabled.add(x)
        e = {"id": cid, "type": "civ", "name": f.get("name", cid), "color": f.get("roof_color", "#ffffff"),
             "effects": effects, "disabled": sorted(disabled),
             "unique_units": sorted(unique_units_by_civ.get(cid, set())),
             "unique_techs": sorted(unique_techs_by_civ.get(cid, []))}
        if legacy:
            e["legacy_effects"] = legacy
            report["legacy_effects"][cid] = [b.get("id", "team_bonus") for b in legacy]
        write(os.path.join(out, "civs", cid + ".json"), e)

    # Mapas (los usa el cargador de mapas de F1; el Registry no los lee)
    os.makedirs(os.path.join(out, "maps"), exist_ok=True)
    shutil.copy(os.path.join(src, "maps", "arabia.json"), os.path.join(out, "maps", "arabia.json"))

    write(os.path.join(out, "_migration_report.json"), report)
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default="data")
    ap.add_argument("--out", default=os.path.join("mods", "aoe2_base"))
    ap.add_argument("--sprites", default=os.path.join("assets", "sprites"))
    args = ap.parse_args()
    report = migrate(args.src, args.out, args.sprites)
    print(f"[migrate] OK -> {args.out}")
    print(f"[migrate] refs de Train descartadas: {sum(len(v) for v in report['dropped_train_refs'].values())}")
    print(f"[migrate] entidades con efectos sin portar: {len(report['legacy_effects'])}")
    print(f"[migrate] avisos: {len(report['warnings'])}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `python -m unittest discover -s tools/tests -v`
Expected: `Ran 12 tests ... OK`. Si `test_migrate_real_data` falla por conteos, revisar que `data/` no cambió (25 unidades, 20 edificios, 8 recursos, 4 edades, 5 civs).

- [ ] **Step 5: Commit**

```bash
git add tools/migrate_data_to_mod.py tools/tests
git commit -m "F0: migrador data/ -> mods/aoe2_base

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Generar `mods/aoe2_base`, validarlo con el Registry y CLI `validate_mods`

**Files:**
- Create (generado): `mods/aoe2_base/**`
- Create: `tools/validate_mods.gd`, `tests/engine/test_aoe2_base.gd`
- Modify: `tests/run_all.sh` (añadir tests del motor), `docs/MODDING.md` (sección nuevo formato), `.gitignore` (nada que ignorar en mods/: se commitea)

**Interfaces:**
- Consumes: `Registry` (Task 5), `PlayerDefs` (Task 6), migrador (Task 8).
- Produces: `mods/aoe2_base` válido (0 errores, `content_hash` estable); CLI `godot --headless --path . -s tools/validate_mods.gd [-- --root=res://mods]` que sale 0/1.

- [ ] **Step 1: Generar el mod**

Run: `python tools/migrate_data_to_mod.py`
Expected: `[migrate] OK -> mods/aoe2_base` y los contadores. Revisar `mods/aoe2_base/_migration_report.json`: se esperan `dropped_train_refs` (p. ej. `castillo: ["unidad_unica","trabuquete","petardo"]`, `establo: ["camello"]`) y `legacy_effects` para techs de monasterio/universidad y bonus de civ no mapeables.

- [ ] **Step 2: Test que falla** — `tests/engine/test_aoe2_base.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")


func _reg() -> Registry:
	var r := Registry.new()
	r.load_mods("res://mods")
	return r


func test_aoe2_base_loads_without_errors() -> void:
	var r := _reg()
	assert_eq(r.errors, [])
	assert_eq(r.ids_of_type("unit").size(), 25)
	assert_eq(r.ids_of_type("building").size(), 20)
	assert_eq(r.ids_of_type("resource").size(), 8)
	assert_eq(r.ids_of_type("age").size(), 4)
	assert_eq(r.ids_of_type("civ").size(), 5)
	assert_eq(r.content_hash.length(), 64)


func test_key_gameplay_data() -> void:
	var r := _reg()
	var aldeano := r.get_def("aldeano")
	assert_eq(aldeano["abilities"]["Gather"]["rates"]["wood"], 0.39)
	assert_eq(aldeano["abilities"]["Gather"]["capacity"], 10)
	assert_true(aldeano["tags"].has("aldeano") and aldeano["tags"].has("unidad"))
	assert_true(aldeano["abilities"].has("Garrisonable"))
	assert_true(r.get_def("cuartel")["abilities"]["Train"]["units"].has("milicia"))
	assert_true(r.get_def("establo")["abilities"]["Train"]["units"].has("scout"))
	assert_eq(r.get_def("centro_urbano")["abilities"]["DropSite"]["accepts"], ["wood", "food", "gold", "stone"])
	assert_eq(r.get_def("casa")["abilities"]["ProvidesPop"]["amount"], 5)
	assert_true(r.get_def("herreria")["abilities"]["Research"]["techs"].has("forja"))


func test_civs_and_techs_apply() -> void:
	var r := _reg()
	var brit := PlayerDefs.new(r.defs, "britones")
	assert_eq(brit.get_def("arquero")["cost"]["wood"], 22.5)
	assert_false(brit.is_available("paladin_franco"))
	assert_true(brit.is_available("arquero_tiro_largo"))
	var fr := PlayerDefs.new(r.defs, "francos")
	assert_true(fr.is_available("paladin_franco"))
	assert_false(fr.is_available("arquero_tiro_largo"))
	var before: float = fr.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"]
	assert_eq(fr.research("forja"), [])
	assert_eq(fr.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], before + 1)


func test_hash_is_stable_between_loads() -> void:
	assert_eq(_reg().content_hash, _reg().content_hash)
```

- [ ] **Step 3: Correr**

Run: `sh tests/engine/run.sh test_aoe2_base`
Expected: `4 tests, 0 fallos`. Si hay errores de validación, **corregir el migrador** (no los JSON generados a mano), regenerar (Step 1) y repetir. Errores típicos: bonus a clases con nombre de unidad (`"milicia"` en `bonus_vs`) son válidos (class_map admite cualquier texto); un `requires.age` con edad inexistente se corrige mapeándolo en el migrador.

- [ ] **Step 4: CLI** — `tools/validate_mods.gd`

```gdscript
extends SceneTree
## Valida los mods y muestra errores, avisos y content_hash.
## Uso: godot --headless --path . -s tools/validate_mods.gd [-- --root=res://mods]
## Sale 0 si no hay errores, 1 si los hay.

const Registry := preload("res://engine/data/Registry.gd")


func _initialize() -> void:
	var root := "res://mods"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--root="):
			root = str(a).get_slice("=", 1)
	var r := Registry.new()
	var ok := r.load_mods(root)
	print("[validate_mods] mods: %s" % ", ".join(PackedStringArray(r.mods.map(func(m): return "%s@%s" % [m["id"], m["version"]]))))
	for w in r.warnings:
		print("[aviso] " + w)
	for e in r.errors:
		printerr("[error] " + e)
	if ok:
		var counts := []
		for t in ["unit", "building", "resource", "tech", "age", "civ"]:
			counts.append("%s=%d" % [t, r.ids_of_type(t).size()])
		print("[validate_mods] OK  %s" % " ".join(PackedStringArray(counts)))
		print("[validate_mods] content_hash %s" % r.content_hash)
	else:
		print("[validate_mods] %d errores" % r.errors.size())
	quit(0 if ok else 1)
```

Run: `"$GODOT" --headless --path . -s tools/validate_mods.gd`
Expected: `[validate_mods] OK  unit=25 building=20 resource=8 tech=44 age=4 civ=5` (36 techs de edificio + 8 únicas de civ; las 2 vikingas duplicadas se reportan y se conservan una vez) y una línea `content_hash`.

- [ ] **Step 5: Integrar en `tests/run_all.sh`**

Añadir antes de `echo "[run_all] 1/2 Lan8Bots..."`:

```sh
code_eng=0
echo "[run_all] 0/2 Motor nuevo (tests/engine)..."
"$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" || code_eng=$?
```

y en el resumen/salida:

```sh
if [ "$code_eng" -eq 0 ]; then echo "[run_all] Motor nuevo:   PASS"; else echo "[run_all] Motor nuevo:   FAIL ($code_eng)"; fi
```

cambiando la condición final a `if [ "$code_eng" -ne 0 ] || [ "$code_lan" -ne 0 ] || [ "$code_bal" -ne 0 ]; then`.

- [ ] **Step 6: Documentar en `docs/MODDING.md`**

Añadir al final:

```markdown
## Formato nuevo (motor por habilidades) — `mods/`

El motor nuevo lee `mods/<mod>/` (el juego viejo sigue leyendo `data/` hasta la fase F5).

- `mod.json`: `{"id": "mi_mod", "version": "1", "depends": ["aoe2_base"], "priority": 10}`
- Entidades en `base/ units/ buildings/ resources/ techs/ ages/ civs/`, un JSON por entidad.
  Archivos que empiezan con `_` se ignoran.
- Herencia: `"extends": "infanteria_base"` (los `tags` se suman).
- Parchear algo de otro mod: mismo `id` + `"patch": true` con solo los campos a cambiar.
- Unidad nueva = copiar `mods/aoe2_base/units/milicia.json`, cambiar `id` y habilidades, y añadir
  el id a `abilities.Train.units` de un edificio (con un parche).
- Habilidades disponibles y sus campos: `engine/data/Schemas.gd` (`ABILITIES`).
- Validar: `godot --headless --path . -s tools/validate_mods.gd` (errores con archivo y campo).
- `mods/aoe2_base` se genera con `py tools/migrate_data_to_mod.py`; lo no portado está en
  `mods/aoe2_base/_migration_report.json`.
```

- [ ] **Step 7: Correr todo y commit**

Run: `sh tests/engine/run.sh` → Expected: todos los tests en verde (`… tests, 0 fallos`).
Run: `python -m unittest discover -s tools/tests` → Expected: `OK`.

```bash
git add mods/aoe2_base tools/validate_mods.gd tests/engine/test_aoe2_base.gd tests/run_all.sh docs/MODDING.md
git commit -m "F0: mods/aoe2_base generado y validado + CLI validate_mods

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Lint de arquitectura

**Files:**
- Test: `tests/engine/test_architecture.gd`

**Interfaces:**
- Consumes: el contenido de `res://engine/sim` y `res://engine/data`.
- Produces: test que falla con `archivo:línea: token` si alguien usa APIs visuales, de tiempo o aleatorias en la simulación/datos.

- [ ] **Step 1: Escribir el test** — `tests/engine/test_architecture.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"
## engine/sim y engine/data deben ser deterministas y sin dependencias visuales.

const DIRS := ["res://engine/sim", "res://engine/data"]
const FORBIDDEN := ["Node2D", "Node3D", "Sprite2D", "Sprite3D", "Time.", "randf(", "randi(",
	"randomize(", "OS.get_ticks", "RandomNumberGenerator"]


func test_sim_and_data_are_pure() -> void:
	var violations: Array[String] = []
	for d in DIRS:
		for path in _gd_files(d):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var code := lines[i].get_slice("#", 0)
				for tok in FORBIDDEN:
					if tok in code:
						violations.append("%s:%d: %s" % [path, i + 1, tok])
	assert_eq(violations, [])


func test_lint_detects_forbidden_token() -> void:
	var code := "var x := randf()  # comentario".get_slice("#", 0)
	assert_true("randf(" in code)
	assert_false("Time." in "var t := 1 # Time.get_ticks_msec()".get_slice("#", 0))


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, f])
	for s in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [dir_path, s]))
	return out
```

- [ ] **Step 2: Correr**

Run: `sh tests/engine/run.sh test_architecture`
Expected: `2 tests, 0 fallos`. Comprobación manual: añadir temporalmente `var z := randf()` a `engine/sim/World.gd`, ver que el test falla señalando `World.gd:<línea>: randf(`, y revertir.

- [ ] **Step 3: Suite completa y commit**

Run: `sh tests/run_all.sh 600` → Expected: `Motor nuevo: PASS` (Lan8Bots/BalanceTester siguen como antes: el juego viejo no se tocó).

```bash
git add tests/engine/test_architecture.gd
git commit -m "F0: lint de arquitectura para engine/sim y engine/data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Qué queda para F1 (no es parte de este plan)

Autoloads `Registry`/`Sim`, render 2D isométrico, `AssetLocator` + importador, `MoveSystem` + pathfinding sobre `World`, escena "Partida (nuevo motor)". Se planifica aparte al cerrar F0.
