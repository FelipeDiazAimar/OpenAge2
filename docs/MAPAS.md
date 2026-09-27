# Mapas originales del AoE2 en OpenAge-LAN

## Importar escenarios de campaña (.aoe2campaign / .aoe2scenario)

```powershell
# Ver escenarios dentro de una campaña:
py tools/convert_scenario.py --list "C:/XboxGames/.../campaign/acam1.aoe2campaign"
# Convertir campaña entera a data/maps/imported/:
py tools/convert_scenario.py --campaign "C:/XboxGames/.../campaign/acam1.aoe2campaign" --out data/maps/imported
# Un escenario suelto:
py tools/convert_scenario.py --file "C:/....../0_E3_Scenario.aoe2scenario" --out data/maps/imported
```

Requiere `pip install AoE2ScenarioParser` (solo para convertir, no para jugar).
Convierte terreno (hierba/tierra/bosque/agua/vado), recursos (árboles
agrupados, minas, bayas, caza), spawns por TC y registra unidades/reliquias.

## Jugar un mapa importado

```powershell
# Desde el editor:
godot --path . res://ui/hud/Game.tscn -- --map=res://data/maps/imported/acam1_00.oamap.json
```

El lobby se ajusta solo al nº de spawns del mapa (equipos alternos).
Próximo: elegir mapa desde el lobby (hoy es por `--map`).

## Límites v1

- El relieve visual es propio (la grilla importada la usará el motor v2).
- Las unidades del escenario se registran en el JSON (`units`, `relics`)
  pero v1 solo spawnea TCs + aldeanos + recursos.
- Legal: no redistribuyas los `.oamap.json` convertidos (el `.gitignore`
  no los excluye por defecto: no hagas push de `data/maps/imported/` si
  subes tu fork a público).
