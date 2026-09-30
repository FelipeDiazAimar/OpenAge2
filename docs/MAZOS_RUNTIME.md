# Mazos Runtime — jugar cartas
- Flujo: mano → click carta → valida → aplica → descarta.
- Coste: `cost={wood,food,gold,stone}`; si falta, rechaza sin consumir.
- Edad: `min_age`; si `edad_actual < min_age`, bloqueada.
- Efectos: `fx=[{k,v}]` (`add_res,buff,unlock,spawn`); atomicos en orden.
- Target: `self|ally|enemy|pos`; si `pos`, espera 2do click.
- Cooldown: `cd_s` por mazo; no apila misma activa.
- Estado: pendiente hook sim — sin `Sim.play_card()`, solo def. en `MAZOS.md`.
