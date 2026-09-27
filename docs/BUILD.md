# BUILD — exportar a Windows / Linux desde Godot 4.4

El proyecto ya usa el preset **GL Compatibility** (exigido para PCs modestos y máxima compatibilidad):
`project.godot` → `[rendering] renderer/rendering_method="gl_compatibility"` y `config/features` incluye `"GL Compatibility"`. No lo cambies a Forward+/Mobile.

## 1. Instalar plantillas de exportación (una vez)

1. En Godot: **Editor → Manage Export Templates → Download and Install** (versión 4.4 exacta).
2. Verifica que aparecen `windows_64` y `linux_64` en `%APPDATA%/Godot/export_templates/4.4/`.

## 2. Presets incluidos (`export_presets.cfg`)

| Preset | Plataforma | Salida | Incluye |
|---|---|---|---|
| `Windows Desktop` | Windows Desktop | `build/OpenAge-LAN.exe` | Solo `.exe` (los `.pck` van al lado automáticamente) |
| `Linux` | Linux | `build/OpenAge-LAN.x86_64` | Binario + `.pck` |

Opciones clave ya fijadas: exportar **Release** (debug OFF), runnable, `export_path` relativo a `build/`, recursos filtrados `*.pck`, y arquitectura `x86_64`. Añade tu icono en `application/config/icon` si quieres `.ico` personalizado.

## 3. Exportar (GUI)

1. **Proyecto → Exportar…** → selecciona `Windows Desktop` → **Exportar proyecto** → `build/OpenAge-LAN.exe`.
2. Repite con `Linux` → `build/OpenAge-LAN.x86_64` (en Windows sale igualmente; dale permiso `chmod +x` en Linux).
3. Reparte la carpeta `build/` entera (exe + pck). No necesita Godot instalado.

## 4. Exportar por línea de comandos

```powershell
# Windows (desde la carpeta del proyecto)
godot --headless --export-release "Windows Desktop" build/OpenAge-LAN.exe
godot --headless --export-release "Linux" build/OpenAge-LAN.x86_64
```

## 5. LAN y firewall en el .exe

El exportado abre igual **UDP 7777 (descubrimiento) + TCP 7778 (partida)**. En el primer arranque Windows pedirá permiso de red privada: aceptar. Alternativa por PowerShell admin:

```
New-NetFirewallRule -DisplayName "OpenAge UDP" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
New-NetFirewallRule -DisplayName "OpenAge TCP" -Direction Inbound -Protocol TCP -LocalPort 7778 -Action Allow
```

## 6. Problemas típicos

- **"No export templates found"** → instala las 4.4 exactas (ver paso 1).
- **Pantalla negra / OpenGL** → el preset ya fija GL Compatibility; en PCs muy viejos baja a 1280×720 y desactiva MSAA en `project.godot`.
- **No se ven en LAN** → misma subred, misma versión del juego (mismo commit), firewall abierto, host visible como `Host OK en 192.168.1.X:7778`.
- **Desync** → ejecuta `godot --headless --test lan_8_bots --map arabia --ticks 3600` antes de exportar; debe terminar sin desync.
