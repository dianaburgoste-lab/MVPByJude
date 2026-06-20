-- MVP By Jude -- Hard Res
-- Items pre-assigned by the raid leader to specific players.
-- The item is GUARANTEED to that player when it drops -- no roll, no bid.
-- Full raid sync; on LOOT_OPENED the host gets a reminder of who gets what.

local RMS = MVPByJude
local M = RMS:RegisterModule("hardres", { title = "Hard Res", order = 2 })

-- ---------- state ----------
M.state = {
    active      = false,    -- session open?
    leader      = nil,      -- host name
    assignments = {},       -- list of {id=itemID, link=link, name=name, player=playerName}
    log         = {},       -- recent events
}

local function persist() RMS.db.hardresState = M.state end
local function restore()
    if RMS.db.hardresState then
        for k, v in pairs(RMS.db.hardresState) do M.state[k] = v end
    end
end

local function canHostSession()
    return (not RMS:InRaid()) or RMS:IsRaidLeader()
end

local function isHost()
    return M.state.active and M.state.leader == RMS:PlayerName()
end

local function getItemFromLink(link)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("%[(.-)%]") or "?"
    return id, name
end

local function pushLog(msg)
    table.insert(M.state.log, 1, msg)
    if #M.state.log > 30 then table.remove(M.state.log) end -- [FIXED: FIX-HR-3]
end

local function getCandidateIndex(slot, name)
    for i = 1, 40 do
        local cand = GetMasterLootCandidate(slot, i)
        if cand == name then return i end
    end
    return nil
end

-- ---------- session lifecycle ----------
function M:Open()
    if not canHostSession() then RMS:Print("Only the raid leader can open a Hard Res session.") return end
    self.state.active      = true
    self.state.leader      = RMS:PlayerName()
    self.state.assignments = {}
    self.state.log         = {}
    -- FIX BUG #3: Identificador único de sesión para evitar sincronizar datos obsoletos
    self.state.sessionId = RMS:PlayerName() .. ":" .. tostring(math.floor(GetTime()))
    RMS.db.shardCount = 0
    RMS.db.saroniteCount = 0
    persist()
    RMS.Comm:Send("hardres", "open", { leader = self.state.leader, sessionId = self.state.sessionId })
    RMS:Print("Hard Res session OPEN. Counters reset.")
    self:Refresh()
end

function M:Close()
    if not canHostSession() then RMS:Print("Only the raid leader can close a Hard Res session.") return end
    self.state.active = false
    self.state.sessionId = nil -- [FIX BUG #3]
    persist()
    RMS.Comm:Send("hardres", "close", {})
    RMS:Print("Hard Res session CLOSED.")
    self:Refresh()
end

function M:Reset()
    if not canHostSession() then RMS:Print("Only the raid leader can reset assignments.") return end
    self.state.assignments = {}
    self.state.log         = {}
    RMS.db.shardCount = 0
    RMS.db.saroniteCount = 0
    persist()
    RMS.Comm:Send("hardres", "reset", {})
    RMS:Print("Hard Res assignments and counters cleared.")
    self:Refresh()
end

-- ---------- assignment actions (host only) ----------
function M:Assign(player, itemLink, manualPrice)
    if not isHost() then RMS:Print("Only the session host can assign items.") return end
    if not player or player == "" then RMS:Print("Set the assignee first.") return end
    local id, name = getItemFromLink(itemLink)
    if not id then RMS:Print("Invalid item link.") return end

    table.insert(self.state.assignments, { id = id, link = itemLink, name = name, player = player, price = manualPrice })
    pushLog(("Assigned %s -> %s"):format(itemLink, player))
    persist()
    -- FIX BUG #2: Incluir el precio en el paquete de red
    RMS.Comm:Send("hardres", "assign", { id = id, link = itemLink, name = name, player = player, price = manualPrice or 0 })
    RMS:Print("Hard-assigned %s to %s.", itemLink, player)
    self:Refresh()
end

function M:Unassign(index)
    if not isHost() then RMS:Print("Only the session host can remove assignments.") return end
    local a = self.state.assignments[index]
    if not a then return end
    table.remove(self.state.assignments, index)
    pushLog(("Removed %s -> %s"):format(a.link or a.name or "?", a.player or "?"))
    persist()
    RMS.Comm:Send("hardres", "unassign", { id = a.id, player = a.player })
    self:Refresh()
end

-- ---------- comm handlers (incoming) ----------
RMS.Comm:On("hardres", "open", function(p, sender)
    M.state.active      = true
    M.state.leader      = p.leader or sender
    M.state.assignments = {}
    M.state.log         = {}
    -- [FIX BUG #3] Sincronizar identificador de sesión
    M.state.sessionId = p.sessionId or (p.leader or sender)
    persist()
    M:Refresh()
    RMS:Print("Hard Res opened by %s.", sender)
end)

RMS.Comm:On("hardres", "close", function(_, sender)
    M.state.active = false
    persist()
    M:Refresh()
    RMS:Print("Hard Res closed by %s.", sender)
end)

RMS.Comm:On("hardres", "reset", function(_, sender)
    M.state.assignments = {}
    M.state.log         = {}
    persist()
    M:Refresh()
    RMS:Print("Hard Res reset by %s.", sender)
end)

RMS.Comm:On("hardres", "assign", function(p, sender)
    if not p.id or not p.player then return end
    -- only accept from current host
    if M.state.leader ~= sender then return end
    -- [FIX BUG #2] Recibir el precio del paquete COMM
    table.insert(M.state.assignments, {
        id = tonumber(p.id), link = p.link, name = p.name, player = p.player,
        price = tonumber(p.price) or 0,
    })
    pushLog(("Assigned %s -> %s"):format(p.link or p.name or "?", p.player))
    persist()
    M:Refresh()
end)

RMS.Comm:On("hardres", "unassign", function(p, sender)
    if M.state.leader ~= sender then return end
    if not p.id or not p.player then return end
    local id = tonumber(p.id)
    for i = #M.state.assignments, 1, -1 do
        local a = M.state.assignments[i]
        if a.id == id and a.player == p.player then
            table.remove(M.state.assignments, i)
            break
        end
    end
    persist()
    M:Refresh()
end)

-- ---------- late-join sync ----------
function M:RequestSync()
    if not RMS:InGroup() then return end
    if self.state.active then return end
    -- [FIX BUG #3] Enviar el sessionId conocido (si existe)
    RMS.Comm:Send("hardres", "syncreq", { from = RMS:PlayerName(), sessionId = M.state.sessionId })
end

RMS.Comm:On("hardres", "syncreq", function(p, sender)
    if not isHost() then return end
    if sender == RMS:PlayerName() then return end
    -- FIX BUG #3: Solo responder si el sessionId del solicitante coincide o es nuevo
    if p.sessionId and p.sessionId == M.state.sessionId then return end
    
    RMS.Comm:SendWhisper("hardres", "open", { leader = M.state.leader, sessionId = M.state.sessionId }, sender)
    for _, a in ipairs(M.state.assignments) do
        -- [FIX BUG #2] Reenviar asignaciones con el precio
        RMS.Comm:SendWhisper("hardres", "assign", {
            id = a.id, link = a.link or "", name = a.name or "", player = a.player,
            price = a.price or 0,
        }, sender)
    end
end)

-- ---------- loot-drop reminder ----------
-- When loot window opens, remind the host of any assigned items present.
local function onLootOpened()
    if not M.state.active then return end
    if not RMS:IsMasterLooter() then return end -- Any ML with the addon will execute the list
    
    local me = RMS:PlayerName()
    local n = GetNumLootItems()
    for slot = 1, n do
        local link = GetLootSlotLink(slot)
        local id   = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, quality = GetItemInfo(link)
            local assignedTo = nil
            
            -- 1. Check assignments
            for _, a in ipairs(M.state.assignments) do
                if a.id == id then
                    assignedTo = a.player
                    break
                end
            end
            
            if assignedTo then
                local idx = getCandidateIndex(slot, assignedTo)
                if idx then
                    RMS:Print("|cff00ff00Asignación Automática:|r Entregando %s a %s", link, assignedTo)
                    SendChatMessage(("[MVP By Jude] Entregando %s a %s (Reserva Directa)"):format(link, assignedTo), "GUILD")
                    
                    -- COBRO DE DKP AL ENTREGAR
                    local dkpMod = RMS:GetModule("dkp")
                    if dkpMod then
                        local price = 0
                        -- Buscar el precio guardado en la asignación
                        for _, a in ipairs(M.state.assignments) do
                            if a.id == id and a.player == assignedTo then
                                price = a.price or 0
                                if not a.price then
                                    if id == 50274 then price = 70 end -- Fragmento default
                                end
                                break
                            end
                        end
                        
                        if price > 0 then
                            -- FIX BUG #1: select(1, ...) evita que el multi-retorno rompa la concatenación
                            local itemName = select(1, GetItemInfo(link)) or "Fragmento"
                            dkpMod:Award({assignedTo}, -price, "Botín: " .. itemName)
                            RMS:Print("|cffff0000[COBRO]|r -%d DKP a %s por %s", price, assignedTo, link)
                        end
                    end

                    -- CONTEO DE FRAGMENTOS Y SARONITAS
                    if id == 50274 then
                        RMS.db.shardCount = (RMS.db.shardCount or 0) + 1
                        RMS:Print("|cffff8000[CONTADOR]|r Fragmentos obtenidos: %d", RMS.db.shardCount)
                    elseif id == 49908 then
                        RMS.db.saroniteCount = (RMS.db.saroniteCount or 0) + 1
                        RMS:Print("|cff00ffff[CONTADOR]|r Saronitas obtenidas: %d", RMS.db.saroniteCount)
                    end

                    GiveMasterLoot(slot, idx)
                else
                    RMS:Print("|cffff0000Error de Asignación:|r No se encontró a %s en la lista de loot para %s", assignedTo, link)
                end
            elseif quality and quality >= 4 then
                -- 2. "Vacuum" mode: take unassigned epics to ML bags
                local myIdx = getCandidateIndex(slot, me)
                if myIdx then
                    RMS:Print("|cffffff00Recogida Automática:|r %s no tiene dueño, guardando en bolsa.", link)
                    SendChatMessage(("[MVP By Jude] Recogiendo %s (Sin reserva) para lotear luego."):format(link), "GUILD")
                    GiveMasterLoot(slot, myIdx)
                end
            end
        end
    end
end

-- ---------- events ----------
M.events = {
    LOOT_OPENED = function(self) onLootOpened() end,
    PLAYER_LOGIN = function(self)
        restore()
        self._wasInGroup = RMS:InGroup()
        if self._wasInGroup then
            local d = CreateFrame("Frame"); local elapsed = 0
            d:SetScript("OnUpdate", function(s, dt)
                elapsed = elapsed + dt
                if elapsed > 3 then s:SetScript("OnUpdate", nil); self:RequestSync() end
            end)
        end
    end,
    RAID_ROSTER_UPDATE     = function(self) self:OnGroupChange() end,
    PARTY_MEMBERS_CHANGED  = function(self) self:OnGroupChange() end,
}

function M:OnGroupChange()
    local nowIn = RMS:InGroup()
    if nowIn and not self._wasInGroup then self:RequestSync() end
    self._wasInGroup = nowIn
end

-- ---------- slash ----------
function M:OnSlash(arg)
    arg = arg or ""
    if arg == "open"  then return self:Open()  end
    if arg == "close" then return self:Close() end
    if arg == "reset" then return self:Reset() end
    RMS.UI:Show("hardres")
end

-- ---------- UI ----------
function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "Reserva Hard (Asignación Directa)")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)

    local status = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(status, 12, true)
    status:SetPoint("RIGHT", header, "RIGHT", -10, 0)

    -- session controls
    local openBtn  = Skin:Button(panel, "Abrir Sesión", 110, 24)
    local closeBtn = Skin:Button(panel, "Cerrar",         70, 24)
    local resetBtn = Skin:Button(panel, "Reiniciar",         70, 24)
    openBtn :SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    closeBtn:SetPoint("LEFT", openBtn,  "RIGHT", 6, 0)
    resetBtn:SetPoint("LEFT", closeBtn, "RIGHT", 6, 0)
    openBtn :SetScript("OnMouseUp", function() self:Open()  end)
    closeBtn:SetScript("OnMouseUp", function() self:Close() end)
    resetBtn:SetScript("OnMouseUp", function() self:Reset() end)

    openBtn:Hide()
    closeBtn:Hide()
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)

    local noteFs = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(noteFs, 10, false)
    noteFs:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    noteFs:SetTextColor(0.8, 0.8, 0.8)
    noteFs:SetText("La sesión se abre sola al 'Iniciar Raid' en Gestión DKP.")

    -- assignee row
    local label = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(label, 11, false)
    label:SetTextColor(unpack(C.textDim))
    label:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -10)
    label:SetText("Asignar al jugador:")

    local nameEdit = Skin:EditBox(panel, 180, 22)
    nameEdit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)

    local pickRaidBtn = Skin:Button(panel, "Seleccionar de Banda", 140, 22)
    pickRaidBtn:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
    pickRaidBtn:SetScript("OnMouseUp", function() self:_ShowRaidPicker(nameEdit) end)

    -- item entry row
    local label2 = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(label2, 11, false)
    label2:SetTextColor(unpack(C.textDim))
    label2:SetPoint("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, -10)
    label2:SetText("Objeto (pega el link o usa el buscador):")

    local linkEdit = Skin:EditBox(panel, 360, 22)
    linkEdit:SetPoint("TOPLEFT", label2, "BOTTOMLEFT", 0, -4)
    hooksecurefunc("ChatEdit_InsertLink", function(text)
        if linkEdit:HasFocus() then linkEdit:SetText(text); return true end
    end)

    local assignBtn = Skin:Button(panel, "Asignar", 80, 22)
    assignBtn:SetPoint("LEFT", linkEdit, "RIGHT", 6, 0)
    assignBtn:SetScript("OnMouseUp", function()
        local link = linkEdit:GetText():match("(|c%x+|Hitem:.-|h.-|h|r)")
        if not link then RMS:Print("Pega primero un enlace de objeto válido.") return end
        self:Assign(nameEdit:GetText(), link)
        linkEdit:SetText("")
    end)

    local pickBtn = Skin:Button(panel, "Añadir de buscador", 130, 22)
    pickBtn:SetPoint("LEFT", assignBtn, "RIGHT", 6, 0)
    pickBtn:SetScript("OnMouseUp", function()
        if not RMS.LootPicker then RMS:Print("Buscador de botín no cargado.") return end
        local who = nameEdit:GetText()
        if not who or who == "" then RMS:Print("Escribe el nombre del jugador primero.") return end
        
        -- BiS integration: fetch recommended items for the player
        local bisMod = RMS:GetModule("bis")
        local highlights = bisMod and bisMod.GetBiSIDsForPlayer and bisMod:GetBiSIDsForPlayer(who)
        
        RMS.LootPicker:Open({
            title       = "Asignar a -> "..who,
            highlights  = highlights, -- BiS highlights
            actionLabel = "Asignar",
            unpickLabel = "Quitar",
            isPicked    = function(id)
                for _, a in ipairs(self.state.assignments) do
                    if a.id == id and a.player == who then return true end
                end
                return false
            end,
            onPick   = function(link) self:Assign(who, link) end,
            onUnpick = function(id)
                for i = #self.state.assignments, 1, -1 do
                    local a = self.state.assignments[i]
                    if a.id == id and a.player == who then self:Unassign(i); return end
                end
            end,
        })
    end)
    -- UX improvement: explain why it might be disabled
    pickBtn:SetScript("OnEnter", function(s)
        if not s:IsEnabled() then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText("Buscador Deshabilitado", 1, 1, 1)
            GameTooltip:AddLine("Debes 'Abrir Sesión' y ser el líder para asignar ítems.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    pickBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Quick Assign Section (SHARDS & SARONITES)
    local qaHdr = Skin:Header(panel, "Asignación Rápida Especial")
    qaHdr:SetPoint("TOPLEFT", linkEdit, "BOTTOMLEFT", 0, -14)
    qaHdr:SetWidth(540)
    
    -- ROW 1: SHARDS
    local shardIcon = panel:CreateTexture(nil, "OVERLAY")
    shardIcon:SetSize(22, 22)
    shardIcon:SetPoint("TOPLEFT", qaHdr, "BOTTOMLEFT", 4, -10)
    local _, _, _, _, _, _, _, _, _, shardTexture = GetItemInfo(50274)
    shardIcon:SetTexture(shardTexture or "Interface\\Icons\\inv_misc_shadowfrozenshard_01") -- [FIXED: FIX-HR-1]
    
    local shardLabel = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(shardLabel, 11, true)
    shardLabel:SetPoint("LEFT", shardIcon, "RIGHT", 8, 0)
    shardLabel:SetText("Fragmento a:")
    
    local shardEdit = Skin:EditBox(panel, 110, 22)
    shardEdit:SetPoint("LEFT", shardLabel, "RIGHT", 4, 0)
    
    local shardPick = Skin:Button(panel, "Banda", 50, 22)
    shardPick:SetPoint("LEFT", shardEdit, "RIGHT", 4, 0)
    shardPick:SetScript("OnMouseUp", function() self:_ShowRaidPicker(shardEdit) end)
    
    local shardPriceLabel = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(shardPriceLabel, 10, false)
    shardPriceLabel:SetPoint("LEFT", shardPick, "RIGHT", 6, 0)
    shardPriceLabel:SetText("Precio:")
    
    local shardPriceEdit = Skin:EditBox(panel, 40, 22)
    shardPriceEdit:SetPoint("LEFT", shardPriceLabel, "RIGHT", 4, 0)
    shardPriceEdit:SetText("70")
    shardPriceEdit:SetNumeric(true)

    local shardExec = Skin:Button(panel, "ASIGNAR FRAGMENTO", 125, 22)
    shardExec:SetPoint("LEFT", shardPriceEdit, "RIGHT", 6, 0)
    shardExec:SetScript("OnMouseUp", function()
        local who = shardEdit:GetText()
        local price = tonumber(shardPriceEdit:GetText()) or 0
        if not who or who == "" then RMS:Print("Escribe un nombre.") return end
        self:Assign(who, "|cffff8000|Hitem:50274::::::::80:::::|h[Fragmento de escarcha de las Sombras]|h|r", price)
    end)
    
    -- CONTADORES VISUALES
    local counterFs = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(counterFs, 11, true)
    counterFs:SetTextColor(0.1, 0.9, 1, 0.9)
    counterFs:SetPoint("LEFT", shardExec, "RIGHT", 15, 0)
    self.counterFs = counterFs

    -- ROW 2: SARONITES
    local saronIcon = panel:CreateTexture(nil, "OVERLAY")
    saronIcon:SetSize(22, 22)
    saronIcon:SetPoint("TOPLEFT", shardIcon, "BOTTOMLEFT", 0, -10)
    local _, _, _, _, _, _, _, _, _, saronTexture = GetItemInfo(49908)
    saronIcon:SetTexture(saronTexture or "Interface\\Icons\\inv_crafting_primordialsaronite") -- [FIXED: FIX-HR-1]
    
    local saronLabel = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(saronLabel, 11, true)
    saronLabel:SetPoint("LEFT", saronIcon, "RIGHT", 8, 0)
    saronLabel:SetText("Saronita a:")
    
    local saronEdit = Skin:EditBox(panel, 110, 22)
    saronEdit:SetPoint("LEFT", saronLabel, "RIGHT", 14, 0) -- Adjusted for alignment
    
    local saronPick = Skin:Button(panel, "Banda", 50, 22)
    saronPick:SetPoint("LEFT", saronEdit, "RIGHT", 4, 0)
    saronPick:SetScript("OnMouseUp", function() self:_ShowRaidPicker(saronEdit) end)
    
    local saronPriceLabel = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(saronPriceLabel, 10, false)
    saronPriceLabel:SetPoint("LEFT", saronPick, "RIGHT", 6, 0)
    saronPriceLabel:SetText("Precio:")
    
    local saronPriceEdit = Skin:EditBox(panel, 40, 22)
    saronPriceEdit:SetPoint("LEFT", saronPriceLabel, "RIGHT", 4, 0)
    saronPriceEdit:SetText("0")
    saronPriceEdit:SetNumeric(true)

    local saronExec = Skin:Button(panel, "ASIGNAR SARONITA", 125, 22)
    saronExec:SetPoint("LEFT", saronPriceEdit, "RIGHT", 6, 0)
    saronExec:SetScript("OnMouseUp", function()
        local who = saronEdit:GetText()
        local price = tonumber(saronPriceEdit:GetText()) or 0
        if not who or who == "" then RMS:Print("Escribe un nombre.") return end
        self:Assign(who, "|cffff8000|Hitem:49908::::::::80:::::|h[Saronita primordial]|h|r", price)
    end)

    -- assignments list
    local listHdr = Skin:Header(panel, "Asignaciones Actuales")
    -- [FIXED: FIX-HR-2] Limpieza de anclajes redundantes
    listHdr:ClearAllPoints()
    listHdr:SetPoint("TOPLEFT", saronIcon, "BOTTOMLEFT", 0, -20)
    listHdr:SetWidth(540)

    local function buildAssignRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(22)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg

        -- a hidden Button covers the item-link area to capture mouse for tooltip
        local hover = CreateFrame("Button", nil, r)
        hover:SetPoint("TOPLEFT", 0, 0); hover:SetPoint("BOTTOMRIGHT", -200, 0)
        r.hover = hover

        local item = hover:CreateFontString(nil, "OVERLAY")
        Skin:Font(item, 11, false)
        item:SetPoint("LEFT", 6, 0); item:SetPoint("RIGHT", -4, 0)
        item:SetJustifyH("LEFT"); item:SetWordWrap(false); item:SetNonSpaceWrap(false)
        r.item = item

        local who = r:CreateFontString(nil, "OVERLAY")
        Skin:Font(who, 11, true)
        who:SetPoint("RIGHT", -90, 0); who:SetWidth(120)
        who:SetJustifyH("RIGHT")
        r.who = who

        local rm = Skin:Button(r, "Quitar", 70, 18)
        rm:SetPoint("RIGHT", -4, 0)
        r.rm = rm
        return r
    end
    local function updateAssignRow(r, item, idx, alt)
        if not item then return end
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
        r.item:SetText(item.link or item.name or ("item:"..item.id))
        local color = M:_PlayerColor(item.player)
        r.who:SetText(("|c%s%s|r"):format(color, item.player or "?"))
        if isHost() then r.rm:Enable() else r.rm:Disable() end
        r.rm:SetScript("OnMouseUp", function()
            for i, a in ipairs(M.state.assignments) do
                if a.id == item.id and a.player == item.player then
                    M:Unassign(i); return
                end
            end
        end)
        -- hover tooltip on the item area
        r.hover:SetScript("OnEnter", function(s)
            if not item.id then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:"..item.id)
            GameTooltip:Show()
        end)
        r.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local listScroll = Skin:ScrollList(panel, 22, buildAssignRow, updateAssignRow)
    listScroll:SetPoint("TOPLEFT",  listHdr,  "BOTTOMLEFT", 0, -2)
    listScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    self._ui = {
        panel = panel, status = status,
        openBtn = openBtn, closeBtn = closeBtn, resetBtn = resetBtn,
        nameEdit = nameEdit, linkEdit = linkEdit,
        assignBtn = assignBtn, pickBtn = pickBtn, pickRaidBtn = pickRaidBtn,
        listScroll = listScroll,
    }
    self:Refresh()
    return panel
end

-- color player name green if currently in group, dim otherwise
function M:_PlayerColor(name)
    if not name then return "ff999999" end
    local me = RMS:PlayerName()
    if name == me then return "ffffd070" end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            if GetRaidRosterInfo(i) == name then return "ff60ff60" end
        end
        return "ffff6060"
    end
    n = GetNumPartyMembers()
    for i = 1, n do
        if UnitName("party"..i) == name then return "ff60ff60" end
    end
    return "ff999999"
end

-- raid-name picker popup attached to an editbox.
-- Toggle behavior: clicking the trigger button again closes it.
-- Closes on: row click, X button, ESC (via UISpecialFrames).
function M:_ShowRaidPicker(editbox)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local roster = RMS:GetRosterNames()
    if #roster == 0 then RMS:Print("No raid/party members.") return end

    -- toggle: if open, just close
    if self._raidPickerWin and self._raidPickerWin:IsShown() then
        self._raidPickerWin:Hide(); return
    end

    local f = self._raidPickerWin
    if not f then
        f = CreateFrame("Frame", "MVPByJudeRaidPickerPopup", UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        Skin:SetBackdrop(f, C.bgMain, C.accent)
        f:EnableMouse(true)
        f._rows = {}
        self._raidPickerWin = f
        -- ESC closes it
        tinsert(UISpecialFrames, "MVPByJudeRaidPickerPopup")

        local close = Skin:Button(f, "x", 18, 18)
        close:SetPoint("TOPRIGHT", -3, -3)
        close.text:SetTextColor(unpack(C.bad))
        close:SetScript("OnMouseUp", function() f:Hide() end)
        f._close = close
    end

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", editbox, "BOTTOMLEFT", 0, -2)
    f:SetSize(180, 24 + #roster * 22)

    -- rebuild rows for current roster (reuse pooled rows where possible)
    for i = #f._rows + 1, #roster do
        local b = Skin:Button(f, "", 168, 20)
        b:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 22)
        f._rows[i] = b
    end
    for i, b in ipairs(f._rows) do
        if i <= #roster then
            local name = roster[i]
            b:SetText(name)
            b:SetScript("OnMouseUp", function()
                editbox:SetText(name); f:Hide()
            end)
            b:Show()
        else
            b:Hide()
        end
    end
    f:Show()
end

function M:Refresh()
    if not self._ui then return end
    local C = RMS.Skin.COLOR

    if self.counterFs then
        self.counterFs:SetText(("|cffff8000Frag: %d|r  |cff00ffffSaro: %d|r"):format(
            RMS.db.shardCount or 0, RMS.db.saroniteCount or 0
        ))
    end
    if self.state.active then
        self._ui.status:SetText("OPEN -- host: "..(self.state.leader or "?"))
        self._ui.status:SetTextColor(unpack(C.good))
    else
        self._ui.status:SetText("CLOSED")
        self._ui.status:SetTextColor(unpack(C.textDim))
    end

    if canHostSession() then
        self._ui.openBtn:Enable(); self._ui.closeBtn:Enable(); self._ui.resetBtn:Enable()
    else
        self._ui.openBtn:Disable(); self._ui.closeBtn:Disable(); self._ui.resetBtn:Disable()
    end
    if isHost() then
        self._ui.assignBtn:Enable(); self._ui.pickBtn:Enable()
    else
        self._ui.assignBtn:Disable(); self._ui.pickBtn:Disable()
    end

    -- snapshot for the scroll list (we want stable references for click handlers)
    local data = {}
    for i, a in ipairs(self.state.assignments) do
        data[i] = a
    end
    self._ui.listScroll:SetData(data)
end
