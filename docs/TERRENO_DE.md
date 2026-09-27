# Terreno AoE2 DE — hallazgo F1b (2026-09-27)

## Rutas (solo lectura)
- Texturas: `Content/Game/resources/_common/terrain/textures/2x/` (85 `.dds`)
- Mezclas: `terrain/blends/` (10 `.png`), máscaras: `terrain/masks/` (26 `.png`)
- Agua: `terrain/water/` (PNG + DDS) + `terrain/water_json/water_def.json`
- Sprites SLD: `drs/graphics/` (~7800 `.sld`); en `terrain/` hay 0 `.sld`

## Formato
- Terreno: DDS, magic `DDS ` (44 44 53 20). Ej. `g_grs.dds`: 2048×2048, FourCC `DXT1`, 2796344 bytes.
- Variantes: DXT1 (77), DXT5 (2, ej. `g_wt_yellow.dds`), DX10/BC7 DXGI 98 (5, ej. `g_pc1.dds`, 2048×2048, 5592580 bytes), RGBA8 sin comprimir (1, `g_kf1.dds`, 1024×1024, 4194432 bytes).
- Blends/masks: PNG estándar (`89504E47…`). Ej. `landland.png` 76123 bytes, `grass.png` 543844 bytes.

## Veredicto
Riesgo §11 confirmado como "distinto de SLD": el terreno DE **no es familia SLD** y el extractor actual (`SLDX`, DXT1/DXT4 por bloques + comandos skip/draw) **no aplica**. No se ejecutó prueba `--max-frames` sobre terreno por no haber SLD (evita falso positivo); el flag existe según `--help`.

## Siguiente paso (sin implementar)
Decodificar DDS en el importador F1: Godot 4 `Image.load_dds_from_buffer` cubre DXT1/DXT5/RGBA; verificar BC7 (DXGI 98) en 4.4 y, si falla, preconvertir offline a PNG con herramienta externa sobre copia del jugador. Placeholders mientras tanto. No exportar ni versionar assets.
