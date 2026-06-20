-- MVPByJude JSON - Debug & Fix Script - DETALLADO
local RMS = MVPByJude
local Debug = {}
RMS.DebugModule = Debug

function Debug:Run()
    print("\n" .. string.rep("=", 60))
    print(">>> MVPByJude JSON - DIAGNÓSTICO DETALLADO <<<")
    print(string.rep("=", 60))
    
    -- Test 1: Modulos básicos
    print("\n[1] MÓDULOS BÁSICOS")
    print("RMS:", RMS and "OK" or "FAIL")
    print("RMS.DKP:", RMS.DKP and "OK" or "FAIL")
    print("RMS.Export:", RMS.Export and "OK" or "FAIL")
    print("RMS.Import:", RMS.Import and "OK" or "FAIL")
    
    -- Test 2: LibStub
    print("\n[2] LIBSTUB")
    print("LibStub existe:", LibStub and "SI" or "NO")
    if LibStub then
        print("LibStub.NewLibrary:", type(LibStub.NewLibrary) == "function" and "OK" or "FAIL")
    end
    
    -- Test 3: LibJSON
    print("\n[3] LIBJSON-1.0")
    local json = nil
    if LibStub then
        json = LibStub("LibJSON-1.0")
        print("Via LibStub:", json and "OK" or "FAIL")
    end
    if not json and _G.LibJSON then
        json = _G.LibJSON
        print("Via _G.LibJSON:", json and "OK (FALLBACK)" or "FAIL")
    end
    if json then
        print("JSON.Serialize:", type(json.Serialize) == "function" and "OK" or "FAIL")
        print("JSON.Deserialize:", type(json.Deserialize) == "function" and "OK" or "FAIL")
    end
    
    -- Test 4: Export functions
    print("\n[4] EXPORT FUNCTIONS")
    if RMS.Export then
        print("Export.ToJSON:", type(RMS.Export.ToJSON) == "function" and "OK" or "FAIL")
        print("Export.ExportToEditbox:", type(RMS.Export.ExportToEditbox) == "function" and "OK" or "FAIL")
    end
    
    -- Test 5: Import functions
    print("\n[5] IMPORT FUNCTIONS")
    if RMS.Import then
        print("Import.FromJSON:", type(RMS.Import.FromJSON) == "function" and "OK" or "FAIL")
        print("Import.ShowImportDialog:", type(RMS.Import.ShowImportDialog) == "function" and "OK" or "FAIL")
    end
    
    -- Test 6: DKP State
    print("\n[6] DKP STATE")
    if RMS.DKP then
        print("DKP.state:", RMS.DKP.state and "OK" or "FAIL")
        if RMS.DKP.state then
            print("state.log:", RMS.DKP.state.log and ("OK (" .. #RMS.DKP.state.log .. " entries)") or "FAIL")
            print("state.standings:", RMS.DKP.state.standings and "OK" or "FAIL")
        end
    end
    
    -- Test 7: Intentar exportar
    print("\n[7] TEST DE EXPORTACIÓN")
    if RMS.Export and type(RMS.Export.ToJSON) == "function" then
        local success, result = pcall(function()
            return RMS.Export:ToJSON()
        end)
        
        if success then
            if result then
                print("ToJSON():", "OK (" .. #result .. " bytes)")
            else
                print("ToJSON():", "RETORNA NIL")
            end
        else
            print("ToJSON() ERROR:", tostring(result))
        end
    end
    
    -- Test 8: Slash commands
    print("\n[8] SLASH COMMANDS")
    print("/mvpexport json:", SlashCmdList.MVPEXPORT and "OK" or "FAIL")
    print("/mvpimport json:", SlashCmdList.MVPIMPORT and "OK" or "FAIL")
    
    -- Test 9: Sumary
    print("\n" .. string.rep("=", 60))
    print("RESUMEN:")
    local allOK = (RMS and RMS.DKP and RMS.Export and RMS.Import and json and 
                   type(RMS.Export.ToJSON) == "function" and 
                   type(RMS.Import.FromJSON) == "function")
    
    if allOK then
        print("✓ TODO OK - El addon debería funcionar correctamente")
    else
        print("✗ PROBLEMAS DETECTADOS - Ver arriba los items en FAIL")
    end
    print(string.rep("=", 60) .. "\n")
end

-- Diagnostic helper
function Debug:TestExportDirect()
    print("\n=== TEST DIRECTO DE EXPORTACIÓN ===")
    if not RMS.Export then
        print("ERROR: RMS.Export no existe")
        return
    end
    
    if not RMS.DKP then
        print("ERROR: RMS.DKP no existe")
        return
    end
    
    if not RMS.DKP.state then
        print("ERROR: RMS.DKP.state no existe")
        return
    end
    
    print("RMS, DKP, state: OK")
    print("Intentando ToJSON()...")
    
    local success, result = pcall(function()
        return RMS.Export:ToJSON()
    end)
    
    if not success then
        print("ERROR en ToJSON():", result)
        return
    end
    
    if not result then
        print("ToJSON() retorna nil (sin datos)")
        return
    end
    
    print("✓ Exportación exitosa:", #result, "bytes")
    print("Primeros 100 caracteres:", result:sub(1, 100))
end

-- Slash commands
SLASH_MVPDEBUG1 = "/mvpdebug"
SlashCmdList.MVPDEBUG = function(args)
    args = args:lower():match("^%s*(.-)%s*$") or ""
    
    if args == "" or args == "run" then
        Debug:Run()
    elseif args == "export" then
        Debug:TestExportDirect()
    else
        print("=== MVPByJude Debug ===")
        print("/mvpdebug run - Diagnóstico completo")
        print("/mvpdebug export - Test de exportación detallado")
    end
end

print("|cff00ff00✓ Debug ready|r - Usa |cff00ddff/mvpdebug run|r o |cff00ddff/mvpdebug export|r")
