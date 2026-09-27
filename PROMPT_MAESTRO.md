# PROMPT MAESTRO - OpenAge-LAN (pegar en terminal nueva con 30 agentes)
# Proyecto ya scaffoldeado en esta carpeta. No re-crear, CONTINUAR desde aquí.

ERES coordinador de 30 agentes. Objetivo: RTS tipo AoE2 jugable LAN 8p, 100% GRATIS, aspecto AoE2 (cámara orto fija -32,-45, HUD con minimapa abajo-izq, 3D low-poly CC0), acciones 1:1 AoE2 (smart right-click, A attack-move, P patrulla, S stop, G guarecer, T campana, Ml recolectar/reparar, monje convertir/curar, mercado comerciar).

STACK: Godot 4.4 GDScript, ENet (7777 UDP discovery, 7778 TCP), lockstep 10Hz, JSON data-driven en data/. Prohibidoassets de pago o con copyright. Solo CC0 en assets/cc0 + placeholders.

REGLAS: cada agente solo su carpeta, API en core/API.md, nada de randf/Time en lógica (usar SimRNG), comandos via SimAPI.queue_command, commits pequeños.

REPARTO:
1 Arquitecto GameManager 2 Sim tick+RNG 3 Economy 4 Construction 5 Ages/Tech 6 Combat melee 7 Combat ranged 8 Producción/rally 9 Villager AI 10 Military AI 11 Pathfinding A* 12 Fog 13 Building base 14 Edificios eco 15 Edificios militares 16 Monje/reliquias 17 Infantería 18 Arqueros/asedio 19 Civs JSON 20 Discovery UDP 21 Lobby 8p 22 Lockstep+desync 23 Importador SCX/RMS (tools/convert_aoe2.py) 24 Generador Arabia 25 3D+cámara+terreno 26 Menús+lobby UI 27 HUD comandos 28 Minimapa+pings 29 Audio Bfxr CC0 30 QA/tests+docs

FASES: 0 mover aldeano LAN -> 1 eco+niebla+minimapa -> 2 combate+edades MVP 1v1 -> 3 8p+importador -> 4 modding.

HECHO cuando: godot --headless --test lan_8_bots 3600 ticks sin desync + Host visible en LAN y partida 20min 8p sin crash + screenshot TC+casas+aldeanos talando con HUD AoE2.

EMPIEZA: lee README.md, core/API.md, data/actions.json y sigue por FASE 0 sin romper lo existente.
