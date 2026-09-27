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
