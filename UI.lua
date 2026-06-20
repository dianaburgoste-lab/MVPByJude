-- MVP Raid Tools -- UI
local RMS = MVPByJude
local UI = {}
RMS.UI = UI

local TAB_NAMES = {
    ["dkp"]         = "Gestión DKP",
    ["goldbid"]     = "Subasta Oro",
    ["hardres"]     = "Reserva Hard",
    ["advertising"] = "Anuncios",
    ["settings"]    = "Ajustes",
    ["donate"]      = "Donar",
}

local TAB_ORDER = {
    "dkp", "goldbid", "hardres", "advertising",
    "settings", "donate",
}

function UI:Build()
    if self.frame then return self.frame end

    local Skin = RMS.Skin
    local C = Skin.COLOR
    local f = CreateFrame("Frame", "MVPByJudeFrame", UIParent)

    local function getStoredSize()
        local w = RMS.db and RMS.db.ui and RMS.db.ui.w or 900
        local h = RMS.db and RMS.db.ui and RMS.db.ui.h or 640
        if w < 900 then w = 900 end
        if h < 500 then h = 500 end
        return w, h
    end

    local function getStoredPosition()
        local pos = RMS.db and RMS.db.ui and RMS.db.ui.pos
        if pos and pos.point and pos.x and pos.y then
            return pos.point, pos.x, pos.y
        end
        return "CENTER", 0, 0
    end

    local w, h = getStoredSize()
    f:SetSize(w, h)
    local point, x, y = getStoredPosition()
    f:SetPoint(point, UIParent, point, x, y)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    -- [FIXED: FIX-UI-1] f:SetMinResize(900, 500) NO existe en 3.3.5a
    f:EnableMouse(true)
    f:Hide()
    Skin:SetBackdrop(f, C.bgMain, C.borderHi)
    self.frame = f

    local function saveSize()
        if RMS.db and RMS.db.ui then
            local currW, currH = f:GetSize()
            if currW < 900 then currW = 900 end
            if currH < 500 then currH = 500 end
            RMS.db.ui.w = currW
            RMS.db.ui.h = currH
        end
    end

    local function savePosition()
        if RMS.db and RMS.db.ui then
            local point, _, _, x, y = f:GetPoint()
            if point and x and y then
                RMS.db.ui.pos = { point = point, x = x, y = y }
            end
        end
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    grip:SetScript("OnMouseDown", function()
        if not (RMS.db and RMS.db.ui and RMS.db.ui.locked) then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        -- [FIXED: FIX-UI-1] Aplicar límite mínimo manualmente (SetMinResize no existe en 3.3.5a)
        local cw, ch = f:GetSize()
        if cw < 900 then f:SetWidth(900) end
        if ch < 500 then f:SetHeight(500) end
        saveSize()
        savePosition()
    end)
    self.resizeGrip = grip

    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(32)
    Skin:SetBackdrop(title, C.bgHeader, C.border)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if not (RMS.db and RMS.db.ui and RMS.db.ui.locked) then
            f:StartMoving()
        end
    end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        saveSize()
        savePosition()
    end)

    local logo = title:CreateFontString(nil, "OVERLAY")
    Skin:Font(logo, 16, true)
    logo:SetTextColor(unpack(C.accent))
    logo:SetPoint("LEFT", 12, 0)
    logo:SetText("MVP Raid Tools")

    local sub = title:CreateFontString(nil, "OVERLAY")
    Skin:Font(sub, 10, false)
    sub:SetTextColor(unpack(C.textDim))
    sub:SetPoint("LEFT", logo, "RIGHT", 8, -1)
    sub:SetText("Ver "..RMS.VERSION)

    local close = Skin:CloseButton(title)
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    local lock = Skin:Button(title, "Bloquear", 70, 22)
    lock:SetPoint("RIGHT", close, "LEFT", -4, 0)

    local function refreshLock()
        local locked = RMS.db and RMS.db.ui and RMS.db.ui.locked
        lock.text:SetText(locked and "Desbloquear" or "Bloquear")
        if self.resizeGrip then
            if locked then self.resizeGrip:Hide() else self.resizeGrip:Show() end
        end
    end

    lock:SetScript("OnMouseUp", function(s)
        s:SetBackdropColor(unpack(C.bgHover))
        if RMS.db and RMS.db.ui then
            RMS.db.ui.locked = not RMS.db.ui.locked
        end
        refreshLock()
    end)

    f:SetScript("OnShow", refreshLock)
    f:SetScript("OnHide", saveSize)

    local tabbarScroll = CreateFrame("ScrollFrame", "MVPByJudeTabScroll", f)
    tabbarScroll:SetPoint("TOPLEFT", 6, -38)
    tabbarScroll:SetPoint("BOTTOMLEFT", 6, 6)
    tabbarScroll:SetWidth(160)
    Skin:SetBackdrop(tabbarScroll, C.bgPanel, C.border)
    tabbarScroll:EnableMouseWheel(true)
    tabbarScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, self.scrollChildHeight - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 30)))
    end)

    local tabbar = CreateFrame("Frame", nil, tabbarScroll)
    tabbar:SetWidth(148)
    tabbarScroll:SetScrollChild(tabbar)
    self.tabbar = tabbar
    self.tabbarScroll = tabbarScroll

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", tabbarScroll, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -6, 6)
    Skin:SetBackdrop(content, C.bgPanel, C.border)
    self.content = content

    self.tabs = {}
    self.panels = {}

    local y = -8
    for _, id in ipairs(TAB_ORDER) do
        if id:sub(1,5) == "_sep_" then
            local sepLabel = ({
                _sep_mrt     = "── MRT ──",
                _sep_combat  = "── Combate ──",
                _sep_inspect = "── Inspección ──",
                _sep_org     = "── Organización ──",
                _sep_log     = "── Registro ──",
                _sep_extra   = "── Extra ──",
                _sep_config  = "── Sistema ──",
            })[id]
            if sepLabel then
                local sep = tabbar:CreateFontString(nil, "OVERLAY")
                Skin:Font(sep, 9, true)
                sep:SetTextColor(unpack(C.accentDim))
                sep:SetPoint("TOPLEFT", 10, y - 4)
                sep:SetText(sepLabel)
                y = y - 20
            end
        else
            local mod = RMS:GetModule(id)
            if mod then
                local label = TAB_NAMES[id] or mod.title
                local b = Skin:TabButton(tabbar, label, 138, 24)
                b:SetPoint("TOPLEFT", 6, y)
                b:SetScript("OnClick", function() UI:Show(id) end)
                self.tabs[id] = b
                y = y - 27
            end
        end
    end
    tabbar:SetHeight(math.abs(y) + 10)
    if tabbarScroll then tabbarScroll.scrollChildHeight = tabbar:GetHeight() end

    local status = title:CreateFontString(nil, "OVERLAY")
    Skin:Font(status, 10, false)
    status:SetTextColor(unpack(C.textDim))
    status:SetPoint("RIGHT", lock, "LEFT", -10, 0)
    self.status = status
    self:UpdateStatus()

    self:_SelectTab(TAB_ORDER[1])

    return f
end

function UI:_SelectTab(id)
    if not id then return end
    if not self.tabs or not self.tabs[id] then return end

    for tid, btn in pairs(self.tabs) do
        btn:SetSelected(tid == id)
    end
    for pid, panel in pairs(self.panels) do
        if pid ~= id then panel:Hide() end
    end

    local ok, p = pcall(function() return self:GetOrBuildPanel(id) end)
    if ok and p then
        p:Show()
    elseif not ok then
        RMS:Print("|cffff4444Error al construir panel '%s': %s|r", id, tostring(p))
    end

    self.activeTab = id
end

function UI:UpdateStatus()
    if not self.status then return end
    local role = RMS:IsRaidLeader() and "L\195\175der"
              or RMS:IsAssist()    and "Ayudante"
              or RMS:InRaid()      and "Banda"
              or RMS:InGroup()     and "Grupo"
              or "Solo"
    local ml = RMS:IsMasterLooter() and " | Bot\195\173n Maestro" or ""
    self.status:SetText(role..ml)
end

function UI:GetOrBuildPanel(id)
    if self.panels[id] then return self.panels[id] end
    local mod = RMS:GetModule(id)
    if not mod or not mod.BuildUI then return nil end
    local p = mod:BuildUI(self.content)
    p:SetAllPoints(self.content)
    p:Hide()
    self.panels[id] = p
    return p
end

function UI:Show(id)
    self:Build()
    self:_SelectTab(id)
    self:UpdateStatus()
    self.frame:Show()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show(self.activeTab or TAB_ORDER[1])
    end
end

RMS:RegisterEvent("RAID_ROSTER_UPDATE",      function() UI:UpdateStatus() end)
RMS:RegisterEvent("PARTY_MEMBERS_CHANGED",   function() UI:UpdateStatus() end)
RMS:RegisterEvent("PARTY_LEADER_CHANGED",    function() UI:UpdateStatus() end)

local menuFrame = CreateFrame("Frame", "MVPByJudeMenuFrame", UIParent, "UIDropDownMenuTemplate")
function RMS:ShowMenu(menuList)
    -- [FIXED: FIX-UI-2]
    if not menuList then return end
    if not EasyMenu then
        RMS:Print("EasyMenu no disponible en este cliente.")
        return
    end
    EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
end
