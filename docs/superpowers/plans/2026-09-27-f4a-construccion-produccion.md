# F4a — Construcción, producción, investigación y edades: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Partida jugable de punta a punta contra nada: los aldeanos colocan cimientos y construyen (cooperativo AoE2), los edificios entrenan unidades con cola de 5, reembolso y punto de reunión, se investigan tecnologías y se avanza de edad. Panel de órdenes mínimo (el HUD DE completo es F5).

**Architecture:**
- `Sim` gana estado por jugador `age` (índice) y `pending` (techs/edades en cola), y consultas puras `requirements_met`, `can_afford`, `can_place` que usan tanto los comandos como la UI.
- **Cimiento** = el edificio real con un componente `Foundation {progress, total}` añadido al colocarlo (HP empieza en 1). Mientras exista, el edificio no es funcional: no es depósito, no da población, no dispara, no produce.
- `BuildSystem` (habilidad `Build` del aldeano): ir al borde del cimiento y construir; avance por tick = n+2 tercios (tiempo = base × 3 / (n + 2)). Al terminar, el constructor sigue con otro cimiento propio cercano o, si el edificio es un depósito sin `Train`, se pone a recolectar el recurso aceptado más cercano.
- `ProductionSystem`: componente `Queue {items, progress, housed, rally, rally_target}` que `Sim` agrega a edificios con `Train`/`Research`/`AgeAdvance`. Cola compartida de 5 (AoE2) con unidades, tecnologías y edades. Unidad lista → casilla de salida libre más cercana al punto de reunión; si el punto es un recurso y es aldeano, recolecta.
- Investigar = `PlayerDefs.research` (parchea en el sitio: los `params` de las entidades vivas apuntan a esas definiciones) + refresco de cachés (`Move.step`, `Hitpoints.max`).
- Render: cimientos translúcidos con barra de progreso, animación `build` del aldeano, vista previa de colocación verde/roja, bandera de reunión. UI: `engine/ui/CommandPanel.gd` (botones de construir/entrenar/investigar/edad + cola con cancelar) y la edad en la barra superior.

**Tech Stack:** Godot 4.4 GDScript, Python 3.12.

**Spec:** §4.2 (Build, Constructable, Train, Research, RallyPoint, ProvidesPop), §5.2 (construcción cooperativa), §5.4 (edades, colas de 5 con reembolso, población con tope 200), §10-F4.

## Global Constraints

- Tests: `GODOT=/c/Users/Asus/AppData/Local/Temp/opencode/godot44/Godot_v4.4-stable_win64_console.exe sh tests/engine/run.sh [test_x]`; Python `python -m unittest discover -s tools/tests`.
- Sim determinista (enteros, iteración por id, sin APIs visuales en engine/sim ni engine/data); render y UI solo leen `Sim` y mandan comandos con `queue_command`. Write/Edit para GDScript. `git add` con rutas explícitas.
- Todo comando valida su payload (ids propios, def existente, requisitos, coste) y es inerte si no es válido.
- Valores AoE2 de los datos del mod (casa 25 madera/20 s, aldeano 50 alimento/20 s, feudal 500 alimento/130 s...).

## Fuera de alcance (F4b)

Granjas y resiembra, reparación, guarnición y campana, monjes/reliquias, comercio, mejoras de línea (`replace_entity`) en la UI, muros arrastrables, cola con Shift, iconos del DE (F5).

## Review Focus

1. **Recursos nunca se duplican ni se pierden**: coste al encolar/colocar, reembolso íntegro al cancelar, nada se cobra si el comando es inválido. → `test_cancel_refunds`, `test_place_rejects_*`.
2. **Cimiento no funcional**: sin población, sin depósito, sin ataque, sin cola hasta terminar. → `test_foundation_not_functional`.
3. **Fórmula cooperativa** base × 3/(n+2) con 1 y 3 aldeanos. → `test_build_time_*`.
4. **Población**: la cola se detiene sin casas (housed) y dos edificios no superan el tope en el mismo tick. → `test_housed_*`.
5. **Requisitos**: edad, techs previas, deshabilitadas por civ, edificios previos para la edad; una tech no se encola dos veces. → `test_requirements_*`.
6. **Investigación afecta unidades vivas** (ataque, velocidad, HP). → `test_research_updates_live_units`.
7. **Determinismo** del ciclo completo. → `test_economy_cycle_deterministic`.

---

### Task 1: Sim — estado por jugador, requisitos, colocación y cimientos

**Files:** `engine/sim/Sim.gd`, `engine/sim/World.gd`, `engine/sim/systems/CombatSystem.gd`, `engine/sim/systems/GatherSystem.gd`; test `tests/engine/test_construction.gd`.

- [ ] `World.add_component(id, ability, comp)`; `state_hash` incluye `Foundation.progress` y la longitud/progreso de `Queue`.
- [ ] `add_player`: `age = 0`, `pending = {}`. `Sim.age_of(pid)`, `Sim.researched(pid)`.
- [ ] `Sim.can_afford(pid, cost)`, `Sim.pay(pid, cost)`, `Sim.refund(pid, cost)` (cost en unidades de datos → milésimas).
- [ ] `Sim.requirements_met(pid, def) -> String` ("" o motivo): `is_available`, `requires.age` (índice ≤ edad), `requires.techs` investigadas.
- [ ] `Sim.can_place(pid, def_id, tile) -> String`: edificio, requisitos, coste, huella dentro del mapa y transitable, sin carcasas/recursos dentro.
- [ ] `Sim.is_built(id)`: sin `Foundation`. `population` ignora cimientos; `_nearest_dropsite` ignora cimientos; `CombatSystem.step` salta cimientos.
- [ ] Comando `place {ids, def, tile}`: valida con `can_place`, cobra, `spawn` + `Foundation {progress 0, total build_time·10·3}` y HP 1; desplaza unidades (Move) dentro de la huella a la casilla libre más cercana fuera; ordena construir a los aldeanos (`BuildSystem.order_build`, Task 2).
- [ ] Tests: `test_place_creates_foundation_and_charges`, `test_place_rejects_blocked_unaffordable_and_locked`, `test_foundation_not_functional`, `test_place_displaces_units`.

### Task 2: BuildSystem — construcción cooperativa

**Files:** `engine/sim/systems/BuildSystem.gd` (nuevo), `engine/sim/World.gd` (init `Build {state, target}`), `engine/sim/Sim.gd` (comando `build {ids, target}`, orden de sistemas, `stop` en move/gather/attack/stop), `engine/sim/systems/GatherSystem.gd` (`order_gather` detiene la construcción); test `tests/engine/test_construction.gd`.

- [ ] Estados `idle`, `to_site`, `building`. Llegada: distancia al rectángulo ≤ 800 (como el depósito).
- [ ] Avance por cimiento: n constructores en `building` → `progress += n + 2`; HP sube en proporción al avance (conserva el daño recibido).
- [ ] Al terminar: quita `Foundation`, evento `built`; constructores → otro cimiento propio a ≤ 12 casillas, si no, si el edificio es `DropSite` sin `Train`, recolectar el recurso aceptado más cercano (sin caza ni agua); si no, ociosos.
- [ ] Tests: `test_build_time_single` (casa: 200 ticks ± 3), `test_build_time_three` (120 ± 3), `test_foundation_hp_grows`, `test_builder_goes_to_gather_after_camp`, `test_move_stops_building`, `test_build_command_resumes_foundation`.

### Task 3: ProductionSystem — entrenar, investigar, edades, reunión

**Files:** `engine/sim/systems/ProductionSystem.gd` (nuevo), `engine/sim/Sim.gd` (`Queue` al crear edificios con Train/Research/AgeAdvance; comandos `train {id, def}`, `research {id, tech}`, `age_up {id}`, `cancel {id, index}`, `rally {ids, pos, target?}`; `research_done(pid, tech)` refresca cachés); test `tests/engine/test_production.gd`.

- [ ] Cola de 5 (`Train.queue` o 5). Ítems `{kind, id, cost}`; cobro al encolar; `cancel` reembolsa íntegro (y reinicia progreso si era el primero).
- [ ] Unidad: `train_time·10` ticks; no avanza si la población no alcanza (`housed = true`); población calculada una vez por tick y sumada al generar.
- [ ] Salida: casilla transitable del anillo alrededor de la huella más cercana al punto de reunión (o al frente sur); orden `(dist², y, x)`. Con reunión: recurso + aldeano → recolectar; cimiento propio + aldeano → construir; si no, mover.
- [ ] Tech: en `Research.techs` del edificio, requisitos, no investigada ni pendiente. Al completar `PlayerDefs.research` + refresco de `Move.step`/`Hitpoints` de las entidades del jugador.
- [ ] Edad: edificio con `AgeAdvance`, índice = edad+1, `prerequisite_buildings` (tipos distintos construidos ≥ count), una a la vez. Al completar `age += 1`.
- [ ] Tests: `test_train_villager`, `test_queue_limit_and_cost`, `test_cancel_refunds`, `test_housed_pauses_and_resumes`, `test_housed_no_overshoot_two_buildings`, `test_rally_move_and_gather`, `test_requirements_*` (edad, techs previas, deshabilitada por civ, edificio ajeno), `test_research_updates_live_units`, `test_age_up_needs_buildings`, `test_economy_cycle_deterministic`.

### Task 4: Render — cimientos, constructor, vista previa y reunión

**Files:** `tools/migrate_data_to_mod.py` (alias `build` → `builder`), `engine/render2d/EntityView.gd` (`progress`: translúcido + barra), `engine/render2d/EntityLayer.gd` (acción `build`, progreso de cimiento, `ghost` de colocación verde/roja), `engine/render2d/SelectionOverlay.gd` (bandera de reunión); tests en `tests/engine/test_combat_render.gd` o nuevo `test_build_render.gd`.

- [ ] Tests: cimiento con `modulate.a < 1` y progreso; aldeano construyendo usa `builder`; ghost rojo sobre casilla bloqueada y verde en libre.

### Task 5: UI — panel de órdenes y edad

**Files:** `engine/ui/CommandPanel.gd` (nuevo), `engine/ui/ResourceBar.gd` (edad), `game/scenes/Match.gd` (modo colocación, clic derecho en cimiento = construir, clic derecho con edificio = reunión, atajos de unidad `hotkey`); test `tests/engine/test_command_panel.gd`.

- [ ] Aldeanos seleccionados → botones de edificios disponibles (requisitos) con coste; deshabilitados si no alcanza.
- [ ] Edificio propio → entrenar (unidades de `Train` disponibles), investigar, avanzar edad; cola con progreso y clic para cancelar; “sin casas” cuando `housed`.
- [ ] Colocación: sigue al ratón ajustado a la casilla; clic izquierdo coloca (Shift mantiene el modo); clic derecho o Esc cancela.

### Task 6: Docs, demo y suite

- [ ] `docs/CONTROLES.md` (motor nuevo: construir, entrenar, reunión, cancelar), `docs/MODDING.md` (Foundation/Queue en tiempo de ejecución; requisitos).
- [ ] Demo con capturas: cimiento a medio construir, edificio terminado, unidades saliendo al punto de reunión.
- [ ] Suite verde; commit "F4a: documentación".
