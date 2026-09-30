# Cartas y Facciones — esquema real (DeckValidator + CivGallery)

## 1. Esquema carta (validado por `game/cards/DeckValidator.gd`)
- Campos: `{id, name, civ, age, type, cost, effect{target, op, path, value}, icon, rarity, desc}`. Obligatorios no-vacíos: `id, name, icon, desc`. `age`: entero 1-4. `civ`: id de civ o `"todas"` (`cards_for_civ()`).
- `type ∈ {unidad, mejora, recurso, edificio}`. `cost`: dict solo `{madera, alimento, oro, piedra}` numérico ≥0.
- `effect.op ∈ {set, add, mul, append, remove, replace_entity, enable, disable}`. `effect.path` válido si `res.*` (envío directo) o `abilities.*` / `cost.*` / `enabled` / `""` (`is_effect_path_valido()`).
- Mazo: 1–25 cartas (`MIN/MAX_CARTAS`), ids únicos. Carga: `CARDS_DIR=res://mods/aoe2_base/cards` recursivo (`_recoger_json`), `*.json` ordenados, cada fichero dict o array.
- Presets: `game/cards/presets/*.json` = `{civ, name, card_ids[20]}` (ej. `francos.json`: 20 ids `fran_*` + `name:"Inicial Francos"`).
- Ejemplos leídos: `neut_madera_1` (todas/1/recurso, `add res.wood +300`) y `fran_paladin_4` (francos/4/unidad, coste 300 alimento+250 oro, `add abilities.Attack.damage.melee +3` a `id:paladin_franco`).

## 2. Esquema faction (lo que lee `ui/civs/CivGallery.gd::_cargar_civs`)
- Fuente: `data/factions/*.json` (ej. `francos.json`). Lee solo: `id`, `name→nombre`, `roof_color|color→color (def. #73706a)`, `bonus[]` (solo muestra `str(b)`), `ventajas[]` (tarjeta 3, detalle todas), `debilidades[]` (tarjeta 2), `unique_unit→unique {name|id, hp, attack, cost}`. Ignora `tech_tree, unique_techs, team_bonus` en galería.
- Conteo cartas (`_contar_cartas`): lee `FACTIONS_DIR=res://mods/aoe2_base/cards/*.json` **solo nivel superior** (sin subdirs), `civ=="todas|neutral|neutrales|\"\""` → neutrales, resto `propias[civ.lower()]++`.

## 3. Issues conocidos (código vs datos)
1. `effect.target` **nunca se valida** (ej. `id:jugador`, `tag:aldeano`, `id:huscarle` pasan igual).
2. `path res.*` se acepta (`res.wood/food/gold/stone` en neutrales) pero **sin lector real** en validador/juego; además claves `wood/food` ≠ `madera/alimento` de `cost`.
3. `type:building` rechazaría (válido es `edificio`); `id:jugador` como target sin entidad `jugador` definida. `cost` carta usa `madera/alimento/oro/piedra` pero `unique_unit.cost` en faction usa `food/gold` (esquemas distintos).
4. Desfase conteo: `DeckValidator._recoger_json` es recursivo (cartas por civ en subdirs `eslavos/`, `aztecas/`…), `CivGallery._contar_cartas` no baja a subdirs → cifras de galería infra-cuentan. Const `FACTIONS_DIR` en CivGallery mal nombrada (apunta a cards).
