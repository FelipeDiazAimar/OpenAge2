# Mazos (barajas estilo Age 3)

Sistema de barajas de envíos. Solo datos + parches §4.3. Sin cambios de motor. HUD en F5.

## 1. Formato de carta JSON

| Campo | Tipo | Oblig. | Descripción |
|---|---|---|---|
| `id` | string | sí | Único, ej. `env_700_madera` |
| `name` | `@str:clave` | sí | Texto desde `lang/*.json` |
| `civ` | string/null | sí | `id` de civ o `null` = neutral |
| `age` | I/II/III/IV | sí | Edad mínima para enviarla |
| `icon` | string | sí | `icon:<id>` (AssetLocator, §7) |
| `shipment` | int | no | Coste en envíos (def. 1) |
| `limit` | int | no | Veces enviable por partida |
| `effects` | array | sí | Parches §4.3 (ver §4) |

Ejemplo:

```json
{
  "id": "env_forja_avanzada",
  "name": "@str:card_forja_av",
  "civ": null,
  "age": "II",
  "icon": "icon:card_swords",
  "shipment": 1, "limit": 1,
  "effects": [
    {"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 2}
  ]
}
```

## 2. Reparto por edades

Mazo = 20 cartas: **5 / 6 / 5 / 4** (I / II / III / IV). Una carta solo se envía si `edad_actual >= carta.age`.

## 3. Reglas de mazo

- 20 cartas exactas. Validador falla si no.
- Cada carta: `civ == mi_civ` o `civ == null` (neutral). Nada de otras civs.
- Sin duplicados de `id`. `limit` controla repetición en partida.
- Una carta = uno o más `effects` (§4.3). Nada de código.

## 4. Efectos como parches (aplica en F4)

El envío aplica sus `effects` a la **vista parcheada del jugador** (§4.3): recálculo al recibir, nunca por tick. Unidades vivas leen la vista (igual que techs).

| `op` | Uso en cartas |
|---|---|
| `add` | +N directo: `damage.melee +2`, `Hitpoints.max +50` |
| `mul` | %: `Gather.rates.food ×1.15`, `Train` tiempo ×0.9 |
| `set` | Fija valor: `Vision.sight = 8` |
| `append` | Añade a lista: unidad a `Train.units`, recurso a `DropSite.accepts` |
| `remove` | Quita de lista |
| `enable` / `disable` | Desbloquea/bloquea `id:x` (unidad única, tech) |
| `replace_entity` | Sustituye una entidad por otra (mejora de unidad) |

`target`: `id:x`, `tag:x`, `type:x`, con `|` (unión) y `&` (intersección).

## 5. Añadir carta o civ nueva

Carta nueva (`mods/aoe2_base/cards/<id>.json` o tu mod):
1. Crea el JSON §1 con `effects` válidos.
2. Pasa `tools/validate_mods` (esquema + refs + `age` válida).
3. Inclúyela en un mazo `user://decks/` (§6).

Civ nueva (`mods/<tu_mod>/civs/<civ>.json` + `cards/`):
1. Define civ con su `effects` de tick 0 (§4.3).
2. Añade sus cartas con `"civ": "<tu_civ>"`.
3. Declara `mod.json` (`depends`, `priority`); Registry ordena y calcula `content_hash`.

## 6. Dónde se guardan los mazos

- `user://decks/<nombre>.json`: `{civ, cards: [20 ids]}`. Fuera del repo, como `user://aoe2_assets/`.
- Contenido del juego (`cards/`, `civs/`) vive en `mods/`. Los mazos solo referencian ids.
- LAN (F6): el lobby exige mismo `content_hash`; los mazos se eligen tras validar hash.

## 7. Qué falta (envíos en partida)

No incluido aún: recurso de experiencia, edificio/punto de envío, comando `Sim.queue_command(pid,"ship",{card})`, cola y confirmación en red, panel de envíos en HUD F5 (grilla + teclas + tooltips), IA que use mazos.
