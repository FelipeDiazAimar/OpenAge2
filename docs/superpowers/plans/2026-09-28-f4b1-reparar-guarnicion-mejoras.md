# F4b-1 — Mejoras de línea, reparación, guarnición y campana: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jugabilidad AoE2 que falta tras F4a: las mejoras de línea (`replace_entity`) convierten las unidades vivas y cambian qué entrena cada edificio; los aldeanos reparan edificios pagando recursos; las unidades se guarecen en edificios (más flechas, a salvo) y la campana del centro urbano mete y saca a los aldeanos.

**Architecture:**
- Mejoras: `Sim.complete_research` detecta efectos `replace_entity` y convierte las entidades vivas del jugador (`World.convert_entity`: cambia `def_id`, re-apunta `params`, conserva estado y HP proporcional). `train_error` rechaza unidades ya mejoradas ("mejorada a X") y destinos de mejora no investigados ("requiere mejora").
- Reparación: en `BuildSystem` (estados `to_repair`/`repairing` del componente `Build`); HP por tick = `Repair.rate`/10 (acumulado en milésimas), coste = coste del edificio × `cost_factor` × HP reparado / HP máx, cobrado por tick; se detiene sin recursos o con el HP lleno.
- Guarnición: componente de tiempo de ejecución `Garrisoned {in}` en la unidad (fuera del `SpatialHash`, sin moverse ni ser objetivo) y `Garrison.units` en el edificio. Comandos `garrison {ids, target}`, `ungarrison {ids}`, `bell {id}`. Al morir el edificio, salen todos. Flechas: un edificio con `Attack` y `Garrison.arrows_per_unit` dispara 1 + n × arrows proyectiles.
- Render/UI (acotado, la otra sesión trabaja en lo visual): unidades guarecidas no se dibujan; número de guarecidos sobre el edificio; botones "Sacar" y "Campana"; clic derecho: aldeano sobre edificio propio dañado = reparar, unidad `Garrisonable` sobre edificio propio con `Garrison` = guarecer.

**Tech Stack:** Godot 4.4 GDScript.

**Spec:** §5.2 (reparación con coste), §5.3 (guarnición, campana), §4.3 (`replace_entity`), §10-F4.

## Global Constraints

- Tests: `GODOT=/c/Users/Asus/AppData/Local/Temp/opencode/godot44/Godot_v4.4-stable_win64_console.exe sh tests/engine/run.sh [test_x]`.
- Otra sesión trabaja en paralelo en la MISMA carpeta y rama (`main`) en lo visual/datos: `git add` solo de rutas propias; no cambiar de rama; no correr el migrador; cambios en `engine/render2d`, `engine/ui` y `game/scenes/Match.gd` mínimos.
- Sim determinista; comandos validados e inertes si son inválidos.

## Review Focus

1. Conversión de unidades vivas: estado de combate/recolección y selección siguen válidos. → `test_upgrade_converts_live_units`.
2. Reparación nunca cobra de más ni repara gratis; se detiene sin recursos. → `test_repair_costs_and_stops`.
3. Guarecidos: no los alcanza nada, no se mueven, cuentan población; salen vivos al morir el edificio y a casillas libres conectadas. → `test_garrison_*`.
4. Campana: ida y vuelta solo con aldeanos propios. → `test_bell_round_trip`.

---

### Task 1: Mejoras de línea (`replace_entity`)
**Files:** `engine/sim/World.gd` (`convert_entity`), `engine/sim/Sim.gd`; test `tests/engine/test_upgrades.gd`.
- [ ] Tests: `test_upgrade_converts_live_units`, `test_train_list_follows_upgrades`, `test_upgrade_deterministic`.

### Task 2: Reparación
**Files:** `engine/sim/systems/BuildSystem.gd`, `engine/sim/Sim.gd` (comando `repair`); test `tests/engine/test_repair.gd`.
- [ ] Tests: `test_repair_restores_hp`, `test_repair_costs_and_stops`, `test_no_repair_of_foundation_or_enemy`.

### Task 3: Guarnición y campana
**Files:** `engine/sim/systems/GarrisonSystem.gd` (nuevo), `engine/sim/Sim.gd`, `engine/sim/systems/CombatSystem.gd`, `engine/sim/World.gd`; test `tests/engine/test_garrison.gd`.
- [ ] Tests: `test_garrison_hides_and_protects`, `test_ungarrison_to_free_tiles`, `test_building_death_ejects`, `test_garrison_adds_arrows`, `test_bell_round_trip`, `test_garrison_capacity_and_owner`.

### Task 4: Render/UI mínimos y docs
**Files:** `engine/render2d/EntityLayer.gd`, `engine/ui/CommandPanel.gd`, `game/scenes/Match.gd`, `docs/CONTROLES.md`, `docs/MODDING.md`; tests en `tests/engine/test_command_panel.gd`.
- [ ] Guarecidos ocultos; botones Sacar/Campana; clic derecho reparar/guarecer.
