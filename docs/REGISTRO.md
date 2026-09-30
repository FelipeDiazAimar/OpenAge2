# Registro de partidas (diagnóstico)

Cada partida del motor nuevo escribe un registro mientras se juega, para poder
investigar después congelamientos, errores o comportamientos raros.

## Dónde queda

`%APPDATA%\Godot\app_userdata\OpenAge-LAN\logs\partidas\partida_<fecha>_<ms>.log`
(`C:\Users\<usuario>\AppData\Roaming\Godot\app_userdata\OpenAge-LAN\logs\partidas\`).
Se guardan los últimos 30; las capturas de F12 quedan al lado (`..._marcaN.png`).
La ruta exacta se imprime en la consola al empezar la partida.

## Qué hacer si algo sale mal

- Si ves algo raro, aprieta **F12**: queda una marca con captura de pantalla en ese momento.
- Si el juego se congela o se cierra, no hace falta nada: el registro se escribe línea a
  línea y sobrevive. Una partida que no cerró bien no tiene la línea `fin`.
- Después, pasa el archivo (o su nombre) para revisarlo.

## Qué contiene (una línea JSON por evento)

| `t` | Qué es |
|---|---|
| `inicio` | versión/commit, Godot, SO, CPU, GPU, pantalla y opciones de la partida (civs, equipos, IA, semilla, lago, tope) |
| `cmd` | cada orden encolada: tick, jugador, `src` (jugador/ia), tipo y datos |
| `pulso` | cada 10 s de juego: huella del estado (`state_hash`), población, recursos, entidades, FPS, peor frame, ms de simulación e IA por tick, memoria |
| `lento` | frame de más de 300 ms y en qué fase estaba |
| `congelado` / `descongelado` | el vigilante (otro hilo) no vio un frame en 2,5 s: fase del cliente y del motor, tick; luego cuánto duró |
| `anomalia` | recursos negativos, entidades fuera del mapa, unidades sobre agua/muros, barcos en tierra, unidades trabadas 20 s, obras pasadas de 100 %, guarniciones con unidades inexistentes, errores de Godot (`error_godot`) |
| `marca` | F12 del jugador (con captura) |
| `fin` | cierre normal |

## Repetir una partida

La simulación es determinista: con la semilla, las opciones y las órdenes se reproduce
exacta. Desde la carpeta del proyecto:

```
godot --headless --path . -s tools/replay_log.gd -- "<ruta del registro>" [--hasta=TICK] [--estado]
```

Rearma la partida (`game/MatchSetup.gd`), le da las mismas órdenes en los mismos ticks y
compara la huella de cada pulso. Informa el primer tick donde diverge (si el motor cambió
desde la partida) y lista anomalías, congelamientos y marcas. `--estado` resume al final
las entidades de cada jugador.
