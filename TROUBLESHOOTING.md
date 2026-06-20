# MVPByJude JSON - Solución de Problemas

## 🔴 "Módulo Export/Import no disponible"

### Causa
Los módulos `Export.lua` e `Import.lua` no se están cargando correctamente porque hay un problema con `LibJSON-1.0`.

### ✅ Solución Rápida

**Paso 1**: Reinicia WoW completamente (cierra y abre el juego)

**Paso 2**: En el chat de WoW, ejecuta:
```
/mvpdebug run
```

**Paso 3**: Revisa qué dice. Si ves:
- `✓ LibJSON-1.0 cargado correctamente` → el problema está en otro lado
- `✗ LibJSON-1.0 NO está disponible` → continúa al Paso 4

**Paso 4**: Si LibJSON no se cargó:
```
/reload
```

Espera a que recargue el addon completamente (verás el mensaje en chat).

**Paso 5**: Prueba de nuevo:
```
/mvpdebug run
```

Debería mostrar todo con ✓.

### Si sigue sin funcionar

1. **Verifica que el archivo existe**:
   ```
   G:\Marzo2026\WoW 3.3.5a Macalo\Interface\Addons\MVPByJude\LibJSON-1.0.lua
   ```

2. **Habilita errores de Lua**:
   ```
   /console scriptErrors 1
   ```

3. **Abre la consola de errores**:
   - En WoW: `Escape` → busca "Errors" o presiona `Ctrl+Shift+U`
   - Busca líneas que digan "Export.lua" o "Import.lua"
   - Copia el error exacto y contacta

4. **Intenta recargar manualmente**:
   ```
   /run MVPByJude.Export = MVPByJude.Export or {}; RMS = MVPByJude; print("Export:", RMS.Export and "OK" or "FAIL")
   ```

---

## 🔴 "JSON vacío" / "Invalid JSON schema"

### Causa
El JSON que intentas importar está incompleto o tiene formato incorrecto.

### ✅ Solución

**Para Exportación**:
1. Abre addon: `/mvp`
2. Click "Exportar JSON"
3. En la ventana que se abre, presiona `Ctrl+A` (seleccionar todo)
4. Presiona `Ctrl+C` (copiar)
5. El JSON está copiado

**Para Importación**:
1. Pega el JSON: `Ctrl+V`
2. Verifica que empiece con `{` y termine con `}`
3. Verifica que NO tenga caracteres de control (líneas raras)
4. Click "Importar"

**Validar JSON**:
- Abre https://jsonlint.com/
- Pega tu JSON
- Si muestra "Valid JSON" ✓, el JSON es correcto
- Si muestra error, corrige y prueba de nuevo

---

## 🔴 No aparecen botones "Exportar/Importar"

### Causa
Los botones están en el UI pero no se ven, o se cargan después de que el UI ya está dibujado.

### ✅ Solución

**Opción 1**: Usa slash commands (más confiable):
```
/mvpexport json    # Exportar
/mvpimport json    # Importar
```

**Opción 2**: Si quieres que aparezcan los botones:
1. Cierra addon: Click X
2. Recarga: `/reload`
3. Abre addon: `/mvp`
4. Los botones deberían estar en el header (arriba a la derecha)

---

## 🔴 Se importan muchos duplicados

### Causa
Posiblemente el JSON contiene entradas duplicadas, o el sistema no está deduplicando correctamente.

### ✅ Solución

El sistema **automáticamente** detecta duplicados y los omite. Verás un mensaje tipo:
```
Importación completada:
  • Importadas: 500 entradas
  • Omitidas: 50 duplicadas
```

**Si esto ocurre muchas veces**:
- Revisa que el JSON no tenga entradas repetidas (usando un validador JSON)
- El `event_uid` debe ser único por evento

**Para limpiar duplicados manualmente**:
```lua
/run local dkp = MVPByJude.DKP; local seen = {}; local new_log = {}; for _, e in ipairs(dkp.state.log) do if not seen[e.id] then table.insert(new_log, e); seen[e.id] = true end end; dkp.state.log = new_log; print("Limpiados duplicados. Recarga: /reload")
```

---

## 🔴 Los datos importados no se guardan

### Causa
Los SavedVariables no se sincronizan hasta que recargas o cierras WoW.

### ✅ Solución

**Después de importar, SIEMPRE**:
1. Recarga el addon: `/reload`
2. Cierra WoW correctamente (no Alt+Tab)
3. Abre WoW de nuevo

Los datos se guardan automáticamente en:
```
WTF/Account/<TuCuenta>/SavedVariables/MVPByJudeDB.lua
```

---

## 🟡 Diferencia entre "EP" y "GP" after import

### Causa
Diferentes addons pueden mostrar EP/GP de manera diferente (algunos incluyen base_gp, otros no).

### ✅ Solución

MVPByJude usa:
- **EP (Effort Points)**: Puntos ganados (acumulativo)
- **GP (Gear Points)**: Puntos gastados al obtener loot
- **Balance**: EP - GP (saldo actual)

Si ves diferencias después de importar desde otro addon:
- Es normal (cada addon calcula diferente)
- Verifica manualmente los campos `ep_current`, `gp_current` en el JSON
- Puedes ajustar manualmente en el UI si es necesario

---

## 🟡 JSON muy grande (> 1 MB)

### Causa
Addon con muchos eventos (1000+), el JSON es voluminoso.

### ✅ Solución

**Exportar por partes**:
1. Manualmente limpia `state.log` de eventos antiguos
2. O exporta solo eventos recientes

**Importar por partes**:
1. Divide el JSON en secciones más pequeñas
2. Importa cada sección por separado

**Comando para eliminar eventos viejos**:
```lua
/run
local dkp = MVPByJude.DKP
local cutoff = time() - (30 * 24 * 60 * 60)  -- 30 días atrás
local new_log = {}
for _, e in ipairs(dkp.state.log) do
    if (e.time or 0) > cutoff then
        table.insert(new_log, e)
    end
end
dkp.state.log = new_log
print("Eventos conservados: " .. #new_log)
/reload
```

---

## 🟡 LibJSON disponible pero Export/Import no funciona

### Causa
Hay un error de Lua en Export.lua o Import.lua que evita que se ejecuten completamente.

### ✅ Solución

**Habilita debug de Lua**:
```
/console scriptErrors 1
```

**Abre consola de errores**: `Ctrl+Shift+U` (en WoW)

**Busca errores tipo**:
```
Error in MVPByJude/Export.lua:XX:
  attempt to call method 'ExportToEditbox' (a nil value)
```

**Solución**:
1. Copia el error exacto
2. Si es problema de Lua syntax, contacta
3. Prueba `/reload` primero

---

## 🆘 Todos los tests en /mvpdebug muestran ✗

### Causa
El addon probablemente no se cargó en absoluto, o hay un error crítico.

### ✅ Solución

1. **Verifica que el addon esté habilitado**:
   - Interfaz → Addons → busca "MVP By Jude" → asegúrate que tiene ✓

2. **Recarga addon**:
   ```
   /reload
   ```
   Espera a que termine (verás mensajes en chat)

3. **Si sigue sin funcionar**:
   - Disable addons one by one (temporarily)
   - Prueba con solo MVPByJude

4. **Última opción - reinstalar**:
   ```
   1. Cierra WoW
   2. Borra carpeta: G:\Marzo2026\WoW 3.3.5a Macalo\Interface\Addons\MVPByJude
   3. Descomprime backup o vuelve a copiar
   4. Abre WoW
   5. Prueba de nuevo
   ```

---

## 📞 Si nada funciona

1. Ejecuta debug:
   ```
   /mvpdebug run
   ```

2. Copia TODO el output

3. Habilita errores:
   ```
   /console scriptErrors 1
   ```

4. Intenta usar los botones/comandos

5. Copia los errores del chat

6. Contacta con esta información:
   - Output de `/mvpdebug run`
   - Errores de Lua
   - Pasos exactos para reproducir el error
   - Screenshot si es posible

---

## ✅ Checklist de Instalación Correcta

- [ ] Archivo `LibJSON-1.0.lua` existe
- [ ] Archivo `Export.lua` existe
- [ ] Archivo `Import.lua` existe
- [ ] Archivo `Debug.lua` existe
- [ ] `.toc` carga los 4 archivos arriba
- [ ] `/reload` recarga sin errores
- [ ] `/mvpdebug run` muestra la mayoría con ✓
- [ ] `/mvpexport json` abre ventana
- [ ] `/mvpimport json` abre ventana
- [ ] Botones "Exportar JSON" e "Importar JSON" aparecen en header del addon

Si todo está ✓, el addon debería funcionar correctamente.
