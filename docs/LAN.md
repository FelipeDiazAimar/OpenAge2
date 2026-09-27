# LAN 8 jugadores - Guía (gratis, sin internet)

## Host (tu PC)
1. Abre el juego en Godot: F5
2. Multijugador -> Crear LAN -> mapa Arabia -> Abrir
3. Te muestra: `Host OK en 192.168.1.X:7778`
4. Pasa esa IP a tus amigos (misma WiFi/Ethernet).

## Unirse (PCs amigos)
1. Misma red WiFi.
2. Multijugador -> Buscar LAN (escucha UDP 7777) o Unirse por IP.
3. Elige color/civ/equipo -> Listo.

## Firewall Windows (solo una vez)
Permitir `Godot` en red privada. O abrir:
- UDP 7777 (descubrimiento)
- TCP 7778 (partida)

Comando (admin PowerShell):
```
New-NetFirewallRule -DisplayName "OpenAge UDP" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
New-NetFirewallRule -DisplayName "OpenAge TCP" -Direction Inbound -Protocol TCP -LocalPort 7778 -Action Allow
```

## Test sin amigos
```
godot --headless --test lan_8_bots --map arabia --ticks 3600
```
Simula 8 bots, debe terminar sin desync.

Máximo: 8 jugadores (1 host + 7). Latencia LAN típica <50ms.
