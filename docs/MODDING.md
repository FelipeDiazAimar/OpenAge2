# MODDING - Cómo añadir lo tuyo sin programar (gratis)

Todo es JSON en `data/`. Copia un archivo y cámbialo. El juego lo carga al arrancar.

## Nueva facción
1. Copia `data/factions/britones.json` -> `data/factions/misvikingos.json`
2. Cambia `id`, `name`, `bonus`, `roof_color`
3. Aparece sola en el lobby.

## Nueva tropa
1. Copia `data/units/aldeano.json` -> `data/units/huscarle.json`
2. Ajusta `hp, attack, cost, trained_at`
3. Añade el id a la facción en `tech_tree`.

## Nuevo edificio
1. Copia `data/buildings/casa.json` -> `data/buildings/torre_homenaje.json`
2. Define `hp, cost, size_tiles, trains`
3. Si entrena tropas, pon su id en `trains`.

## Nueva edad
Edita `data/ages/ages.json`, añade coste y nombre.

## Nueva acción
Edita `data/actions.json`. Las unidades la referencian por nombre.

Nada hardcodeado: si no está en JSON, no existe en juego.

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
- Recolección: una unidad con `Gather {rates: {rate_key: por_seg}, capacity}` recolecta de
  cualquier entidad con `ResourceSource {resource, amount, rate_key}` cuyo `rate_key` esté en sus
  `rates`, y deposita en edificios propios con `DropSite {accepts: [recursos]}`.
- Combate: `Attack {damage: {melee|pierce|<clase>: n}, range, reload, attack_delay?, projectile_speed?,
  area_radius?, min_range?}`. Daño = máx(1, Σ max(0, ataque − armadura)) por clase; las clases
  distintas de melee/pierce son bonus contra el id o un tag del objetivo (admite plural:
  `arquero` vale contra `arqueros`). Con `projectile_speed` dispara un proyectil que puede fallar.
  Las unidades con `Attack` y sin `Gather` (militares) y los edificios con `Attack` atacan solos.

- Construcción: una unidad con `Build` levanta edificios. El edificio necesita `cost`, `build_time`
  y `footprint`; `requires {age, techs}` limita cuándo se puede colocar. Al colocarlo el motor le
  añade en tiempo de ejecución un `Foundation` (no va en los datos): hasta terminarlo no es
  depósito, no da población, no dispara ni produce. Tiempo con n aldeanos = base × 3 / (n + 2).
- Producción: `Train {units, queue}`, `Research {techs}` y `AgeAdvance {}` en un edificio le dan una
  cola (componente `Queue`, también de tiempo de ejecución). Las unidades necesitan `train_time` y
  `pop_cost`; las techs `research_time`, `at` y `effects`; las edades `index`, `research_time` y
  `prerequisite_buildings {any_of, count}` (tipos distintos de edificio terminados).
- Población: `ProvidesPop {amount}` en edificios terminados, tope 200.
- Menú de construir: `"build_menu": "economico" | "militar"` y `"hotkey": "Q"` en el edificio
  (tecla dentro de su página; sin `build_menu` va a la económica).
- Mejoras de línea: una tech con `{"op": "replace_entity", "from": "lancero", "to": "piquero"}`
  convierte las unidades vivas del jugador y el edificio que entrena `from` pasa a entrenar `to`
  (las unidades que solo son destino de una mejora no se entrenan hasta investigarla).
- Guarnición: `Garrison {capacity, arrows_per_unit}` en el edificio y `Garrisonable {}` en la
  unidad; `Bell {}` en el centro urbano. `Repair {rate, cost_factor}` en el aldeano (HP/s y
  fracción del coste del edificio que se paga por el HP reparado).
- Monjes: `Convert {range, cooldown, chance}` (tirada por segundo desde los 4 s, segura a los 10 s;
  el asedio requiere la tech `redencion`) y `Heal {range, rate}`. Reliquias: entidad con
  `Relic {gold_per_sec}`; el edificio que las guarda lleva `RelicHolder {}`.
- Comercio: `Trade {gold_base, gold_per_tile}` en la carreta y `Market {}` en el mercado; oro por
  viaje = gold_base + gold_per_tile × casillas entre mercados (solo con mercados de otros jugadores
  no enemigos).
- Agua y barcos: las unidades con la etiqueta `barco` navegan solo por agua (grilla naval); el resto
  no entra al agua. `Dock {}` marca el muelle: toda su huella en agua y tocando la costa; los barcos
  salen al agua y descargan solo en muelles. Recursos con `"water": true` (peces) solo los buscan
  solos los barcos; los aldeanos pescan desde la orilla si se les ordena.
- Render: `sim.grid.is_water(casilla)` dice qué casillas son agua (para dibujarlas).
