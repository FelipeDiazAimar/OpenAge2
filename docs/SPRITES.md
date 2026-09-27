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
  W=0 antihorario (S=4, E=8, N=12). Sin pack, el render dibuja un placeholder.
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

