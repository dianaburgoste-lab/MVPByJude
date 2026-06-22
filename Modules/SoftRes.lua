-- MVP By Jude -- BOTIN
-- Displays loot history from Method Raid Tools (MRT).
-- When MRT is available, BOTIN uses its Loot History as the source of truth.
-- Includes DKP billing system for charged items.

local RMS = MVPByJude
local M = RMS:RegisterModule("softres", { title = "BOTIN", order = 1 })

-- ---------- Configuration ----------
local BlizzGetItemInfo = _G.GetItemInfo  -- alias directo para evitar shadowing
local SOFTRES_DEBUG = false  -- activar para logs de depuración

local function DebugPrint(...)
    if SOFTRES_DEBUG then
        RMS:Print(...)
    end
end

-- ---------- Data Structure ----------
-- M.state now only tracks which items have been charged (for UI status).
-- Loot entries come from RMS.MRT:GetRecentLoot().
M.state = {
    charged = {},  -- [itemLink] = true (items we've already charged DKP for)
}

local function persist()
    RMS.db.softresState = M.state
end
local function restore()
    if RMS.db.softresState then
        for k, v in pairs(RMS.db.softresState) do M.state[k] = v end
    end
end

-- ---------- Helpers ----------
local function SafeGetItemInfoFromLink(link)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    local _, _, quality = BlizzGetItemInfo(link)
    return id, quality
end

-- ---------- DKP Billing Logic ----------
function M:ChargeDKP(player, itemLink, amount)
    if not player or not itemLink then return end
    
    local dkpMod = RMS:GetModule("dkp")
    if not dkpMod then 
        RMS:Print("Error: Módulo DKP no encontrado.")
        return 
    end
    
    if not dkpMod:IsOfficer() then
        RMS:Print("Solo los oficiales pueden cobrar DKP.")
        return
    end

    -- Mark as charged to avoid double-charging in UI
    M.state.charged[itemLink] = true
    persist()

    -- Apply the deduction
    dkpMod:Award({player}, -amount, "BOTIN: " .. (itemLink or "Item"))
    
    -- Send announcement to Guild
    local msg = ("[MVP By Jude] Se cobraron %d DKP a %s por %s."):format(amount, player, itemLink)
    SendChatMessage(msg, "GUILD")
    
    self:Refresh()
end

-- ---------- Events ----------
-- [DEPRECATED] BOTIN no longer tracks loot manually; MRT handles that.
M.events = {
    PLAYER_LOGIN = function(self)
        restore()
        self:Refresh()
    end,
}

-- ---------- UI ----------
function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "BOTIN - Historial de Raid (MRT)")
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)

    local desc = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(desc, 11, false); desc:SetTextColor(unpack(C.textDim))
    desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
    desc:SetText("Historial de botín de MRT con control de cobro DKP (60/70 para fragmentos).")

    -- Check if MRT is available
    if not RMS.MRT:IsAvailable() then
        local noMRT = panel:CreateFontString(nil, "OVERLAY")
        Skin:Font(noMRT, 12, false); noMRT:SetTextColor(1, 0.5, 0)
        noMRT:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
        noMRT:SetText("|cffff9900MRT no está cargado.|r Instala Method Raid Tools para ver el historial de botín avanzado.")
        return panel
    end

    -- Summary Panel
    local summary = Skin:Panel(panel)
    summary:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -6)
    summary:SetPoint("RIGHT", -8, 0)
    summary:SetHeight(40)
    
    local shardCount = summary:CreateFontString(nil, "OVERLAY")
    Skin:Font(shardCount, 14, true); shardCount:SetTextColor(unpack(C.accent))
    shardCount:SetPoint("LEFT", 12, 0)
    shardCount:SetText("Items: 0")
    
    local pendingFs = summary:CreateFontString(nil, "OVERLAY")
    Skin:Font(pendingFs, 11, false); pendingFs:SetTextColor(unpack(C.text))
    pendingFs:SetPoint("LEFT", shardCount, "RIGHT", 20, 0)
    pendingFs:SetText("Pendientes: 0")

    local function buildRow(parent)
        local r = CreateFrame("Button", nil, parent)
        r:SetHeight(22)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg
        local icon = r:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18); icon:SetPoint("LEFT", 4, 0); r.icon = icon
        local text = r:CreateFontString(nil, "OVERLAY")
        Skin:Font(text, 12, false); text:SetPoint("LEFT", icon, "RIGHT", 6, 0); r.text = text
        local sub = r:CreateFontString(nil, "OVERLAY")
        Skin:Font(sub, 10, false); sub:SetTextColor(unpack(C.textDim)); sub:SetPoint("RIGHT", -100, 0); r.sub = sub
        
        -- Charge button
        local chargeBtn = Skin:Button(r, "Cobrar", 70, 18)
        chargeBtn:SetPoint("RIGHT", -4, 0)
        r.chargeBtn = chargeBtn

        r:SetScript("OnEnter", function(s)
            if not s.itemLink then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(s.itemLink)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end

    local function updateRow(r, data, idx, alt)
        if not data then return end
        if data.isHeader then
            r.bg:SetVertexColor(0.2, 0.2, 0.22, 0.9)
            r.icon:SetTexture(nil)
            r.text:SetText("|cffffd070" .. data.name .. "|r")
            r.text:SetPoint("LEFT", 10, 0)
            r.sub:SetText("")
            r.chargeBtn:Hide()
            r.itemLink = nil
        else
            r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)

            local _, _, _, _, _, _, _, _, _, itemIcon = BlizzGetItemInfo(data.itemLink)
            r.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.text:SetText(data.itemLink)
            r.text:SetPoint("LEFT", 28, 0)
            r.sub:SetText((data.player or "?") .. " @ " .. (data.difficultyName or "?"))
            r.itemLink = data.itemLink
            
            if data.charged then
                r.chargeBtn:SetText("|cff60ff60PAGADO|r")
                r.chargeBtn:Disable()
                r.chargeBtn:Show()
            else
                r.chargeBtn:SetText("Cobrar")
                r.chargeBtn:Enable()
                r.chargeBtn:Show()
                r.chargeBtn:SetScript("OnMouseUp", function()
                    local menu = {
                        { text = "Cobrar 60 DKP", func = function() M:ChargeDKP(data.player, data.itemLink, 60) end },
                        { text = "Cobrar 70 DKP", func = function() M:ChargeDKP(data.player, data.itemLink, 70) end },
                        { text = "Otro monto...", func = function()
                            StaticPopup_Show("MVP_CHARGE_CUSTOM", nil, nil, {player = data.player, itemLink = data.itemLink})
                        end },
                    }
                    RMS:ShowMenu(menu)
                end)
            end
        end
    end

    local list = Skin:ScrollList(panel, 22, buildRow, updateRow)
    list:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Custom charge popup
    StaticPopupDialogs["MVP_CHARGE_CUSTOM"] = {
        text = "Ingresar monto de DKP a cobrar por el ítem:",
        button1 = "Aceptar",
        button2 = "Cancelar",
        hasEditBox = true,
        OnAccept = function(s, data)
            local val = tonumber(s.editBox:GetText())
            if val then M:ChargeDKP(data.player, data.itemLink, val) end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    self._ui = { list = list, shardCount = shardCount, pendingFs = pendingFs }
    self:Refresh()
    return panel
end

function M:Refresh()
    if not self._ui then return end
    if not RMS.MRT:IsAvailable() then return end
    
    local history = RMS.MRT:GetRecentLoot(4)
    local displayData = {}
    local sources = {}
    
    -- Group by instance/boss
    local grouped = {}
    for _, entry in ipairs(history) do
        local key = (entry.instance ~= "" and entry.instance or entry.boss ~= "" and entry.boss or "Unknown")
        if not grouped[key] then
            grouped[key] = {}
        end
        table.insert(grouped[key], entry)
    end
    
    -- Build display data with headers
    for key in pairs(grouped) do
        table.insert(sources, key)
    end
    table.sort(sources, function(a, b)
        return a < b
    end)
    
    local totalShards = 0
    local pendingCharges = 0
    
    for _, source in ipairs(sources) do
        -- Add header
        table.insert(displayData, { isHeader = true, name = source })
        
        -- Add entries for this source
        for _, entry in ipairs(grouped[source]) do
            local itemLink = entry.items[1] and entry.items[1].link or ""
            local isCharged = M.state.charged[itemLink] == true
            
            table.insert(displayData, {
                itemLink = itemLink,
                player = entry.player,
                difficultyName = entry.difficultyName or "",
                charged = isCharged,
                timestamp = entry.time,
            })
            
            -- Count shards (ID 50274 or similar epic items)
            if itemLink:find("item:50274") then
                totalShards = totalShards + 1
                if not isCharged then
                    pendingCharges = pendingCharges + 1
                end
            elseif not isCharged then
                pendingCharges = pendingCharges + 1
            end
        end
    end
    
    self._ui.shardCount:SetText("Items: " .. #history)
    self._ui.pendingFs:SetText("Pendientes: " .. (pendingCharges > 0 and "|cffff6060" or "|cff60ff60") .. pendingCharges .. "|r")
    
    self._ui.list:SetData(displayData)
end

