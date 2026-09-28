#!/usr/bin/env python3
"""
extract_aoe2_sprites.py - Convierte sprites de Age of Empires 2: DE (.sld) a PNG.

Formato SLD documentado por el proyecto openage (doc/media/sld-files.md):
  Header: "SLDX", version u16, num_frames u16.
  Frame: canvas w/h u16, hotspot x/y i16, frame_type u8 (bits: main=0x01,
    shadow=0x02, ???=0x04, playercolor=0x08, damage=0x10), ...
  Capas con content_length u32 (incluye esos 4 bytes, padded a múltiplo de 4).
  Main/shadow: header gfx (offsets x1,y1,x2,y2 + 2 flags), command array
    [(skip,draw)...], bloques DXT1 (main/damage) o DXT4 (shadow/playercolor).
  Damage/???: se saltan por content_length. Damage no se usa en display.

Salida por archivo .sld:
  <out>/<base>/frame_%03d.png        (sprite RGBA sobre canvas)
  <out>/<base>/frame_%03d.mask.png   (máscara player-color: blanco+alpha)
  <out>/<base>/frame_%03d.shadow.png (sombra en escala de grises+alpha)
  <out>/<base>/manifest.json         (frames, canvas, hotspot, anim info)

Uso:
  py tools/extract_aoe2_sprites.py --src "C:/XboxGames/.../drs/graphics" --out assets/sprites --files u_vil_male_farmer_walkA_x1
  py tools/extract_aoe2_sprites.py --src ... --out ... --list "u_vil_male*"
  py tools/extract_aoe2_sprites.py --src ... --out ... --files u_inf_militia_idleA_x1 u_inf_militia_walkA_x1 --angles 8

Solo stdlib (struct/zlib/json/os/argparse). Los assets son de tu copia
comprada del juego: úsalos solo para ti, no los redistribuyas.
"""
import argparse
import json
import os
import struct
import sys
import zlib

MAGIC = b"SLDX"
HDR = struct.Struct("<4s4HI")      # magic, ver, nframes, u1, u2, u3
FHDR = struct.Struct("<4H2BH")     # cw, ch, cx, cy, ftype, unk, idx
GFXHDR = struct.Struct("<4H2B")    # ox1, oy1, ox2, oy2, flag1, unk
U32 = struct.Struct("<I")
U16 = struct.Struct("<H")
BC1 = struct.Struct("<2H I")
BC4 = struct.Struct("<8B")

F_MAIN, F_SHADOW, F_UNK, F_PLAYER, F_DAMAGE = 0x01, 0x02, 0x04, 0x08, 0x10
REUSE_MASK = 0x80  # flag1: reutiliza bloques del frame anterior


def _r5(v):
    return (v * 255 + 15) // 31


def _g6(v):
    return (v * 255 + 31) // 63


def decode_dxt1(block):
    """8 bytes -> lista de 16 tuplas RGBA (izq->der, arriba->abajo)."""
    c0, c1, idx = BC1.unpack(block[:8])

    def split(c):
        return ((c & 0xF800) >> 11, (c & 0x07E0) >> 5, c & 0x001F)

    r0, g0, b0 = split(c0)
    r1, g1, b1 = split(c1)
    R0, G0, B0 = _r5(r0), _g6(g0), _r5(b0)
    R1, G1, B1 = _r5(r1), _g6(g1), _r5(b1)
    if c0 > c1:
        lut = [(R0, G0, B0, 255), (R1, G1, B1, 255),
               ((2 * R0 + R1) // 3, (2 * G0 + G1) // 3, (2 * B0 + B1) // 3, 255),
               ((R0 + 2 * R1) // 3, (G0 + 2 * G1) // 3, (B0 + 2 * B1) // 3, 255)]
    else:
        lut = [(R0, G0, B0, 255), (R1, G1, B1, 255),
               ((R0 + R1) // 2, (G0 + G1) // 2, (B0 + B1) // 2, 255),
               (0, 0, 0, 0)]
    return [lut[(idx >> (2 * i)) & 3] for i in range(16)]


def decode_dxt4(block):
    """8 bytes -> lista de 16 grises 0..255."""
    c0 = block[0]
    c1 = block[1]
    bits = int.from_bytes(block[2:8], "little")
    if c0 > c1:
        lut = [c0, c1] + [( (6 - k) * c0 + (1 + k) * c1 + 3) // 7 for k in range(6)]
    else:
        lut = [c0, c1] + [( (4 - k) * c0 + (1 + k) * c1 + 2) // 5 for k in range(4)] + [0, 255]
    return [lut[(bits >> (3 * i)) & 7] for i in range(16)]


def draw_blocks(w, h, cmds, raw_blocks, decode, prev_img):
    """Compone una capa w*h. raw_blocks: bytes de bloques de 8. Devuelve lista RGBA o grises."""
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    is_rgba = decode is decode_dxt1
    img = [(0, 0, 0, 0)] * (w * h) if is_rgba else [0] * (w * h)
    pos = 0
    bi = 0
    for skip, draw in cmds:
        if prev_img is not None:
            for _ in range(skip):
                x, y = pos % bw, pos // bw
                _copy_block(img, prev_img, w, h, x, y)
                pos += 1
        else:
            pos += skip
        for _ in range(draw):
            x, y = pos % bw, pos // bw
            px = decode(raw_blocks[bi * 8:bi * 8 + 8])
            _put_block(img, px, w, h, x, y)
            pos += 1
            bi += 1
    return img


def _put_block(img, px, w, h, bx, by):
    for j in range(4):
        for i in range(4):
            x, y = bx * 4 + i, by * 4 + j
            if x < w and y < h:
                img[y * w + x] = px[j * 4 + i]


def _copy_block(img, prev, w, h, bx, by):
    for j in range(4):
        for i in range(4):
            x, y = bx * 4 + i, by * 4 + j
            if x < w and y < h:
                img[y * w + x] = prev[y * w + x]


def write_png(path, w, h, rgba):
    """PNG RGBA8 mínimo con zlib (sin dependencias). rgba: lista de (r,g,b,a)."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(rgba[y * w + x])

    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


def read_png(path):
    """Lee un PNG RGBA8 con filter 0 (los que escribe write_png). Devuelve (w,h,rgba)."""
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "firma PNG mala en %s" % path
    w, h = struct.unpack(">II", d[16:24])
    assert d[24:27] == bytes([8, 6, 0]), "solo RGBA8 filter0 en %s" % path
    pos = 8
    raw = b""
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        if d[pos + 4:pos + 8] == b"IDAT":
            raw += d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    px = zlib.decompress(raw)
    ch = w * 4 + 1
    rgba = []
    for y in range(h):
        assert px[y * ch] == 0, "filter no soportado en %s" % path
        row = px[y * ch + 1:(y + 1) * ch]
        rgba.extend((row[i], row[i + 1], row[i + 2], row[i + 3]) for i in range(0, len(row), 4))
    return w, h, rgba


def detect_dirs(n):
    """(dirs, per_dir, drop_last) desde el nº de frames. DE usa 16 slots x N + 1 extra."""
    if n > 16 and (n - 1) % 16 == 0:
        return 16, (n - 1) // 16, True
    for cand in (16, 8, 5, 4):
        if n % cand == 0:
            return cand, n // cand, False
    return 1, n, False


def _png_raw(path):
    """IDAT descomprimido de un PNG RGBA8 filter0. Devuelve (w,h,bytes)."""
    d = open(path, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("firma PNG mala en %s" % path)
    w, h = struct.unpack(">II", d[16:24])
    if d[24:27] != bytes([8, 6, 0]):
        raise ValueError("solo RGBA8 filter0 en %s" % path)
    pos = 8
    raw = b""
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        if d[pos + 4:pos + 8] == b"IDAT":
            raw += d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    return w, h, zlib.decompress(raw)


def _bbox_raw(w, h, raw, thr=10):
    """bbox de píxeles con alfa>thr. Devuelve (x0,y0,x1,y1) o None si vacío."""
    ch = w * 4 + 1
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        base = y * ch + 1
        for x in range(w):
            if raw[base + x * 4 + 3] > thr:
                if x < x0:
                    x0 = x
                if y < y0:
                    y0 = y
                if x > x1:
                    x1 = x
                if y > y1:
                    y1 = y
    return None if x1 < x0 else (x0, y0, x1, y1)


def _crop_raw(w, h, raw, x0, y0, cw, ch):
    """Recorte a lista de tuplas RGBA (solo para frames conservados, pequeños)."""
    s = w * 4 + 1
    out = []
    for y in range(ch):
        base = (y0 + y) * s + 1 + x0 * 4
        row = raw[base:base + cw * 4]
        out.extend((row[i], row[i + 1], row[i + 2], row[i + 3]) for i in range(0, len(row), 4))
    return out


def pack_anim(folder, step=2, margin=2):
    """Recorta al bbox común + submuestrea. Reescribe PNGs y manifest.pack.json.
    Streaming: 2 pasadas sin cachear frames (los .sld grandes mataban la RAM).
    Devuelve el manifest pack."""
    man = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))
    frames = man["frames"]
    n = len(frames)
    dirs, per_dir, drop = detect_dirs(n)
    if drop:
        frames = frames[:-1]
    # Pasada 1: bbox común del canal alfa (bytes crudos, sin tuplas).
    x0, y0, x1, y1 = 10 ** 9, 10 ** 9, -1, -1
    fw = fh = 0
    for e in frames:
        w, h, raw = _png_raw(os.path.join(folder, e["png"]))
        fw, fh = w, h
        bb = _bbox_raw(w, h, raw)
        if bb is None:
            continue
        bx0, by0, bx1, by1 = bb
        x0 = min(x0, bx0)
        y0 = min(y0, by0)
        x1 = max(x1, bx1)
        y1 = max(y1, by1)
    if x1 < x0:
        raise ValueError("animación vacía en %s" % folder)
    x0 = max(0, x0 - margin)
    y0 = max(0, y0 - margin)
    x1 = min(fw - 1, x1 + margin)
    y1 = min(fh - 1, y1 + margin)
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    # submuestreo por dirección (mantiene fluidez reduciendo VRAM)
    keep = []
    for d in range(dirs):
        seg = frames[d * per_dir:(d + 1) * per_dir]
        keep.extend(seg[::step])
    out_frames = []
    # Pasada 2: solo los conservados.
    for e in keep:
        idx = frames.index(e)
        w, h, raw = _png_raw(os.path.join(folder, e["png"]))
        cut = _crop_raw(w, h, raw, x0, y0, cw, ch)
        name = "p_%03d.png" % len(out_frames)
        write_png(os.path.join(folder, name), cw, ch, cut)
        # Máscara player-color recortada con el MISMO bbox (misma geometría y hotspot).
        mask_out = None
        mask_name = e.get("mask", "")
        if mask_name:
            mpath = os.path.join(folder, mask_name)
            if os.path.exists(mpath):
                mw, mh, mraw = _png_raw(mpath)
                if mw == w and mh == h:
                    mcut = _crop_raw(mw, mh, mraw, x0, y0, cw, ch)
                    if any(px[3] != 0 for px in mcut):
                        mask_out = "m_%03d.png" % len(out_frames)
                        write_png(os.path.join(folder, mask_out), cw, ch, mcut)
        # hotspot ajustado al recorte
        hx, hy = e["hotspot"]
        out_frames.append({"png": name, "mask": mask_out, "dir": idx // per_dir,
                           "sub": (idx % per_dir) // step,
                           "hotspot": [hx - x0, hy - y0]})
    # borra los frame_*.png originales (incluye mask/shadow; el pack deja p_/m_*)
    import glob as _glob
    for p in _glob.glob(os.path.join(folder, "frame_*.png")):
        os.remove(p)
    pack = {"source": man["file"], "dirs": dirs, "per_dir": per_dir,
            "kept_per_dir": (per_dir + step - 1) // step, "step": step,
            "size": [cw, ch], "frames": out_frames}
    json.dump(pack, open(os.path.join(folder, "manifest.pack.json"), "w", encoding="utf-8"), indent=1)
    return pack


def pad4(n):
    return n + ((4 - n) % 4)


class Reader:
    def __init__(self, data):
        self.d = data
        self.o = 0

    def take(self, n):
        b = self.d[self.o:self.o + n]
        if len(b) != n:
            raise ValueError("SLD truncado en offset %d (pedía %d)" % (self.o, n))
        self.o += n
        return b

    def u16(self):
        return U16.unpack(self.take(2))[0]

    def u32(self):
        return U32.unpack(self.take(4))[0]


def parse_gfx_layer(r, want):
    """Lee header gfx + command array. Devuelve (w,h,ox1,oy1,flag,cmds,block_start)."""
    ox1, oy1, ox2, oy2, flag, _ = GFXHDR.unpack(r.take(10))
    w, h = ox2 - ox1, oy2 - oy1
    if w <= 0 or h <= 0 or w > 4096 or h > 4096:
        raise ValueError("dimensiones de capa inválidas %dx%d" % (w, h))
    ncmd = r.u16()
    cmds = [(r.d[r.o + 2 * i], r.d[r.o + 2 * i + 1]) for i in range(ncmd)]
    r.o += 2 * ncmd
    return w, h, ox1, oy1, flag, cmds, r.o


def convert_file(path, outdir, verbose=True, max_frames=0):
    with open(path, "rb") as f:
        data = f.read()
    r = Reader(data)
    magic, ver, nframes, _, header_size, _ = HDR.unpack(r.take(16))
    if magic != MAGIC:
        raise ValueError("%s: firma inválida %r" % (path, magic))
    # header_size (u2) = offset del primer frame: 16 normal, 14 en archivos
    # 0x0e (openage sld.pyx: current_offset = header_size).
    r.o = header_size
    base = os.path.splitext(os.path.basename(path))[0]
    dest = os.path.join(outdir, base)
    os.makedirs(dest, exist_ok=True)
    manifest = {"file": base, "version": ver, "frames": []}
    prev_main = None
    for fi in range(nframes):
        cw, ch, cx, cy, ftype, _, fidx = FHDR.unpack(r.take(12))
        if cw == 0 or ch == 0 or cw > 4096 or ch > 4096:
            raise ValueError("%s frame %d: canvas inválido %dx%d" % (base, fi, cw, ch))
        canvas = [(0, 0, 0, 0)] * (cw * ch)
        mask = [0] * (cw * ch)
        shadow = [0] * (cw * ch)
        main_geom = None  # (w, h, ox1, oy1) de la capa main de ESTE frame
        entry = {"index": fi, "frame_index": fidx, "w": cw, "h": ch,
                 "hotspot": [cx, cy], "layers": []}
        for bit, name in ((F_MAIN, "main"), (F_SHADOW, "shadow"), (F_UNK, "unk"),
                          (F_DAMAGE, "dmg"), (F_PLAYER, "player")):
            if not (ftype & bit):
                continue
            layer_start = r.o
            clen = r.u32()
            if name in ("main", "shadow"):
                w, h, ox1, oy1, flag, cmds, bstart = parse_gfx_layer(r, name)
                nblocks = sum(d for _, d in cmds)
                raw = data[bstart:bstart + nblocks * 8]
                if len(raw) != nblocks * 8:
                    raise ValueError("%s f%d %s: faltan bloques (%d/%d)" % (base, fi, name, len(raw), nblocks * 8))
                if name == "main":
                    prev = prev_main if (bool(flag & REUSE_MASK) and prev_main is not None and len(prev_main) == w * h) else None
                    img = draw_blocks(w, h, cmds, raw, decode_dxt1, prev)
                    _paste(canvas, cw, img, w, h, ox1, oy1)
                    prev_main = list(img)
                    main_geom = (w, h, ox1, oy1)
                    entry["layers"].append("main")
                else:
                    img = draw_blocks(w, h, cmds, raw, decode_dxt4, None)
                    _paste_gray(shadow, cw, img, w, h, ox1, oy1)
                    entry["layers"].append("shadow")
                r.o = bstart + nblocks * 8
            elif name == "player":
                r.take(2)  # mask header
                ncmd = r.u16()
                cmds = [(r.d[r.o + 2 * i], r.d[r.o + 2 * i + 1]) for i in range(ncmd)]
                r.o += 2 * ncmd
                nblocks = sum(d for _, d in cmds)
                raw = data[r.o:r.o + nblocks * 8]
                if len(raw) != nblocks * 8:
                    raise ValueError("%s f%d player: faltan bloques" % (base, fi))
                # La máscara cubre lo mismo que main (misma geometría).
                mw, mh, mox, moy = main_geom if main_geom is not None else (cw, ch, 0, 0)
                img = draw_blocks(mw, mh, cmds, raw, decode_dxt4, None)
                _paste_gray(mask, cw, img, mw, mh, mox, moy)
                r.o += nblocks * 8
                entry["layers"].append("player")
            # dmg y unk se saltan por content_length
            r.o = layer_start + pad4(clen)
        # Escribe PNGs
        fp = os.path.join(dest, "frame_%03d.png" % fi)
        write_png(fp, cw, ch, canvas)
        mp = os.path.join(dest, "frame_%03d.mask.png" % fi)
        write_png(mp, cw, ch, [(255, 255, 255, v) for v in mask])
        sp = os.path.join(dest, "frame_%03d.shadow.png" % fi)
        write_png(sp, cw, ch, [(0, 0, 0, v) for v in shadow])
        entry.update({"png": os.path.basename(fp), "mask": os.path.basename(mp), "shadow": os.path.basename(sp)})
        manifest["frames"].append(entry)
        if verbose and (fi % 50 == 0 or fi == nframes - 1):
            print("  frame %d/%d" % (fi + 1, nframes), flush=True)
        if max_frames and fi + 1 >= max_frames:
            manifest["truncated"] = True
            break
    with open(os.path.join(dest, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    return manifest


def _blocks_bbox(w, h, cmds):
    """bbox en píxeles de los bloques dibujados (sin decodificar)."""
    bw = (w + 3) // 4
    pos = 0
    x0, y0, x1, y1 = 10 ** 9, 10 ** 9, -1, -1
    for skip, draw in cmds:
        pos += skip
        for _ in range(draw):
            bx, by = pos % bw, pos // bw
            x0 = min(x0, bx * 4)
            y0 = min(y0, by * 4)
            x1 = max(x1, min(w - 1, bx * 4 + 3))
            y1 = max(y1, min(h - 1, by * 4 + 3))
            pos += 1
    return None if x1 < x0 else (x0, y0, x1, y1)


def convert_packed(path, outdir, step=2, margin=2, max_frames=0, verbose=True):
    """Vía rápida con --pack: sin PNG intermedios (el antivirus los escaneaba
    uno a uno y parecía colgado). Pasada 1: bbox por comandos; pasada 2: solo
    los frames conservados. Escribe p_*.png (+m_*.png) y manifest.pack.json."""
    import time
    t0 = time.time()
    with open(path, "rb") as f:
        data = f.read()
    r = Reader(data)
    magic, ver, nframes, _, header_size, _ = HDR.unpack(r.take(16))
    if magic != MAGIC:
        raise ValueError("%s: firma inválida %r" % (path, magic))
    # header_size (u2) = offset del primer frame: 16 normal, 14 en archivos
    # 0x0e (openage sld.pyx: current_offset = header_size).
    r.o = header_size
    base = os.path.splitext(os.path.basename(path))[0]
    dest = os.path.join(outdir, base)
    os.makedirs(dest, exist_ok=True)
    metas = []  # por frame: dict ligero con cmds y bloques (bytes)
    gx0, gy0, gx1, gy1 = 10 ** 9, 10 ** 9, -1, -1
    prev_bbox = None
    prev_geom = None
    count = nframes if not max_frames else min(nframes, max_frames)
    for fi in range(count):
        cw, ch, cx, cy, ftype, _, fidx = FHDR.unpack(r.take(12))
        if cw == 0 or ch == 0 or cw > 4096 or ch > 4096:
            raise ValueError("%s frame %d: canvas inválido" % (base, fi))
        meta = {"cw": cw, "ch": ch, "cx": cx, "cy": cy, "fidx": fidx,
                "main": None, "mask": None, "bbox": None}
        for bit, name in ((F_MAIN, "main"), (F_SHADOW, "shadow"), (F_UNK, "unk"),
                          (F_DAMAGE, "dmg"), (F_PLAYER, "player")):
            if not (ftype & bit):
                continue
            layer_start = r.o
            clen = r.u32()
            if name in ("main", "shadow"):
                w, h, ox1, oy1, flag, cmds, bstart = parse_gfx_layer(r, name)
                nblocks = sum(d for _, d in cmds)
                raw = data[bstart:bstart + nblocks * 8]
                if len(raw) != nblocks * 8:
                    raise ValueError("%s f%d %s: faltan bloques" % (base, fi, name))
                if name == "main":
                    bb = _blocks_bbox(w, h, cmds)
                    if bb is None and bool(flag & REUSE_MASK) and prev_bbox is not None and prev_geom == (w, h, ox1, oy1):
                        bb = prev_bbox  # reutiliza: misma zona que el anterior
                    if bb is not None:
                        ax0, ay0, ax1, ay1 = bb[0] + ox1, bb[1] + oy1, bb[2] + ox1, bb[3] + oy1
                        gx0, gy0, gx1, gy1 = min(gx0, ax0), min(gy0, ay0), max(gx1, ax1), max(gy1, ay1)
                    meta["main"] = (w, h, ox1, oy1, flag, cmds, raw)
                    meta["bbox"] = bb
                    prev_bbox, prev_geom = bb, (w, h, ox1, oy1)
                r.o = bstart + nblocks * 8
            elif name == "player":
                r.take(2)
                ncmd = r.u16()
                cmds = [(r.d[r.o + 2 * i], r.d[r.o + 2 * i + 1]) for i in range(ncmd)]
                r.o += 2 * ncmd
                nblocks = sum(d for _, d in cmds)
                raw = data[r.o:r.o + nblocks * 8]
                if len(raw) != nblocks * 8:
                    raise ValueError("%s f%d player: faltan bloques" % (base, fi))
                meta["mask"] = (cmds, raw)
                r.o += nblocks * 8
            r.o = layer_start + pad4(clen)
        metas.append(meta)
        if verbose and (fi % 100 == 0 or fi == count - 1):
            dt = time.time() - t0
            eta = dt / (fi + 1) * (count - fi - 1) if fi + 1 < count else 0
            print("  scan %d/%d (%.0fs, ETA %.0fs)" % (fi + 1, count, dt, eta), flush=True)
    if gx1 < gx0:
        raise ValueError("animación vacía en %s" % base)
    gx0 = max(0, gx0 - margin)
    gy0 = max(0, gy0 - margin)
    gx1 = min(metas[0]["cw"] - 1, gx1 + margin)
    gy1 = min(metas[0]["ch"] - 1, gy1 + margin)
    cw, ch = gx1 - gx0 + 1, gy1 - gy0 + 1
    dirs, per_dir, drop = detect_dirs(len(metas))
    if max_frames and detect_dirs(nframes)[:2] != (dirs, per_dir):
        print("  AVISO %s: --max-frames %d cambia dirs %s (completo: %s): la unidad no rotara. Re-extrae sin limite." % (
            base, max_frames, (dirs, per_dir), detect_dirs(nframes)[:2]), flush=True)
    fr = metas[:-1] if drop else metas
    # id(e) -> (dir, sub) conservados; se decodifica TODO (barato) para que el
    # flag reuse encadene bien, pero solo se escriben los conservados.
    kept_of = {}
    for d in range(dirs):
        for s, e in enumerate(fr[d * per_dir:(d + 1) * per_dir][::step]):
            kept_of[id(e)] = (d, s)
    out_frames = []
    prev_img = None
    prev_g = None
    done = 0
    total_keep = len(kept_of)
    t1 = time.time()
    for e in fr:
        m = e["main"]
        if m is None:
            continue
        w, h, ox1, oy1, flag, cmds, raw = m
        prev = prev_img if (bool(flag & REUSE_MASK) and prev_img is not None and prev_g == (w, h)) else None
        img = draw_blocks(w, h, cmds, raw, decode_dxt1, prev)
        prev_img, prev_g = list(img), (w, h)
        if id(e) not in kept_of:
            continue
        d, s = kept_of[id(e)]
        layer = [(0, 0, 0, 0)] * (cw * ch)
        _paste(layer, cw, img, w, h, ox1 - gx0, oy1 - gy0)
        name = "p_%03d.png" % len(out_frames)
        write_png(os.path.join(dest, name), cw, ch, layer)
        mask_out = None
        if e["mask"] is not None:
            mcmds, mraw = e["mask"]
            mimg = draw_blocks(w, h, mcmds, mraw, decode_dxt4, None)
            mlayer = [0] * (cw * ch)
            _paste_gray(mlayer, cw, mimg, w, h, ox1 - gx0, oy1 - gy0)
            if any(v != 0 for v in mlayer):
                mask_out = "m_%03d.png" % len(out_frames)
                write_png(os.path.join(dest, mask_out), cw, ch,
                          [(255, 255, 255, v) for v in mlayer])
        out_frames.append({"png": name, "mask": mask_out, "dir": d, "sub": s,
                           "hotspot": [e["cx"] - gx0, e["cy"] - gy0]})
        done += 1
        if verbose and (done % 60 == 0 or done == total_keep):
            print("  pack %d/%d (%.0fs)" % (done, total_keep, time.time() - t1), flush=True)
    pack = {"source": base, "dirs": dirs, "per_dir": per_dir,
            "kept_per_dir": (per_dir + step - 1) // step, "step": step,
            "size": [cw, ch], "frames": out_frames}
    json.dump(pack, open(os.path.join(dest, "manifest.pack.json"), "w", encoding="utf-8"), indent=1)
    return pack


def main_geom_ok(e, w, h, ox1, oy1):
    return True


def prev_img_for(name, canvas, shadow, prev_main):
    # Compat: la reutilización solo aplica a main (prev_main ya validado).
    return prev_main if name == "main" else None


def _layer_copy(img, w, h):
    return list(img)


def _paste(canvas, cw, img, w, h, ox, oy):
    # Recorta al lienzo: la capa del frame puede sobresalir del recorte con
    # contenido (antes desbordaba o envolvía a la fila siguiente).
    ch = len(canvas) // cw
    for y in range(max(0, -oy), min(h, ch - oy)):
        base = (oy + y) * cw + ox
        for x in range(max(0, -ox), min(w, cw - ox)):
            canvas[base + x] = img[y * w + x]


def _paste_gray(canvas, cw, img, w, h, ox, oy):
    ch = len(canvas) // cw
    for y in range(max(0, -oy), min(h, ch - oy)):
        base = (oy + y) * cw + ox
        for x in range(max(0, -ox), min(w, cw - ox)):
            canvas[base + x] = img[y * w + x]


def main(argv=None):
    ap = argparse.ArgumentParser(description="SLD (AoE2:DE) -> PNG. Solo stdlib.")
    ap.add_argument("--src", required=True, help="carpeta drs/graphics del juego")
    ap.add_argument("--out", required=True, help="carpeta destino")
    ap.add_argument("--files", nargs="*", default=[], help="bases .sld (sin extensión)")
    ap.add_argument("--list", dest="listpat", default=None, help="solo lista archivos que casen (prefijo*)")
    ap.add_argument("--max-frames", type=int, default=0, help="límite de frames por archivo (0 = todos)")
    ap.add_argument("--pack", action="store_true", help="tras extraer: recorta+submuestrea (VRAM)")
    ap.add_argument("--step", type=int, default=2, help="submuestreo por dirección con --pack")
    args = ap.parse_args(argv)
    names = sorted(n for n in os.listdir(args.src) if n.endswith(".sld"))
    if args.listpat:
        pat = args.listpat.rstrip("*")
        for n in names:
            if n.startswith(pat):
                print(n)
        return 0
    if args.files:
        want = set()
        for b in args.files:
            want.add(b if b.endswith(".sld") else b + ".sld")
        names = [n for n in names if n in want]
    if not names:
        print("nada que convertir")
        return 1
    for n in names:
        print("convirtiendo", n, flush=True)
        try:
            if args.pack:
                # Vía rápida: sin PNG intermedios (rápida y sin miles de archivos).
                pk = convert_packed(os.path.join(args.src, n), args.out,
                                    step=args.step, max_frames=args.max_frames)
                print("  PACK %d dirs x %d = %d png %dx%d" % (
                    pk["dirs"], pk["kept_per_dir"], len(pk["frames"]), pk["size"][0], pk["size"][1]))
            else:
                m = convert_file(os.path.join(args.src, n), args.out, max_frames=args.max_frames)
                print("  OK %d frames -> %s" % (len(m["frames"]), n.replace(".sld", "")))
        except Exception as e:
            print("  ERROR en %s: %s" % (n, e))
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
