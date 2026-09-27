# UI + Audio DE — hallazgos (solo investigación, sin código de juego)

Audio actual: `audio/AudioManager.gd` es 100% procedural (WAV 22050 Hz 8-bit sintetizado: click, sword, bell...), sin archivos externos. Música: pad en loop stub.

## UI: iconos y cursores
- Iconos PNG directos 80x80 en `widgetui/textures/ingame/icons/` (ej. `age-1.png`), `actions/`, `staticons/`. Muestra extraída: `assets/ui_extraidos/icono_age-1.png`.
- Cursor PNG directo 128x128 en `widgetui/textures/ingame/cursor/` (`drag_scroll_cursor.png`). Muestra extraída: `assets/ui_extraidos/cursor_drag_scroll.png`.
- NO extraídos: `resources/_common/cursors/*.cur` (32x32/48x48, formato CUR, fuera de la regla PNG/BMP/SLD); `.../ingame/tech|units/*.DDS` (256x256, DDS sin FOURCC, no lo convierte `tools/extract_aoe2_sprites.py` que solo acepta SLD); `drs/interface/*.slp|*.bina` (SLP antiguo, no SLD).
- No existen `uiresources/`, `sounds/` ni `drs/sounds*` bajo `_common`; `widgetui/textures/atlas/{HD,SD,UHD}/` solo contiene carpetas vacías.

## Audio: Wwise empaquetado, sin extracción
- Barrido completo de `Content/Game`: cero `.wav/.ogg/.wem/.bnk` sueltos. Sonido solo en `wwise/Base.pck`, `Base.1.pck` y `wwise/{br,de,en,es,fr,it,ko,mx,zh}/*.pck` (decenas a cientos de MB).
- Son WEM/BNK dentro de PCK: NO se convierten (regla de la tarea). Ruta futura: `vgmstream-cli` contra copia local del `.pck` + `wwise_foobar`/`bnkextr` para listar IDs. No se extrajo click/espada/campana.
- Nota legal: usar solo tu copia comprada; no redistribuir PNG/PCK (los extraídos son muestras locales).
