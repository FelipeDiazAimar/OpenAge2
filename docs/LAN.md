# Partidas en red (LAN)

## Jugar

1. Todas las PC deben tener **la misma versión del juego y los mismos mods**
   (la sala compara la huella de los datos; si difiere, marca
   "¡datos distintos!" y no deja empezar).
2. Menú → Nueva partida → **Multijugador LAN**.
3. Una PC pulsa **Crear partida** (será el anfitrión). Se muestra su IP.
4. Las demás eligen la partida en la lista (doble clic) o escriben la IP del
   anfitrión y pulsan **Unirse**.
5. Cada jugador elige civilización y equipo y marca **Estoy listo**. El
   anfitrión puede agregar/quitar IA, cambiar la semilla, la población máxima
   y el lago, y pulsa **¡Empezar!** cuando todos estén listos.

Puertos: **7778/UDP** (partida, ENet) y **7777/UDP** (anuncio en la LAN).
Si el firewall de Windows pregunta, permitir en redes privadas. Si la lista
no muestra la partida, unirse por IP funciona igual.

## Cómo funciona (lockstep)

Cada PC ejecuta la misma simulación determinista (`engine/sim`). Por la red
solo viajan las órdenes:

- Una orden dada en el tick T se aplica en T + 2 (`Sim.INPUT_DELAY`) en todas
  las PC. Cada PC envía un "turno" por tick, aunque no tenga órdenes.
- El tick N solo se simula cuando llegaron los turnos N − 2 de todos los
  humanos (`engine/net/Lockstep.gd`). Si alguien se atrasa, los demás
  esperan y aparece "Esperando a …".
- Las IA corren igual en todas las PC; sus órdenes no viajan.
- Cada 50 ticks se comparan las huellas del estado. Si difieren aparece
  "¡Desincronización!" y queda anotado en el registro de la partida
  (`docs/REGISTRO.md`), con los hashes de cada jugador.
- Si un jugador se desconecta, se avisa y la partida sigue sin esperarlo (sus
  unidades quedan quietas).
- En red no se cambia la velocidad del juego (+/−).

Código: `game/net/NetSession.gd` (sala, ENet, anuncio), `engine/net/Lockstep.gd`
(turnos y huellas), `game/scenes/Lobby.gd` (UI de la sala), `Match._cmd` (toda
orden local pasa por ahí).

## Diagnosticar una desincronización

1. Juntar el registro de cada PC (`%APPDATA%/Godot/app_userdata/OpenAge-LAN/logs/partidas`).
2. `godot --headless --path . -s tools/replay_log.gd -- <registro> --estado`
   en cada uno: el primer tick donde los estados difieren apunta al sistema
   no determinista (buscar `Time`, `randi`, iteración de diccionarios sin
   ordenar, floats).
