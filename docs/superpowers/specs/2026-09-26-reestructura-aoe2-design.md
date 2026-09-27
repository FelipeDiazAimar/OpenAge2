# Reestructura OpenAge-LAN: motor por habilidades + render 2D isométrico AoE2

Fecha: 2026-09-26 · Estado: aprobado en chat, pendiente de revisión escrita

## 1. Objetivo

Convertir OpenAge-LAN en un RTS con la jugabilidad, interfaz y aspecto del Age of Empires II: DE,
construido sobre una arquitectura donde **añadir unidades, edificios, tecnologías, civilizaciones
y mods sea solo datos + assets**, sin tocar código del motor.

Criterios de éxito:
- Un edificio nuevo que entrena, da población y guarnece se crea con un único JSON (sin código).
- La recolección, el combate y las animaciones reproducen las reglas del AoE2 (tasas, armaduras por
  clase, attack delay, proyectiles, sprites por tarea).
- 8 jugadores en LAN, 200 de población cada uno, sin desync (`lan_8_bots` verde).
- Con los assets extraídos, el juego es visualmente indistinguible del AoE2 DE en terreno, unidades,
  edificios, efectos y HUD.
- El juego actual sigue jugable durante toda la migración.

### Decisiones tomadas

| Tema | Decisión |
|---|---|
| Origen del arte | Sprites/UI/terreno/sonido del AoE2 DE extraídos por cada jugador de su copia comprada. Nunca en el repo ni en el ejecutable. |
| Render | 2D isométrico puro (se abandona la escena 3D + billboards). |
| Modelo de datos | Entidades compuestas de habilidades, con herencia (`extends`) y tecnologías/civs como parches. Preparado para, más adelante, habilidades por script (no en este alcance). |
| Migración | Reescritura en paralelo por módulos; el juego viejo convive hasta alcanzar paridad. |
| Motor | Se mantiene Godot 4.4 + GDScript, lockstep 10 Hz, ENet LAN 8p. |

### Fuera de alcance
- Habilidades definidas por scripts de mod (sección 4.5 deja el punto de extensión).
- Multijugador por internet, matchmaking, ranking.
- Arte propio distribuible (solo placeholders geométricos cuando no hay assets extraídos).

## 2. Diagnóstico del estado actual (motivación)

1. **Estado fragmentado**: cada sistema mantiene su copia de entidades (`Combat._units`,
   `Economy._villagers`, `Production._buildings`, `GameWorld.units`). Una unidad se registra en 4–5
   sitios; riesgo de desync.
2. **~10 cargadores JSON duplicados** con fallbacks hardcodeados (`Production.FALLBACK_UNITS`,
   `Construction` fallback, `GameManager.FALLBACK_AGES`) que se desincronizan en silencio.
3. **IDs hardcodeados** que contradicen `docs/MODDING.md`: `BuildingDefs.BUILDING_IDS` (12 de 19),
   `SpriteFactory.PACKS`, menús del `HUD.gd`, capacidades de `Garrison.gd`, `"aldeano"`/`"cuartel"`
   en IA y `GameWorld`.
4. **Objetos dios**: `GameWorld.gd` (624 líneas, cablea todo) y `HUD.gd` (708 líneas).
5. **Estética**: mezcla de placeholders 3D y billboards 2D flotando sobre terreno 3D.

Se conserva: determinismo (`SimRNG`, comandos por `SimAPI`), red LAN (`net/`), contenido JSON
(24 unidades, 19 edificios, 5 civs, edades, techs), extractor SLD (`tools/extract_aoe2_sprites.py`),
lógica de reglas AoE2 ya escrita (tasas, armaduras) como referencia para portar.

## 3. Arquitectura

```
engine/                  motor genérico: no conoce "aldeano" ni "cuartel"
  data/                  Registry: carga mods, resuelve extends, aplica parches, valida, hash
  sim/                   World (única fuente de verdad), Tick, SimRNG, FixedPoint, CommandQueue
    abilities/           esquemas de habilidades (Move, Gather, Attack, Train, ...)
    systems/             un sistema por habilidad o grupo (MoveSystem, GatherSystem, CombatSystem, ...)
    spatial/             SpatialHash, Pathfinding (A* + grupos), Visibility
  net/                   lockstep, discovery, desync (migrado desde net/)
  render2d/              IsoCamera, TerrainLayer, EntityLayer, FxLayer, FogLayer, shaders
  ui/                    widgets base (Button, Tooltip, Panel, CommandGrid, Portrait)
  assets/                AssetLocator: "sprite:<id>" -> pack extraído o placeholder
game/                    pegamento específico de este juego
  scenes/                MainMenu, Lobby, Match, Campaign, Importer
  hud/                   HUD estilo AoE2 DE construido con engine/ui
  ai/                    IA enemiga (emite comandos como un jugador)
mods/
  aoe2_base/             contenido actual migrado: units/ buildings/ techs/ civs/ ages/ maps/ lang/
    mod.json             {id, version, depends:[], priority}
tools/                   extractor SLD/terreno/UI/sonido, validador de mods (CLI)
user://aoe2_assets/      salida del importador (fuera del repo y del ejecutable)
```

**Reglas de dependencia** (verificadas por un test de lint):
- `game → engine`; `engine/render2d → engine/sim` (solo lectura); `engine/sim → engine/data`.
- `engine/sim` no puede referenciar `Node2D`, `Node3D`, `Sprite*`, `Time`, `randf`, `randi`,
  `OS.get_ticks*`, ni `float` en posiciones/estado persistente.
- La UI y el render solo cambian el juego vía `Sim.queue_command(pid, type, payload)`.

**Autoloads finales**: `Registry`, `Sim`, `Net`. `GameManager` y `CampaignManager` se disuelven en
servicios de `Sim` (jugadores, edades, victoria) y escenas de `game/`.

## 4. Modelo de datos

### 4.1 Entidad

```json
{
  "id": "cuartel", "extends": "edificio_base", "type": "building",
  "name": "@str:cuartel",
  "tags": ["militar", "edificio"],
  "requires": {"age": "alta_edad_media"},
  "cost": {"wood": 175}, "build_time": 50, "footprint": [3, 3],
  "graphics": {"idle": "sprite:b_west_barracks_age{age}_x1", "icon": "icon:barracks"},
  "abilities": {
    "Hitpoints":  {"max": 1200},
    "Armor":      {"classes": {"melee": 1, "pierce": 8, "building": 0}},
    "Train":      {"units": ["milicia", "lancero"], "queue": 5},
    "RallyPoint": {},
    "Garrison":   {"capacity": 10, "accepts": ["tag:infanteria"]}
  }
}
```

- `type`: `unit | building | resource | projectile | tech | age | civ | map`.
- `extends`: fusión profunda con el padre (diccionarios se fusionan, arrays se reemplazan salvo
  op explícita). Padres abstractos con `"abstract": true` no aparecen en juego.
- `graphics`: claves de estado → referencias de asset (ver §7). Admite plantillas `{age}`, `{civ_set}`.
- Textos con `@str:<clave>` resueltos desde `lang/<idioma>.json`.

### 4.2 Catálogo inicial de habilidades

| Habilidad | Parámetros principales |
|---|---|
| Hitpoints | max, regen |
| Armor | classes {clase: valor} |
| Move | speed, turn? |
| Selectable | radius, selection_priority |
| Attack | damage {clase: valor}, range, min_range, reload, attack_delay, accuracy, projectile, area {radius, falloff}, targets |
| Gather | rates {tipo_recurso: por_seg}, capacity, carry_graphics |
| DropSite | accepts [recursos] |
| ResourceSource | resource, amount, decay?, gatherers_max, requires_kill? |
| Build / Repair | rate |
| Constructable | build_time, footprint, placement {terrain, adjacency} |
| Train | units, queue |
| Research | techs |
| RallyPoint | — |
| Garrison | capacity, accepts, arrows_per_unit, heal_rate |
| Garrisonable | — |
| ProvidesPop | amount |
| Vision | sight |
| Convert / Heal | range, rate / probabilidades |
| Trade | gold_per_distance |
| Farm | reseed_cost, food |
| Upgradable | to |
| Formation, Stance | defaults |

### 4.3 Parches (tecnologías, civilizaciones, mods)

```json
{"id": "forja", "type": "tech", "cost": {"food": 150}, "research_time": 50, "at": "herreria",
 "requires": {"age": "feudal"},
 "effects": [
   {"target": "tag:infanteria|tag:caballeria", "op": "add",
    "path": "abilities.Attack.damage.melee", "value": 1}
 ]}
```

- Operaciones: `set`, `add`, `mul`, `append`, `remove`, `replace_entity`, `enable`, `disable`.
- Selectores `target`: `id:x`, `tag:x`, `type:x`, combinables con `|` (unión) y `&` (intersección).
- Los bonus de civilización son `effects` aplicados en el tick 0; las unidades únicas se habilitan
  con `enable`.
- Cada jugador tiene su **vista parcheada** de las definiciones; se recalcula al completar una
  investigación, nunca por tick. Las entidades vivas leen stats de esa vista (una mejora afecta a
  las unidades existentes, como en AoE2).

### 4.4 Registry

1. Lee `mods/*/mod.json` y ordena por dependencias y luego por `priority`.
2. Carga entidades; un mod posterior sobrescribe por `id` o parchea con `"patch": true`.
3. Resuelve `extends` (con detección de ciclos).
4. Valida cada habilidad contra su esquema: si falta un campo o el tipo no coincide, error con
   ruta de archivo y ruta del campo. **Sin fallbacks silenciosos.**
5. Calcula `content_hash` (SHA-256 del contenido canónico). El lobby LAN solo arranca si todos los
   jugadores tienen el mismo hash.

### 4.5 Extensión con código
Una habilidad nueva = un esquema (`engine/sim/abilities/<Nombre>.gd`) + un `System` registrado en
`engine/sim/systems/registry.gd`. El HUD, los tooltips, la IA y las teclas rápidas descubren las
acciones a partir de las habilidades presentes (si hay `Train`, aparecen botones de entrenar).
Los scripts de mod quedan fuera de alcance; este registro es el punto de enganche futuro.

## 5. Simulación y jugabilidad

### 5.1 Núcleo determinista
- Tick fijo 10 Hz; `Sim` procesa comandos del tick y luego los sistemas en **orden fijo** declarado.
- Posiciones y velocidades en punto fijo (enteros, 1/1000 de casilla). Divisiones y raíces con
  funciones de `FixedPoint`.
- `World`: almacén de entidades por id entero creciente; componentes por habilidad en tablas
  indexadas por id; iteración siempre por id ascendente.
- `SpatialHash` para consultas de proximidad (objetivos, recursos cercanos, dropsite más cercano).
- Pathfinding A* sobre la grilla de casillas con caché de caminos, movimiento en grupo con
  formaciones y evitación local simple determinista.
- Cada entidad expone al render: `{action, sub_action, heading(0..15), action_start_tick,
  hp_ratio, carry, owner}`.
- Hash de estado por tick para `DesyncDetector` (se conserva el mecanismo actual).

### 5.2 Recolección
- Ciclo: ir al recurso → recolectar a `rates[tipo]` → al llenar `capacity` caminar al `DropSite`
  más cercano que acepte ese recurso → depositar → volver al mismo nodo.
- Nodo agotado: buscar en radio el más cercano del mismo tipo; si no hay, quedar ocioso y emitir
  alerta.
- Caza: matar con `Attack`, el cadáver es `ResourceSource` con `decay`. Jabalí: contraataca.
  Ovejas: se capturan por visión (cambio de dueño).
- Bayas, pesca (barco pesquero y trampas), granjas con cola de resiembra en el molino.
- Construcción cooperativa con la fórmula AoE2: tiempo = base × 3 / (n + 2).
- Reparación que consume recursos. Comercio: oro según distancia entre mercados.
- Mejoras de carga (carretilla/carro de mano) y de tasa vía parches.

### 5.3 Combate
- Daño = max(1, Σ_clases max(0, ataque[c] − armadura[c])), con clases `melee`, `pierce` y bonus
  (`caballeria`, `lancero`, `edificio`, `asedio`...) definidos en datos.
- `reload` entre ataques; `attack_delay` = momento del impacto/disparo dentro de la animación.
- Proyectiles como entidades: trayectoria balística; si fallan (según `accuracy`), caen en un
  punto dispersado y pueden impactar a otra entidad. Balística (tech) cambia a tiro predictivo.
- Daño en área con falloff (onagro, trabuquete, bombarda); `min_range`.
- Posturas: agresiva, defensiva, mantener posición, no atacar. Ataque en movimiento, patrulla, seguir.
- Monjes: conversión con `SimRNG` y probabilidades AoE2; curación; reliquias en monasterio (oro/seg).
- Guarnición: flechas extra por unidad, curación dentro, campana del centro urbano.

### 5.4 Edades, producción, victoria
- Edades como entidades `type: age` con coste, tiempo y requisitos (n edificios de la edad anterior).
- Colas de producción de 5 con reembolso al cancelar; población con `ProvidesPop` y tope 200.
- Victoria por conquista (configurable: maravilla, reliquias). Equipos y diplomacia.

### 5.5 Animaciones ligadas a la simulación
- El render elige el sprite a partir de `action/sub_action` + `graphics` de la entidad:
  aldeano con sprites propios para leñador, minero de oro y de piedra, granjero, cazador,
  recolector, constructor, reparador y pescador, y variantes de caminar cargando.
- La animación de ataque arranca en `action_start_tick` y se escala para que el frame de impacto
  coincida con `attack_delay`.
- Muerte: animación `death` → cadáver (`decay`) que se desvanece; edificios destruidos dejan
  escombros temporales.

## 6. Render 2D isométrico

- Proyección 2:1 como AoE2 DE; `IsoCamera` con pan (bordes, WASD, botón medio), zoom con límites
  y suavizado.
- **Terreno**: texturas originales extraídas, mezcla entre tipos con máscaras de transición,
  elevación con luz/sombra por pendiente, agua animada con shader (ondas y reflejo de orillas).
- **Capas y orden**: terreno → decals (huellas, escombros) → sombras → entidades ordenadas por
  profundidad isométrica (pie de sprite / base del edificio) → proyectiles → marcadores de mundo.
- **Color de jugador**: shader que tiñe la máscara extraída (`m_*.png`) con el color del jugador.
- **Siluetas**: unidades propias detrás de edificios/árboles se dibujan como contorno.
- **Efectos**: humo y fuego en edificios dañados al 75/50/25 %, polvo de construcción, flechas y
  piedras con sombra, escombros, árboles que se sacuden al talar, fauna ambiental.
- **Niebla**: negro sin explorar; gris explorado con fantasmas congelados de edificios vistos.
- **Pulido**: elipse de selección + barra de vida, marcador animado de orden (mover/atacar/
  recolectar), bandera de punto de reunión, vista previa de construcción verde/roja, cursores
  contextuales.
- **Interpolación**: el render interpola posiciones entre ticks para 60+ FPS.
- Rendimiento objetivo: 1600 unidades animadas a 60 FPS en una GPU integrada moderna (atlas de
  sprites por animación, dibujado por lotes, culling por pantalla).

## 7. Assets: importador y AssetLocator

- Escena `game/scenes/Importer`: en el primer arranque detecta la instalación del AoE2 DE (rutas
  típicas de Steam y Xbox; si no, pide elegir la carpeta) y extrae a `user://aoe2_assets/`:
  sprites SLD (unidades, edificios, efectos) con máscara y sombra, terreno, UI (paneles por
  civilización, íconos, cursores, fuentes si procede) y sonidos.
- Un manifiesto `mods/aoe2_base/assets_map.json` mapea los ids lógicos (`sprite:u_inf_militia_walkA`)
  a archivos del juego. El importador solo extrae lo referenciado.
- `AssetLocator.resolve(ref)` → textura/atlas extraído, o placeholder geométrico (rombo de color
  del jugador con inicial) si falta. Sin assets el juego es jugable.
- Legal: nada extraído se versiona ni se incluye en exportaciones (se conserva la regla de
  `.gitignore`); `docs/SPRITES.md` se actualiza.

## 8. Interfaz estilo AoE2 DE

- **Barra superior**: madera, alimento, oro y piedra con cantidad de aldeanos en cada uno;
  población/tope; edad actual; botón de aldeano ocioso; reloj; menú; diplomacia; chat.
- **Panel inferior** con skin de la civilización del jugador:
  - izquierda: `CommandGrid` 5×3 generado desde habilidades y comandos; teclas rápidas en grilla;
    tooltips con coste, tiempo y estadísticas;
  - centro: retrato, nombre, HP, ataque/armadura/alcance, cola de producción, o grilla de
    selección múltiple agrupada por tipo;
  - derecha: minimapa (terreno, unidades por color, niebla, pings, destellos de ataque).
- Árbol de tecnologías generado desde los datos. Pantalla de estadísticas al terminar la partida.
- Controles actuales (`docs/CONTROLES.md`) se mantienen.

## 9. Pruebas

- **Unitarias de simulación (headless)**: un test por sistema con escenarios mínimos, p. ej.
  aldeano leñador junta 10 de madera en `10 / rate` s ± 1 tick; arquero vs lancero aplica el
  daño correcto; granja se agota en 250 de alimento; construcción con 3 aldeanos = base × 3/5.
- **Determinismo**: la misma semilla y comandos dan el mismo hash final en dos corridas.
- **Integración**: `lan_8_bots` (se conserva) en la simulación nueva.
- **Datos**: `tools/validate_mods` falla con errores de esquema, referencias rotas (unidad en
  `Train` inexistente) y ciclos de `extends`.
- **Lint de arquitectura**: falla si `engine/sim` usa APIs visuales, de tiempo o aleatorias.
- Cada fase cierra con todos los tests en verde y la partida jugable.

## 10. Fases de migración

El juego viejo (`world/GameWorld.gd`) sigue siendo el modo por defecto hasta F5; la partida nueva
arranca desde un botón "Partida (nuevo motor)" en el menú.

| Fase | Entrega | Resultado jugable |
|---|---|---|
| F0 | `engine/data` (Registry, esquemas, parches, hash), `engine/sim` (World, Tick, FixedPoint, SpatialHash), migración de todo `data/` a `mods/aoe2_base` con habilidades, validador | Tests verdes; juego viejo intacto |
| F1 | `render2d` (cámara, terreno, EntityLayer, shader de color), AssetLocator + importador mínimo, Move + Pathfinding + selección y comando mover | Aldeanos en isométrico que caminan con su animación |
| F2 | Gather, DropSite, ResourceSource, caza, granjas, pesca, barra superior | Economía completa AoE2 |
| F3 | Attack, proyectiles, área, posturas, formaciones, muerte, animaciones de ataque sincronizadas | Combate completo |
| F4 | Construcción, Train, Research, edades, parches de tech/civ, guarnición, monjes, comercio | Partida completa contra nada |
| F5 | HUD AoE2 DE completo, minimapa, árbol de tecnologías; el nuevo motor pasa a ser el modo por defecto | Paridad con el juego viejo |
| F6 | IA migrada a comandos, LAN + lobby con `content_hash`, campañas | Multijugador 8p |
| F7 | Efectos, niebla con fantasmas, siluetas, sonido, pulido; se elimina el código viejo (`world/`, `systems/`, `entities/`, `models/`, `core/GameManager.gd`) | Versión final |

Cada fase tendrá su propio plan de implementación.

## 11. Riesgos

| Riesgo | Mitigación |
|---|---|
| Formato de terreno/UI/sonido del DE distinto del SLD | Investigar en F1 con documentación de openage; placeholders mientras tanto. |
| Rendimiento de GDScript con 1600 unidades | Tablas por componente, SpatialHash, profiling en F3; mover hot paths a GDExtension (C++) solo si hace falta. |
| Divergencia de reglas AoE2 | Tests con valores conocidos del AoE2 DE en cada sistema. |
| Alcance enorme | Fases con entrega jugable y plan separado por fase. |
