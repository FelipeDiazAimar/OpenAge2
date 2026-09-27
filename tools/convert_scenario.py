#!/usr/bin/env python3
"""
convert_scenario.py - Mapas originales de AoE2:DE (.aoe2scenario / .aoe2campaign)
a mapas jugables de OpenAge-LAN (data/maps/imported/*.json).

- Extrae escenarios de campañas (.aoe2campaign es un contenedor con los
  .aoe2scenario concatenados; se recortan por sus firmas de versión).
- Lee terreno (TerrainId -> leyenda propia), recursos (árboles agrupados
  2x2, minas, bayas, caza), spawns (TC por jugador) y registra unidades.
- Re-muestrea a 144x144 si el escenario es de otro tamaño.

Uso:
  py tools/convert_scenario.py --list "C:/XboxGames/.../campaign/acam1.aoe2campaign"
  py tools/convert_scenario.py --campaign .../acam1.aoe2campaign --out data/maps/imported
  py tools/convert_scenario.py --file .../0_E3_Scenario.aoe2scenario --out data/maps/imported

Requiere AoE2ScenarioParser (pip install AoE2ScenarioParser).
Los assets son de tu copia comprada: no redistribuyas los mapas convertidos
si contienen contenido con copyright (úsalos en tu LAN).
"""
import argparse
import json
import os
import re
import sys

TARGET = 144

# def_id nuestros -> amount por defecto (resource_defs.json)
DEFAULT_AMT = {"tree": 100, "gold_mine": 800, "stone_mine": 800,
               "berry_bush": 125, "boar": 340, "deer": 140, "sheep": 100}


def aoe_tile(name):
    n = name.upper()
    if any(k in n for k in ("WATER", "SEA", "OCEAN", "RIVER", "POND")):
        return 3
    if any(k in n for k in ("BEACH", "SHORE", "SHALLOW", "FORD")):
        return 4
    if "FOREST" in n or "JUNGLE" in n or "BAMBOO" in n or "MANGROVE" in n:
        return 2
    if any(k in n for k in ("DESERT", "DIRT", "SAND", "SAVANNAH", "ROAD",
                            "CRACKED", "STEPPE", "ROCK", "QUICKSAND", "MUD")):
        return 1
    return 0


def build_const_sets():
    """Sets de consts leyendo el dataset (las clases guardan tuplas,
    no ints a nivel módulo: se parsea el .py con regex)."""
    import AoE2ScenarioParser.datasets.other as _other_mod
    src = open(_other_mod.__file__, encoding="utf-8").read()
    trees, relics = set(), set()
    for name, num in re.findall(r"^\s*([A-Z0-9_]*TREE[A-Z0-9_]*)\s*=\s*(\d+)", src, re.M):
        trees.add(int(num))
    for name, num in re.findall(r"^\s*([A-Z0-9_]*RELIC[A-Z0-9_]*)\s*=\s*(\d+)", src, re.M):
        if not any(k in name for k in ("MONK", "PRIEST", "CART", "MISSIONARY",
                                       "WARRIOR", "PAGAN")):
            relics.add(int(num))
    units = {66: "gold_mine", 102: "stone_mine", 59: "berry_bush",
             65: "deer", 48: "boar", 594: "sheep", 109: "centro_urbano",
             70: "casa"}
    return trees, relics, units


def carve_campaign(path):
    """Recorta .aoe2scenario válidos de un .aoe2campaign por firmas de versión."""
    from AoE2ScenarioParser.scenarios.aoe2_de_scenario import AoE2DEScenario
    data = open(path, "rb").read()
    out = []
    for m in re.finditer(rb"[0-9]\.[0-9]{2}\x00", data):
        start = m.start()
        # el escenario termina donde empieza el siguiente marcador válido
        out.append(start)
    out = sorted(set(out))
    found = []
    import tempfile
    for i, s in enumerate(out):
        end = out[i + 1] if i + 1 < len(out) else len(data)
        if end - s < 20000 or end - s > 30000000:
            continue
        tmp = os.path.join(tempfile.gettempdir(), "opencode_carve_%d.aoe2scenario" % i)
        with open(tmp, "wb") as f:
            f.write(data[s:end])
        try:
            AoE2DEScenario.from_file(tmp)
            found.append((s, end))
        except Exception:
            pass
    return found


def convert_one(scenario_path, outdir, name=None):
    from AoE2ScenarioParser.scenarios.aoe2_de_scenario import AoE2DEScenario
    from AoE2ScenarioParser.datasets.terrains import TerrainId
    trees, relics, unit_kinds = build_const_sets()
    s = AoE2DEScenario.from_file(scenario_path)
    mm = s.map_manager
    size = mm.map_size
    sx = size / TARGET if size != TARGET else 1.0

    def scale(v):
        return min(TARGET - 1, max(0, int(v / sx)))

    # Terreno
    grid = []
    for ty in range(size):
        for tx in range(size):
            t = mm.terrain[ty * size + tx]
            try:
                nm = TerrainId(t.terrain_id).name
            except ValueError:
                nm = "GRASS"
            grid.append(aoe_tile(nm))
    if size != TARGET:
        small = []
        for y in range(TARGET):
            for x in range(TARGET):
                small.append(grid[int(y * sx) * size + int(x * sx)])
        grid = small
        size = TARGET

    # Unidades / recursos
    resources = []
    tree_cells = {}
    spawns = []
    units_rec = []
    relics_rec = []
    um = s.unit_manager
    for p, lst in enumerate(um.units):
        tc_tiles = []
        ustiles = []
        for u in lst:
            try:
                ux, uy = float(u.x), float(u.y)
            except (TypeError, ValueError):
                continue
            tx, ty = scale(ux), scale(uy)
            c = u.unit_const
            if p == 0:
                if c in trees:
                    key = (tx // 2, ty // 2)
                    tree_cells[key] = tree_cells.get(key, 0) + 1
                elif c in unit_kinds and unit_kinds[c] in DEFAULT_AMT:
                    k = unit_kinds[c]
                    resources.append({"def_id": k, "tile": [tx, ty],
                                      "amount": DEFAULT_AMT[k]})
                elif c in relics:
                    relics_rec.append([tx, ty])
                continue
            if c == 109:
                tc_tiles.append([tx, ty])
            ustiles.append([tx, ty])
            units_rec.append({"kind": unit_kinds.get(c, "unidad_%d" % c),
                              "player": p, "tile": [tx, ty]})
        if p >= 1:
            if tc_tiles:
                spawns.append(tc_tiles[0])
            elif ustiles:
                ax = sum(t[0] for t in ustiles) // len(ustiles)
                ay = sum(t[1] for t in ustiles) // len(ustiles)
                spawns.append([ax, ay])
    for (cx, cy), n in sorted(tree_cells.items()):
        resources.append({"def_id": "tree",
                          "tile": [min(TARGET - 1, cx * 2 + 1),
                                   min(TARGET - 1, cy * 2 + 1)],
                          "amount": n * DEFAULT_AMT["tree"]})
    base = name or os.path.splitext(os.path.basename(scenario_path))[0]
    safe = re.sub(r"[^A-Za-z0-9_]+", "_", base).strip("_") or "mapa"
    out = {"name": base, "size": [TARGET, TARGET], "terrain_grid": grid,
           "resources": resources, "spawns": spawns, "units": units_rec,
           "relics": relics_rec, "players": len(spawns),
           "imported_from": os.path.basename(scenario_path)}
    os.makedirs(outdir, exist_ok=True)
    fp = os.path.join(outdir, safe + ".oamap.json")
    with open(fp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    return fp, out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Escenarios AoE2:DE -> mapas OpenAge-LAN")
    ap.add_argument("--file", default=None, help=".aoe2scenario suelto")
    ap.add_argument("--campaign", default=None, help=".aoe2campaign (extrae todos)")
    ap.add_argument("--list", dest="listpat", default=None, help="lista escenarios del campaign")
    ap.add_argument("--out", default="data/maps/imported", help="carpeta destino")
    args = ap.parse_args(argv)
    if args.listpat:
        data = open(args.listpat, "rb").read()
        marks = sorted(set(m.start() for m in re.finditer(rb"[0-9]\.[0-9]{2}\x00", data)))
        print("%d marcadores de versión (candidatos a escenario)" % len(marks))
        return 0
    if args.file:
        fp, out = convert_one(args.file, args.out)
        print("OK %s: %dx%d, %d recursos, %d spawns, %d unidades" % (
            fp, out["size"][0], out["size"][1], len(out["resources"]),
            len(out["spawns"]), len(out["units"])))
        return 0
    if args.campaign:
        data = open(args.campaign, "rb").read()
        marks = sorted(set(m.start() for m in re.finditer(rb"[0-9]\.[0-9]{2}\x00", data)))
        import tempfile
        from AoE2ScenarioParser.scenarios.aoe2_de_scenario import AoE2DEScenario
        ok = 0
        for i, st in enumerate(marks):
            en = marks[i + 1] if i + 1 < len(marks) else len(data)
            if en - st < 20000 or en - st > 30000000:
                continue
            tmp = os.path.join(tempfile.gettempdir(), "opencode_camp.aoe2scenario")
            with open(tmp, "wb") as f:
                f.write(data[st:en])
            try:
                AoE2DEScenario.from_file(tmp)
            except Exception:
                continue
            base = "%s_%02d" % (os.path.splitext(os.path.basename(args.campaign))[0], ok)
            fp, out = convert_one(tmp, args.out, name=base)
            print("OK %s: %d recursos, %d spawns" % (fp, len(out["resources"]), len(out["spawns"])))
            ok += 1
        print("%d escenarios convertidos" % ok)
        return 0 if ok else 2
    print("indica --file, --campaign o --list")
    return 1


if __name__ == "__main__":
    sys.exit(main())
