# Sprites 2D del AoE2:DE en OpenAge-LAN

Los gráficos del Age 2 DE son sprites 2D (`.sld`), no modelos 3D. Este proyecto
los convierte a PNG y los muestra como billboards animados (8 direcciones).

## Extraer (una vez por unidad, en tu PC con el juego comprado)

```powershell
py tools/extract_aoe2_sprites.py --src "C:\XboxGames\Age of Empires II- Definitive Edition\Content\Game\resources\_common\drs\graphics" --out assets\sprites\tmp --files u_inf_militia_walkA_x1 u_inf_militia_idleA_x1 --pack --step 2
move assets\sprites\tmp\u_inf_militia_walkA_x1 assets\sprites\militia\walk
move assets\sprites\tmp\u_inf_militia_idleA_x1 assets\sprites\militia\idle
```

- `--list "u_arc*"` lista archivos sin extraer.
- `--pack --step 2` recorta al contenido y guarda 1 de cada 2 frames (VRAM).
- `--pack` usa vía rápida sin PNG intermedios (escribe solo p_*/m_* finales).
- `--max-frames 5` para probar rápido.
- Formato detectado: 16 slots x N frames (8 dirs + 8 espejadas) + 1 extra.

## Cómo lo usa el juego

- `entities/unit/SpriteUnit.gd`: billboard con idle/walk, dirección por rumbo.
- `entities/unit/SpriteFactory.gd`: usa sprites si existen, si no 3D propio.
- Carpetas activas hoy: `assets/sprites/villager/{walk,idle}/`.
- Para añadir militia/arquero: extrae walk+idle, ponlos en
  `assets/sprites/militia/{walk,idle}/` y `assets/sprites/archer/{walk,idle}/`
  (los nombres ya están cableados en SpriteFactory).

## Máscara player-color

- `pack_anim` recorta `frame_*.mask.png` con el mismo bbox que el PNG
  principal y la guarda como `m_*.png` junto a `p_*.png` (misma
  geometría y hotspot; `manifest.pack.json` trae `"mask": <nombre o null>`).
- Si la máscara está vacía (todo alpha 0) no se guarda y queda `"mask": null`.
- Qué contiene: píxel blanco con alpha = zona teñible (ropa/escudo).
- Cómo usarla: donde `m_*.png` tenga alpha > 0, teñir el píxel de `p_*.png`
  con el color del jugador (blanco+alpha = teñir).

## Notas legales y técnicas

- Usa solo tu copia comprada. No redistribuyas los PNG (el ZIP del juego
  no los incluye; cada jugador extrae los suyos o usa el fallback 3D).
- El pack conserva la máscara player-color en `m_*.png` (algunos .sld no la
  traen: entonces `"mask": null`); el tinte en juego queda pendiente.
- Sombras del sprite ignoradas (el sol 3D ya proyecta sombra del quad).

## Motor nuevo (F1)

- Las definiciones en `mods/aoe2_base` referencian sprites como `"sprite:<pack>/<anim>"`
  (p. ej. `"sprite:villager/walk"`). `engine/assets/AssetLocator.gd` los busca en
  `user://aoe2_assets/sprites/<pack>/<anim>/` y luego en `res://assets/sprites/<pack>/<anim>/`.
- Formato: el mismo `manifest.pack.json` + `p_*.png` (+ `m_*.png` máscara) de `--pack`.
- Proyección isométrica 2:1 con casilla de 96×48 (sprites `x1`). Direcciones: 16 slots,
  E=0 en sentido horario (SE=2, S=4, SW=6, W=8, NW=10, N=12, NE=14). Sin pack, el render dibuja un placeholder.
- Probar: menú → "Partida (nuevo motor, beta)", o
  `godot --path . res://game/scenes/Match.tscn -- --screenshot=user://f1.png --frames=90`.
- Recursos y edificios con packs de **1 dirección y varios frames** (p. ej. `nature/oak` con 42
  árboles) se tratan como **variantes**: cada entidad muestra un frame fijo elegido por su id.
  Las unidades sí animan esos frames.
- Recursos: `tree → nature/oak`, `gold_mine → nature/goldmine`, `stone_mine → nature/stonemine`,
  `berry_bush → nature/bush` (definidos en `tools/migrate_data_to_mod.py`).
- Faenas del aldeano: el migrador genera `graphics.task_<rate_key>` (`task_wood → villager/lumber`,
  `task_gold`/`task_stone → villager/miner_gold`, `task_food_forage → villager/forager`,
  `task_food_fish → villager/fisher`); si falta el pack, el render usa `task`.

## Terreno (F1b)

- Al abrir la partida del motor nuevo, si el AoE2 DE está instalado (rutas típicas de Xbox/Steam,
  o `OPENAGE_AOE2_PATH=<carpeta del juego>`), se exportan una vez las texturas
  `resources/_common/terrain/textures/2x/*.dds` que usan los terrenos del mod a
  `user://aoe2_assets/terrain/*.png` (Godot decodifica el DXT1; no hace falta Python).
- Terrenos como datos: `mods/aoe2_base/terrains/*.json` con `texture` (`"terrain:g_gr2"`) y `color`
  de respaldo (se usa si no hay juego instalado). Arabia usa pasto `g_gr2`, pasto seco `g_gr3`,
  tierra `g_ds3` y suelo de bosque `g_fo2`.
- `engine/render2d/terrain.gdshader` mezcla las capas con un mapa de control (bosque bajo los
  árboles, parches por ruido) y bordes orgánicos; fuera del mapa el fondo es negro.


## Animales (F3b)

- Packs en `assets/sprites/animals/<animal>/<anim>` (`deer`, `boar`, `sheep`; anims `idle`, `walk`,
  `death`, `decay` y `attack` en el jabalí), extraídos de `a_hunt_*` / `a_herd_*` del DE. En el repo
  van solo los manifests; los PNG los extrae cada jugador.
- El migrador genera `graphics` por subcarpeta (`"death": "sprite:animals/deer/death"`...).
  Al morir, la carcasa reproduce `death` una vez y luego queda el frame de `decay` en el suelo
  mientras se recolecta.
- Las ovejas con dueño llevan la elipse del color del jugador (no traen máscara) y se re-tiñen
  al cambiar de dueño.


## Variante SLD 0x0e (RESUELTO: era header_size, no variante)

- El campo u2 de la cabecera es header_size = offset del primer frame (openage
  sld.pyx: current_offset = header_size). Archivos 0x10 empiezan en 16; los 226
  archivos 0x0e (establos, banderas b_misc_waypoint_flag_*, etc.) empiezan en 14.
  El extractor arranca en r.o = header_size y ambos parsean con el mismo codigo
  (el establo trae headers estandar ft=0x1f, idx 0..89).
- Granja: no existe sprite de campo en el DE (solo anims de granjero u_*_farmer_*
  y overlay de terreno: terrain/blends/farmland.png, textures/2x/g_fm1-2,
  g_fc1-3, g_wt*.dds). En el clon, EntityView._draw() pinta la granja
  (def_id == granja) como rombo con textura de campo del DE (fc1 en obra, fm1 maduro; tierra plana si faltan) en vez del
  fallback azul. Maravilla usa wonder/b_west_wonder_britons_x1.

## Velas
- `ships_sails`: pack `ships/sail_<anim>`; unidades navales usan `graphics.sail` aparte del casco; si falta, nave sin vela.
## Destruction / rubble
- Cada edificio: `graphics.destruction` (`<bldg>/destruction`, anim 1 vez) + `graphics.rubble` (`<bldg>/rubble`, variante fija por id).
## Maravillas por civi
- `wonder/wonder_<civi>` por civilizacion; con `destruction`/`rubble` propios igual que edificios.
## Elites con sprite propio
- La elite no retinta: `graphics` apunta a pack propio (`<unit>_elite/<anim>`), fallback a linea base si falta.
## Faenas femeninas
- `villager_female/<task>` espejo de `villager/<task>` (`lumber`, `miner_gold`, `forager`, `fisher`, `farmer`); fallback a faena masculina.
## Proyectiles reserva
- Packs `projectiles/<flecha,piedra,virote>/` ya cableados en `graphics.projectile`; placeholder si falta el PNG.
## Fauna / deco
- `animals/<lobo,gaviota,pez>/` + `deco/<rocas,flores,ruinas>/` como variantes 1-dir fijas por id (como `nature/oak`).
## Edades {age} + refresh
- Packs con `{age}` (`<bldg>_<age>/`) se re-resuelven al avanzar de edad con `refresh` sin recrear la entidad.
## Minas por etapas + andamios
- `nature/<goldmine,stonemine>_<pct>` por % restante; `scaffold/<bldg>` visible solo en obra, se oculta al terminar.
## Terrenos nuevos (14)
- 14 texturas `terrain:g_*` nuevas; limite shader: mezcla 4 capas (base + 3 overlays); resto cae a `color` respaldo.
