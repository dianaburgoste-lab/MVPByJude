-- MVP By Jude -- Advertising (v3.1)
-- Localized and Enhanced for Comunidad Naer
local RMS = MVPByJude
local M = RMS:RegisterModule("advertising", { title = "Anuncios", order = 6 })

-- ---------- defaults ----------
local DEFAULTS = {
    raidName    = "ICC 25",
    runType     = "Dados",
    minGS       = "6.3",
    classes     = "Only Picaro cazador mago chaman heal Cazador Demon", 
    discord     = "-Expe-DC-DBM- F.R.",
    achievement = "La caída del Rey Exánime (25)", -- Logro específico
    notes       = "mvp", -- Keyword para Autoinvitarse
    customMsg   = "",      
    template    = "auto",  
    interval    = 90,      
    channels    = {},      
    log         = {},
}

local RUN_TYPES = {
    "Dados", "Subasta Oro", "DKP", "Loot Council", "Botín Libre",
}

local ACHIEVEMENT_LIST = {
    { tier = "Ciudadela de la Corona de Hielo", entries = {
        { 4530, "Asalto a la Ciudadela (10)" }, { 4604, "Asalto a la Ciudadela (25)" },
        { 4531, "Los Talleres de la Peste (10)" }, { 4605, "Los Talleres de la Peste (25)" },
        { 4532, "La Sala Carmesí (10)" }, { 4606, "La Sala Carmesí (25)" },
        { 4533, "Las Salas de Ala de Escarcha (10)" }, { 4607, "Las Salas de Ala de Escarcha (25)" },
        { 4534, "La caída del Rey Exánime (10)" }, { 4608, "La caída del Rey Exánime (25)" },
        { 4583, "Perdición del Rey Caído (LK 10 HC)" }, { 4584, "La Luz del Alba (LK 25 HC)" },
    }},
    { tier = "Sagrario Rubí", entries = {
        { 4818, "El Destructor Crepuscular (10)" }, { 4817, "El Destructor Crepuscular (25)" },
    }},
}

local MIN_INTERVAL = 30

-- ---------- state ----------
M.cfg     = nil       
M.running = false
M.lastSentAt = 0

function M:OnInit()
    RMS.db.advertising = RMS.db.advertising or {}
    for k, v in pairs(DEFAULTS) do
        if RMS.db.advertising[k] == nil then
            if type(v) == "table" then RMS.db.advertising[k] = {} else RMS.db.advertising[k] = v end
        end
    end
    self.cfg = RMS.db.advertising
end

function M:GetAvailableChannels()
    local out = {}
    if GetGuildInfo("player") then out[#out+1] = { slot = "GUILD", id = 0, name = "HERMANDAD (/g)" } end
    for slot = 1, 10 do
        local id, name = GetChannelName(slot)
        if id and id > 0 and name then out[#out+1] = { slot = slot, id = id, name = name } end
    end
    return out
end

function M:BuildMessage()
    if self.cfg.template == "custom" and self.cfg.customMsg ~= "" then return self.cfg.customMsg end
    
    local parts = {}
    local raid = (self.cfg.raidName or "") ~= "" and ("{RT8} "..self.cfg.raidName.."{RT5}") or ""
    local loot = (self.cfg.runType or "") ~= "" and ("("..self.cfg.runType..")") or ""
    local gs   = (self.cfg.minGS or "") ~= "" and ("Gs Min."..self.cfg.minGS) or ""
    local cls  = (self.cfg.classes or "")
    local dc   = (self.cfg.discord or "")
    local inv  = (self.cfg.notes or "") ~= "" and ("Susurrar '"..self.cfg.notes.."'") or ""
    local ach  = (self.cfg.achievement or "")

    local msg = "@everyone " .. raid
    if loot ~= "" then msg = msg .. " " .. loot end
    if gs ~= ""   then msg = msg .. " " .. gs end
    if cls ~= ""  then msg = msg .. " " .. cls end
    if dc ~= ""   then msg = msg .. " " .. dc end
    if inv ~= ""  then msg = msg .. " " .. inv end
    if ach ~= ""  then msg = msg .. " " .. ach end
    
    return msg .. " {RT7}"
end

function M:SendOnce()
    local msg = self:BuildMessage()
    if not msg or msg == "" then return end
    local sent = {}
    if self.cfg.channels["GUILD"] then SendChatMessage(msg, "GUILD"); sent[#sent+1] = "Hermandad" end
    for slot, on in pairs(self.cfg.channels) do
        if on and tonumber(slot) then
            local id = GetChannelName(slot)
            if id and id > 0 then SendChatMessage(msg, "CHANNEL", nil, slot); sent[#sent+1] = "Ch"..slot end
        end
    end
    if #sent > 0 then
        table.insert(self.cfg.log, 1, { time = time(), msg = msg, channels = table.concat(sent, ", ") })
        if #self.cfg.log > 50 then table.remove(self.cfg.log) end
        self.lastSentAt = GetTime()
    end
    self:Refresh()
end

-- ---------- Auto-Invite Logic ----------
M.events = {
    CHAT_MSG_WHISPER = function(self, msg, sender)
        if not self.running then return end
        local keyword = (self.cfg.notes or ""):lower()
        if keyword ~= "" and msg:lower():find(keyword, 1, true) then InviteUnit(sender) end
    end
}

local advTicker = CreateFrame("Frame") -- [FIXED: FIX-ADV-1]
advTicker:Hide()
advTicker:SetScript("OnUpdate", function()
    if not M.running then return end
    if (GetTime() - M.lastSentAt) >= (tonumber(M.cfg.interval) or 90) then M:SendOnce() end
end)

function M:Start()
    self.running = true; self.lastSentAt = 0; advTicker:Show() -- [FIXED: FIX-ADV-1]
    RMS:Print("Anuncios INICIADOS. Palabra clave: '%s'", self.cfg.notes); self:Refresh()
end

function M:Stop()
    self.running = false; advTicker:Hide() -- [FIXED: FIX-ADV-1]
    RMS:Print("Anuncios DETENIDOS."); self:Refresh()
end

-- ---------- UI ----------
function M:BuildUI(parent)
    local Skin = RMS.Skin; local C = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)
    local header = Skin:Header(panel, "Anuncios de Banda + Autoinvitarse")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)
    local st = panel:CreateFontString(nil, "OVERLAY"); Skin:Font(st, 12, true); st:SetPoint("RIGHT", header, "RIGHT", -10, 0)

    local fHdr = Skin:Header(panel, "Creador de Mensajes")
    fHdr:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8); fHdr:SetWidth(360)
    local fBody = Skin:Panel(panel); fBody:SetPoint("TOPLEFT", fHdr, "BOTTOMLEFT", 0, -2); fBody:SetWidth(360); fBody:SetHeight(400)

    local function field(label, anchor, isLong)
        local lbl = fBody:CreateFontString(nil, "OVERLAY"); Skin:Font(lbl, 10, false); lbl:SetTextColor(unpack(C.textDim))
        lbl:SetPoint("TOPLEFT", anchor or fBody, anchor and "BOTTOMLEFT" or "TOPLEFT", anchor and 0 or 8, anchor and -10 or -8)
        lbl:SetWidth(110); lbl:SetText(label)
        local input = Skin:EditBox(fBody, 100, isLong and 40 or 22); input:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        input:SetPoint("RIGHT", fBody, "RIGHT", -8, 0)
        if isLong then input:SetMultiLine(true); input:SetAutoFocus(false); input:SetTextInsets(6,6,4,4) end
        return lbl, input
    end

    local rL, rE = field("Nombre Raid:")
    local tL, tB
    do
        tL = fBody:CreateFontString(nil, "OVERLAY"); Skin:Font(tL, 10, false); tL:SetTextColor(unpack(C.textDim))
        tL:SetPoint("TOPLEFT", rL, "BOTTOMLEFT", 0, -10); tL:SetWidth(110); tL:SetText("Tipo de Loot:")
        tB = Skin:Button(fBody, self.cfg.runType, 100, 22); tB:SetPoint("LEFT", tL, "RIGHT", 4, 0); tB:SetPoint("RIGHT", fBody, "RIGHT", -8, 0)
        tB:SetScript("OnMouseUp", function()
            local idx = 1; for i, n in ipairs(RUN_TYPES) do if n == self.cfg.runType then idx = i break end end
            self.cfg.runType = RUN_TYPES[(idx % #RUN_TYPES) + 1]; tB:SetText(self.cfg.runType); self:_RefreshPreview()
        end)
    end
    local gL, gE = field("GS Mínimo:", tL)
    local dL, dE = field("Discord / Info:", gL)
    local aL, aE = field("Clases Necesarias:", dL, true)
    
    -- Logro Requerido (con botón picker)
    local achL = fBody:CreateFontString(nil, "OVERLAY"); Skin:Font(achL, 10, false); achL:SetTextColor(unpack(C.textDim))
    achL:SetPoint("TOPLEFT", aL, "BOTTOMLEFT", 0, -10); achL:SetWidth(110); achL:SetText("Logro Requerido:")
    local achE = Skin:EditBox(fBody, 100, 22); achE:SetPoint("LEFT", achL, "RIGHT", 4, 0); achE:SetPoint("RIGHT", fBody, "RIGHT", -34, 0)
    local pB = Skin:Button(fBody, "...", 30, 22); pB:SetPoint("TOPLEFT", achE, "TOPRIGHT", 4, 0); pB:SetScript("OnMouseUp", function() M:_ShowAchievementPicker(achE) end)
    self._achEdit = achE

    local nL, nE = field("Autoinvitarse:", achL)

    local pH = fBody:CreateFontString(nil, "OVERLAY"); Skin:Font(pH, 10, true); pH:SetTextColor(unpack(C.accent)); pH:SetPoint("TOPLEFT", nL, "BOTTOMLEFT", 0, -12); pH:SetText("Previsualización:")
    local pr = fBody:CreateFontString(nil, "OVERLAY"); Skin:Font(pr, 10, false); pr:SetTextColor(unpack(C.text)); pr:SetPoint("TOPLEFT", pH, "BOTTOMLEFT", 0, -2); pr:SetPoint("BOTTOMRIGHT", fBody, "BOTTOMRIGHT", -8, 8); pr:SetJustifyH("LEFT"); pr:SetJustifyV("TOP"); pr:SetWordWrap(true)

    local function bE(e, k)
        e:SetText(tostring(self.cfg[k] or "")); e:SetScript("OnTextChanged", function(s) self.cfg[k] = s:GetText() or ""; self:_RefreshPreview() end)
    end
    bE(rE, "raidName"); bE(gE, "minGS"); bE(aE, "classes"); bE(achE, "achievement"); bE(dE, "discord"); bE(nE, "notes")

    -- Right Column
    local cHdr = Skin:Header(panel, "Canales de Chat")
    cHdr:SetPoint("TOPLEFT", fHdr, "TOPRIGHT", 8, 0); cHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local cBody = Skin:Panel(panel); cBody:SetPoint("TOPLEFT", cHdr, "BOTTOMLEFT", 0, -2); cBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0); cBody:SetHeight(190)
    local rC = Skin:Button(cBody, "Actualizar Canales", 140, 20); rC:SetPoint("BOTTOMRIGHT", -8, 8); rC:SetScript("OnMouseUp", function() self:Refresh() end)

    -- Guild checkbox: enviar anuncio también al canal de Hermandad (/g)
    local guildChk = Skin:CheckBox(cBody, "Enviar a Hermandad (/g)"); guildChk:SetPoint("TOPLEFT", 8, -8)
    guildChk:SetChecked(self.cfg.channels["GUILD"] == true)
    guildChk.OnValueChanged = function(_, v) self.cfg.channels["GUILD"] = v and true or nil end

    local bHdr = Skin:Header(panel, "Difusión Automática")
    bHdr:SetPoint("TOPLEFT", cBody, "BOTTOMLEFT", 0, -8); bHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local bBody = Skin:Panel(panel); bBody:SetPoint("TOPLEFT", bHdr, "BOTTOMLEFT", 0, -2); bBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0); bBody:SetHeight(80)
    local iL = bBody:CreateFontString(nil, "OVERLAY"); Skin:Font(iL, 10, false); iL:SetTextColor(unpack(C.textDim)); iL:SetPoint("TOPLEFT", 8, -8); iL:SetText("Intervalo (SEGUNDOS):")
    local iE = Skin:EditBox(bBody, 50, 20); iE:SetPoint("LEFT", iL, "RIGHT", 4, 0); iE:SetNumeric(true); iE:SetText(tostring(self.cfg.interval or 90))
    iE:SetScript("OnEditFocusLost", function(s) local v = tonumber(s:GetText()) or 90; if v < MIN_INTERVAL then v = MIN_INTERVAL end; self.cfg.interval = v; s:SetText(tostring(v)) end)
    local sN = Skin:Button(bBody, "Enviar Ahora", 90, 22); sN:SetPoint("BOTTOMLEFT", 8, 8); sN:SetScript("OnMouseUp", function() self:SendOnce() end)
    local sB = Skin:Button(bBody, "Iniciar", 60, 22); sB:SetPoint("LEFT", sN, "RIGHT", 4, 0); sB:SetScript("OnMouseUp", function() self:Start() end)
    local tB = Skin:Button(bBody, "Detener", 60, 22); tB:SetPoint("LEFT", sB, "RIGHT", 4, 0); tB:SetScript("OnMouseUp", function() self:Stop() end)

    local lHdr = Skin:Header(panel, "Anuncios Recientes")
    lHdr:SetPoint("TOPLEFT", fBody, "BOTTOMLEFT", 0, -8); lHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local function bLR(p)
        local r = CreateFrame("Frame", nil, p); r:SetHeight(18)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetTexture(Skin.TEX_WHITE)
        r.fs = r:CreateFontString(nil, "OVERLAY"); Skin:Font(r.fs, 9, false); r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", -6, 0); r.fs:SetJustifyH("LEFT")
        return r
    end
    local function uLR(r, i, idx, alt)
        if not i then return end; r.bg:SetVertexColor(alt and 0.1 or 0.13, 0.1, 0.15, 0.5)
        r.fs:SetText(("|cff999999%s|r |cffffd070[%s]|r %s"):format(date("%H:%M:%S", i.time), i.channels, i.msg))
    end
    local lS = Skin:ScrollList(panel, 18, bLR, uLR); lS:SetPoint("TOPLEFT", lHdr, "BOTTOMLEFT", 0, -2); lS:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    self._ui = { panel=panel, status=st, prev=pr, chBody=cBody, logScroll=lS, intEdit=iE }
    self._chRows = {}; self:Refresh(); return panel
end

function M:_RefreshPreview() if self._ui then self._ui.prev:SetText(self:BuildMessage()) end end

function M:Refresh()
    if not self._ui then return end
    local Skin = RMS.Skin
    self._ui.status:SetText(self.running and ("|cff60ff60EJECUTANDO|r ("..self.cfg.interval.."s)") or "|cffaaaaaaDETENIDO|r")
    self:_RefreshPreview()
    local channels = self:GetAvailableChannels()
    for i = 1, math.max(#channels, #self._chRows) do
        local row = self._chRows[i]
        if not row and i <= #channels then
            row = Skin:CheckBox(self._ui.chBody, ""); row:SetPoint("TOPLEFT", 8, -32 - (i-1)*22); self._chRows[i] = row
        end
        if row then
            local ch = channels[i]
            if ch then
                row:Show(); row.text:SetText(ch.name); row:SetChecked(self.cfg.channels[ch.slot] == true)
                row.OnValueChanged = function(_, v) self.cfg.channels[ch.slot] = v and true or nil end
            else row:Hide() end
        end
    end
    if self._ui and self._ui.guildCheck then self._ui.guildCheck:SetChecked(self.cfg.channels["GUILD"] == true) end
    self._ui.logScroll:SetData(self.cfg.log or {})
end

function M:_ShowAchievementPicker(ed)
    local Skin = RMS.Skin; local C = Skin.COLOR
    if self._achPopup and self._achPopup:IsShown() then self._achPopup:Hide() return end
    local f = self._achPopup
    if not f then
        f = CreateFrame("Frame", "MVPByJudeAchPicker", UIParent); f:SetSize(380, 460); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        Skin:SetBackdrop(f, C.bgMain, C.accent); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
        local t = f:CreateFontString(nil, "OVERLAY"); Skin:Font(t, 14, true); t:SetTextColor(unpack(C.accent)); t:SetPoint("TOP", 0, -8); t:SetText("BUSCADOR DE LOGROS")
        local c = Skin:CloseButton(f); c:SetPoint("TOPRIGHT", -4, -4); c:SetScript("OnClick", function() f:Hide() end)
        local s = Skin:EditBox(f, 1, 22); s:SetPoint("TOPLEFT", 8, -32); s:SetPoint("RIGHT", -8, 0); f.search = s
        local function bR(p)
            local r = CreateFrame("Frame", nil, p); r:SetHeight(20)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetTexture(Skin.TEX_WHITE)
            r.fs = r:CreateFontString(nil, "OVERLAY"); Skin:Font(r.fs, 11, false); r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", -56, 0)
            r.btn = Skin:Button(r, "Añadir", 50, 18); r.btn:SetPoint("RIGHT", -3, 0)
            return r
        end
        local function uR(r, item, idx, alt)
            r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.5)
            if item.section then r.fs:SetText(("|cffffd070-- %s --|r"):format(item.section)); r.btn:Hide()
            else local link = item.id and GetAchievementLink(item.id); r.fs:SetText(link or item.name or "?"); r.btn:Show()
                 r.btn:SetScript("OnMouseUp", function() 
                    local lk = item.id and GetAchievementLink(item.id) 
                    if lk and M._achEdit then 
                        -- [FIXED: FIX-ADV-2] Asegurar que el link es detectable por otros jugadores
                        M._achEdit:SetText(lk)
                        M._achEdit:SetCursorPosition(0) 
                        M:_RefreshPreview() 
                    end 
                 end) end
        end
        local l = Skin:ScrollList(f, 22, bR, uR); l:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -6); l:SetPoint("BOTTOMRIGHT", -8, 8); f.list = l
        f._rebuild = function(q)
            q = (q or ""):lower(); local d = {}
            for _, g in ipairs(ACHIEVEMENT_LIST) do
                local k = {}
                for _, e_ in ipairs(g.entries) do if q == "" or (e_[2] and e_[2]:lower():find(q, 1, true)) then k[#k+1] = { id = e_[1], name = e_[2] } end end
                if #k > 0 then d[#d+1] = { section = g.tier }; for _, x in ipairs(k) do d[#d+1] = x end end
            end
            l:SetData(d)
        end
        s:SetScript("OnTextChanged", function(ed) f._rebuild(ed:GetText() or "") end); self._achPopup = f
    end
    f.search:SetText(""); f._rebuild(""); f:Show()
end

function M:OnSlash(arg)
    arg = (arg or ""):lower()
    if arg == "start" then return self:Start() end
    if arg == "stop"  then return self:Stop()  end
    RMS.UI:Show("advertising")
end
