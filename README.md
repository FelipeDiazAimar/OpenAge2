# OpenAge-LAN — Clon AoE2 gratuito, LAN 8p, moddeable por JSON

RTS tipo Age of Empires 2 hecho desde cero en **Godot 4.4 (GDScript)**, 100% gratis y libre (MIT + assets CC0).
Sin internet, sin servidores, sin DLCs: **8 jugadores en red local (1 host + 7)** por ENet.

## Estado final — qué está implementado

**Simulación determinista (lockstep 10 Hz, `core/`):**
- `GameManager.gd` (500+ líneas): economía por jugador, edades (Alta Edad Media → Feudal → Castillos → Imperial), población y tope (casa +5, máx 200), victoria por equipos, reembolsos.
- `SimRNG.gd` + `SimAPI.gd`: prohibido `randf/Time/física` en lógica; comandos via `SimAPI.queue_command(pid, tipo, payload)`. Tipos válidos: `move, attack, attack_move, patrol, stop, gather, build, repair, garrison, ungarrison, bell, convert, heal, trade, train, research, set_rally, tribute, chat, ping` (ver `core/API.md`).
- `AoeCamera.gd`: cámara ortográfica fija estilo AoE2 (elevación −32°, yaw −45°), pan con WASD/flechas/edge, zoom con rueda, drag con botón medio.

**Sistemas (`systems/`):**
- Economía (`Economy.gd`, `FarmingTrade.gd`): tasas AoE2 en `data/actions.json` (madera 0.39, forraje 0.41, granja 0.32, pesca 0.43, oro 0.38, piedra 0.36), capacidad 10, carretas y granjas.
- Construcción (`Construction.gd`), Edades/Techs (`Ages.gd`, `Techs.gd`), Producción con rally y cola de 5 (`Production.gd`).
- Combate (`Combat.gd`, `Garrison.gd`, `SiegeProjectiles.gd`): melee + rango + asedio con proyectiles.
- IAs (`VillagerAI.gd`, `MilitaryAI.gd`, `MonkAI.gd`): recolectar/reparar, stances (agresivo/defensivo/mantener/no-atacar), formaciones (línea/escalonada/caja/flanco), monje convertir/curar.
- Navegación (`Pathfinding.gd` A* + `Avoidance.gd`), Niebla de guerra (`FogOfWar.gd`), Selección RTS completa (`Selection.gd`, máx 60, drag-box, doble-click por tipo, grupos Ctrl+1..9).

**Red (`net/`):** `NetManager.gd` + `LanDiscovery.gd` — host en TCP 7778, descubrimiento por broadcast UDP 7777, lobby 8 slots con color/civ/equipo.

**Contenido (`data/`):** todo data-driven en JSON — 4 civs (britones, francos, godos, bizantinos con bonus/unidad única/tecnologías/árbol completo), 24 unidades, 19 edificios, techs de herrería/monasterio/universidad, `actions.json` 1:1 AoE2, mapa Arabia + defs de recursos.

**Presentación:** terreno + generador Arabia (`world/`), HUD clon AoE2 con barra de recursos arriba y panel de comandos 3×5 abajo (`ui/hud/HUD.gd`, 700 líneas), minimapa con pings (`ui/minimap/`), lobby, menú principal/pausa/ajustes, árbol de tecnologías, diplomacia, audio Bfxr CC0 (`audio/`). Modelos placeholder low-poly CC0 vía `ModelFactory.gd`.

**Herramientas y tests:** `tools/convert_aoe2.py` (importa mapas SCX/RMS **solo si ya posees AoE2**, nunca incluye assets originales), `tests/Lan8Bots.gd` (`godot --headless --test lan_8_bots` — 3600 ticks sin desync).

## Cómo jugar en LAN (8 jugadores)

Requisitos: todos en la **misma WiFi/Ethernet**, Godot o el ejecutable exportado (ver `docs/BUILD.md`), puertos **UDP 7777 + TCP 7778** permitidos.

**Host (tu PC):**
1. Abre el proyecto en Godot 4.4 → F5 (o ejecuta el `.exe` exportado).
2. Multijugador → Crear LAN → mapa Arabia → Abrir.
3. Te muestra `Host OK en 192.168.1.X:7778` — pasa esa IP a tus amigos.

**Unirse (PCs amigos):**
1. Misma red WiFi.
2. Multijugador → Buscar LAN (escucha UDP 7777) o Unirse por IP.
3. Elige color / civ / equipo → Listo.

**Firewall Windows (solo una vez, PowerShell admin):**
```
New-NetFirewallRule -DisplayName "OpenAge UDP" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
New-NetFirewallRule -DisplayName "OpenAge TCP" -Direction Inbound -Protocol TCP -LocalPort 7778 -Action Allow
```
O permitir `Godot` / `OpenAge-LAN.exe` en red privada.

**Probar sin amigos:**
```
godot --headless --test lan_8_bots --map arabia --ticks 3600
```
Detalle completo en `docs/LAN.md`.

## Controles estilo AoE2

Smart right-click (mover/atacar/recolectar/reparar/guarecer según objetivo), **A** attack-move, **P** patrulla, **S** stop, **G** guarecer, **U** desguarecer, **B** menú construir, **R** reparar, **T** campana, **H** ir al TC, **.** aldeano idle, **/** militares idle, **Ctrl+1..9 / 1..9** grupos, **Shift** encolar/añadir a selección, doble-click selecciona mismo tipo en pantalla, rueda = zoom, botón medio = arrastrar cámara.

Lista completa con conflictos conocidos en **`docs/CONTROLES.md`**.

## Cómo moddear (sin programar)

Todo está en `data/` en JSON y se carga al arrancar. Copia un archivo, cámbialo y listo:
- Nueva facción: copia `data/factions/britones.json` → cambia `id`, `name`, `bonus`, `roof_color` → aparece sola en el lobby.
- Nueva tropa: copia `data/units/aldeano.json` → ajusta `hp, attack, cost, trained_at` → añade el id al `tech_tree` de la facción.
- Nuevo edificio: copia `data/buildings/casa.json` → define `hp, cost, size_tiles, trains`.
- Nueva edad: edita `data/ages/ages.json`. Nueva acción: edita `data/actions.json`.

Guía completa en `docs/MODDING.md`. Licencias de assets en `assets/cc0/CREDITS.md`.

## Abrir y exportar

1. Instala **Godot 4.4** (gratis, https://godotengine.org).
2. Abre esta carpeta `OpenAge-LAN` como proyecto (usa renderer **GL Compatibility**, ya configurado en `project.godot`).
3. F5 para jugar en editor.
4. Para repartir el juego sin Godot: ver **`docs/BUILD.md`** (presets en `export_presets.cfg`: Windows + Linux).

## Documentación

- `docs/LAN.md` — guía LAN y firewall.
- `docs/CONTROLES.md` — lista completa de teclas.
- `docs/BUILD.md` — exportar Windows/Linux.
- `docs/MODDING.md` — modding por JSON.
- `core/API.md` — contrato SimAPI para desarrolladores.
- `PROMPT_MAESTRO.md` — plan original de los 30 agentes.
- `assets/cc0/CREDITS.md` — créditos CC0. **Prohibido subir assets originales de AoE2.**
