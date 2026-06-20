-- QuickTest - Prueba rápida de todo
-- Ejecutar: /run dofile("QuickTest.lua")

print("\n" .. string.rep("=", 70))
print("QUICK TEST - MVPByJude JSON")
print(string.rep("=", 70))

local RMS = MVPByJude

-- Test 1: Básicos
print("\n[1] ESTADO DEL ADDON")
print(string.format("  RMS: %s", RMS and "✓" or "✗"))
print(string.format("  RMS.DKP: %s", RMS and RMS.DKP and "✓" or "✗"))
print(string.format("  RMS.Export: %s", RMS and RMS.Export and "✓" or "✗"))
print(string.format("  RMS.Import: %s", RMS and RMS.Import and "✓" or "✗"))

-- Test 2: LibStub
print("\n[2] LIBSTUB & JSON")
local libstub_ok = LibStub ~= nil
print(string.format("  LibStub disponible: %s", libstub_ok and "✓" or "✗"))

local json = nil
if libstub_ok then
    json = LibStub("LibJSON-1.0")
    print(string.format("  LibJSON via LibStub: %s", json and "✓" or "✗"))
end

if not json and _G.LibJSON then
    json = _G.LibJSON
    print(string.format("  LibJSON via _G (fallback): %s", json and "✓" or "✗"))
end

if json then
    print(string.format("    - Serialize: %s", type(json.Serialize) == "function" and "✓" or "✗"))
    print(string.format("    - Deserialize: %s", type(json.Deserialize) == "function" and "✓" or "✗"))
end

-- Test 3: DKP State
print("\n[3] DKP STATE")
if RMS and RMS.DKP then
    print(string.format("  state: %s", RMS.DKP.state and "✓" or "✗"))
    if RMS.DKP.state then
        local entries = RMS.DKP.state.log and #RMS.DKP.state.log or 0
        print(string.format("  state.log entries: %d", entries))
        local standingsCount = 0
        if RMS.DKP.state.standings then
            for _ in pairs(RMS.DKP.state.standings) do standingsCount = standingsCount + 1 end
        end
        print(string.format("  state.standings players: %d", standingsCount))
    end
end

-- Test 4: Export test
print("\n[4] EXPORT TEST")
if RMS and RMS.Export and type(RMS.Export.ToJSON) == "function" then
    local success, json_result, err = pcall(function()
        return RMS.Export:ToJSON()
    end)
    
    if success then
        if json_result then
            print(string.format("  ✓ ToJSON() exitoso: %d bytes", #json_result))
            print(string.format("    Primeros 80 chars: %s...", json_result:sub(1, 80)))
        else
            print(string.format("  ✗ ToJSON() retorna nil: %s", err or "(sin error)"))
        end
    else
        print(string.format("  ✗ ToJSON() error: %s", tostring(json_result)))
    end
else
    print("  ✗ Export.ToJSON no disponible")
end

-- Test 5: Commands
print("\n[5] SLASH COMMANDS")
print(string.format("  /mvpexport json: %s", SlashCmdList.MVPEXPORT and "✓" or "✗"))
print(string.format("  /mvpimport json: %s", SlashCmdList.MVPIMPORT and "✓" or "✗"))

-- Summary
print("\n" .. string.rep("=", 70))
local all_ok = (RMS and RMS.DKP and RMS.Export and RMS.Import and json and 
                 type(RMS.Export.ToJSON) == "function")

if all_ok then
    print("✓✓✓ TODO FUNCIONA - Prueba los botones en el addon")
else
    print("✗✗✗ PROBLEMAS DETECTADOS - Ver items con ✗ arriba")
end
print(string.rep("=", 70) .. "\n")
