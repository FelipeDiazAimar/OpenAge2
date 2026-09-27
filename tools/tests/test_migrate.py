import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import migrate_data_to_mod as M  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ACTIONS = {
    "repair": {"rate_hp_per_sec": 15.0, "cost_factor": 0.5},
    "convert": {"range": 8.0, "cooldown_sec": 12, "chance_base": 0.35},
    "heal": {"rate_hp_per_sec": 2.5, "range": 4.0},
    "trade": {"gold_per_trip_base": 20, "bonus_per_tile": 0.3},
}
RATES = {"wood": 0.39, "food_forage": 0.41, "food_farm": 0.32, "food_fish": 0.43, "gold": 0.38, "stone": 0.36}


class TestUnits(unittest.TestCase):
    def test_category(self):
        self.assertEqual(M.unit_category({"trained_at": "cuartel"}), "infanteria")
        self.assertEqual(M.unit_category({"trained_at": "caballeriza"}), "caballeria")
        self.assertEqual(M.unit_category({"trained_at": "castillo", "armor_class": "arquero"}), "arqueros")
        self.assertEqual(M.unit_category({"trained_at": "castillo"}), "infanteria")

    def test_ranged_unit(self):
        u = {"id": "arquero", "name": "Arquero", "hp": 30, "attack": 4, "armor_melee": 0, "armor_pierce": 0,
             "range": 5.0, "sight": 6.0, "speed": 0.96, "cost": {"wood": 25, "gold": 45}, "train_time_sec": 27,
             "pop_cost": 1, "trained_at": "arqueria", "hotkey": "Q", "projectile_speed": 12.0, "fire_cooldown_sec": 2.0}
        e = M.convert_unit(u, RATES, 10, ACTIONS)
        self.assertEqual(e["extends"], "arqueros_base")
        self.assertEqual(e["abilities"]["Attack"],
                         {"damage": {"pierce": 4}, "range": 5.0, "reload": 2.0, "projectile_speed": 12.0})
        self.assertEqual(e["train_time"], 27)
        self.assertNotIn("graphics", e)

    def test_melee_unit_bonus_and_upgrade(self):
        u = {"id": "milicia", "hp": 45, "attack": 4, "armor_melee": 0, "armor_pierce": 1, "range": 1.2,
             "sight": 4.0, "speed": 0.9, "cost": {"food": 60, "gold": 20}, "train_time_sec": 21, "pop_cost": 1,
             "trained_at": "cuartel", "bonus_vs": {"edificio": 2}, "upgrade_to": None}
        e = M.convert_unit(u, RATES, 10, ACTIONS)
        self.assertEqual(e["abilities"]["Attack"], {"damage": {"melee": 4, "edificio": 2}, "range": 0, "reload": 2.0})
        self.assertNotIn("upgrades_to", e)

    def test_villager(self):
        u = {"id": "aldeano", "hp": 25, "attack": 3, "range": 1.0, "sight": 4.0, "speed": 0.8,
             "cost": {"food": 50}, "train_time_sec": 20, "pop_cost": 1, "trained_at": "centro_urbano", "gather_carry": 10}
        ab = M.convert_unit(u, RATES, 10, ACTIONS)["abilities"]
        self.assertEqual(ab["Gather"], {"rates": RATES, "capacity": 10})
        self.assertEqual(ab["Build"], {"rate": 1.0})
        self.assertEqual(ab["Repair"], {"rate": 15.0, "cost_factor": 0.5})

    def test_derive_trains_alias_and_hotkey_order(self):
        units = [{"id": "scout", "trained_at": "caballeriza", "hotkey": "Q"},
                 {"id": "paladin", "trained_at": "caballeriza", "hotkey": "E"},
                 {"id": "jinete", "trained_at": "caballeriza", "hotkey": "W"}]
        self.assertEqual(M.derive_trains(units), {"establo": ["scout", "jinete", "paladin"]})


class TestEffects(unittest.TestCase):
    def test_blacksmith(self):
        eff, legacy = M.tech_effects({"categoria": "infanteria", "attack": 1})
        self.assertEqual(eff, [{"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}])
        self.assertEqual(legacy, {})
        eff, _ = M.tech_effects({"categoria": "arqueros", "attack": 1, "range": 1})
        self.assertEqual([e["path"] for e in eff], ["abilities.Attack.damage.pierce", "abilities.Attack.range"])

    def test_unknown_goes_to_legacy(self):
        eff, legacy = M.tech_effects({"teocracia": True})
        self.assertEqual(eff, [])
        self.assertEqual(legacy, {"teocracia": True})

    def test_civ_discount(self):
        eff = M.civ_bonus_effects({"descuento_madera": 0.1, "descuento_oro": 0.1, "aplica_a": ["arquero", "ballestero"]})
        self.assertEqual(eff, [
            {"target": "id:arquero|id:ballestero", "op": "mul", "path": "cost.wood", "value": 0.9},
            {"target": "id:arquero|id:ballestero", "op": "mul", "path": "cost.gold", "value": 0.9}])

    def test_effect_targets_aliased_and_filtered(self):
        known = {"hombre_armas", "jinete"}
        dropped = []
        eff, legacy = M.tech_effects({"aplica_a": ["hombre_de_armas", "piquero"], "attack": 1}, known, dropped)
        self.assertEqual(eff, [{"target": "id:hombre_armas", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}])
        self.assertEqual(legacy, {})
        self.assertEqual(dropped, ["piquero"])
        dropped = []
        eff, legacy = M.tech_effects({"aplica_a": ["alabardero"], "hp": 5}, known, dropped)
        self.assertEqual(eff, [])
        self.assertEqual(legacy, {"hp": 5, "aplica_a": ["alabardero"]})
        dropped = []
        eff = M.civ_bonus_effects({"hp_caballeria_bonus": 0.2, "aplica_a": ["jinete", "husar"]}, known, dropped)
        self.assertEqual(eff, [{"target": "id:jinete", "op": "mul", "path": "abilities.Hitpoints.max", "value": 1.2}])
        self.assertEqual(dropped, ["husar"])

    def test_civ_partial_bonus_not_mapped(self):
        self.assertEqual(M.civ_bonus_effects({"descuento_madera": 0.1, "raro": 1, "aplica_a": ["x"]}), [])


class TestFiles(unittest.TestCase):
    def test_write_keeps_utf8(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x", "torre.json")
            M.write(p, {"name": "Torre Vigía"})
            with open(p, "rb") as f:
                raw = f.read()
            self.assertIn("Vigía".encode("utf-8"), raw)
            with open(p, encoding="utf-8") as f:
                self.assertEqual(json.load(f)["name"], "Torre Vigía")

    def test_villager_task_graphics_per_resource(self):
        with tempfile.TemporaryDirectory() as d:
            for anim in ("idle", "walk", "task", "lumber", "miner_gold"):
                os.makedirs(os.path.join(d, "villager", anim))
            g = M.graphics_for_unit("aldeano", d)
            self.assertEqual(g["task_wood"], "sprite:villager/lumber")
            self.assertEqual(g["task_gold"], "sprite:villager/miner_gold")
            self.assertEqual(g["task_stone"], "sprite:villager/miner_gold", "piedra usa el minero si no hay pack propio")
            self.assertNotIn("task_food_forage", g, "sin pack forager no se inventa")
            self.assertEqual(g["walk"], "sprite:villager/walk")

    def test_resource_graphics(self):
        rd = {"id": "tree", "resource": "wood", "amount": 100, "gather": {"rate_key": "wood"}}
        self.assertNotIn("graphics", M.convert_resource(rd, {}))
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "nature", "oak"))
            self.assertEqual(M.convert_resource(rd, {}, d)["graphics"], {"idle": "sprite:nature/oak"})

    def test_migrate_real_data(self):
        with tempfile.TemporaryDirectory() as d:
            report = M.migrate(os.path.join(ROOT, "data"), d, os.path.join(ROOT, "assets", "sprites"))

            def count(sub):
                return len([f for f in os.listdir(os.path.join(d, sub)) if f.endswith(".json")])

            self.assertEqual(count("units"), 25)
            self.assertEqual(count("buildings"), 20)
            self.assertEqual(count("resources"), 8)
            self.assertEqual(count("ages"), 4)
            self.assertEqual(count("civs"), 5)
            self.assertTrue(os.path.exists(os.path.join(d, "mod.json")))
            self.assertTrue(os.path.exists(os.path.join(d, "maps", "arabia.json")))
            with open(os.path.join(d, "buildings", "establo.json"), encoding="utf-8") as f:
                establo = json.load(f)
            self.assertIn("scout", establo["abilities"]["Train"]["units"])
            with open(os.path.join(d, "buildings", "castillo.json"), encoding="utf-8") as f:
                castillo = json.load(f)
            self.assertIn("trebuchet", castillo["abilities"]["Train"]["units"])
            self.assertIn("dropped_train_refs", report)


if __name__ == "__main__":
    unittest.main()
