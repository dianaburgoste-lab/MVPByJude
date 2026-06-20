-- MVP By Jude -- BiS Scan
local RMS = MVPByJude
local M = RMS:RegisterModule("bis", { title = "Escaneo BiS", order = 5 })

local BlizzGetItemInfo = _G.GetItemInfo  -- FIX BUG 2: alias seguro a la API de Blizzard

-- ---------- state ----------
M.peers = {} 

local SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands",
    "Belt", "Legs", "Feet", "Ring1", "Ring2", "Trinket1", "Trinket2",
    "MainHand", "OffHand", "Ranged", "Relic",
} -- [FIXED: FIX-BIS-1]

local SLOT_MAP = {
    ["Head"] = "Cabeza", ["Neck"] = "Cuello", ["Shoulder"] = "Hombros", ["Back"] = "Espalda",
    ["Chest"] = "Pecho", ["Wrist"] = "Muñecas", ["Hands"] = "Manos", ["Belt"] = "Cintura",
    ["Legs"] = "Piernas", ["Feet"] = "Pies", ["Ring1"] = "Anillo 1", ["Ring2"] = "Anillo 2",
    ["Trinket1"] = "Abalorio 1", ["Trinket2"] = "Abalorio 2", ["MainHand"] = "Mano Derecha",
    ["OffHand"] = "Mano Izquierda", ["Ranged"] = "Rango", ["Relic"] = "Reliquia"
} -- [FIXED: FIX-BIS-1]

local SPEC_MAP = {
    ["Sangre"] = "Blood", ["Escarcha"] = "Frost", ["Profano"] = "Unholy",
    ["Equilibrio"] = "Balance", ["Combate_Feral"] = "Feral_Combat", ["Restauración"] = "Restoration",
    ["Bestias"] = "Beast_Mastery", ["Puntería"] = "Marksmanship", ["Supervivencia"] = "Survival",
    ["Arcano"] = "Arcane", ["Fuego"] = "Fire",
    ["Sagrado"] = "Holy", ["Protección"] = "Protection", ["Reprensión"] = "Retribution",
    ["Disciplina"] = "Discipline", ["Sombra"] = "Shadow",
    ["Asesinato"] = "Assassination", ["Combate"] = "Combat", ["Sutileza"] = "Subtlety",
    ["Elemental"] = "Elemental", ["Mejora"] = "Enhancement",
    ["Aflicción"] = "Affliction", ["Demonología"] = "Demonology", ["Destrucción"] = "Destruction",
    ["Armas"] = "Arms", ["Furia"] = "Fury"
}

local OWNED_MARK = "|cff60ff60\226\156\147|r "

local function playerHasItem(id)
    if not id or id <= 1 then return false end
    if GetItemCount and (GetItemCount(id) or 0) > 0 then return true end
    for slot = 0, 19 do
        if GetInventoryItemID("player", slot) == id then return true end
    end
    return false
end

local function warmItem(id)
    if not id or id <= 1 or BlizzGetItemInfo(id) then return false end
    if not RMS._itemQueryTip then
        RMS._itemQueryTip = CreateFrame("GameTooltip", "RMSItemQueryTip", UIParent, "GameTooltipTemplate")
    end
    RMS._itemQueryTip:SetOwner(UIParent, "ANCHOR_NONE")
    RMS._itemQueryTip:SetHyperlink("item:"..id)
    return true
end

local function detectSpec()
    if not GetTalentTabInfo then return nil end
    local best, bestPts = nil, 0  -- FIX BUG 4: 0 como mínimo, no -1
    for tab = 1, 3 do
        local name, _, points = GetTalentTabInfo(tab)
        if name and (points or 0) > bestPts then
            best, bestPts = name, points or 0
        end
    end
    -- FIX BUG 4: Retornar nil si no hay puntos gastados para evitar spec incorrecta
    if not best or bestPts == 0 then return nil end
    local norm = best:gsub("%s+", "_")
    return SPEC_MAP[norm] or norm
end

function M:GetBiSFor(class, spec)
    local out = {}
    local seed = RMS.BiSSeed and RMS.BiSSeed[class] and RMS.BiSSeed[class][spec]
    if seed then
        for slot, ids in pairs(seed) do
            out[slot] = {}
            for _, id in ipairs(ids) do 
                if id and id > 1 then table.insert(out[slot], id) end
            end
        end
    end
    if RMS.charDB.bis and RMS.charDB.bis.overrides then
        for slot, id in pairs(RMS.charDB.bis.overrides) do
            id = tonumber(id)
            if id and id > 1 then
                out[slot] = out[slot] or {}
                local found = nil
                for i, v in ipairs(out[slot]) do if v == id then found = i break end end
                if found then table.remove(out[slot], found) end
                table.insert(out[slot], 1, id)
            end
        end
    end
    return out
end

function M:BroadcastMySpec()
    local _, class = UnitClass("player")
    local spec = detectSpec()
    if not class or not spec then return end
    self.peers[UnitName("player")] = { class = class, spec = spec }
    if RMS.Comm and RMS:InGroup() then
        RMS.Comm:Send("bis", "spec", { class = class, spec = spec })
    end
    if self._ui then self:Refresh() end
end

-- [FIXED: FIX-BIS-3] Movido a OnInit

-- BiS integration: returns a table of [itemID] = true for a given player
function M:GetBiSIDsForPlayer(name)
    local data = self.peers[name]
    if name == UnitName("player") then
        local _, cls = UnitClass("player")
        local spec = detectSpec()
        data = { class = cls, spec = spec }
    end
    if not data or not data.class or not data.spec then return nil end
    
    local list = self:GetBiSFor(data.class, data.spec)
    local ids = {}
    for slot, itemIDs in pairs(list) do
        for _, id in ipairs(itemIDs) do
            if id and id > 1 then ids[id] = true end
        end
    end
    return ids
end

-- [FIXED: FIX-BIS-3] Movido a OnInit

function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "Escaneo de Equipo Ideal (BiS)")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)

    local meLabel = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(meLabel, 12, true)
    meLabel:SetTextColor(unpack(C.text))
    meLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -8)

    local rebroadcastBtn = Skin:Button(panel, "Re-detectar y Anunciar", 180, 22)
    rebroadcastBtn:SetPoint("LEFT", meLabel, "RIGHT", 12, 0)
    rebroadcastBtn:SetScript("OnMouseUp", function() self:BroadcastMySpec() end)

    local mineHdr = Skin:Header(panel, "Tu Lista BiS (ICC 25H)")
    mineHdr:SetPoint("TOPLEFT", meLabel, "BOTTOMLEFT", 0, -10)
    mineHdr:SetWidth(360)

    local function buildSlotRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(20)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg
        local slot = r:CreateFontString(nil, "OVERLAY"); Skin:Font(slot, 11, true); slot:SetPoint("LEFT", 6, 0); slot:SetWidth(70); r.slot = slot
        local altsBtn = CreateFrame("Button", nil, r); altsBtn:SetSize(60, 18); altsBtn:SetPoint("RIGHT", -4, 0)
        local altsFs = altsBtn:CreateFontString(nil, "OVERLAY"); Skin:Font(altsFs, 10, false); altsFs:SetTextColor(unpack(C.accent)); altsFs:SetAllPoints(); altsFs:SetJustifyH("RIGHT"); altsBtn.text = altsFs; altsBtn:Hide(); r.altsBtn = altsBtn
        local hover = CreateFrame("Button", nil, r); hover:SetPoint("TOPLEFT", slot, "TOPRIGHT", 4, 0); hover:SetPoint("BOTTOMRIGHT", altsBtn, "BOTTOMLEFT", -4, 0); r.hover = hover
        local item = hover:CreateFontString(nil, "OVERLAY"); Skin:Font(item, 11, false); item:SetPoint("LEFT", 0, 0); item:SetPoint("RIGHT", 0, 0); item:SetJustifyH("LEFT"); item:SetWordWrap(false); item:SetNonSpaceWrap(false); r.item = item
        hover:SetScript("OnEnter", function(s) if not s._id then return end GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:"..s._id); GameTooltip:Show() end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end
    local function updSlotRow(r, item, idx, alt)
        if not item then return end
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
        r.slot:SetText(SLOT_MAP[item.slot] or item.slot)
        if item.ids and #item.ids > 0 then
            local id = item.ids[1]; r.hover._id = id; local _, link = BlizzGetItemInfo(id); local prefix = playerHasItem(id) and OWNED_MARK or ""
            r.item:SetText(prefix..(link or ("ID:"..id)))
            if #item.ids > 1 then r.altsBtn:Show(); r.altsBtn.text:SetText("+"..(#item.ids - 1).." alt"); r.altsBtn:SetScript("OnMouseUp", function(s) M:_ShowAltsPopup(s, item.slot, item.ids) end)
            else r.altsBtn:Hide() end
        else r.hover._id = nil; r.item:SetText("|cff666666(vacio)|r"); r.altsBtn:Hide() end
    end
    local mineList = Skin:ScrollList(panel, 20, buildSlotRow, updSlotRow)
    mineList:SetPoint("TOPLEFT", mineHdr, "BOTTOMLEFT", 0, -2); mineList:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8); mineList:SetWidth(360)

    local peersHdr = Skin:Header(panel, "Roster de Banda (Ramas detectadas)")
    peersHdr:SetPoint("TOPLEFT", mineHdr, "TOPRIGHT", 8, 0); peersHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

    local function buildPeerRow(parent)
        local r = CreateFrame("Frame", nil, parent); r:SetHeight(20)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg
        local who = r:CreateFontString(nil, "OVERLAY"); Skin:Font(who, 11, true); who:SetPoint("LEFT", 6, 0); r.who = who
        local sp  = r:CreateFontString(nil, "OVERLAY"); Skin:Font(sp,  11, false); sp:SetPoint("RIGHT", -6, 0); sp:SetTextColor(unpack(C.textDim)); r.sp = sp
        return r
    end
    local function updPeerRow(r, item, idx, alt)
        if not item then return end
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
        local c = RAID_CLASS_COLORS[item.class] or {r=1,g=1,b=1}
        r.who:SetText(("|cff%02x%02x%02x%s|r"):format(c.r*255, c.g*255, c.b*255, item.player))
        r.sp:SetText((item.spec or "??").."  "..item.class)
    end
    local peersList = Skin:ScrollList(panel, 20, buildPeerRow, updPeerRow)
    peersList:SetPoint("TOPLEFT", peersHdr, "BOTTOMLEFT", 0, -2); peersList:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8); peersList:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

    self._ui = { panel = panel, meLabel = meLabel, mineList = mineList, peersList = peersList }
    self:Refresh()
    return panel
end

function M:Refresh()
    if not self._ui then return end
    local _, cls = UnitClass("player")
    local spec = detectSpec()
    if cls and spec then self._ui.meLabel:SetText(("Tu rama: %s %s"):format(cls, spec))
    else self._ui.meLabel:SetText("Tu rama: |cff999999(detectando...)|r") end

    local rows = {}
    if cls and spec then
        local list = self:GetBiSFor(cls, spec)
        for _, slot in ipairs(SLOTS) do
            local ids = list[slot] or {}
            for _, id in ipairs(ids) do warmItem(id) end
            rows[#rows+1] = { slot = slot, ids = ids }
        end
    end
    self._ui.mineList:SetData(rows)

    local peers = {}
    for p, i in pairs(self.peers) do table.insert(peers, { player = p, class = i.class, spec = i.spec }) end
    table.sort(peers, function(a,b) return a.player < b.player end)
    self._ui.peersList:SetData(peers)
end

function M:_ShowAltsPopup(anchor, slot, ids)
    local Skin = RMS.Skin; local C = Skin.COLOR
    if self._altsPopup and self._altsPopup:IsShown() then self._altsPopup:Hide() return end
    if not self._altsPopup then
        local f = CreateFrame("Frame", "MVPByJudeBiSAltsPopup", UIParent); f:SetFrameStrata("DIALOG")
        Skin:SetBackdrop(f, C.bgMain, C.accent); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "MVPByJudeBiSAltsPopup"); f._rows = {}
        f.title = f:CreateFontString(nil, "OVERLAY"); Skin:Font(f.title, 12, true); f.title:SetTextColor(unpack(C.accent)); f.title:SetPoint("TOPLEFT", 8, -6)
        local c = Skin:CloseButton(f); c:SetSize(16,16); c:SetPoint("TOPRIGHT", -3,-3); c:SetScript("OnClick", function() f:Hide() end)
        self._altsPopup = f
    end
    local f = self._altsPopup; f:ClearAllPoints(); f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    f:SetSize(380, 26 + #ids*22); f.title:SetText(("Opciones para %s"):format(SLOT_MAP[slot] or slot))
    for i = 1, #ids do
        local r = f._rows[i]
        if not r then
            r = CreateFrame("Frame", nil, f); r:SetSize(364, 20); r:EnableMouse(true)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetTexture(Skin.TEX_WHITE)
            r.rank = r:CreateFontString(nil, "OVERLAY"); Skin:Font(r.rank, 10, false); r.rank:SetPoint("LEFT", 6, 0); r.rank:SetWidth(28)
            r.name = r:CreateFontString(nil, "OVERLAY"); Skin:Font(r.name, 11, false); r.name:SetPoint("LEFT", r.rank, "RIGHT", 4, 0); r.name:SetPoint("RIGHT", -8, 0); r.name:SetJustifyH("LEFT")
            r:SetScript("OnEnter", function(s) if s._id then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:"..s._id); GameTooltip:Show() end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnMouseUp", function(s)
                if s._id then
                    -- [FIXED: FIX-BIS-2]
                    RMS.charDB.bis = RMS.charDB.bis or {}
                    RMS.charDB.bis.overrides = RMS.charDB.bis.overrides or {}
                    RMS.charDB.bis.overrides[slot] = s._id
                    M:Refresh()
                    f:Hide()
                end
            end)
            f._rows[i] = r
        end
        local id = ids[i]; r._id = id; warmItem(id); r:SetPoint("TOPLEFT", 8, -22-(i-1)*22); r.bg:SetVertexColor(i%2==0 and 0.1 or 0.13, 0.1, 0.13, 0.5)
        r.rank:SetText(i==1 and "BiS" or "alt"..(i-1))
        local _, link = BlizzGetItemInfo(id); r.name:SetText((playerHasItem(id) and OWNED_MARK or "")..(link or "ID:"..id))
        r:Show()
    end
    for i = #ids+1, #f._rows do f._rows[i]:Hide() end
    f:Show()
end

function M:OnSlash(arg) RMS.UI:Show("bis") end

function M:OnInit()
    -- [FIXED: FIX-BIS-3]
    RMS.charDB.bis = RMS.charDB.bis or {}
    RMS.charDB.bis.overrides = RMS.charDB.bis.overrides or {}
    for k, v in pairs(RMS.charDB.bis.overrides) do
        if not tonumber(v) or tonumber(v) < 1 then
            RMS.charDB.bis.overrides[k] = nil
        end
    end

    -- Registrar handlers de Comm dentro de OnInit para mayor seguridad
    RMS.Comm:On("bis", "spec", function(p, sender)
        if not p.class or not p.spec then return end
        M.peers[sender] = { class = p.class, spec = p.spec }
        if M._ui then M:Refresh() end
    end)
    RMS.Comm:On("bis", "specreq", function(_, sender)
        if sender == UnitName("player") then return end
        M:BroadcastMySpec()
    end)
end
