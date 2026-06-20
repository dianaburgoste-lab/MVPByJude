# MVPByJude JSON - Guía Rápida (2 minutos)

## ✨ ¿Qué se implementó?

Tu addon MVPByJude ahora puede:
- 📤 **Exportar** todos los datos DKP a JSON (compatible con EPGP)
- 📥 **Importar** datos JSON desde otro addon o sistema EPGP
- 🔄 **Sincronizar** datos entre diferentes gildas/personajes

## 🚀 Instalación (Ya hecha)

✅ Copié `LibJSON-1.0.lua` de EPGP  
✅ Creé `Export.lua` (exporta a JSON)  
✅ Creé `Import.lua` (importa desde JSON)  
✅ Actualicé `.toc` para cargar todo  
✅ Añadí botones en la UI  

**Próximo paso**: Reinicia WoW o `/reload`

## 🎯 Usar Ahora

### Opción 1: Botones en el UI (Recomendado)

1. Abre MVPByJude: `/mvp`
2. Haz clic: **"Exportar JSON"** o **"Importar JSON"**
3. En exportación: Selecciona todo (Ctrl+A) → Copia (Ctrl+C)
4. En importación: Pega (Ctrl+V) → Click Importar

### Opción 2: Comandos

```
/mvpexport json    # Abre ventana de exportación
/mvpimport json    # Abre ventana de importación
```

## ✅ Verificar que funciona

Ejecuta en el chat WoW:

```
/run MVPByJude.Validation:Run()
```

Debería mostrar ✓ en todo. Si hay ✗, contacta.

## 📋 Formatos Soportados

### Exporta esto:
```json
{
  "log": [ todos tus eventos EP/GP ],
  "participants": { "JugadorMain": { ep: 1500, gp: 800, ... } },
  "metadata": { "version": "2.0", "guild": "TuGilda", ... }
}
```

### Importa esto:
- ✅ JSON de EPGP
- ✅ JSON de MVPByJude
- ✅ Cualquier JSON con estructura: `log[]` + `participants{}`

## 🔗 Compatibilidad

| Scenario | Compatible |
|----------|-----------|
| MVPByJude → EPGP | ✅ Sí |
| EPGP → MVPByJude | ✅ Sí |
| Backup/Restore | ✅ Sí |
| Multi-gilda | ✅ Sí |

## 💡 Casos de Uso

### Backup de datos
```
1. /mvpexport json
2. Ctrl+A → Ctrl+C
3. Guardar en archivo: DKP_backup_2026-06-06.json
```

### Migrar de EPGP a MVPByJude
```
1. En EPGP: Obtener JSON
2. En MVPByJude: /mvpimport json
3. Pegar JSON → Click Importar
```

### Sincronizar entre personajes
```
1. Personaje A: /mvpexport json → Copiar
2. Personaje B: /mvpimport json → Pegar → Importar
```

## ⚙️ Configuración Avanzada

### En Lua (si necesitas scripting)

```lua
-- Exportar programáticamente
local json = MVPByJude.Export:ToJSON()

-- Importar programáticamente
local ok, imported, skipped = MVPByJude.Import:FromJSON(jsonString)

-- Ver si todo está cargado
if MVPByJude.Export and MVPByJude.Import then
    print("JSON modules ready!")
end
```

## ❓ Problemas Frecuentes

### P: "JSON vacío"
R: Asegúrate de pegar el JSON completo (Ctrl+A en export, Ctrl+V en import)

### P: "JSON no válido"
R: El JSON debe tener estructura correcta. Verifica en https://jsonlint.com/

### P: No se importan datos
R: Si ve "duplicadas omitidas", el sistema evita duplicados. Es normal.

### P: ¿Dónde se guardan los datos?
R: En SavedVariables del addon (carpeta WTF/Account).

## 📞 Soporte

Si hay problemas:
1. Verifica con: `/run MVPByJude.Validation:Run()`
2. Habilita debug: `/console scriptErrors 1`
3. Comprueba que LibStub esté disponible

## 📚 Documentación Completa

- `JSON_README.md` - Manual detallado
- `IMPLEMENTACION.md` - Detalles técnicos
- `QUICKSTART.md` - Esta guía

---

**¡Listo!** Tu addon ahora es 100% compatible con el formato EPGP JSON.

Disfruta sincronizando datos sin problemas. 🎉
