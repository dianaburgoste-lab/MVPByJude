-- MVP Raid Tools -- Import from JSON
-- Importa datos DKP desde formato JSON compatible con EPGP
local RMS = MVPByJude
local Import = {}
RMS.Import = Import

-- Lazy load JSON para evitar errores de carga
local function GetJSON()
    if LibStub then
        local json = LibStub("LibJSON-1.0")
        if json then return json end
    end
    if _G.LibJSON then
        return _G.LibJSON
    end
    return nil
end

-- =============================================================================
-- MAIN IMPORT FUNCTION
-- =============================================================================

function Import:FromJSON(jsonString)
    if not jsonString or type(jsonString) ~= "string" then
        return false, "Invalid JSON string"
    end
    
    if not RMS.DKP or not RMS.DKP.state then
        return false, "DKP module not loaded"
    end
    
    local dkp = RMS.DKP
    local state = dkp.state
    
    -- Get JSON library
    local JSON = GetJSON()
    if not JSON then
        return false, "Error: LibJSON-1.0 no disponible"
    end
    
    -- Parse JSON
    local success, data = pcall(function()
        return JSON.Deserialize(jsonString)
    end)
    
    if not success then
        return false, "Error parsing JSON: " .. tostring(data)
    end
    
    if type(data) ~= "table" then
        return false, "JSON must be an object"
    end
    
    -- Validate schema
    if (not data.log or type(data.log) ~= "table") and 
       (not data.participants or type(data.participants) ~= "table") then
        return false, "Invalid JSON schema: missing 'log' or 'participants'"
    end
    
    -- Initialize state if needed
    if not state.log then state.log = {} end
    if not state.standings then state.standings = {} end
    if not state.altIndex then state.altIndex = {mainToAlts = {}} end
    
    local importedCount = 0
    local skippedCount = 0
    local errorCount = 0
    
    -- 1. IMPORT LOG ENTRIES
    if data.log and type(data.log) == "table" then
        for _, logEntry in ipairs(data.log) do
            if type(logEntry) ~= "table" then
                errorCount = errorCount + 1
                goto continue_log
            end
            
            -- Safely extract fields with defaults
            local entry = {
                id = logEntry.event_uid or ("imported-" .. (logEntry.timestamp or time())),
                time = logEntry.timestamp or time(),
                by = logEntry.master or "Imported",
                delta = tonumber(logEntry.amount) or 0,
                reason = tostring(logEntry.reason or logEntry.event or "Imported"),
                players = self:ParseTargets(logEntry.target, logEntry.target_main),
            }
            
            -- Check for duplicates (same uid or very close timestamp with same master)
            local isDuplicate = false
            for _, existing in ipairs(state.log) do
                if existing.id == entry.id then
                    isDuplicate = true
                    skippedCount = skippedCount + 1
                    break
                end
                -- Also check for near-duplicates: same time, master, delta, and players
                if existing.time == entry.time and 
                   existing.by == entry.by and 
                   existing.delta == entry.delta and
                   existing.players == entry.players then
                    isDuplicate = true
                    skippedCount = skippedCount + 1
                    break
                end
            end
            
            if not isDuplicate and entry.players ~= "" then
                table.insert(state.log, entry)
                importedCount = importedCount + 1
            end
            
            ::continue_log::
        end
    end
    
    -- 2. IMPORT PARTICIPANTS (update standings)
    if data.participants and type(data.participants) == "table" then
        for playerName, partData in pairs(data.participants) do
            if type(partData) == "table" then
                local ep = tonumber(partData.ep_current) or 0
                local gp = tonumber(partData.gp_current) or 0
                local main = tostring(partData.main or playerName)
                
                -- Update standings
                state.standings[playerName] = {
                    balance = ep - gp,
                    earned = ep,
                    spent = gp,
                }
                
                -- Register alt relationship if different from main
                if main ~= playerName then
                    if not state.altIndex.mainToAlts[main] then
                        state.altIndex.mainToAlts[main] = {}
                    end
                    -- Check if already in list
                    local found = false
                    for _, alt in ipairs(state.altIndex.mainToAlts[main]) do
                        if alt == playerName then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(state.altIndex.mainToAlts[main], playerName)
                    end
                end
            end
        end
    end
    
    -- Mark as synced
    state.altIndexSeeded = true
    
    -- Return multiple values: success, imported, skipped
    if importedCount == 0 and skippedCount == 0 and errorCount > 0 then
        return false, "No valid entries found in JSON"
    end
    
    return true, importedCount, skippedCount
end

-- =============================================================================
-- HELPER: Parse targets from JSON (handles string, array, or dict)
-- =============================================================================

function Import:ParseTargets(target, target_main)
    if not target then
        return ""
    end
    
    local players = {}
    
    -- If target is a string
    if type(target) == "string" then
        if target ~= "" then
            return target
        end
    -- If target is a table (could be array or dict)
    elseif type(target) == "table" then
        -- Check if it's a dict {name: true, ...}
        local hasStringKeys = false
        for k, v in pairs(target) do
            if type(k) == "string" then
                hasStringKeys = true
                if v == true or v == 1 then
                    table.insert(players, k)
                end
            end
        end
        
        -- If no string keys found, assume array
        if #players == 0 and not hasStringKeys then
            for _, name in ipairs(target) do
                if type(name) == "string" and name ~= "" then
                    table.insert(players, name)
                end
            end
        end
    end
    
    if #players > 0 then
        return table.concat(players, ",")
    end
    
    -- Fallback to target_main if available
    if target_main then
        if type(target_main) == "string" then
            return target_main
        elseif type(target_main) == "table" then
            players = {}
            for k, v in pairs(target_main) do
                if type(k) == "string" and (v == true or v == 1) then
                    table.insert(players, k)
                end
            end
            for _, name in ipairs(target_main) do
                if type(name) == "string" and name ~= "" then
                    table.insert(players, name)
                end
            end
            return table.concat(players, ",")
        end
    end
    
    return ""
end

-- =============================================================================
-- SHOW IMPORT DIALOG
-- =============================================================================

function Import:ShowImportDialog()
    if self.importFrame then
        self.importFrame:Hide()
        self.importFrame = nil
    end

    self.importFrame = CreateFrame("Frame", nil, UIParent)
    self.importFrame:SetSize(700, 500)
    self.importFrame:SetPoint("CENTER")
    self.importFrame:SetClampedToScreen(true)
    self.importFrame:SetMovable(true)
    self.importFrame:EnableMouse(true)
    self.importFrame:RegisterForDrag("LeftButton")
    self.importFrame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    self.importFrame:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
    self.importFrame:SetToplevel(true)
    self.importFrame:SetFrameStrata("DIALOG")

    if self.importFrame.SetBackdrop then
        self.importFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        self.importFrame:SetBackdropColor(0, 0, 0, 0.85)
        self.importFrame:SetBackdropBorderColor(1, 1, 1, 1)
    end

    self.importFrame.title = self.importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.importFrame.title:SetPoint("TOP", 0, -15)
    self.importFrame.title:SetTextColor(1, 0.85, 0.5)
    self.importFrame.title:SetText("MVPByJude - Importar desde JSON")

    local closeBtn = CreateFrame("Button", nil, self.importFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetFrameLevel(40)
    closeBtn:SetScript("OnClick", function()
        self.importFrame:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, self.importFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -12, 90)
    scrollFrame:SetClipsChildren(true)
    scrollFrame:EnableMouse(true)
    scrollFrame:SetFrameLevel(1)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(999999)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetJustifyH("LEFT")
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 8, -8)
    editBox:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -8, 8)
    if editBox.SetBackdrop then
        editBox:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
        editBox:SetBackdropColor(0, 0, 0, 0.6)
        editBox:SetBackdropBorderColor(0.7, 0.7, 0.7, 0.9)
    end
    scrollFrame:SetScrollChild(editBox)
    self.importFrame.editBox = editBox

    local importBtn = CreateFrame("Button", nil, self.importFrame, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 25)
    importBtn:SetText("Importar")
    importBtn:SetPoint("BOTTOMLEFT", 12, 12)
    importBtn:SetFrameLevel(40)
    importBtn:SetScript("OnClick", function()
        Import:ExecuteImport(self.importFrame.editBox:GetText())
    end)

    local cancelBtn = CreateFrame("Button", nil, self.importFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetText("Cancelar")
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelBtn:SetFrameLevel(40)
    cancelBtn:SetScript("OnClick", function()
        self.importFrame:Hide()
    end)

    local infoText = self.importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOMLEFT", importBtn, "TOPRIGHT", 10, 5)
    infoText:SetTextColor(0.8, 0.8, 0.8)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("Pega el código JSON abajo y pulsa 'Procesar'.\nSobrescribirá los DKP actuales y las notas de oficial.")

    self.importFrame.editBox:SetText("")
    self.importFrame.editBox:SetFocus()
    self.importFrame:Show()
end

-- =============================================================================
-- EXECUTE IMPORT
-- =============================================================================

function Import:ExecuteImport(jsonText)
    if not jsonText or jsonText:len() == 0 then
        RMS:Print("|cffff0000Error:|r JSON vacío. Pega el contenido JSON completo.")
        return
    end
    
    local success, importCount, skippedCount = self:FromJSON(jsonText)
    
    if not success then
        RMS:Print("|cffff0000Error:|r " .. tostring(importCount))
        return
    end
    
    self.importFrame:Hide()
    
    local msg = "|cff00ff00Importación completada:|r\n"
    msg = msg .. "  • Importadas: " .. importCount .. " entradas\n"
    msg = msg .. "  • Omitidas: " .. skippedCount .. " duplicadas"
    
    RMS:Print(msg)
    
    -- Refresh UI if available
    if RMS.DKP and RMS.DKP.Refresh then
        RMS.DKP:Refresh()
    end
    
    -- Mark data as modified
    if RMS.db then
        RMS.db.lastImport = time()
    end
end

-- =============================================================================
-- BATCH IMPORT (for scripts)
-- =============================================================================

function Import:BatchImportMultiple(jsonArray)
    if type(jsonArray) ~= "table" then
        return false, "Expected table of JSON strings"
    end
    
    local totalImported = 0
    local totalSkipped = 0
    
    for _, jsonString in ipairs(jsonArray) do
        if type(jsonString) == "string" then
            local success, imported, skipped = self:FromJSON(jsonString)
            if success then
                totalImported = totalImported + imported
                totalSkipped = totalSkipped + skipped
            end
        end
    end
    
    return true, totalImported, totalSkipped
end

-- =============================================================================
-- REGISTER SLASH COMMAND
-- =============================================================================

SLASH_MVPIMPORT1 = "/mvpimport"
SlashCmdList.MVPIMPORT = function(args)
    if args:lower() == "json" then
        Import:ShowImportDialog()
    else
        RMS:Print("|cff00ff00Comandos disponibles:|r")
        RMS:Print("/mvpimport json - Importar datos desde JSON")
    end
end

