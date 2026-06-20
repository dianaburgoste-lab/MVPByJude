-- MVP By Jude -- BOTIN
-- Automatically tracks epic loot drops from bosses and trash.
-- Groups items by source (Boss Name or Trash).
-- Includes DKP billing system.

local RMS = MVPByJude
local M = RMS:RegisterModule("softres", { title = "BOTIN", order = 1 })

-- ---------- Configuration & Safety ----------
local BlizzGetItemInfo = _G.GetItemInfo  -- alias directo para evitar shadowing
local MIN_LOOT_QUALITY = 4  -- 4 = Épico; cambiar a 3 para incluir raros
local SOFTRES_DEBUG = false  -- activar para logs de depuración

local function DebugPrint(...)
    if SOFTRES_DEBUG then
        RMS:Print(...)
    end
end

-- ---------- Data Structure ----------
M.state = {
    loot = {},          -- [sourceName] = { {link="...", player="...", time=..., charged=false}, ... }
    lastBoss = "Trash", -- Current anchor for loot
    lastBossTime = 0,   -- Time when last boss died
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
-- Extrae el ID y calidad de un item link de forma segura
local function SafeGetItemInfoFromLink(link)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    local _, _, quality = BlizzGetItemInfo(link)
    return id, quality
end

-- List of Bosses to track (Simplified for ICC/RS)
local BOSS_IDS = {
    ["Lord Marrowgar"] = true, ["Lord Tuétano"] = true,
    ["Lady Deathwhisper"] = true, ["Lady Susurramuerte"] = true,
    ["Icecrown Gunship Battle"] = true, ["Batalla aérea Corona de Hielo"] = true,
    ["Deathbringer Saurfang"] = true, ["Libramorte Colmillosauro"] = true,
    ["Festergut"] = true, ["Panzachancro"] = true,
    ["Rotface"] = true, ["Carapútrea"] = true,
    ["Professor Putricide"] = true, ["Profesor Putricidio"] = true,
    ["Blood Queen Lana'thel"] = true, ["Reina de Sangre Lana'thel"] = true,
    ["Valithria Dreamwalker"] = true, ["Valithria Caminasueños"] = true,
    ["Sindragosa"] = true,
    ["The Lich King"] = true, ["El Rey Exánime"] = true,
    ["Halion"] = true,
}

local IGNORE_ITEMS = {
    [49426] = true, -- Emblem of Frost
    [47241] = true, -- Emblem of Triumph
    [50444] = true, -- Sack of Frosty Treasures (Weekly)
}

-- ---------- DKP Billing Logic ----------
function M:ChargeDKP(source, index, amount)
    local entry = self.state.loot[source][index]
    if not entry or entry.charged then return end
    
    local dkpMod = RMS:GetModule("dkp")
    if not dkpMod then RMS:Print("Error: Módulo DKP no encontrado.") return end
    
    if not dkpMod:IsOfficer() then
        RMS:Print("Solo los oficiales pueden cobrar DKP.")
        return
    end

    -- Apply the deduction
    dkpMod:Award({entry.player}, -amount, "Botin: " .. (entry.link or "Item"))
    
    -- Send announcement to Guild
    local msg = ("[MVP By Jude] Se cobraron %d DKP a %s por %s."):format(amount, entry.player, entry.link)
    SendChatMessage(msg, "GUILD")
    
    entry.charged = true
    persist()
    self:Refresh()
end

-- ---------- Logic ----------
function M:AddLoot(itemLink, player)

    local id, quality = SafeGetItemInfoFromLink(itemLink)
    if not id then return end
    

    if quality == nil then
        DebugPrint("|cffffa000[SoftRes]|r Item no en caché (quality=nil): %s", itemLink)
        return
    end


    if quality < MIN_LOOT_QUALITY then 
        DebugPrint("|cffaaaaaa[SoftRes]|r Ignorado por calidad (%d < %d): %s", quality, MIN_LOOT_QUALITY, itemLink)
        return 
    end

    if IGNORE_ITEMS[id] then return end

    local source = "Trash / Varios"
    if (GetTime() - M.state.lastBossTime) < 300 then
        source = M.state.lastBoss
    end

    M.state.loot[source] = M.state.loot[source] or {}
    
    -- Avoid duplicates
    for _, entry in ipairs(M.state.loot[source]) do
        if entry.link == itemLink and entry.player == player then return end
    end

    table.insert(M.state.loot[source], {
        link    = itemLink,
        player  = player,
        time    = GetTime(),
        charged = false,
    })
    
    DebugPrint("|cff80ff80[SoftRes]|r Loot agregado: %s para %s", itemLink, player)
    persist()
    self:Refresh()
end

function M:ClearLoot()
    M.state.loot = {}
    M.state.lastBoss = "Trash"
    M.state.lastBossTime = 0
    persist()
    self:Refresh()
    RMS:Print("Historial de BOTÍN limpiado.")
end

function M:MarkLooted(itemLink)
    if not itemLink then return end
    local found = false
    for source, items in pairs(M.state.loot) do
        for i = #items, 1, -1 do
            if items[i].link == itemLink then
                table.remove(items, i)
                found = true
            end
        end
        if #items == 0 then M.state.loot[source] = nil end
    end
    if found then
        persist()
        self:Refresh()
    end
end

-- ---------- Events ----------
M.events = {
    PLAYER_LOGIN = function(self)
        restore()
        self:Refresh()
    end,
    CHAT_MSG_LOOT = function(self, _, msg)
        
        local link = msg:match("(|c%x+|Hitem:.-|h.-|h|r)")
        if not link then return end
        link = link:gsub("%.$", "")

        local player = msg:match("^(.-)%s+recibe botín:")
                    or msg:match("^(.-)%s+obtiene:")
        if not player then
            -- Mensaje propio: "Obtienes botín:" o "Recibes botín:"
            if msg:find("Obtienes botín:") or msg:find("Recibes botín:") or msg:find("obtiene:") then
                player = RMS:PlayerName()
            end
        end

        if player and link then
            self:AddLoot(link, player)
        end
    end,
    COMBAT_LOG_EVENT_UNFILTERED = function(self, event, timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags)
        -- Firma corregida para 3.3.5a
        DebugPrint("CLEU: %s -> %s (dest: %s)", subevent, destName or "nil", destGUID or "nil")
        if subevent == "UNIT_DIED" then
            if BOSS_IDS[destName] then
                M.state.lastBoss = destName
                M.state.lastBossTime = GetTime()
                RMS:Print("|cff00ff00BOTÍN:|r Jefe detectado: " .. destName)
            end
        end
    end,
}

-- ---------- UI ----------
function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "BOTIN - Rastreador y Facturación")
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)

    local clearBtn = Skin:Button(panel, "Limpiar Historial", 140, 24)
    clearBtn:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
    clearBtn:SetScript("OnMouseUp", function() self:ClearLoot() end)

    local desc = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(desc, 11, false); desc:SetTextColor(unpack(C.textDim))
    desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
    desc:SetText("Control de botín y cobro de DKP (60/70 para fragmentos).")

    -- Summary Panel
    local summary = Skin:Panel(panel)
    summary:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -6)
    summary:SetPoint("RIGHT", -8, 0)
    summary:SetHeight(40)
    
    local shardCount = summary:CreateFontString(nil, "OVERLAY")
    Skin:Font(shardCount, 14, true); shardCount:SetTextColor(unpack(C.accent))
    shardCount:SetPoint("LEFT", 12, 0)
    shardCount:SetText("Fragmentos: 0")
    
    local pendingFs = summary:CreateFontString(nil, "OVERLAY")
    Skin:Font(pendingFs, 11, false); pendingFs:SetTextColor(unpack(C.text))
    pendingFs:SetPoint("LEFT", shardCount, "RIGHT", 20, 0)
    pendingFs:SetText("Pendientes de cobro: 0")

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
            if not s.link then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(s.link)
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
            r.link = nil
        else
            r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)

            local _, _, _, _, _, _, _, _, _, itemIcon = BlizzGetItemInfo(data.link)
            r.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.text:SetText(data.link)
            r.text:SetPoint("LEFT", 28, 0)
            r.sub:SetText(data.player or "")
            r.link = data.link
            
            if data.charged then
                r.chargeBtn:SetText("|cff60ff60PAGADO|r")
                r.chargeBtn:Disable()
                r.chargeBtn:Show()
            else
                r.chargeBtn:SetText("Cobrar")
                r.chargeBtn:Enable()
                r.chargeBtn:Show()
                r.chargeBtn:SetScript("OnMouseUp", function()
    
                    showChargeMenu({source = data.source, idx = data.idx})
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
            if val then self:ChargeDKP(data.source, data.idx, val) end
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
    local displayData = {}
    local sources = {}
    for sname in pairs(M.state.loot) do table.insert(sources, sname) end
    table.sort(sources, function(a, b)
        if a == "Trash / Varios" then return false end
        if b == "Trash / Varios" then return true end
        return a < b
    end)

    local totalShards = 0
    local pendingCharges = 0

    for _, sname in ipairs(sources) do
        table.insert(displayData, { isHeader = true, name = sname })
        for idx, entry in ipairs(M.state.loot[sname]) do
            entry.source = sname
            entry.idx = idx
            table.insert(displayData, entry)
            
            -- Count shards (ID 50274)
            if entry.link:find("item:50274") then
                totalShards = totalShards + 1
                if not entry.charged then pendingCharges = pendingCharges + 1 end
            end
        end
    end
    
    self._ui.shardCount:SetText("Fragmentos: " .. totalShards)
    self._ui.pendingFs:SetText("Pendientes de cobro: " .. (pendingCharges > 0 and "|cffff6060" or "|cff60ff60") .. pendingCharges .. "|r")
    
    self._ui.list:SetData(displayData)
end



local function showChargeMenu(data)
    local menu = {
        { text = "Cobrar 60 DKP", func = function() M:ChargeDKP(data.source, data.idx, 60) end },
        { text = "Cobrar 70 DKP", func = function() M:ChargeDKP(data.source, data.idx, 70) end },
        { text = "Otro monto...", func = function()
            StaticPopup_Show("MVP_CHARGE_CUSTOM", nil, nil, data)
        end },
    }
    RMS:ShowMenu(menu)
end
