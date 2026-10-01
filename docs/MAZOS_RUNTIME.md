# Mazos Runtime — jugar cartas
- Flujo: mano → click carta → valida → aplica → descarta.
- Coste: `cost={wood,food,gold,stone}`; si falta, rechaza sin consumir.
- Edad: `min_age`; si `edad_actual < min_age`, bloqueada.
- Efectos: `fx=[{k,v}]` (`add_res,buff,unlock,spawn`); atomicos en orden.
- Target: `self|ally|enemy|pos`; si `pos`, espera 2do click.
- Cooldown: `cd_s` por mazo; no apila misma activa.
- Estado: existe `engine/sim/systems/CardSystem.play_card(sim,pid,card_id)` (edad/coste, `res.*`+`defs.apply_effects`). Tests: `tests/engine/test_cards_runtime.gd` (4 casos). Pendiente: sin `Sim.play_card()` wrapper ni hook UI click.
