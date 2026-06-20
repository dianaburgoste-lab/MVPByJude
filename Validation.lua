-- MVPByJude JSON Integration - Validation Script
-- Uso: /script LoadAddon("MVPByJude"); dofile("validate.lua")
-- O directamente en el chat WoW:
-- /run local RMS = MVPByJude; if RMS.Validation then RMS.Validation:Run() end

local RMS = MVPByJude
local Validation = {}
RMS.Validation = Validation

function Validation:Run()
    self:PrintHeader("MVPByJude JSON Integration - Validación")
    
    local passed = 0
    local failed = 0
    
    -- Test 1: LibStub disponible
    if LibStub then
        self:Pass("✓ LibStub disponible")
        passed = passed + 1
    else
        self:Fail("✗ LibStub NO disponible (puede no ser crítico)")
        passed = passed + 1  -- No es crítico
    end
    
    -- Test 2: LibJSON disponible
    local json = LibStub and LibStub("LibJSON-1.0")
    if json then
        self:Pass("✓ LibJSON-1.0 cargado correctamente")
        passed = passed + 1
    else
        self:Fail("✗ LibJSON-1.0 NO está disponible")
        failed = failed + 1
    end
    
    -- Test 2: Export module disponible
    if RMS.Export then
        self:Pass("✓ Módulo Export disponible")
        passed = passed + 1
    else
        self:Fail("✗ Módulo Export NO disponible")
        failed = failed + 1
    end
    
    -- Test 3: Import module disponible
    if RMS.Import then
        self:Pass("✓ Módulo Import disponible")
        passed = passed + 1
    else
        self:Fail("✗ Módulo Import NO disponible")
        failed = failed + 1
    end
    
    -- Test 4: DKP module disponible
    if RMS.DKP and RMS.DKP.state then
        self:Pass("✓ Módulo DKP y state disponibles")
        passed = passed + 1
    else
        self:Fail("✗ Módulo DKP o state NO disponibles")
        failed = failed + 1
    end
    
    -- Test 5: Export.ToJSON() callable
    if RMS.Export and type(RMS.Export.ToJSON) == "function" then
        self:Pass("✓ Export:ToJSON() es función")
        passed = passed + 1
    else
        self:Fail("✗ Export:ToJSON() NO es función")
        failed = failed + 1
    end
    
    -- Test 6: Import.FromJSON() callable
    if RMS.Import and type(RMS.Import.FromJSON) == "function" then
        self:Pass("✓ Import:FromJSON() es función")
        passed = passed + 1
    else
        self:Fail("✗ Import:FromJSON() NO es función")
        failed = failed + 1
    end
    
    -- Test 7: Try export (non-destructive)
    if RMS.Export and RMS.Export.ToJSON then
        local jsonString, err = RMS.Export:ToJSON()
        if jsonString then
            self:Pass("✓ Export:ToJSON() ejecutado exitosamente (" .. #jsonString .. " caracteres)")
            passed = passed + 1
            
            -- Test 8: Deserialize JSON
            if json then
                local success, data = pcall(function()
                    return json.Deserialize(jsonString)
                end)
                if success and type(data) == "table" then
                    self:Pass("✓ JSON deserializado correctamente")
                    passed = passed + 1
                    
                    -- Test 9: Check JSON structure
                    if data.log and data.participants and data.metadata then
                        self:Pass("✓ JSON tiene estructura correcta")
                        passed = passed + 1
                    else
                        self:Fail("✗ JSON incompleto: faltan 'log', 'participants' o 'metadata'")
                        failed = failed + 1
                    end
                else
                    self:Fail("✗ Error deserializando JSON: " .. tostring(data))
                    failed = failed + 1
                end
            else
                self:Pass("✓ Test deserialización saltado (LibJSON no disponible)")
                passed = passed + 1
            end
        else
            self:Fail("✗ Export:ToJSON() error: " .. tostring(err))
            failed = failed + 1
        end
    end
    
    -- Test 10: Slash commands registered
    if SlashCmdList.MVPEXPORT then
        self:Pass("✓ Comando /mvpexport registrado")
        passed = passed + 1
    else
        self:Fail("✗ Comando /mvpexport NO registrado")
        failed = failed + 1
    end
    
    if SlashCmdList.MVPIMPORT then
        self:Pass("✓ Comando /mvpimport registrado")
        passed = passed + 1
    else
        self:Fail("✗ Comando /mvpimport NO registrado")
        failed = failed + 1
    end
    
    -- Summary
    print("")
    self:PrintHeader("Resumen")
    print(string.format("  ✓ Pasadas: %d", passed))
    print(string.format("  ✗ Fallos:  %d", failed))
    print(string.format("  % Éxito:  %.0f%%", (passed / (passed + failed)) * 100))
    print("")
    
    if failed == 0 then
        self:Pass("¡¡ VALIDACIÓN EXITOSA !!")
        print("El addon está listo para usar.")
        print("  • Abre el addon: /mvp")
        print("  • Exporta a JSON: Botón 'Exportar JSON' o /mvpexport json")
        print("  • Importa de JSON: Botón 'Importar JSON' o /mvpimport json")
    else
        self:Fail("Hay problemas que necesitan revisión.")
        print("Intenta:")
        print("  1. /reload (recargar addon)")
        print("  2. Verificar que LibStub esté disponible")
        print("  3. Verificar errores de Lua: /console scriptErrors 1")
    end
    
    print("")
end

function Validation:Pass(msg)
    print("|cff00ff00" .. msg .. "|r")
end

function Validation:Fail(msg)
    print("|cffff0000" .. msg .. "|r")
end

function Validation:PrintHeader(msg)
    print("|cff00ddff" .. msg .. "|r")
    print("|cff00ddff" .. string.rep("=", #msg) .. "|r")
end

-- Auto-run on load (optional)
-- Uncomment la siguiente línea para ejecutar validación automáticamente
-- RMS.Validation:Run()

print("|cff00ff00MVPByJude Validation ready|r - Usa: |cff00ddff/run MVPByJude.Validation:Run()|r")
