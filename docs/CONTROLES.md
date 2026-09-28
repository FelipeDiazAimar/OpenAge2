# CONTROLES — lista completa (estilo AoE2)

Fuente de verdad: `project.godot` ([input]), `ui/hud/HUD.gd`, `core/AoeCamera.gd`, `systems/selection/Selection.gd`, `data/actions.json`.

## Ratón

| Entrada | Acción |
|---|---|
| Click izquierdo | Seleccionar unidad/edificio propio (radio 24 px). Con caja de arrastre: seleccionar hasta 60 propios en el rectángulo |
| Doble-click izquierdo | Seleccionar todas las unidades visibles en pantalla del mismo tipo |
| Click derecho (smart action) | Contextual: atacar si enemigo, recolectar si recurso, reparar si aliado dañado, guarecer si edificio propio, comerciar si mercado, mover en otro caso |
| Click derecho con edificio seleccionado | Fijar punto de rally (`set_rally`) |
| Shift + click / Shift + caja | Añadir/quitar de la selección en vez de reemplazar |
| Rueda arriba/abajo | Zoom cámara (orto size 10–40) |
| Botón medio (mantener + arrastrar) | Desplazar cámara |
| Borde de pantalla (4 px) | Edge-pan de cámara |

## Teclado — órdenes

| Tecla | Acción (input map) | Notas |
|---|---|---|
| `A` | `attack_move` — atacar-mover | Luego click en destino. Encolable con Shift |
| `P` | `patrol` — patrulla | Luego click destino. Encolable |
| `S` | `stop_action` — alto | Inmediato, no encolable |
| `G` | `garrison` — guarecer | Luego click en edificio propio |
| `U` | `ungarrison` — desguarecer | Inmediato |
| `B` | `build_menu` — submenú construir | Abre 12 edificios (casa, TC, cuartel, camp. maderero, molino, camp. minero, granja, mercado, monasterio, herrería, universidad, muelle) + Atrás/Cancelar |
| `R` | Reparar | Con aldeano seleccionado, luego click en edificio/asedio aliado dañado (15 HP/s, coste 50%) |
| `T` | `bell` — campana | Alterna: aldeanos se refugian en el TC |
| `H` | `go_tc` — ir al Centro Urbano | Centra la cámara en tu TC |
| `.` (punto) | `idle_villager` — siguiente aldeano inactivo | Round-robin, centra cámara |
| `/` | Todos los militares inactivos | Selecciona sin mover cámara |
| `Shift` | Modificador | Encola órdenes (move/attack/gather/build...) y añade a selección o a grupos |

## Teclado — cámara

| Tecla | Acción |
|---|---|
| `W` / `↑`, `S` / `↓`, `A` / `←`, `D` / `→` | Pan de cámara (relativo a yaw 45°, escala con zoom) |
| Flechas | Pan (alternativa sin conflictos, recomendada) |
| Rueda / botón medio | Zoom / drag (ver Ratón) |

## Grupos de control

| Entrada | Acción |
|---|---|
| `Ctrl+1..9` | Guardar selección como grupo Nº |
| `1..9` | Recuperar grupo Nº (se podan bajas) |
| Doble `Nº` (<400 ms) | Recuperar + centrar cámara en centroide |
| `Shift+Nº` | Añadir grupo Nº a la selección actual |

## Posturas y formaciones (vía HUD / comandos sim)

- Posturas: agresivo, defensivo, mantener_posición, no_atacar (`MilitaryAI`).
- Formaciones: línea, escalonada, caja, flanco.
- Cola de producción: máx 5 por edificio.

## ⚠️ Conflictos conocidos (a tener en cuenta)

1. **`WASD` vs hotkeys `A`/`S`:** `AoeCamera.gd` usa `A`/`S` para pan izquierda/abajo mientras el HUD los usa para attack-move/stop. En la práctica: con unidades seleccionadas, `A`/`S` actúan como órdenes; para mover la cámara sin ambigüedad usa **flechas, edge-pan o botón medio**. Si te molesta, reasigna el pan a solo-flechas en `AoeCamera.gd`.
2. **`B` (construir) no escribe en chat:** el chat debe confirmarse con Enter; `B` con foco en juego abre el submenú.
3. **Monje (convertir/curar) y carreta (comerciar)** no tienen hotkey fija: se lanzan con smart right-click sobre objetivo válido.

## Reasignar teclas

Proyecto → Configuración → Mapa de entrada, o edita la sección `[input]` de `project.godot`. Los nombres de acción (`attack_move`, `patrol`, `stop_action`, `garrison`, `build_menu`, `go_tc`, `bell`, `idle_villager`, `select_single`, `smart_action`) son los que leen `HUD.gd` y `Selection.gd`: no los renombres sin actualizar esos scripts.

## Motor nuevo ("Partida (nuevo motor, beta)")

- Clic izquierdo: seleccionar (arrastrar para seleccionar varias unidades propias).
- Clic derecho: sobre un enemigo, **atacar**; sobre un recurso, recolectar (aldeanos); en el suelo, mover.
- Clic derecho sobre un **animal** con aldeanos: cazar (ciervo/jabalí se matan primero y luego se
  recolecta la carcasa; el jabalí contraataca). Las **ovejas propias** se seleccionan y mueven como
  unidades; si te alejas, un aldeano enemigo cercano puede quedárselas.
- **Construir**: con aldeanos seleccionados, el panel de abajo a la izquierda muestra las páginas
  **Q** (económicos) y **W** (militares); dentro, cada edificio tiene su tecla (económicos: Q casa,
  W molino, E campamento minero, R campamento maderero, T muelle, A granja, S herrería, D mercado,
  F monasterio, G universidad, Z centro urbano, X maravilla; militares: Q cuartel, W arquería,
  E establo, R taller de asedio, A muro, S puerta, D torre, F castillo). **Esc** vuelve atrás.
  En gris los bloqueados (el motivo aparece al pasar el ratón). Elige uno y haz clic en el mapa
  para colocarlo (vista previa verde/roja); **Shift** coloca varios; clic derecho o **Esc** cancela.
  Clic derecho sobre un cimiento propio = seguir construyéndolo.
- **Entrenar / investigar / avanzar de edad**: selecciona el edificio y usa su panel; la tecla de
  cada unidad (p. ej. **C** aldeano, **Q** milicia) también entrena. Clic en un puesto de la cola
  = cancelar (devuelve el coste). Sin casas, la cola se detiene.
- **Punto de reunión**: con un edificio seleccionado, clic derecho en el mapa (sobre un recurso,
  los aldeanos nuevos lo recolectan; sobre un cimiento, lo construyen).
- **Reparar**: clic derecho de aldeanos sobre un edificio propio dañado (cuesta la mitad de su
  coste en proporción al daño; se detiene si no alcanzan los recursos).
- **Guarecer**: clic derecho de militares (aldeanos: **Alt**+clic derecho) sobre un edificio propio
  con guarnición (centro urbano, torre, castillo); dentro no se las puede atacar y cada una suma una flecha. **Sacar**: botón en
  el panel del edificio. **Campana**: botón del centro urbano; mete a los aldeanos cercanos y, al
  tocarla de nuevo, los saca.
- **Monjes** (clic derecho): sobre un enemigo = convertir (4–10 s, luego recargan la fe); sobre una
  unidad propia o aliada herida = curar (si están quietos curan solos a los heridos cercanos);
  sobre una **reliquia** = recogerla; con la reliquia, sobre tu monasterio = guardarla (+0,5 oro/s).
- **Carreta de comercio**: clic derecho sobre el mercado de un aliado; va y viene desde tu mercado
  más cercano y trae oro según la distancia.
- **Descargar**: aldeanos con carga, clic derecho sobre un depósito propio que la acepte; después
  vuelven a su recurso.
- **Mejoras de línea** (p. ej. Piquero): convierten las unidades existentes y el edificio pasa a
  entrenar la versión mejorada.
- **S**: detener. Flechas / borde de pantalla / botón medio: cámara. Rueda: zoom. Esc: menú.
- **F9** / **Shift+F9**: tropas de prueba (5 milicias + 5 arqueros) propias / enemigas bajo el cursor,
  hasta que exista producción en los edificios.

