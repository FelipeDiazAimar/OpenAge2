# SimAPI para los 30 agentes - NO romper compatibilidad

- Tick 10Hz. NADA de randf, Time, física en lógica. Usar SimRNG.
- Comando: {"tick": int, "player_id": int, "type": str, "payload": dict}
- Tipos válidos: move, attack, attack_move, patrol, stop, gather, build, repair, garrison, ungarrison, bell, convert, heal, trade, train, research, set_rally, tribute, chat, ping
- Enviar: SimAPI.queue_command(pid, "move", {"pos": [x,y]})
- Recibir: EventBus.command_issued en GameManager._on_tick (determinista)
- Recursos: GameManager.add_resource / try_spend
- Colores: SimAPI.get_player_color(pid)
- Visual (cámara, HUD, minimapa, sonido) es SOLO cliente, no entra en hash desync.
