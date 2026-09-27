# MAZOS — Índice (solo lectura, 2026-09-27)

> Generado por auditoría. No modifica lógica ajena. Fuentes: `mods/aoe2_base/cards/*.json`, `game/cards/presets/*.json`, `ui/decks/CardArt.gd` (`icon_for`, solo leído), `ui/menus/MainMenu.*`, `ui/decks/DeckBuilder.*`, `ui/decks/CardWidget.*`.

## 1. Sets de cartas (9 archivos, 154 cartas, 154 ids únicos, 0 duplicados)

| Archivo | `civ` | Nº | Edades (I/II/III/IV) |
|---|---|---:|---|
| `mods/aoe2_base/cards/bizantinos.json` | `bizantinos` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/britones.json` | `britones` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/francos.json` | `francos` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/godos.json` | `godos` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/vikingos.json` | `vikingos` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/neutrales.json` | `todas` | 20 | 5 / 6 / 5 / 4 |
| `mods/aoe2_base/cards/mercenarios.json` | `todas` | 10 | 0 / 0 / 5 / 5 |
| `mods/aoe2_base/cards/equipo.json` | `todas` | 12 | 0 / 4 / 4 / 4 |
| `mods/aoe2_base/cards/especiales.json` | `todas` | 12 | 0 / 3 / 5 / 4 |

Pendientes de otros agentes (a esta fecha): `mar*.json` en `mods/aoe2_base/cards/` **no existe** (solo `maravilla.json` de edificios); `test_decks*` **no existe** en el repo.

## 2. Presets (9 archivos, 20 cartas c/u, 0 ids rotos)

| Archivo | `civ` | Nº | Estado ids |
|---|---|---:|---|
| `game/cards/presets/bizantinos.json` | `bizantinos` | 20 | OK |
| `game/cards/presets/britones.json` | `britones` | 20 | OK |
| `game/cards/presets/francos.json` | `francos` | 20 | OK |
| `game/cards/presets/godos.json` | `godos` | 20 | OK |
| `game/cards/presets/vikingos.json` | `vikingos` | 20 | OK |
| `game/cards/presets/mixto.json` | `todas` | 20 | OK (solo neutrales) |
| `game/cards/presets/camp_sangre.json` | `britones` | 20 | OK (idéntico a britones) |
| `game/cards/presets/camp_fiordo.json` | `vikingos` | 20 | OK (idéntico a vikingos) |
| `game/cards/presets/camp_conquistador.json` | `francos` | 20 | OK (idéntico a francos) |

Nota: ningún preset cita `eq_*`, `esp_*` ni `merc_*`; esos sets solo son usables desde DeckBuilder filtrando `todas`.

## 3. Pantallas UI y cableado al menú

| Pantalla | Archivos | Cableado al menú | Estado |
|---|---|---|---|
| Menú principal | `ui/menus/MainMenu.gd` + `MainMenu.tscn` (botón `DecksButton` “Mazos”) | `_on_decks()` → `res://ui/decks/DeckBuilder.tscn` si existe | **Cableado OK** |
| Constructor de mazos | `ui/decks/DeckBuilder.gd` + `DeckBuilder.tscn` | `_on_volver()` → `res://ui/menus/MainMenu.tscn`; usa `game/cards/Deck.gd` + `DeckValidator.gd` (`CARDS_DIR=res://mods/aoe2_base/cards`, `TAMANO_MAZO=20`) | **Cableado OK** |
| Tarjeta | `ui/decks/CardWidget.gd` + `CardWidget.tscn` (`signal card_pressed`) | Usada por DeckBuilder (tscn→gd, fallback a `Button`); helpers `CardArt.card_frame/icon_for/rarity_color/cost_text` | **Integrada OK (con fallback)** |
| Arte procedural | `ui/decks/CardArt.gd` (sin escena; `icon_for`, `cost_text`, `card_frame`, `rarity_color`) | Consumida por CardWidget + DeckBuilder | **En uso OK** |
| Lógica mazos | `game/cards/Deck.gd`, `DeckValidator.gd`, `DeckTips.gd` | Sin escena; DeckBuilder la precarga | **OK** |
| Menú campaña | `ui/menus/CampaignMenu.gd` + `.tscn` vía `systems/campaign/CampaignManager.gd` (`data/campaigns/*.json`) | **No** carga `game/cards/presets/camp_*` (solo coincidencia nominal) | **No cableado a mazos** |
| Galería civs / TechViewer | `ui/civs/CivGallery.gd`+`.tscn`, `CivDetail.*`, `ui/techviewer/TechViewer.gd`+`.tscn` | Solo enlazadas desde MainMenu (`_on_civs`, `_on_tech`); sin refs a mazos | **No cableado a mazos** |

## 4. Coherencia de ids (presets → cards)

- 9 presets × 20 citas = 180 citas; **0 ids rotos** (todo `card_ids` existe en §1).
- 0 ids duplicados entre sets.

## 5. Iconos vs `CardArt.icon_for` (solo lectura, sin modificar)

- `icon_for` mapea exacto (minúsculas) 42 claves en 17 grupos; resto → `◆`.
- Distintos usados: 72 → **21 mapeados, 51 sin mapear** (caen a `◆`, visual pero no roto).
- Mapeados (21): `aldeano, antorcha, arco, ariete, barco, caballo, castillo, catapulta, corona, escudo, espada, fuego, granja, hacha, lanza, madera, monje, muralla, oro, piedra, torre`.
- Sin mapear (51): `alabarda, alimento, ancla, arco_largo, armadura, arqueria, arquero_tiro_largo, balistica, bota, botas, camello, campeon, carne, carreta, carretilla, catafracta, cesta, comercio, cruz, cuartel, daga, diana, dragon, drakkar, espadachin_mandoble, establo, estandarte, flecha, guerrillero, herradura, herreria, huscarle, invasor_nordico, jabali, maravilla, molino, muelle, ojo, oveja, paladin_franco, pica, quimica, red, reloj, telar, trabuquete, trebuchet, tridente, trigo, vela, yelmo`.
- Ids rotos: **ninguno**. Acción requerida: ninguna (solo ampliar `icon_for` si se quiere, fuera de alcance).
