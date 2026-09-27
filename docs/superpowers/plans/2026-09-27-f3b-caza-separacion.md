# F3b — Caza, ovejas, represalia y separación de unidades: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Caza estilo AoE2 (ciervo, jabalí que contraataca, ovejas que se capturan por vista y se pueden arrear), represalia de militares atacados fuera de su vista, y separación para que las unidades no se amontonen.

**Architecture:** Los animales son `resource` con `Hitpoints`/`Move` (y `Attack` el jabalí) generados por el migrador con sus sprites (`assets/sprites/animals/*`, extraídos con el extractor del proyecto). Al morir quedan como **carcasa** (`ResourceSource.killed`, sin `Hitpoints/Move/Attack`) en vez de desaparecer. `GatherSystem` agrega el estado `hunting` (ataca con `CombatSystem` hasta que el animal cae y luego recolecta). `CombatSystem.apply_damage` hace represalia. `HerdSystem` asigna ovejas por vista. `SeparationSystem` empuja unidades superpuestas. `MapGen` coloca 4 ovejas propias, 2 jabalíes y ciervos por jugador.

**Tech Stack:** Godot 4.4 GDScript, Python 3.12.

**Spec:** §5.2 (caza, ovejas), §5.3 (combate), §10-F3.

## Global Constraints

- Tests: `GODOT=/c/Users/Asus/AppData/Local/Temp/opencode/godot44/Godot_v4.4-stable_win64_console.exe sh tests/engine/run.sh [test_x]` (única suite); Python `python -m unittest discover -s tools/tests`.
- Sim determinista (enteros, orden por id); render solo lee. Write/Edit para GDScript. `git add` con rutas explícitas (el usuario trabaja en paralelo en `main`).
- Datos AoE2: ciervo 5 HP (vel. 1.1), jabalí 75 HP (vel. 1.0, ataque 8 cuerpo a cuerpo, armadura 0/1), oveja 7 HP (vel. 0.7); comida ciervo 140, jabalí 340, oveja 100.

## Review Focus

1. **Varios aldeanos cazando el mismo ciervo / carcasa agotada**: nadie queda atascado; siguen con el siguiente animal cercano, nunca con un jabalí por su cuenta. → `test_retarget_after_carcass_skips_boar`.
2. **Oveja ajena**: no se puede recolectar ni robar si su dueño tiene unidades cerca; sí se captura si se queda sola. → `test_sheep_capture_and_steal`, `test_cannot_gather_enemy_sheep`.
3. **Represalia**: aldeanos no contraatacan (AoE2); militares sí aunque el atacante esté fuera de su vista; el jabalí persigue al que lo atacó. → `test_boar_fights_back`, `test_military_retaliates_out_of_sight`.
4. **Separación**: nunca empuja a una casilla bloqueada; una unidad sola no se mueve; determinista. → `test_separation_*`.
5. **Animales no bloquean casillas** (se mueven) y su carcasa tampoco. → `test_animals_do_not_block`.

---

### Task 1: Migrador — animales con HP, movimiento, ataque y sprites

**Files:** `tools/migrate_data_to_mod.py`, `tools/tests/test_migrate.py`; regenerar `mods/aoe2_base`; commitear los `manifest*.json` de `assets/sprites/animals/*/*/` (los PNG siguen ignorados).

- [ ] Test (en `TestFiles`):

```python
    def test_animals_have_hp_move_and_sprites(self):
        with tempfile.TemporaryDirectory() as d:
            for anim in ("idle", "walk", "attack", "death", "decay"):
                os.makedirs(os.path.join(d, "animals", "boar", anim))
            rd = {"id": "boar", "resource": "food", "amount": 340, "hostile": True, "gather": {"rate_key": "food_forage"}}
            e = M.convert_resource(rd, {}, d)
            ab = e["abilities"]
            self.assertEqual(ab["Hitpoints"], {"max": 75})
            self.assertEqual(ab["Move"], {"speed": 1.0})
            self.assertEqual(ab["Attack"], {"damage": {"melee": 8}, "range": 0, "reload": 2.0})
            self.assertTrue(ab["ResourceSource"]["requires_kill"])
            self.assertEqual(e["graphics"]["decay"], "sprite:animals/boar/decay")
        sheep = M.convert_resource({"id": "sheep", "resource": "food", "amount": 100, "tame": True, "gather": {"rate_key": "food_forage"}}, {})
        self.assertTrue(sheep["abilities"]["ResourceSource"]["requires_kill"], "las ovejas también se matan antes de recolectar")
        self.assertEqual(sheep["abilities"]["Hitpoints"], {"max": 7})
```

- [ ] Implementar: constante

```python
ANIMALS = {
    "deer": {"hp": 5, "speed": 1.1},
    "boar": {"hp": 75, "speed": 1.0, "attack": 8, "armor": {"melee": 0, "pierce": 1}},
    "sheep": {"hp": 7, "speed": 0.7},
}
```

`RESOURCE_SPRITES` + `"deer": "animals/deer", "boar": "animals/boar", "sheep": "animals/sheep"`; `HUNTABLE` incluye `sheep`. En `convert_resource`: si el pack del recurso tiene subcarpetas, `graphics = {sub: "sprite:<pack>/<sub>"}`; si no, `{"idle": "sprite:<pack>"}`. Si `r["id"] in ANIMALS`: `Hitpoints {max}`, `Move {speed}`, `Armor {classes: armor or {melee: 0, pierce: 0}}` y, si tiene `attack`, `Attack {damage: {melee: n}, range: 0, reload: 2.0}`.
- [ ] Unittest OK; migrar; `validate_mods` OK. Commit "F3b: animales con HP, movimiento, ataque y sprites".

### Task 2: Carcasas, animales que no bloquean, caza, represalia

**Files:** `engine/sim/World.gd` (`remove_component`, `ResourceSource.killed`), `engine/sim/Sim.gd` (`spawn`/`remove` no bloquean si la entidad tiene `Move`; `kill` convierte en carcasa si `requires_kill`), `engine/sim/systems/CombatSystem.gd` (`apply_damage(sim, atk, t, attacker := -1)` con represalia; proyectiles guardan `src`), `engine/sim/systems/GatherSystem.gd` (estado `hunting`, filtros de `_retarget` y de ovejas ajenas); Test `tests/engine/test_hunting.gd`.

**Interfaces:** `World.remove_component(id, ability)`; `ResourceSource` comp `killed: bool`; evento `{"type": "carcass", "id", "pos", "facing"}`; `GatherSystem` estado `"hunting"`.

- [ ] Tests (`tests/engine/test_hunting.gd`): `test_villager_hunts_deer_then_gathers`, `test_boar_fights_back`, `test_retarget_after_carcass_skips_boar`, `test_cannot_gather_enemy_sheep`, `test_military_retaliates_out_of_sight`, `test_animals_do_not_block`, `test_hunting_deterministic` (código en el archivo de test; ver Step de implementación).
- [ ] Implementación clave:
  - `Sim.kill(id)`: si tiene `ResourceSource` con `requires_kill` → quitar `Hitpoints`, `Attack`, `Armor`, `Move`; `killed = true`; evento `carcass`; no eliminar.
  - `CombatSystem._hit`/`_land` pasan el atacante; `apply_damage`: tras restar HP, si el objetivo sigue vivo, tiene `Attack`, no tiene `Gather` y su `target < 0` → `order_attack(objetivo, atacante)`.
  - `GatherSystem.order_gather`: oveja con dueño distinto → ignorar; si `requires_kill` y no `killed` → estado `hunting` + `CombatSystem.order_attack`. En `step`, `hunting`: objetivo desaparecido → `_retarget`; `killed` → `CombatSystem.stop` y `order_gather` de nuevo.
  - `_retarget`: saltar `hostile` vivo, ovejas ajenas y `water`.
- [ ] Suite verde. Commit "F3b: caza, carcasas y represalia".

### Task 3: HerdSystem (ovejas por vista) + SeparationSystem

**Files:** Create `engine/sim/systems/HerdSystem.gd`, `engine/sim/systems/SeparationSystem.gd`; Modify `Sim.step` (orden: comandos → Move → Separation → Combat → Gather → Herd); Test `tests/engine/test_herd_separation.gd`.

**Interfaces:** `HerdSystem.RADIUS := 4000`, `EVERY := 5`; `SeparationSystem.SEP := 400`.

- [ ] Tests: `test_sheep_capture_and_steal`, `test_separation_spreads_stacked_units`, `test_separation_leaves_single_unit`, `test_separation_never_into_blocked`, `test_separation_deterministic`.
- [ ] Reglas: oveja viva (`tame`, con `Hitpoints`) cada `EVERY` ticks: si su dueño no tiene unidades a ≤ `RADIUS`, pasa al jugador de la unidad más cercana a ≤ `RADIUS` (desempate por id). Separación: por pares (a < b) de entidades con `Move` a menos de `SEP`, cada una se aparta `(SEP - d) / 2` en la dirección que las une (si coinciden, dirección fija por id), solo si la casilla destino es caminable.
- [ ] Commit "F3b: ovejas por vista y separación de unidades".

### Task 4: Render — carcasas, recolor, marcas; MapGen con animales

**Files:** `engine/render2d/EntityLayer.gd` (evento `carcass` → `death` una vez ~1.2 s y luego `decay` fijo; recolor si cambia el dueño), `engine/render2d/EntityView.gd` (`set_color`, `FPS["decay"] = 0`, `owned` para marca de animales propios), `engine/sim/MapGen.gd` (por jugador: 4 ovejas propias a 4–6 casillas, 2 jabalíes a ~15, 4 ciervos a ~19); Tests `tests/engine/test_combat_render.gd`, `tests/engine/test_mapgen.gd` (añadir).
- [ ] Verificación visual: aldeanos cazando un ciervo y arreando ovejas; captura.
- [ ] Commit "F3b: render de caza y animales en el mapa".

### Task 5: Docs y suite

- [ ] `docs/SPRITES.md`: animales (`assets/sprites/animals/<animal>/<anim>`, extraídos de `a_hunt_*`/`a_herd_*`). `docs/CONTROLES.md`: clic derecho sobre animal = cazar; ovejas propias se seleccionan y mueven.
- [ ] Suite verde; commit "F3b: documentación".
