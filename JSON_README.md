# MVPByJude - Funcionalidad de Importación/Exportación JSON

## Resumen

El addon MVPByJude ahora soporta la importación y exportación de datos DKP en formato JSON, permitiendo:
- ✅ Exportar todos los datos del addon a formato JSON compatible con EPGP
- ✅ Importar datos JSON de otros addons o sistemas EPGP
- ✅ Sincronizar datos entre diferentes guildas o personajes

## Instalación

1. Los archivos han sido añadidos automáticamente:
   - `LibJSON-1.0.lua` - Librería JSON (copiada de EPGP)
   - `Export.lua` - Módulo de exportación
   - `Import.lua` - Módulo de importación
   - `MVPByJude.toc` - Actualizado con nuevos archivos

2. Reinicia WoW o recarga el addon `/reload`

## Uso

### Exportación a JSON

#### Método 1: UI (Recomendado)
1. Abre el addon MVPByJude (`/mvp`)
2. Haz clic en el botón "Exportar JSON" en el header
3. Se abrirá una ventana con el JSON completo
4. Selecciona todo (Ctrl+A) y copia (Ctrl+C)
5. Pega en un editor de texto o guarda en archivo

#### Método 2: Línea de Comandos
```
/mvpexport json
```

### Importación desde JSON

#### Método 1: UI (Recomendado)
1. Abre el addon MVPByJude (`/mvp`)
2. Haz clic en el botón "Importar JSON" en el header
3. Se abrirá una ventana con un cuadro de texto
4. Pega el JSON en el cuadro
5. Haz clic en "Importar"

#### Método 2: Línea de Comandos
```
/mvpimport json
```

## Formato JSON

### Estructura Exportada

```json
{
  "loot_history": [],
  "log": [
    {
      "event_uid": "action-1234567890",
      "timestamp": 1234567890,
      "type": "EPAward",
      "kind": "EP",
      "event": "EPAward",
      "amount": 100,
      "reason": "Kill de jefe",
      "master": "NombreMaestro",
      "target": "NombreJugador",
      "zone": "Unknown",
      "boss": "Global",
      "raid_id": "unknown-raid"
    }
  ],
  "participants": {
    "NombreJugador": {
      "ep_current": 1500,
      "gp_current": 800,
      "balance": 700,
      "class": "DEATHKNIGHT",
      "main": "NombreMain"
    }
  },
  "metadata": {
    "version": "2.0",
    "guild": "NombreGilda",
    "addon": "MVPByJude",
    "addon_version": "1.0",
    "exported": 1234567890,
    "exporter": "NombreJugador"
  }
}
```

### Campos JSON

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `event_uid` | string | ID único del evento |
| `timestamp` | number | Timestamp UNIX del evento |
| `type` | string | Tipo de evento (EPAward, etc) |
| `kind` | string | Categoría (EP, MASS_EP) |
| `amount` | number | Cantidad de puntos |
| `reason` | string | Motivo del evento |
| `master` | string | Nombre de quien otorgó |
| `target` | string/object | Jugador(es) afectado(s) |
| `zone` | string | Zona del evento |
| `boss` | string | Nombre del jefe |
| `raid_id` | string | ID de la raid |
| `ep_current` | number | EP actual del participante |
| `gp_current` | number | GP actual del participante |
| `class` | string | Clase WoW del jugador |
| `main` | string | Nombre del main (si es alt) |

## Compatibilidad

### EPGP ↔ MVPByJude

La estructura JSON es compatible bidireccional:
- **Exportar MVPByJude → Importar en EPGP**: ✅ Parcialmente (los campos básicos funcionan)
- **Exportar EPGP → Importar en MVPByJude**: ✅ Completamente compatible

### Datos Sincronizados

✅ **Sincroniza perfectamente:**
- Eventos EP/GP
- Standings (EP y GP por jugador)
- Información de alts/mains
- Historial de cambios

⚠️ **Sincroniza parcialmente:**
- Información de raids (zone, boss detectados pero limitados)
- Historial de loot

❌ **No sincroniza:**
- Configuración específica del addon
- Datos de Hard Res, Soft Res, Gold Bid
- Anuncios y publicidad

## Ejemplos de Uso

### Backup Automático
```
/mvpexport json
# Copiar y guardar en archivo DKP_backup_2026-06-06.json
```

### Migración entre Addons
```
1. En EPGP: /epgp export
2. En MVPByJude: Copiar JSON y /mvpimport json
```

### Sincronización entre Gildas
```
1. Gilda A: /mvpexport json
2. Gilda B: /mvpimport json
3. Ambas tendrán los mismos datos
```

## Resolución de Problemas

### Error "JSON vacío"
- Asegúrate de pegar el JSON completo (Ctrl+A, Ctrl+C)
- El JSON debe ser válido (sin caracteres de control)

### Error "Invalid JSON schema"
- El JSON debe contener campos "log" y "participants"
- Verifica que el formato sea correcto

### Se importan duplicados
- Usa el event_uid único para evitar duplicados
- El sistema detecta automáticamente duplicados por UID

### Los datos no se guardan
- Verifica que estés en una gilda (SavedVariables requiere contexto de gilda)
- Recarga el addon después de importar: `/reload`

## Comandos de Depuración

```lua
-- Ver módulo Export
/script print(MVPByJude.Export and "Export disponible" or "Export NO disponible")

-- Ver módulo Import
/script print(MVPByJude.Import and "Import disponible" or "Import NO disponible")

-- Exportar directamente a chat
/script local json, err = MVPByJude.Export:ToJSON(); print(err or "OK: " .. (#json) .. " caracteres")

-- Importar desde chat (testing)
/script MVPByJude.Import:ExecuteImport('{"log":[],"participants":{}}')
```

## Contribución y Bugs

Si encuentras problemas:
1. Revisa la consola de errores: `/console scriptErrors 1`
2. Reporta el error exacto junto con el JSON que lo causó
3. Asegúrate de que LibJSON se haya cargado correctamente

---

**Versión**: 1.0
**Compatible con**: WoW 3.3.5a (Wrath of the Lich King)
**Requiere**: LibStub (incluido en mayoría de addons)
