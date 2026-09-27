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
