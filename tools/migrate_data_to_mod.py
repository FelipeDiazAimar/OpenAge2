#!/usr/bin/env python3
"""migrate_data_to_mod.py - Convierte data/ (formato viejo) a mods/aoe2_base (habilidades).

Uso:
  py tools/migrate_data_to_mod.py [--src data] [--out mods/aoe2_base] [--sprites assets/sprites]

Regenera las carpetas de entidades de --out (idempotente). Lo que no se puede
portar automáticamente queda en <out>/_migration_report.json y en los campos
legacy_effects de techs/civs (se portan a mano en F4). Solo stdlib.
"""
import argparse
import glob
import json
import os
import shutil

RESOURCES = ["wood", "food", "gold", "stone"]
ENTITY_DIRS = ["base", "units", "buildings", "resources", "techs", "ages", "civs"]
BUILDING_ALIASES = {"caballeriza": "establo"}
CATEGORY_BY_BUILDING = {
    "cuartel": "infanteria", "arqueria": "arqueros", "establo": "caballeria",
    "taller_asedio": "asedio", "muelle": "barco", "monasterio": "monje",
    "mercado": "comercio", "centro_urbano": "aldeano",
}
CATEGORY_BY_ARMOR_CLASS = {
    "infanteria": "infanteria", "arquero": "arqueros", "caballeria": "caballeria",
    "asedio": "asedio", "ariete": "asedio", "barco": "barco", "comercio": "comercio",
}
RANGED_CATEGORIES = {"arqueros", "barco"}
GARRISONABLE = {"infanteria", "arqueros", "caballeria", "aldeano", "monje"}
DROPSITES = {
    "centro_urbano": RESOURCES, "campamento_maderero": ["wood"],
    "campamento_minero": ["gold", "stone"], "molino": ["food"], "muelle": ["food"],
}
SPRITE_PACKS = {
    "aldeano": "villager", "milicia": "militia", "arquero": "archer", "scout": "scout",
    "monje": "monk", "ariete": "ram", "barco_pesquero": "fishingship", "carreta_comercio": "cart",
}
BUILDING_SPRITES = {
    "centro_urbano": "buildings/tc/b_west_town_center_age3_x1",
    "casa": "buildings/house/b_west_house_age3_x1",
    "cuartel": "buildings/barracks/b_west_barracks_age3_x1",
    "arqueria": "buildings/archery/b_west_archery_range_age2_x1",
    "castillo": "buildings/castle/b_west_castle_age3_x1",
    "torre_vigia": "buildings/tower/b_west_tower_age2_x1",
    "mercado": "buildings/market/b_west_market_age2_x1",
    "monasterio": "buildings/monastery/b_west_monastery_age3_x1",
    "herreria": "buildings/smith/b_west_blacksmith_age2_x1",
}
BUILDING_ARROW_SPEED = 7.0  # casillas/s de las flechas de torres y castillos
# rate_key -> packs de faena del aldeano, en orden de preferencia.
VILLAGER_TASKS = {
    "wood": ["lumber"], "gold": ["miner_gold"], "stone": ["miner_stone", "miner_gold"],
    "food_forage": ["forager"], "food_farm": ["farmer", "task"], "food_fish": ["fisher"],
    "food_hunt": ["hunter", "forager"], "food_herd": ["shepherd", "forager"],
}
RESOURCE_SPRITES = {
    "tree": "nature/oak", "gold_mine": "nature/goldmine",
    "stone_mine": "nature/stonemine", "berry_bush": "nature/berry",  # n_forage_bush (con frutos)
    "deer": "animals/deer", "boar": "animals/boar", "sheep": "animals/sheep",
}
AGE_PREREQS = {"herreria_o_mercado": ["herreria", "mercado"], "castillo_o_monasterio": ["castillo", "monasterio"]}
# Reglas AoE2 para avanzar de edad: n tipos de edificio de la edad anterior
# (los datos originales piden solo 1 y no traen la de feudal).
AGE_BUILDINGS = {
    "feudal": {"any_of": ["cuartel", "molino", "campamento_maderero", "campamento_minero", "muelle"], "count": 2},
    "castillos": {"any_of": ["herreria", "mercado", "arqueria", "establo"], "count": 2},
    "imperial": {"any_of": ["castillo", "monasterio", "universidad", "taller_asedio"], "count": 2},
}
# Edad mínima de edificios que los datos originales no traen (AoE2).
BUILDING_AGE = {"herreria": "feudal", "mercado": "feudal", "universidad": "castillos", "monasterio": "castillos",
                "centro_urbano": "castillos"}
# Menú de construcción del aldeano (AoE2 DE): página y tecla de cada edificio.
BUILD_MENU = {
    "casa": ("economico", "Q"), "molino": ("economico", "W"), "campamento_minero": ("economico", "E"),
    "campamento_maderero": ("economico", "R"), "muelle": ("economico", "T"), "granja": ("economico", "A"),
    "herreria": ("economico", "S"), "mercado": ("economico", "D"), "monasterio": ("economico", "F"),
    "universidad": ("economico", "G"), "centro_urbano": ("economico", "Z"), "maravilla": ("economico", "X"),
    "cuartel": ("militar", "Q"), "arqueria": ("militar", "W"), "establo": ("militar", "E"),
    "taller_asedio": ("militar", "R"), "muro": ("militar", "A"), "puerta": ("militar", "S"),
    "torre_vigia": ("militar", "D"), "castillo": ("militar", "F"),
}
HOTKEY_ORDER = "QWERTASDFGZXCVB"
UNIT_ALIASES = {"hombre_de_armas": "hombre_armas", "trabuquete": "trebuchet"}
HUNTABLE = {"boar", "deer", "sheep"}
ANIMAL_RATES = {"food_hunt": 0.41, "food_herd": 0.33}
# Animales (AoE2): se matan y quedan como carcasa recolectable.
ANIMALS = {
    "deer": {"hp": 5, "speed": 1.1, "rate_key": "food_hunt"},
    "boar": {"hp": 75, "speed": 1.0, "attack": 8, "rate_key": "food_hunt", "armor": {"melee": 0, "pierce": 1}},
    "sheep": {"hp": 7, "speed": 0.7, "rate_key": "food_herd"},
}
DEFAULT_MELEE_RELOAD = 2.0  # AoE2: recarga cuerpo a cuerpo estándar
TRAIN_QUEUE = 5
TC_POP = 5
FARM_FOOD = 250  # igual que Economy.FARM_FOOD_MAX del juego viejo
UNIT_FIELDS_USED = {
    "id", "name", "hp", "attack", "armor_melee", "armor_pierce", "armor_class", "range", "sight", "speed",
    "cost", "train_time_sec", "pop_cost", "trained_at", "hotkey", "bonus_vs", "projectile_speed",
    "fire_cooldown_sec", "min_range", "splash_radius", "requires_age", "upgrade_to", "gather_carry",
    "packable", "pack_time_sec", "unpack_time_sec", "unique_to", "civ_unica",
}


def load(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def building_id(name):
    return BUILDING_ALIASES.get(name, name)


def unit_category(u):
    at = building_id(u.get("trained_at", ""))
    if at in CATEGORY_BY_BUILDING:
        return CATEGORY_BY_BUILDING[at]
    return CATEGORY_BY_ARMOR_CLASS.get(u.get("armor_class", ""), "infanteria")


def graphics_for_unit(unit_id, sprites_root):
    pack = SPRITE_PACKS.get(unit_id)
    if not pack or not sprites_root:
        return {}
    base = os.path.join(sprites_root, pack)
    if not os.path.isdir(base):
        return {}
    out = {a: f"sprite:{pack}/{a}" for a in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base, a))}
    # Animación de faena por tipo de recurso (render: acción "task_<rate_key>").
    for rate_key, candidates in VILLAGER_TASKS.items():
        for anim in candidates:
            if anim in out:
                out[f"task_{rate_key}"] = out[anim]
                break
    # El aldeano del DE llama "fight" a su animación de ataque.
    if "attack" not in out and "fight" in out:
        out["attack"] = out["fight"]
    # ...y "builder" a la de construir (render: acción "build").
    if "build" not in out and "builder" in out:
        out["build"] = out["builder"]
    return out


def convert_unit(u, rates, carry, actions, sprites_root=None):
    cat = unit_category(u)
    e = {"id": u["id"], "type": "unit", "extends": f"{cat}_base", "name": u.get("name", u["id"])}
    ac = u.get("armor_class")
    if ac and CATEGORY_BY_ARMOR_CLASS.get(ac) != cat:
        e["tags"] = [ac]
    if u.get("requires_age"):
        e["requires"] = {"age": u["requires_age"]}
    e["cost"] = u.get("cost", {})
    e["train_time"] = u["train_time_sec"]
    e["pop_cost"] = u.get("pop_cost", 1)
    if u.get("hotkey"):
        e["hotkey"] = u["hotkey"]
    if u.get("upgrade_to"):
        e["upgrades_to"] = u["upgrade_to"]
    g = graphics_for_unit(u["id"], sprites_root)
    if g:
        e["graphics"] = g
    ab = {
        "Hitpoints": {"max": u["hp"]},
        "Armor": {"classes": {"melee": u.get("armor_melee", 0), "pierce": u.get("armor_pierce", 0)}},
        "Move": {"speed": u["speed"]},
        "Vision": {"sight": u["sight"]},
    }
    if u.get("attack", 0) > 0:
        ranged = "projectile_speed" in u
        dmg = {"pierce" if ranged else "melee": u["attack"]}
        dmg.update(u.get("bonus_vs", {}))
        atk = {"damage": dmg, "range": u["range"] if ranged else 0,
               "reload": u.get("fire_cooldown_sec", DEFAULT_MELEE_RELOAD)}
        if "min_range" in u:
            atk["min_range"] = u["min_range"]
        if "projectile_speed" in u:
            atk["projectile_speed"] = u["projectile_speed"]
        if "splash_radius" in u:
            atk["area_radius"] = u["splash_radius"]
        ab["Attack"] = atk
    if cat == "aldeano":
        ab["Gather"] = {"rates": dict(rates), "capacity": u.get("gather_carry", carry)}
        ab["Build"] = {"rate": 1.0}
        ab["Repair"] = {"rate": actions["repair"]["rate_hp_per_sec"], "cost_factor": actions["repair"]["cost_factor"]}
    if u["id"] == "barco_pesquero":
        ab["Gather"] = {"rates": {"food_fish": rates["food_fish"]}, "capacity": carry}
    if cat == "monje":
        c, h = actions["convert"], actions["heal"]
        ab["Convert"] = {"range": c["range"], "cooldown": c["cooldown_sec"], "chance": c["chance_base"]}
        ab["Heal"] = {"range": h["range"], "rate": h["rate_hp_per_sec"]}
    if cat == "comercio":
        t = actions["trade"]
        ab["Trade"] = {"gold_base": t["gold_per_trip_base"], "gold_per_tile": t["bonus_per_tile"]}
    if u.get("packable"):
        ab["Packable"] = {"pack_time": u["pack_time_sec"], "unpack_time": u["unpack_time_sec"]}
    civ = u.get("unique_to") or u.get("civ_unica")
    if civ:
        ab["Unique"] = {"civ": civ}
    e["abilities"] = ab
    return e


def derive_trains(units):
    out = {}
    for u in units:
        out.setdefault(building_id(u["trained_at"]), []).append(u)
    for b, lst in out.items():
        lst.sort(key=lambda u: (HOTKEY_ORDER.find(u["hotkey"]) if u.get("hotkey") and u["hotkey"] in HOTKEY_ORDER else 99, u["id"]))
        out[b] = [u["id"] for u in lst]
    return out


def convert_building(b, trains, research, sprites_root=None):
    e = {"id": b["id"], "type": "building", "extends": "edificio_base", "name": b.get("name", b["id"]),
         "cost": b.get("cost", {}), "build_time": b["build_time_sec"], "footprint": b["size_tiles"]}
    age = b.get("requires_age") or BUILDING_AGE.get(b["id"])
    if age:
        e["requires"] = {"age": age}
    if b["id"] in BUILD_MENU:
        e["build_menu"], e["hotkey"] = BUILD_MENU[b["id"]]
    sp = BUILDING_SPRITES.get(b["id"])
    if sp and sprites_root and os.path.isdir(os.path.join(sprites_root, sp)):
        e["graphics"] = {"idle": f"sprite:{sp}"}
    ab = {"Hitpoints": {"max": b["hp"]},
          "Armor": {"classes": {"melee": b.get("armor_melee", 0), "pierce": b.get("armor_pierce", 0)}}}
    if "sight" in b:
        ab["Vision"] = {"sight": b["sight"]}
    if trains:
        ab["Train"] = {"units": list(trains), "queue": TRAIN_QUEUE}
        ab["RallyPoint"] = {}
    if research:
        ab["Research"] = {"techs": list(research)}
    if b["id"] in DROPSITES:
        ab["DropSite"] = {"accepts": list(DROPSITES[b["id"]])}
    if b.get("garrison_max"):
        ab["Garrison"] = {"capacity": b["garrison_max"], "arrows_per_unit": 1}
    if b.get("attack", 0) > 0:
        # Torres y castillos disparan flechas (proyectil visible, puede fallar).
        ab["Attack"] = {"damage": {"pierce": b["attack"]}, "range": b["range"], "reload": DEFAULT_MELEE_RELOAD,
                        "projectile_speed": BUILDING_ARROW_SPEED}
    if "pop_supply" in b:
        ab["ProvidesPop"] = {"amount": b["pop_supply"]}
    if b["id"] == "centro_urbano":
        ab["ProvidesPop"] = {"amount": TC_POP}
        ab["AgeAdvance"] = {}
        ab["Bell"] = {}
    if b["id"] == "granja":
        ab["Farm"] = {"food": FARM_FOOD, "rate_key": "food_farm"}
    if b.get("wonder"):
        ab["Wonder"] = {"victory_time": b.get("victory_time_min", 0) * 60}
    e["abilities"] = ab
    return e


def id_target(ids, known=None, dropped=None):
    """Selector "id:a|id:b" con alias aplicados. Con known, descarta ids
    inexistentes (los anota en dropped); None si no queda ninguno."""
    out = []
    for x in ids:
        x = UNIT_ALIASES.get(x, x)
        if known is not None and x not in known:
            if dropped is not None:
                dropped.append(x)
            continue
        if x not in out:
            out.append(x)
    return "|".join(f"id:{x}" for x in out) or None


def tech_effects(ef, known=None, dropped=None):
    """Efectos del formato viejo -> (efectos portables, legacy sin portar)."""
    if "aplica_a" in ef:
        target = id_target(ef["aplica_a"], known, dropped)
    elif ef.get("categoria") in ("infanteria", "arqueros", "caballeria", "barco"):
        target = f"tag:{ef['categoria']}"
    else:
        target = None
    ranged = ef.get("categoria") in RANGED_CATEGORIES
    paths = {
        "attack": "abilities.Attack.damage." + ("pierce" if ranged else "melee"),
        "armor_melee": "abilities.Armor.classes.melee",
        "armor_pierce": "abilities.Armor.classes.pierce",
        "range": "abilities.Attack.range",
        "hp": "abilities.Hitpoints.max",
        "bonus_vs_edificio": "abilities.Attack.damage.edificio",
    }
    effects, legacy = [], {}
    for k, v in ef.items():
        if k in ("categoria", "aplica_a"):
            continue
        numeric = isinstance(v, (int, float)) and not isinstance(v, bool)
        if k in paths and target and numeric:
            effects.append({"target": target, "op": "add", "path": paths[k], "value": v})
        else:
            legacy[k] = v
    if legacy:
        for k in ("categoria", "aplica_a"):
            if k in ef:
                legacy[k] = ef[k]
    return effects, legacy


def convert_tech(t, building, known=None, dropped=None):
    e = {"id": t["id"], "type": "tech", "name": t.get("nombre", t["id"]), "cost": t.get("coste", {}),
         "research_time": t.get("tiempo_sec", 0), "at": building_id(building)}
    if t.get("descripcion"):
        e["description"] = t["descripcion"]
    req = {}
    if t.get("edad"):
        req["age"] = t["edad"]
    if t.get("requiere"):
        req["techs"] = list(t["requiere"])
    if req:
        e["requires"] = req
    effects, legacy = tech_effects(t.get("efectos", {}), known, dropped)
    e["effects"] = effects
    if legacy:
        e["legacy_effects"] = legacy
    return e


def civ_bonus_effects(ef, known=None, dropped=None):
    """Bonus de civ portables (descuentos, HP). Si queda algo sin mapear -> []."""
    if "aplica_a" not in ef:
        return []
    target = id_target(ef["aplica_a"], known, dropped)
    if target is None:
        return []
    out, handled = [], {"aplica_a"}
    for key, path in (("descuento_madera", "cost.wood"), ("descuento_oro", "cost.gold")):
        if key in ef:
            out.append({"target": target, "op": "mul", "path": path, "value": round(1 - ef[key], 6)})
            handled.add(key)
    if "hp_caballeria_bonus" in ef:
        out.append({"target": target, "op": "mul", "path": "abilities.Hitpoints.max",
                    "value": round(1 + ef["hp_caballeria_bonus"], 6)})
        handled.add("hp_caballeria_bonus")
    if set(ef) - handled:
        return []
    return out


def convert_age(a, index, report):
    e = {"id": a["id"], "type": "age", "name": a.get("name", a["id"]), "index": index,
         "cost": a.get("cost", {}), "research_time": a.get("research_time_sec", 0)}
    for r in a.get("requires", []):
        if r in AGE_PREREQS:
            e["prerequisite_buildings"] = {"any_of": AGE_PREREQS[r], "count": 1}
        else:
            report["warnings"].append(f"edad {a['id']}: requisito '{r}' sin mapear")
    if a["id"] in AGE_BUILDINGS:
        e["prerequisite_buildings"] = dict(AGE_BUILDINGS[a["id"]])
    return e


def convert_resource(r, defaults, sprites_root=None):
    rr = {**defaults, **r}
    rate_key = ANIMALS.get(r["id"], {}).get("rate_key", rr["gather"]["rate_key"])
    src = {"resource": rr["resource"], "amount": rr["amount"], "rate_key": rate_key}
    if rr.get("infinite"):
        src["infinite"] = True
    if r["id"] in HUNTABLE:
        src["requires_kill"] = True
    for flag in ("hostile", "tame", "flees", "water"):
        if rr.get(flag):
            src[flag] = True
    e = {"id": r["id"], "type": "resource", "name": rr.get("name", r["id"]), "tags": ["recurso"]}
    sp = RESOURCE_SPRITES.get(r["id"])
    if sp and sprites_root and os.path.isdir(os.path.join(sprites_root, sp)):
        base = os.path.join(sprites_root, sp)
        subs = sorted(a for a in os.listdir(base) if os.path.isdir(os.path.join(base, a)))
        # Pack con animaciones (animales) o pack único de variantes (árboles, minas).
        e["graphics"] = {a: f"sprite:{sp}/{a}" for a in subs} if subs else {"idle": f"sprite:{sp}"}
    ab = {"ResourceSource": src}
    animal = ANIMALS.get(r["id"])
    if animal:
        ab["Hitpoints"] = {"max": animal["hp"]}
        ab["Move"] = {"speed": animal["speed"]}
        ab["Armor"] = {"classes": dict(animal.get("armor", {"melee": 0, "pierce": 0}))}
        if animal.get("attack"):
            ab["Attack"] = {"damage": {"melee": animal["attack"]}, "range": 0, "reload": DEFAULT_MELEE_RELOAD}
    e["abilities"] = ab
    return e


def bases():
    out = [
        {"id": "unidad_base", "type": "unit", "abstract": True, "tags": ["unidad"], "abilities": {"Selectable": {}}},
        {"id": "edificio_base", "type": "building", "abstract": True, "tags": ["edificio"], "abilities": {"Selectable": {}}},
    ]
    for cat in sorted(set(CATEGORY_BY_BUILDING.values()) | set(CATEGORY_BY_ARMOR_CLASS.values())):
        b = {"id": f"{cat}_base", "type": "unit", "abstract": True, "extends": "unidad_base", "tags": [cat], "abilities": {}}
        if cat in GARRISONABLE:
            b["abilities"]["Garrisonable"] = {}
        out.append(b)
    return out


def migrate(src, out, sprites_root):
    report = {"dropped_train_refs": {}, "dropped_effect_targets": {}, "legacy_effects": {},
              "unported_fields": {}, "warnings": []}
    actions = load(os.path.join(src, "actions.json"))["actions"]
    # Caza y pastoreo (AoE2): tasas propias; así un recolector de bayas no
    # se va a cazar al agotarse el arbusto (y viceversa).
    rates = {**actions["gather"]["rates_per_sec"], **ANIMAL_RATES}
    carry = actions["gather"]["carry_capacity"]
    units = [load(p) for p in sorted(glob.glob(os.path.join(src, "units", "*.json")))]
    buildings = [load(p) for p in sorted(glob.glob(os.path.join(src, "buildings", "*.json")))]
    factions = [load(p) for p in sorted(glob.glob(os.path.join(src, "factions", "*.json")))]
    tech_files = [load(p) for p in sorted(glob.glob(os.path.join(src, "techs", "*.json")))]
    unit_ids = {u["id"] for u in units}
    building_ids = {b["id"] for b in buildings}
    targetable = unit_ids | building_ids

    def note_dropped(eid, dropped):
        if dropped:
            report["dropped_effect_targets"].setdefault(eid, [])
            for x in dropped:
                if x not in report["dropped_effect_targets"][eid]:
                    report["dropped_effect_targets"][eid].append(x)

    for sub in ENTITY_DIRS + ["maps"]:
        shutil.rmtree(os.path.join(out, sub), ignore_errors=True)
    write(os.path.join(out, "mod.json"), {"id": "aoe2_base", "version": "0.3.0", "depends": [], "priority": 0})
    for b in bases():
        write(os.path.join(out, "base", b["id"] + ".json"), b)

    # Unidades
    for u in units:
        extra = sorted(set(u) - UNIT_FIELDS_USED)
        if extra:
            report["unported_fields"][u["id"]] = extra
        if building_id(u.get("trained_at", "")) not in building_ids:
            report["warnings"].append(f"unidad {u['id']}: trained_at '{u.get('trained_at')}' no existe")
        write(os.path.join(out, "units", u["id"] + ".json"), convert_unit(u, rates, carry, actions, sprites_root))

    # Tecnologías (archivos de edificio + únicas de civ); la primera definición gana
    techs, research, unique_techs_by_civ = {}, {}, {}

    def add_tech(t, building, civ=None):
        if t["id"] in techs:
            report["warnings"].append(f"tech {t['id']} duplicada: se conserva la primera")
            return
        dropped = []
        e = convert_tech(t, building, targetable, dropped)
        note_dropped(t["id"], dropped)
        techs[t["id"]] = e
        research.setdefault(e["at"], []).append(t["id"])
        if civ:
            unique_techs_by_civ.setdefault(civ, []).append(t["id"])
        if "legacy_effects" in e:
            report["legacy_effects"][t["id"]] = e["legacy_effects"]

    for tf in tech_files:
        for t in tf["techs"]:
            add_tech(t, tf["building"], tf.get("civ"))
    for f in factions:
        for t in f.get("unique_techs", []):
            add_tech(t, t.get("edificio", "castillo"), f["id"])
    for tid, e in techs.items():
        if e["at"] not in building_ids:
            report["warnings"].append(f"tech {tid}: edificio '{e['at']}' no existe")
        write(os.path.join(out, "techs", tid + ".json"), e)

    # Edificios (Train se deriva de trained_at de las unidades)
    trains = derive_trains(units)
    for b in buildings:
        dropped = [x for x in b.get("trains", []) if x not in trains.get(b["id"], [])]
        if dropped:
            report["dropped_train_refs"][b["id"]] = dropped
        e = convert_building(b, trains.get(b["id"], []), research.get(b["id"], []), sprites_root)
        write(os.path.join(out, "buildings", b["id"] + ".json"), e)

    # Recursos
    rd = load(os.path.join(src, "maps", "resource_defs.json"))
    for r in rd["resources"]:
        write(os.path.join(out, "resources", r["id"] + ".json"), convert_resource(r, rd.get("defaults", {}), sprites_root))

    # Edades
    for i, a in enumerate(load(os.path.join(src, "ages", "ages.json"))["ages"]):
        write(os.path.join(out, "ages", a["id"] + ".json"), convert_age(a, i, report))

    # Civilizaciones
    unique_units_by_civ = {}
    for u in units:
        civ = u.get("unique_to") or u.get("civ_unica")
        if civ:
            unique_units_by_civ.setdefault(civ, set()).add(u["id"])
    for f in factions:
        uu = f.get("unique_unit", {}).get("id")
        if uu in unit_ids:
            unique_units_by_civ.setdefault(f["id"], set()).add(uu)
        elif uu:
            report["warnings"].append(f"civ {f['id']}: unidad única '{uu}' no existe")
    known = unit_ids | set(techs)
    for f in factions:
        cid = f["id"]
        effects, legacy = [], []
        for bonus in f.get("bonus", []):
            dropped = []
            mapped = civ_bonus_effects(bonus.get("efecto", {}), targetable, dropped)
            note_dropped(cid, dropped)
            if mapped:
                effects.extend(mapped)
            else:
                legacy.append(bonus)
        if f.get("team_bonus"):
            legacy.append({"team_bonus": f["team_bonus"]})
        disabled = set()
        for other, ids in unique_units_by_civ.items():
            if other != cid:
                disabled |= ids
        for other, ids in unique_techs_by_civ.items():
            if other != cid:
                disabled |= set(ids)
        for _building, entries in f.get("tech_tree", {}).items():
            if isinstance(entries, dict):
                for x, ok in entries.items():
                    if ok is False and x in known:
                        disabled.add(x)
        e = {"id": cid, "type": "civ", "name": f.get("name", cid), "color": f.get("roof_color", "#ffffff"),
             "effects": effects, "disabled": sorted(disabled),
             "unique_units": sorted(unique_units_by_civ.get(cid, set())),
             "unique_techs": sorted(unique_techs_by_civ.get(cid, []))}
        if legacy:
            e["legacy_effects"] = legacy
            report["legacy_effects"][cid] = [b.get("id", "team_bonus") for b in legacy]
        write(os.path.join(out, "civs", cid + ".json"), e)

    # Mapas (los usa el cargador de mapas de F1; el Registry no los lee)
    os.makedirs(os.path.join(out, "maps"), exist_ok=True)
    shutil.copy(os.path.join(src, "maps", "arabia.json"), os.path.join(out, "maps", "arabia.json"))

    write(os.path.join(out, "_migration_report.json"), report)
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default="data")
    ap.add_argument("--out", default=os.path.join("mods", "aoe2_base"))
    ap.add_argument("--sprites", default=os.path.join("assets", "sprites"))
    args = ap.parse_args()
    report = migrate(args.src, args.out, args.sprites)
    print(f"[migrate] OK -> {args.out}")
    print(f"[migrate] refs de Train descartadas: {sum(len(v) for v in report['dropped_train_refs'].values())}")
    print(f"[migrate] entidades con efectos sin portar: {len(report['legacy_effects'])}")
    print(f"[migrate] avisos: {len(report['warnings'])}")


if __name__ == "__main__":
    main()
