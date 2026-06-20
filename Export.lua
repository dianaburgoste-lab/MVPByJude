-- MVP Raid Tools -- Export to JSON
-- Exporta datos DKP a formato JSON compatible con EPGP
local RMS = MVPByJude
local Export = {}
RMS.Export = Export

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
-- MAIN EXPORT FUNCTION - Convierte datos DKP a JSON compatible con EPGP
-- =============================================================================

function Export:ToJSON()
    -- Verificar DKP
    if not RMS.DKP or not RMS.DKP.state then
        return nil, "Error: DKP data not loaded"
    end
    
    -- Verificar JSON
    local JSON = GetJSON()
    if not JSON then
        return nil, "Error: LibJSON-1.0 no disponible"
    end
    
    local dkp = RMS.DKP
    local state = dkp.state
    
    -- Build the export structure matching the EPGP JSON format
    local export = {
        version = "2.0",
        loot_history = {},
        log = {},
        participants = {},
        metadata = {
            version = "2.0",
            guild = GetGuildInfo("player") or "Unknown",
            addon = "MVPByJude",
            addon_version = "1.0",
            exported = time(),
            exporter = UnitName("player"),
            export_format = "EPGP_Compatible",
        }
    }
    
    -- 1. BUILD LOG ENTRIES from state.log
    if state.log then
        for _, entry in ipairs(state.log) do
            -- Parse players string to array
            local playersArray = {}
            if entry.players and entry.players ~= "" then
                for playerName in entry.players:gmatch("([^,]+)") do
                    table.insert(playersArray, playerName:match("^%s*(.-)%s*$")) -- trim
                end
            end
            
            -- Create log entry
            local logEntry = {
                event_uid = entry.id or ("mvp-" .. entry.time .. "-" .. math.random(10000)),
                timestamp = entry.time or time(),
                event = "EPAward",
                kind = "EP",
                type = "EPAward",
                amount = entry.delta or 0,
                reason = entry.reason or "",
                master = entry.by or "Unknown",
                
                -- For single targets
                target = #playersArray > 0 and playersArray[1] or "Unknown",
                target_main = #playersArray > 0 and playersArray[1] or "Unknown", -- Could lookup alt->main mapping
                target_class = #playersArray > 0 and self:GetPlayerClass(playersArray[1]) or "UNKNOWN",
                
                -- For multiple targets, store as dict
                players_dict = {},
                
                -- Raid info
                zone = "Unknown",
                boss = "Global",
                raid_id = "unknown-raid",
                
                -- Attendance
                attendance = playersArray,
            }
            
            -- If multiple players, convert target to dict {player: true, ...}
            if #playersArray > 1 then
                for _, pname in ipairs(playersArray) do
                    logEntry.players_dict[pname] = true
                end
                logEntry.target = logEntry.players_dict
                logEntry.target_main = logEntry.players_dict
                logEntry.event = "MassEPAward"
                logEntry.kind = "MASS_EP"
                logEntry.type = "MassEPAward"
            end
            
            table.insert(export.log, logEntry)
        end
    end
    
    -- 2. BUILD PARTICIPANTS from state.standings
    if state.standings then
        for playerName, standing in pairs(state.standings) do
            export.participants[playerName] = {
                ep_current = standing.earned or 0,
                gp_current = standing.spent or 0,
                balance = standing.balance or 0,
                class = self:GetPlayerClass(playerName),
                main = playerName, -- Could lookup if is alt
                player = playerName,
            }
        end
    end
    
    -- 3. ADD ALT INFORMATION to participants
    if state.altIndex and state.altIndex.mainToAlts then
        for mainName, alts in pairs(state.altIndex.mainToAlts) do
            for _, altName in ipairs(alts) do
                if not export.participants[altName] then
                    export.participants[altName] = {
                        ep_current = 0,
                        gp_current = 0,
                        balance = 0,
                        class = self:GetPlayerClass(altName),
                        main = mainName,
                        player = altName,
                    }
                else
                    export.participants[altName].main = mainName
                end
            end
        end
    end
    
    -- 4. SERIALIZE to JSON
    local JSON = GetJSON()
    if not JSON then
        return nil, "Error: LibJSON-1.0 no disponible"
    end
    
    local success, result = pcall(function()
        return JSON.Serialize(export)
    end)
    
    if not success then
        return nil, "Error serializing to JSON: " .. tostring(result)
    end
    
    return result, nil
end

-- =============================================================================
-- EXPORT TO EDITBOX WINDOW
-- =============================================================================

function Export:ExportToEditbox()
    local jsonString, err = self:ToJSON()
    
    if err then
        RMS:Print("|cffff0000Error:|r " .. err)
        return
    end
    
    -- Create or reuse export frame
    if not self.exportFrame then
        self.exportFrame = CreateFrame("Frame", "MVPByJudeExportFrame", UIParent, "UIPanelDialogTemplate")
        self.exportFrame:SetSize(700, 500)
        self.exportFrame:SetPoint("CENTER")
        self.exportFrame:SetClampedToScreen(true)
        self.exportFrame:SetMovable(true)

        if not self.exportFrame.title then
            self.exportFrame.title = self.exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            self.exportFrame.title:SetPoint("TOP", 0, -12)
            self.exportFrame.title:SetTextColor(1, 0.85, 0.5)
        end
        self.exportFrame.title:SetText("MVPByJude - Exportar a JSON")
        
        -- Scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, self.exportFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -30)
        scrollFrame:SetPoint("BOTTOMRIGHT", -32, 90)
        scrollFrame:SetClipsChildren(true)
        scrollFrame:EnableMouse(true)
        scrollFrame:SetFrameLevel(1)
        
        -- Edit box
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(999999)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetAutoFocus(false)
        editBox:EnableMouse(true)
        editBox:SetTextInsets(6, 6, 6, 6)
        editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 8, -8)
        editBox:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -8, 8)
        scrollFrame:SetScrollChild(editBox)
        
        self.exportFrame.editBox = editBox
        
        -- Buttons
        local copyBtn = CreateFrame("Button", nil, self.exportFrame, "UIPanelButtonTemplate")
        copyBtn:SetSize(120, 25)
        copyBtn:SetText("Seleccionar Todo")
        copyBtn:SetPoint("BOTTOMLEFT", 12, 12)
        copyBtn:SetFrameLevel(20)
        copyBtn:SetScript("OnClick", function()
            self.exportFrame.editBox:SetFocus()
            self.exportFrame.editBox:HighlightText(0, -1)
        end)
        
        local closeBtn = CreateFrame("Button", nil, self.exportFrame, "UIPanelButtonTemplate")
        closeBtn:SetSize(100, 25)
        closeBtn:SetText("Cerrar")
        closeBtn:SetPoint("BOTTOMRIGHT", -12, 12)
        closeBtn:SetFrameLevel(20)
        closeBtn:SetScript("OnClick", function()
            self.exportFrame:Hide()
        end)
        
        -- Info text
        local infoText = self.exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoText:SetPoint("BOTTOMLEFT", copyBtn, "TOPRIGHT", 10, 5)
        infoText:SetTextColor(0.5, 0.9, 1)
        infoText:SetText("1. Haz clic 'Seleccionar Todo' | 2. Presiona Ctrl+C para copiar")
    end
    
    self.exportFrame.editBox:SetText(jsonString)
    self.exportFrame.editBox:SetCursorPosition(0)
    self.exportFrame:Show()
    
    RMS:Print("|cff00ff00Exportación completada.|r JSON disponible en ventana emergente.")
    RMS:Print("|cff00ff00Tamaño:|r " .. (#jsonString) .. " caracteres")
end

-- =============================================================================
-- HELPER: Get player class from guild roster
-- =============================================================================

function Export:GetPlayerClass(playerName)
    if not playerName then return "UNKNOWN" end

    -- Usar el cache central de DKP en vez de llamar GetGuildRosterInfo cada vez
    if RMS.DKP and RMS.DKP._rosterCache then
        local cached = RMS.DKP._rosterCache[playerName]
        if cached and cached.class then
            return cached.class
        end
    end

    -- Fallback: buscar en roster en vivo si no está en cache
    local num = GetNumGuildMembers() or 0
    for i = 1, num do
        local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if name and name == playerName then
            return class or "UNKNOWN"
        end
    end
    return "UNKNOWN"
end

-- =============================================================================
-- COPY TO CLIPBOARD (Windows-specific workaround)
-- =============================================================================

function Export:CopyToClipboard(text)
    if not text then
        return false
    end
    
    -- WoW doesn't provide native clipboard access in 3.3.5a
    -- Users must manually copy from the editbox window
    return true
end

-- =============================================================================
-- EXPORT RAW FUNCTION (for scripting)
-- =============================================================================

function Export:GetExportData()
    return self:ToJSON()
end


