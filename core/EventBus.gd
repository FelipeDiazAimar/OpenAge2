extends Node
# EventBus - desacopla a los 30 agentes. Todo pasa por aquí.
# Uso: EventBus.command_issued.emit(cmd) / EventBus.tick_finished.emit(tick)

signal command_issued(cmd: Dictionary)
signal tick_finished(tick: int)
signal resources_changed(player_id: int, res: Dictionary)
signal selection_changed(units: Array)
signal age_up(player_id: int, new_age: String)
signal minimap_ping(player_id: int, pos: Vector2)
signal chat_msg(player_id: int, text: String)
signal desync_detected(tick: int, hash_local: int, hash_remote: int)
signal unit_died(unit_id: int, killer_id: int)
signal building_placed(player_id: int, building: String, pos: Vector3)
