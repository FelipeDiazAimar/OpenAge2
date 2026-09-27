#!/usr/bin/env python3
"""
tools/convert_aoe2.py - GRATIS, solo usa stdlib.
Convierte mapas AoE2 (si el usuario YA tiene el juego) a nuestro formato .oamap.json
Uso:
  python tools/convert_aoe2.py --aoe2-path "C:/Program Files/AoE2" --out assets/imported/
Si no tienes AoE2, el juego usa data/maps/arabia.json propio. No necesitas comprar nada.
"""
import argparse, json, os, struct, sys
from pathlib import Path

def parse_rms_stub(path: Path):
    # Parser mínimo: RMS son scripts de texto. Extraemos recursos aproximados.
    text = path.read_text(errors="ignore")
    return {"source": path.name, "hint_resources": text.count("gold") + text.count("wood")}

def convert_folder(aoe2_path: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    found = 0
    for ext in ("*.scx", "*.scn", "*.rms"):
        for f in aoe2_path.rglob(ext):
            found += 1
            data = {
                "name": f.stem,
                "imported_from": f.name,
                "size_tiles": [144, 144],
                "note": "Convertido a formato OpenAge-LAN. Terreno aproximado, balancear a mano.",
            }
            if f.suffix == ".rms":
                try:
                    data.update(parse_rms_stub(f))
                except Exception as e:
                    data["parse_error"] = str(e)
            (out / (f.stem + ".oamap.json")).write_text(json.dumps(data, indent=2, ensure_ascii=False))
    print(f"Convertidos {found} mapas a {out}")
    if found == 0:
        print("No se encontraron .scx/.rms. Revisa --aoe2-path o usa mapas propios de data/maps/.")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--aoe2-path", required=True)
    ap.add_argument("--out", default="assets/imported/")
    a = ap.parse_args()
    convert_folder(Path(a.aoe2_path), Path(a.out))
