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
