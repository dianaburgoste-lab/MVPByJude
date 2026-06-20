-- MVP By Jude -- Config
-- SavedVariables defaults + Settings tab UI builder.

local RMS = MVPByJude
local Config = {}
RMS.Config = Config

Config.DEFAULTS = {
    debug = false,
    minimap = { hide = false, angle = 215 },
    softres = {
        autoAccept    = true,
        oneItemPerPlayer = false,
        announceRolls = true,
    },
    hardres = {
        autoAccept = true,
    },
    dkp = {
        defaultBidIncrement = 100,
        minBid = 0,
        bidTimer = 30,
        decayPercent = 10,
    },
    dkp_officerRank = 2,    -- guild rank index <= this counts as officer for DKP
    goldbid = {
        minBid       = 100,
        bidIncrement = 100,
        bidTimer     = 30,
        autoTradeDetect = true,
    },
    ui = {
        scale       = 1.0,
        locked      = false,
        openOnLogin = false,
    },
}

local function deepMerge(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            deepMerge(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function Config:ApplyDefaults()
    deepMerge(RMS.db, self.DEFAULTS)
end

function Config:Get(path)
    local node = RMS.db
    for seg in tostring(path):gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[seg]
    end
    return node
end

function Config:Set(path, value)
    local node = RMS.db
    local segs = {}
    for seg in tostring(path):gmatch("[^.]+") do segs[#segs+1] = seg end
    for i = 1, #segs - 1 do
        if type(node[segs[i]]) ~= "table" then node[segs[i]] = {} end
        node = node[segs[i]]
    end
    node[segs[#segs]] = value
end

-- ---------- Settings tab builder ----------
function Config:BuildPanel(parent)
    local Skin = RMS.Skin
    local C = Skin.COLOR

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local header = Skin:Header(panel, "Ajustes del Addon")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)

    local issueLbl = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(issueLbl, 11, false); issueLbl:SetTextColor(unpack(C.text))
    issueLbl:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -6); issueLbl:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -6)
    issueLbl:SetHeight(16); issueLbl:SetJustifyH("LEFT")
    issueLbl:SetText("¿Has encontrado un error o quieres una mejora? |cffffd070Abre una incidencia en GitHub:|r")

    local issueUrl = Skin:EditBox(panel, 1, 22)
    issueUrl:SetPoint("TOPLEFT", issueLbl, "BOTTOMLEFT", 0, -2); issueUrl:SetPoint("TOPRIGHT", issueLbl, "BOTTOMRIGHT", 0, -2)
    local URL = "https://github.com/MVPByJude"
    issueUrl:SetText(URL); issueUrl:SetTextColor(unpack(C.accent)); issueUrl:SetCursorPosition(0)
    issueUrl:SetScript("OnMouseUp", function(s) s:HighlightText() end)
    issueUrl:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    issueUrl:SetScript("OnTextChanged", function(s) if s:GetText() ~= URL then s:SetText(URL); s:HighlightText() end end)

    local y = -90
    local function addCheck(label, path, tooltip)
        local cb = Skin:CheckBox(panel, label)
        cb:SetPoint("TOPLEFT", 16, y); cb:SetChecked(Config:Get(path))
        cb.OnValueChanged = function(_, v) Config:Set(path, v) end
        if tooltip then Skin:AttachTooltip(cb.box, label, {tooltip}) end
        y = y - 22
        return cb
    end

    local function addSection(text)
        y = y - 8
        local fs = panel:CreateFontString(nil, "OVERLAY")
        Skin:Font(fs, 13, true); fs:SetTextColor(unpack(C.accent)); fs:SetPoint("TOPLEFT", 12, y); fs:SetText(text)
        y = y - 20
    end

    local function addNumber(label, path, w)
        local fs = panel:CreateFontString(nil, "OVERLAY")
        Skin:Font(fs, 12, false); fs:SetTextColor(unpack(C.text)); fs:SetPoint("TOPLEFT", 16, y - 4); fs:SetText(label)
        local e = Skin:EditBox(panel, w or 80, 20); e:SetPoint("TOPLEFT", 220, y); e:SetNumeric(true)
        e:SetText(tostring(Config:Get(path) or 0))
        e:SetScript("OnEditFocusLost", function(s)
            local v = tonumber(s:GetText()) or 0; Config:Set(path, v); s:SetText(tostring(v)); s:SetBackdropBorderColor(unpack(C.border))
        end)
        y = y - 24
    end

    addSection("General")
    addCheck("Abrir ventana al entrar / recargar", "ui.openOnLogin", "Muestra automáticamente la ventana principal al iniciar sesión o recargar la interfaz.")
    addCheck("Habilitar registro de depuración (Debug)", "debug", "Muestra mensajes técnicos detallados en el chat.")

    addSection("Reserva Soft")
    addCheck("Auto-aceptar reservas", "softres.autoAccept", "Acepta automáticamente las solicitudes de SR de los jugadores.")
    addCheck("Un objeto por jugador", "softres.oneItemPerPlayer")
    addCheck("Anunciar resultados de dados", "softres.announceRolls")

    addSection("DKP")
    addNumber("Incremento de puja defecto", "dkp.defaultBidIncrement")
    addNumber("Puja mínima", "dkp.minBid")
    addNumber("Tiempo de puja (segundos)", "dkp.bidTimer")
    addNumber("Decaimiento semanal (%)", "dkp.decayPercent")
    addNumber("Rango de oficial (<=)", "dkp_officerRank")

    addSection("Subasta Oro")
    addNumber("Puja mínima (oro)", "goldbid.minBid")
    addNumber("Incremento de puja (oro)", "goldbid.bidIncrement")
    addNumber("Tiempo de puja (segundos)", "goldbid.bidTimer")
    addCheck ("Auto-detectar pago por comercio", "goldbid.autoTradeDetect", "Vigila la ventana de comercio para confirmar los pagos automáticamente.")

    return panel
end

RMS:RegisterModule("settings", {
    title = "Ajustes",
    order = 99,
    BuildUI = function(self, parent) return Config:BuildPanel(parent) end,
})
