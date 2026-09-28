# F4b-2 — Monjes, reliquias, comercio y descarga: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monjes que curan y convierten (azar determinista), reliquias que se llevan al monasterio y dan oro, carretas de comercio entre mercados aliados, y descarga manual de recursos en un depósito.

**Architecture:**
- `Sim.rng` (xorshift `Rng`, semilla fija de la partida) para la conversión; solo la simulación lo usa, en orden de id.
- `MonkSystem`: `Convert {range, cooldown, chance}` — orden `convert {ids, target}`: ir a alcance, canalizar; desde 4 s tirada por segundo con `chance`, conversión segura a los 10 s; luego `cooldown` s de recarga. Solo unidades enemigas (asedio con la tech `redencion`; monjes nunca). La unidad convertida pasa al nuevo dueño con `World.convert_entity` usando las defs de ese jugador. `Heal {range, rate}` — orden `heal` o automático si está ocioso: HP/s a unidades propias/aliadas heridas (no a sí mismo).
- `RelicSystem`: entidad `reliquia` (`Relic {gold_per_sec}`, no bloquea casilla). El monje (`Convert`) la recoge (`pick_relic`), la lleva a un monasterio propio (`RelicHolder`) con `store_relic`/clic derecho; guardada da oro por tick. Componente de tiempo de ejecución `Held {by}` (oculta y fuera del `SpatialHash`). Muere el monje o cae el monasterio → la reliquia queda en el suelo. `MapGen` coloca 5 lejos de los inicios.
- `TradeSystem`: carreta (`Trade {gold_base, gold_per_tile}`) con orden `trade {ids, target}` a un mercado (`Market`) de otro jugador no enemigo; ida y vuelta al mercado propio más cercano; al volver suma `gold_base + gold_per_tile × distancia en casillas`.
- Descarga: comando `drop {ids, target}` → aldeanos con carga van a ese depósito propio y vuelven a su recurso.
- UI (acotada): clic derecho con monjes: enemigo = convertir, herido propio = curar, reliquia = recoger, monasterio propio = guardar; carreta sobre mercado aliado = comerciar; aldeano con carga sobre depósito propio = descargar. Reliquias guardadas en el estado del panel.

**Datos (mínimos, avisar a la otra sesión):** `mods/aoe2_base/resources/reliquia.json`; `RelicHolder {}` en `monasterio.json`; `Market {}` en `mercado.json`; esquemas `Relic`, `RelicHolder`, `Market` en `engine/data/Schemas.gd`.

**Fuera de alcance:** agua, muelle y barcos (fase naval), conversión de edificios, victoria por reliquias.

## Global Constraints
- Tests: `GODOT=/c/Users/Asus/AppData/Local/Temp/opencode/godot44/Godot_v4.4-stable_win64_console.exe sh tests/engine/run.sh [test_x]`.
- Otra sesión en la MISMA carpeta y rama `main`: `git add` solo rutas propias (staging parcial de `Match.gd`), no cambiar de rama, no correr el migrador.
- Sim determinista; comandos validados e inertes si son inválidos.

## Review Focus
1. Conversión determinista y justa (no convierte monjes/edificios; recarga; el convertido deja sus órdenes). → `test_convert_*`.
2. Reliquias nunca se pierden ni se duplican (muerte del monje, caída del monasterio). → `test_relic_*`.
3. Comercio solo con mercados de otros jugadores no enemigos; oro por viaje correcto. → `test_trade_*`.
4. Descarga no pierde carga y vuelve al recurso. → `test_drop_off`.

---

### Task 1: Monjes (curar y convertir)
**Files:** `engine/sim/systems/MonkSystem.gd` (nuevo), `engine/sim/Sim.gd`, `engine/sim/World.gd`; test `tests/engine/test_monks.gd`.

### Task 2: Reliquias
**Files:** `engine/sim/systems/RelicSystem.gd` (nuevo), `engine/sim/Sim.gd`, `engine/sim/MapGen.gd`, `engine/data/Schemas.gd`, datos; test `tests/engine/test_relics.gd`.

### Task 3: Comercio y descarga
**Files:** `engine/sim/systems/TradeSystem.gd` (nuevo), `engine/sim/Sim.gd`, `engine/sim/systems/GatherSystem.gd`, datos; test `tests/engine/test_trade.gd`.

### Task 4: UI mínima y docs
**Files:** `engine/render2d/EntityLayer.gd`, `engine/ui/CommandPanel.gd`, `game/scenes/Match.gd`, `docs/CONTROLES.md`, `docs/MODDING.md`.
