-- MVP By Jude -- DKP
-- Per-guild DKP standings. Officers (rank index <= configured threshold) can
-- award/deduct points. Sync over the GUILD addon channel so every guild member
-- with the addon sees the same standings. Late-join sync from any officer.

local RMS = MVPByJude
local M = RMS:RegisterModule("dkp", { title = "Gestión DKP", order = 3 })

-- Event helper: auto-refresh when the server sends guild roster updates
do
    local _guildEventFrame = CreateFrame("Frame")
    _guildEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    _guildEventFrame:SetScript("OnEvent", function()
        if M._suspendGuildRefresh then return end
        -- mark that roster updates are incoming and show waiting state
        M._waitingForRoster = true
        -- Debounce bursts of events (longer delay to allow server to send full roster)
        if M._guildRosterDebounce then return end
        M._guildRosterDebounce = true
        M:ScheduleTimer(function()
            M._guildRosterDebounce = false
            M._waitingForRoster = false
            pcall(function()
                if M._RefreshRankCache then pcall(function() M:_RefreshRankCache() end) end
                M:Refresh()
            end)
        end, 0.6)
    end)
end
end

-- ---------- per-guild state ----------
M.state    = nil   -- bound to RMS.db.dkp[<guild>] in OnInit / guild change
M.selected = {}    -- [playerName] = true (UI multi-select)

-- [NEW] Constantes para anuncios
local MAX_CHAT_LEN = 248
local CONT_PREFIX  = "[+] "
local MSG_DELAY    = 1.5

-- [NEW] Sistema de Timer Seguro (Anti-Leak)
local _timerQueue = {}
local _timerFrame = nil

local function _GetTimerFrame()
    if _timerFrame then return _timerFrame end
    _timerFrame = CreateFrame("Frame")
    _timerFrame:Hide()
    _timerFrame:SetScript("OnUpdate", function(self, dt)
        if #_timerQueue == 0 then
            self:Hide()
            return
        end
        local entry = _timerQueue[1]
        entry.remaining = entry.remaining - dt
        if entry.remaining <= 0 then
            table.remove(_timerQueue, 1)
            local ok, err = pcall(entry.callback)
            if not ok then
                RMS:Print("|cffff0000[DKP Timer Error]|r " .. tostring(err))
            end
        end
    end)
    return _timerFrame
end

function M:ScheduleTimer(callback, delay)
    table.insert(_timerQueue, { callback = callback, remaining = delay })
    _GetTimerFrame():Show()
end

-- [NEW] Función de Anuncio por Lotes
function M:AnnounceEPBatch(delta, reason, players)
    local cleanReason = reason or "Sin motivo"
    -- Guard: Truncar motivo si es muy largo para asegurar que el header no consuma todo el espacio
    if #cleanReason > 60 then
        cleanReason = cleanReason:sub(1, 57) .. "..."
    end

    local header = string.format("EPGP: %+d EP (%s): ", delta, cleanReason)
    local contHeader = string.format("EPGP: %+d EP (%s - continuacion): ", delta, cleanReason)
    
    local lines = {}
    local current = header

    for i, name in ipairs(players) do
        local isFirstInLine = (current == header or current == contHeader)
        local sep = isFirstInLine and "" or ", "
        local candidate = current .. sep .. name

        if #candidate > MAX_CHAT_LEN then
            -- Si no es el primer nombre de la línea, cerramos la anterior
            if not isFirstInLine then
                table.insert(lines, current)
                current = contHeader .. name
            else
                -- Caso extremo: un solo nombre desborda la línea (header muy largo)
                -- Lo enviamos como única línea y reseteamos buffer
                table.insert(lines, candidate)
                current = contHeader
            end
        else
            current = candidate
        end
    end

    -- Insertar el último buffer si contiene nombres
    if current ~= header and current ~= contHeader then
        table.insert(lines, current)
    end

    for idx, line in ipairs(lines) do
        self:ScheduleTimer(function()
            pcall(_G.SendChatMessage, line, "GUILD")
        end, (idx == 1 and 0 or (idx - 1) * MSG_DELAY))
    end
end

-- Cache de rangos para evitar spam de GuildRoster() [FIX BUG #1]
M._rankCache = {}         -- [playerName] = rankIndex
M._rankCacheTime = 0      -- timestamp del último refresh
local RANK_CACHE_TTL = 30 -- segundos de validez del cache

-- Helper: fuerza el refresco del roster.
-- forceOffline: si es true, activa temporalmente "Mostrar desconectados" (solo para acciones manuales).
local function WithFullGuildRoster(callback, forceOffline)
    if not callback then return nil end
    if not GetNumGuildMembers then return callback() end

    local canToggle = forceOffline and GetGuildRosterShowOffline and SetGuildRosterShowOffline
    local original = canToggle and GetGuildRosterShowOffline()

    M._suspendGuildRefresh = true

    if canToggle and not original then
        SetGuildRosterShowOffline(true)
    end

    if GuildRoster then GuildRoster() end

    -- Try to run callback immediately. If data isn't ready, schedule a retry.
    local ok, a, b, c, d, e = pcall(callback)
    if ok and a ~= nil then
        -- immediate success, restore state and return
        if canToggle and not original then
            SetGuildRosterShowOffline(false)
            if GuildRoster then GuildRoster() end
        end
        M._suspendGuildRefresh = false
        return a, b, c, d, e
    end

    -- Data likely not ready; schedule a delayed retry to allow server to send roster
    M:ScheduleTimer(function()
        local ok2, a2, b2, c2, d2, e2 = pcall(callback)
        if canToggle and not original then
            SetGuildRosterShowOffline(false)
            if GuildRoster then GuildRoster() end
        end
        M._suspendGuildRefresh = false
        if not ok2 then
            RMS:Print("|cffff0000[DKP]|r Error procesando roster asincrónico: " .. tostring(a2))
        end
    end, 0.6)

    return nil
end


local function emptyState()
    return {
        standings = {},
        log = {},
        raids = {},
        activeRaid = nil,
        altIndex = {
            altToMain = {},
            mainToAlts = {},
            classes = {},
            ranks = {},
            officerNotes = {},
            lastSeen = {}
        },
        pendingNotes = {},
        undoStack = {},
        altIndexSeeded = false,
        lastFullSync = 0
    }
end

-- [NEW] Generador de UID único para deduplicación de log
local function GenerateUID()
    return string.format("%s:%d:%04d", (UnitName("player") or "?"), time(), math.random(1, 9999))
end

-- [NEW] Lock de escritura concurrente (anti-race condition)
local _writeLock = {} -- [playerName] = true mientras se escribe

local STARTER_BOSSES = {
    ["Lord Marrowgar"] = "Ciudadela de la Corona de Hielo",
    ["Lord Tuétano"] = "Ciudadela de la Corona de Hielo",
    ["Halion"] = "Sagrario Rubí",
}

local function currentGuild()
    if not GetGuildInfo then return nil end
    local g = GetGuildInfo("player")
    if g and g ~= "" then return g end
    return nil
end

function M:LoadGuildState()
    local g = currentGuild()
    if not g then self.state = nil; self.guild = nil; return end
    RMS.db.dkp = RMS.db.dkp or {}
    RMS.db.dkp[g] = RMS.db.dkp[g] or emptyState()
    self.state = RMS.db.dkp[g]

    -- Normalización de estructura persistente
    self.state.altIndex = self.state.altIndex or {}
    local ai = self.state.altIndex
    ai.altToMain = ai.altToMain or {}
    ai.mainToAlts = ai.mainToAlts or {}
    ai.classes = ai.classes or {}
    ai.ranks = ai.ranks or {}
    ai.officerNotes = ai.officerNotes or {}
    ai.lastSeen = ai.lastSeen or {}

    self.state.standings = self.state.standings or {}
    self.state.log = self.state.log or {}
    self.state.raids = self.state.raids or {}
    self.state.pendingNotes = self.state.pendingNotes or {}
    self.state.manualAltMap = self.state.manualAltMap or {}
    self.state.altIndexSeeded = self.state.altIndexSeeded or false
    self.state.lastFullSync = self.state.lastFullSync or 0

    self.altIndex = ai
    self.guild = g
end

local function pushLog(entry)
    if not M.state then return end
    table.insert(M.state.log, 1, entry)
    if #M.state.log > 500 then table.remove(M.state.log) end
end

-- ---------- officer detection ----------
function M:OfficerThreshold()
    if RMS.db.dkp_officerRank ~= nil then return RMS.db.dkp_officerRank end
    return 2  -- default: GM(0), Officer(1), Raid Leader(2) = officer-tier
end

function M:_RefreshRankCache()
    if not GetNumGuildMembers then return end
    if self._refreshingRankCache then return end

    self._refreshingRankCache = true

    -- Automatizado: NO forzamos offline para evitar flickers en la UI social del usuario
    WithFullGuildRoster(function()
        -- [FIXED: FIX-DKP-2] Nota: GetNumGuildMembers() sin args da el total (online+offline) solo si
        -- SetGuildRosterShowOffline(true) está activo O después de llamar GuildRoster().
        local n = GetNumGuildMembers() or 0
        -- [FIXED: FIX-DKP-1]
        for k in next, M._rankCache do M._rankCache[k] = nil end

        for i = 1, n do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name then
                M._rankCache[name] = rankIndex
            end
        end

        M._rankCacheTime = GetTime()
    end, false)

    self._refreshingRankCache = false
end

function M:_RankIndexOf(playerName)
    -- Solo refrescar si el cache expiró (cada 30 segundos como máximo) [FIX BUG #1]
    if GetTime() - M._rankCacheTime > RANK_CACHE_TTL then
        self:_RefreshRankCache()
    end
    return M._rankCache[playerName]
end

function M:IsOfficer(playerName)
    playerName = playerName or RMS:PlayerName()
    local r = self:_RankIndexOf(playerName)
    if not r then return false end
    return r <= self:OfficerThreshold()
end

local function DecodeOfficerNote(note)
    if not note then return nil, nil end
    note = note:gsub("^%s*(.-)%s*$", "%1") -- Trim
    if note == "" then return nil, nil end

    -- 1. Intentar formato decimal (EPGP: 5050.0 o 5050,0)
    local ep, gp = string.match(note, "^(%d+)[.,](%d+)$")
    if ep then return tonumber(ep), tonumber(gp) end

    -- 2. Intentar formato entero simple (DKP: 5050)
    local val = string.match(note, "^(%d+)$")
    if val then return tonumber(val), 0 end

    return nil, nil
end

local function GetRosterStandings()
    local standings = {}
    if not GetNumGuildMembers then return standings end
    WithFullGuildRoster(function()
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, _, _, _, _, _, _, note = GetGuildRosterInfo(i)
            if name then
                local ep, gp = DecodeOfficerNote(note)
                if ep then
                    standings[name] = {
                        balance = ep - (gp or 0),
                        earned = ep,
                        spent = gp or 0
                    }
                end
            end
        end
    end, true)

    -- If we didn't read any standings immediately, schedule a delayed refresh
    -- because GuildRoster() is asynchronous and notes may arrive shortly.
    if next(standings) == nil then
        if not M._standingsRetryScheduled then
            M._standingsRetryScheduled = true
            M:ScheduleTimer(function()
                M._standingsRetryScheduled = false
                -- Trigger UI refresh so standings are re-read and shown when available
                pcall(function() M:Refresh() end)
            end, 0.8)
        end
    end

    return standings
end

function M:GetBalance(playerName)
    local resolved = self:GetResolvedMain(playerName)
    local standings = GetRosterStandings()
    local s = standings[resolved]
    return s and s.balance or 0
end

function M:GetResolvedMain(name)
    if not self.state or not self.state.altIndex then return name end
    -- 1. Mapeo manual (prioridad absoluta si existe)
    if self.state.manualAltMap and self.state.manualAltMap[name] then
        return self.state.manualAltMap[name]
    end
    -- 2. Índice persistente (sembrado por Sincronizar Notas)
    return self.state.altIndex.altToMain[name] or name
end

function M:GuildMembers()
    if not GetNumGuildMembers then return {} end

    local out = {}
    local seen = {}

    -- Usar WithFullGuildRoster para asegurar que el roster está actualizado
    WithFullGuildRoster(function()
        local n = GetNumGuildMembers() or 0
        local visibleRoster = {}
        for i = 1, n do
            local name, _, rankIndex, _, classDisplay, _, _, officerNote, online, _, classFile = GetGuildRosterInfo(i)
            if name then
                visibleRoster[name] = {
                    class = classFile or classDisplay,
                    rank = rankIndex,
                    online = online
                }
            end
        end

        -- 1. Mains que están en el roster visible actual
        for name, info in pairs(visibleRoster) do
            local mainName = M:GetResolvedMain(name)
            if mainName == name then
                out[#out+1] = {
                    name = name,
                    class = info.class,
                    rank = info.rank,
                    online = info.online
                }
                seen[name] = true
            end
        end

        -- 2. Fallback: Mains conocidos en Standings/Índice (offline o no visibles)
        local rosterStandings = GetRosterStandings()
        local ai = M.state and M.state.altIndex
        if ai then
            for name, s in pairs(rosterStandings) do
                if not seen[name] then
                    -- Solo añadir si no es un alter conocido
                    if not ai.altToMain[name] then
                        table.insert(out, {
                            name = name,
                            class = ai.classes[name] or "UNKNOWN",
                            rank = ai.ranks[name] or 99,
                            online = false,
                        })
                        seen[name] = true
                    end
                end
            end
        end
    end, false)  -- false = no forzar offline visualmente

    return out
end

-- ---------- core actions (officer only) ----------
-- [IMPROVED] Escritura con protección contra race condition
local function updateOfficerNote(playerName, delta)
    if not CanEditOfficerNote() then return end
    local resolvedMain = M:GetResolvedMain(playerName)

    -- Protección contra escritura concurrente
    if _writeLock[resolvedMain] then
        RMS:Print("|cffff9900[DKP]|r Escritura en curso para %s, encolando...", resolvedMain)
        M.state.pendingNotes = M.state.pendingNotes or {}
        M.state.pendingNotes[resolvedMain] = (M.state.pendingNotes[resolvedMain] or 0) + delta
        return
    end

    _writeLock[resolvedMain] = true

    local n = GetNumGuildMembers() or 0
    local found = false
    for i = 1, n do
        local name, _, _, _, _, _, _, note = GetGuildRosterInfo(i)
        if name and name == resolvedMain then
            local ep, gp = DecodeOfficerNote(note)
            local currentBalance = (ep or 0) - (gp or 0)
            local newBalance = math.max(0, currentBalance + delta)
            GuildRosterSetOfficerNote(i, tostring(newBalance))
            found = true
            break
        end
    end
    -- Si no está visible, guardar como pending
    if not found and M.state then
        M.state.pendingNotes = M.state.pendingNotes or {}
        M.state.pendingNotes[resolvedMain] = (M.state.pendingNotes[resolvedMain] or 0) + delta
    end

    _writeLock[resolvedMain] = nil
end

function M:FlushPendingOfficerNotes()
    if not self.state or not self.state.pendingNotes then return end
    if not CanEditOfficerNote() then return end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return end
    local toRemove = {}
    for name, delta in pairs(self.state.pendingNotes) do
        -- Solo aplicar si sigue siendo main o no es alter
        local isSafeMain = (self:GetResolvedMain(name) == name)
        if isSafeMain then
            for i = 1, n do
                local guildName, _, _, _, _, _, _, note = GetGuildRosterInfo(i)
                if guildName and guildName == name then
                    local ep, gp = DecodeOfficerNote(note)
                    local currentBalance = (ep or 0) - (gp or 0)
                    local newBalance = math.max(0, currentBalance + delta)
                    GuildRosterSetOfficerNote(i, tostring(newBalance))
                    table.insert(toRemove, name)
                    break
                end
            end
        else
            -- Ya no es main → descartar
            table.insert(toRemove, name)
        end
    end
    for _, nm in ipairs(toRemove) do
        self.state.pendingNotes[nm] = nil
    end
end

local function applyDelta(name, delta, class)
    local targetName = M:GetResolvedMain(name)
    updateOfficerNote(targetName, delta)
end

function M:StartRaid(name)
    if not self.state then return end
    if self.state.activeRaid then self:EndRaid() end
    
    local raid = {
        name = name or ("Raid " .. date("%d/%m")),
        startTime = time(),
        endTime = nil,
        entries = {}, -- Indices into M.state.log
    }
    table.insert(self.state.raids, 1, raid)
    self.state.activeRaid = 1
    if #self.state.raids > 20 then table.remove(self.state.raids) end
    RMS:Print("|cff00ff00Raid Iniciada:|r " .. raid.name)

    -- Auto-open HardRes session
    if RMS:GetModule("hardres") then
        RMS:GetModule("hardres"):Open()
    end

    self:Refresh()
end

function M:EndRaid()
    if not self.state or not self.state.activeRaid then return end
    local raid = self.state.raids[self.state.activeRaid]
    if raid then
        raid.endTime = time()
        RMS:Print("|cffff6060Raid Finalizada:|r " .. raid.name)
    end
    self.state.activeRaid = nil

    -- Auto-close HardRes session
    if RMS:GetModule("hardres") then
        RMS:GetModule("hardres"):Close()
    end

    self:Refresh()
end

function M:Award(players, delta, reason)
    if not self.state then RMS:Print("No est\195\161s en una hermandad.") return end
    if not self:IsOfficer() then RMS:Print("Solo los oficiales pueden cambiar DKP.") return end
    if not players or #players == 0 then RMS:Print("No hay jugadores seleccionados.") return end
    delta = tonumber(delta); if not delta or delta == 0 then RMS:Print("Cantidad inv\195\161lida.") return end

    if not self.state.altIndexSeeded then
        RMS:Print("|cffff9900[DKP] AVISO:|r Índice de alters no sembrado. Presiona 'Sincronizar Notas' antes de la raid.")
    end
    -- apply locally
    local roster = self:GuildMembers()
    local classMap = {}
    for _, m in ipairs(roster) do
        classMap[m.name] = m.class
        -- FIX BUG #1: Tambi\195\169n mapear alters al class del Main para evitar corrupci\195\179n
        local alts = self.altIndex and self.altIndex.mainToAlts[m.name]
        if alts then
            for _, altName in ipairs(alts) do
                if not classMap[altName] then
                    classMap[altName] = m.class
                end
            end
        end
    end

    -- VALIDACION ANTI-DUPLICIDAD: Usar fuente de verdad centralizada
    local appliedTo = {} -- [mainName] = true
    local finalPlayers = {}

    for _, name in ipairs(players) do
        local targetName = self:GetResolvedMain(name)

        if not appliedTo[targetName] then
            applyDelta(name, delta, classMap[targetName] or classMap[name])
            appliedTo[targetName] = true
            table.insert(finalPlayers, name)
        end
    end

    local actionId = GenerateUID()

    -- [FIXED] Anuncio inteligente con delay anti-flood y prevención de fugas de memoria
    self:AnnounceEPBatch(delta, reason, finalPlayers)

    local entry = {
        id = actionId, time = time(), by = RMS:PlayerName(),
        delta = delta, reason = reason or "",
        players = table.concat(players, ","),
    }
    table.insert(M.state.log, 1, entry)
    if #M.state.log > 1000 then table.remove(M.state.log) end

    -- [NEW] Guardar en undoStack para permitir Deshacer
    self.state.undoStack = self.state.undoStack or {}
    table.insert(self.state.undoStack, {
        id = actionId, time = time(), by = RMS:PlayerName(),
        delta = delta, reason = reason or "",
        players = finalPlayers, -- tabla, no string, para poder revertir por jugador
    })
    if #self.state.undoStack > 10 then table.remove(self.state.undoStack, 1) end

    -- Link to active raid
    if self.state.activeRaid then
        local raid = self.state.raids[self.state.activeRaid]
        table.insert(raid.entries, 1, entry)
    end

    RMS.Comm:Send("dkp", "delta", {
        id = actionId, by = RMS:PlayerName(),
        d = delta, r = reason or "",
        p = table.concat(players, ","),
    }, "GUILD")
    self:Refresh()
end

-- [NEW] Sistema de Undo: revierte la última acción de DKP
function M:Undo()
    if not self.state then RMS:Print("No estás en una hermandad.") return end
    if not self:IsOfficer() then RMS:Print("Solo los oficiales pueden deshacer.") return end

    self.state.undoStack = self.state.undoStack or {}
    if #self.state.undoStack == 0 then
        RMS:Print("|cffff9900[DKP]|r No hay acciones para deshacer.")
        return
    end

    local last = table.remove(self.state.undoStack)
    local reverseDelta = -last.delta

    -- Aplicar delta inverso a cada jugador afectado
    local appliedTo = {}
    for _, name in ipairs(last.players) do
        local targetName = self:GetResolvedMain(name)
        if not appliedTo[targetName] then
            updateOfficerNote(targetName, reverseDelta)
            appliedTo[targetName] = true
        end
    end

    -- Registrar en el log como acción de Undo
    local undoEntry = {
        id = GenerateUID(), time = time(), by = RMS:PlayerName(),
        delta = reverseDelta, reason = "[UNDO] " .. (last.reason or ""),
        players = table.concat(last.players, ","),
    }
    table.insert(self.state.log, 1, undoEntry)
    if #self.state.log > 1000 then table.remove(self.state.log) end

    -- Anunciar al guild
    local playerList = table.concat(last.players, ", ")
    if #playerList > 80 then playerList = playerList:sub(1, 77) .. "..." end
    local msg = string.format("[DESHACER] %+d DKP (%s): %s", reverseDelta, last.reason or "Sin motivo", playerList)
    pcall(SendChatMessage, msg, "GUILD")

    -- Comunicar a otros clientes
    RMS.Comm:Send("dkp", "delta", {
        id = undoEntry.id, by = RMS:PlayerName(),
        d = reverseDelta, r = "[UNDO] " .. (last.reason or ""),
        p = table.concat(last.players, ","),
    }, "GUILD")

    RMS:Print("|cff00ff00[DKP]|r Acción deshecha: %+d DKP (%s) a %d jugador(es).",
        reverseDelta, last.reason or "?", #last.players)
    self:Refresh()
end

function M:Reset()
    if not self.state then return end
    if not self:IsOfficer() then RMS:Print("Only officers can reset DKP.") return end
    
    -- MODIFICACION HIBRIDA: Limpiar notas
    for name, _ in pairs(GetRosterStandings()) do
        if self:GetResolvedMain(name) == name then
            local n = GetNumGuildMembers() or 0
            for i = 1, n do
                local guildName = GetGuildRosterInfo(i)
                if guildName and guildName == name then
                    GuildRosterSetOfficerNote(i, "0.0")
                    break
                end
            end
        end
    end
    
    pushLog({ time = time(), by = RMS:PlayerName(), delta = 0, reason = "RESET ALL", players = "*" })
    RMS.Comm:Send("dkp", "reset", { by = RMS:PlayerName() }, "GUILD")
    RMS:Print("DKP standings reset.")
    self:Refresh()
end

-- Sincronización Administrativa (Relaciones y Metadatos)
function M:ImportFromNotes()
    if not GetNumGuildMembers then return end
    RMS:Print("|cffffff00Iniciando Sincronización Administrativa...|r")
    WithFullGuildRoster(function()
        local n = GetNumGuildMembers() or 0
        if n == 0 then return end
        local ai = self.state.altIndex
        local nameSet = {}
        local rosterData = {}
        
        -- 1. Scan completo y metadatos
        for i = 1, n do
            local name, _, rankIndex, _, classDisplay, _, _, officerNote, online, _, classFile = GetGuildRosterInfo(i)
            if name then
                nameSet[name] = true
                rosterData[name] = {
                    note   = officerNote or "",
                    class  = classFile or classDisplay,
                    rank   = rankIndex,
                    online = online,
                }
                -- Actualizar metadatos persistentes
                ai.classes[name]      = classFile or classDisplay
                ai.ranks[name]        = rankIndex
                ai.officerNotes[name] = officerNote or ""
                ai.lastSeen[name]     = time()
            end
        end
        
        -- 2. Relaciones Main/Alter (aditivo, con limpieza de huérfanos)
        for altName, data in pairs(rosterData) do
            local ep = DecodeOfficerNote(data.note)
            if not ep then
                -- Posible referencia a main
                local candidate = data.note:gsub("^%s*(.-)%s*$", "%1"):gsub("^%l", string.upper)
                if candidate ~= "" and nameSet[candidate] then
                    local mainNote = rosterData[candidate].note
                    if DecodeOfficerNote(mainNote) then
                        -- Limpiar vínculo antiguo si cambia de main
                        local oldMain = ai.altToMain and ai.altToMain[altName]
                        if oldMain and oldMain ~= candidate and ai.mainToAlts and ai.mainToAlts[oldMain] then
                            for i = #ai.mainToAlts[oldMain], 1, -1 do
                                if ai.mainToAlts[oldMain][i] == altName then
                                    table.remove(ai.mainToAlts[oldMain], i)
                                    break
                                end
                            end
                        end
                        -- Actualizar mapeo
                        ai.altToMain = ai.altToMain or {}
                        ai.altToMain[altName] = candidate
                        ai.mainToAlts = ai.mainToAlts or {}
                        ai.mainToAlts[candidate] = ai.mainToAlts[candidate] or {}
                        local found = false
                        for _, v in ipairs(ai.mainToAlts[candidate]) do
                            if v == altName then found = true; break end
                        end
                        if not found then
                            table.insert(ai.mainToAlts[candidate], altName)
                        end
                    end
                end
            else
                -- Ahora tiene DKP numérico → limpiar si antes era alter
                if ai.altToMain and ai.altToMain[altName] then
                    local oldMain = ai.altToMain[altName]
                    ai.altToMain[altName] = nil
                    if ai.mainToAlts and ai.mainToAlts[oldMain] then
                        for i = #ai.mainToAlts[oldMain], 1, -1 do
                            if ai.mainToAlts[oldMain][i] == altName then
                                table.remove(ai.mainToAlts[oldMain], i)
                                break
                            end
                        end
                    end
                end
            end
        end
        
        self.state.altIndexSeeded = true
        self.state.lastFullSync   = time()
        RMS:Print("|cff00ff00Éxito:|r %d miembros analizados.", n)
    end, true)
    self:Refresh()
end

-- Exportación JSON para Discord
function M:ExportJSON()
    local standings = GetRosterStandings()
    local rows = {}
    for name, s in pairs(standings) do
        local balance = tonumber(s.balance) or 0
        if self:GetResolvedMain(name) == name and balance > 0 then
            table.insert(rows, {
                name = name,
                dkp = balance,
                class = (self.state.altIndex and self.state.altIndex.classes[name]) or "UNKNOWN"
            })
        end
    end

    -- Ordenar de mayor a menor DKP
    table.sort(rows, function(a, b)
        if a.dkp ~= b.dkp then
            return a.dkp > b.dkp
        end
        return a.name < b.name
    end)

    -- Serializar a JSON compacto
    local list = {}
    for _, row in ipairs(rows) do
        table.insert(list, ("{\"name\":\"%s\",\"dkp\":%d,\"class\":\"%s\"}"):format(
            row.name, row.dkp, row.class
        ))
    end

    if #list == 0 then return "[]" end
    return "[" .. table.concat(list, ",") .. "]"
end

-- ---------- UI (POC) ----------
function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "Gestión DKP")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)

    local status = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(status, 12, true)
    status:SetPoint("RIGHT", header, "RIGHT", -10, 0)

    -- Controls row
    local ctrl = CreateFrame("Frame", nil, panel)
    ctrl:SetHeight(30)
    ctrl:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    ctrl:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)

    local deltaBox = Skin:EditBox(ctrl, 80, 22)
    deltaBox:SetPoint("LEFT", 6, 0)
    deltaBox:SetText("0")

    local reasonBox = Skin:EditBox(ctrl, 320, 22)
    reasonBox:SetPoint("LEFT", deltaBox, "RIGHT", 8, 0)

    local awardBtn = Skin:Button(ctrl, "Aplicar", 90, 22)
    awardBtn:SetPoint("LEFT", reasonBox, "RIGHT", 8, 0)

    local undoBtn = Skin:Button(ctrl, "Deshacer", 90, 22)
    undoBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)

    local syncBtn = Skin:Button(ctrl, "Sincronizar Notas", 140, 22)
    syncBtn:SetPoint("LEFT", undoBtn, "RIGHT", 6, 0)

    local importBtn = Skin:Button(ctrl, "Importar Notas", 120, 22)
    importBtn:SetPoint("LEFT", syncBtn, "RIGHT", 6, 0)

    local raidBtn = Skin:Button(ctrl, "Iniciar Raid", 110, 22)
    raidBtn:SetPoint("RIGHT", -6, 0)

    -- Scroll list of guild mains
    local function buildRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(20)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg

        local cb = Skin:CheckBox(r, "")
        cb:SetPoint("LEFT", 0, 0)

        local name = r:CreateFontString(nil, "OVERLAY")
        Skin:Font(name, 12, false)
        name:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        name:SetJustifyH("LEFT")

        local bal = r:CreateFontString(nil, "OVERLAY")
        Skin:Font(bal, 12, true)
        bal:SetPoint("RIGHT", -6, 0)

        cb.OnValueChanged = function(_, val)
            if r._item then M.selected[r._item.name] = val end
        end
        r.checkbox = cb; r.name = name; r.balance = bal
        r:SetScript("OnMouseUp", function() r.checkbox.box:Click() end)
        return r
    end

    local function updateRow(r, item, idx, alt)
        if not item then return end
        r._item = item
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
        r.name:SetText(item.name .. (item.online and "" or " (off)") )
        r.balance:SetText(tostring(M:GetBalance(item.name)))
        r.checkbox:SetChecked(M.selected[item.name])
    end

    local list = Skin:ScrollList(panel, 22, buildRow, updateRow)
    list:SetPoint("TOPLEFT", ctrl, "BOTTOMLEFT", 0, -8)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    -- Wiring actions
    awardBtn:SetScript("OnMouseUp", function()
        local delta = tonumber(deltaBox:GetText()) or 0
        local reason = reasonBox:GetText()
        local players = {}
        for name, sel in pairs(M.selected) do if sel then table.insert(players, name) end end
        M:Award(players, delta, reason)
    end)
    undoBtn:SetScript("OnMouseUp", function() M:Undo() end)
    syncBtn:SetScript("OnMouseUp", function() M:ImportFromNotes() end)
    importBtn:SetScript("OnMouseUp", function() RMS:Print(M:ExportJSON()) end)
    raidBtn:SetScript("OnMouseUp", function()
        if self.state and self.state.activeRaid then self:EndRaid() else self:StartRaid() end
    end)

    -- expose ui handles and initial population
    self._ui = { panel = panel, status = status, list = list, deltaBox = deltaBox, reasonBox = reasonBox }
    self:Refresh()
    return panel
end

function M:Refresh()
    if not self._ui then return end
    local C = RMS.Skin.COLOR
    if self.state and self.state.activeRaid then
        self._ui.status:SetText("RAID: " .. (self.state.raids and (self.state.raids[self.state.activeRaid] and self.state.raids[self.state.activeRaid].name or "?") or "?"))
        self._ui.status:SetTextColor(unpack(C.good))
    else
        local sText = "Sin Raid Activa"
        if self._waitingForRoster then
            sText = sText .. " | |cffffff00Actualizando roster...|r"
        end
        self._ui.status:SetText(sText)
        self._ui.status:SetTextColor(unpack(C.textDim))
    end

    -- snapshot roster
    local roster = self:GuildMembers() or {}
    local data = {}
    for i, v in ipairs(roster) do data[i] = v end
    self._ui.list:SetData(data)
end

-- ---------- comm ----------
RMS.Comm:On("dkp", "delta", function(p, sender)
    if not M.state then return end
    if not M:IsOfficer(sender) then return end
    if sender == RMS:PlayerName() then return end  -- already applied locally
    local delta = tonumber(p.d); if not delta then return end

    -- [NEW] Deduplicación por UID: ignorar si ya tenemos esta entrada
    if p.id then
        for _, existing in ipairs(M.state.log) do
            if existing.id == p.id then return end
        end
    end

    local entry = {
        id = p.id, time = time(), by = sender,
        delta = delta, reason = p.r or "", players = p.p or "",
    }
    table.insert(M.state.log, 1, entry)
    if #M.state.log > 1000 then table.remove(M.state.log) end
    
    if M.state.activeRaid then
        table.insert(M.state.raids[M.state.activeRaid].entries, 1, entry)
    end
    
    M:Refresh()
end)

RMS.Comm:On("dkp", "reset", function(_, sender)
    if not M.state then return end
    if not M:IsOfficer(sender) then return end
    pushLog({ time = time(), by = sender, delta = 0, reason = "RESET ALL", players = "*" })
    M:Refresh()
end)

-- ---------- late-join sync (No-op since Blizzard syncs notes) ----------
function M:RequestSync()
end

RMS.Comm:On("dkp", "syncreq", function() end)
RMS.Comm:On("dkp", "syncpage", function() end)

function M:ImportFromJSON(str)
    if not str or str == "" then return end
    local count = 0
    for entry in str:gmatch("{(.-)}") do
        local name = entry:match('"name"%s*:%s*"(.-)"')
        local dkp  = entry:match('"dkp"%s*:%s*(-?%d+)')
        if name and dkp then
            local val = tonumber(dkp)
            local resolved = self:GetResolvedMain(name)
            local n = GetNumGuildMembers() or 0
            for i = 1, n do
                local guildName, _, _, _, _, _, _, note = GetGuildRosterInfo(i)
                if guildName and guildName == resolved then
                    local _, gp = DecodeOfficerNote(note)
                    gp = gp or 0
                    local ep = val + gp
                    GuildRosterSetOfficerNote(i, string.format("%d.%d", math.max(0, ep), gp))
                    count = count + 1
                    break
                end
            end
        end
    end
    RMS:Print("|cff00ff00Éxito:|r DKP sincronizados desde JSON (%d registros).", count)
    self:Refresh()
end

function M:ShowImportPopup()
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local f = self._importPopup
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(450, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        Skin:SetBackdrop(f, Skin.COLOR.bgMain, Skin.COLOR.borderHi)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        
        Skin:Header(f, "Importar Datos DKP (JSON)"):SetPoint("TOPLEFT", 10, -10)
        
        local desc = f:CreateFontString(nil, "OVERLAY")
        Skin:Font(desc, 10, false)
        desc:SetTextColor(unpack(C.textDim))
        desc:SetPoint("TOPLEFT", 12, -35)
        desc:SetWidth(420)
        desc:SetJustifyH("LEFT")
        desc:SetText("Pega el código JSON abajo y pulsa 'Procesar'.\nSobrescribirá los DKP actuales y las notas de oficial.")
        
        local edit = CreateFrame("EditBox", nil, f)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(99999)
        edit:SetAutoFocus(true)
        Skin:Font(edit, 10, false)
        edit:SetTextColor(unpack(C.text))
        edit:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -70)
        edit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 45)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        edit:SetScript("OnCursorChanged", function() end)
        edit:SetScript("OnEditFocusGained", function() edit:HighlightText() end)
        edit:SetScript("OnEditFocusLost", function() edit:HighlightText(0, 0) end)
        edit:SetFrameLevel(30)
        if edit.SetBackdrop then
            Skin:SetBackdrop(edit, C.bgPanel, C.borderHi)
        end
        f.edit = edit
        
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(180, 25)
        btn:SetPoint("BOTTOM", 0, 10)
        btn:SetText("PROCESAR IMPORTACIÓN")
        btn:SetFrameStrata("DIALOG")
        btn:SetFrameLevel(50)
        btn:SetScript("OnClick", function()
            self:ImportFromJSON(edit:GetText())
            f:Hide()
        end)

        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(80, 25)
        close:SetPoint("RIGHT", btn, "LEFT", -10, 0)
        close:SetText("Cancelar")
        close:SetFrameStrata("DIALOG")
        close:SetFrameLevel(50)
        close:SetScript("OnClick", function() f:Hide() end)
        
        self._importPopup = f
    end
    f:Show()
    f.edit:SetText("")
    f.edit:SetFocus()
end

-- ---------- events ----------
M.events = {
    PLAYER_LOGIN = function(self)
        self:LoadGuildState()
        local d = CreateFrame("Frame"); local t = 0
        d:SetScript("OnUpdate", function(s, dt)
            t = t + dt
            if t > 4 then s:SetScript("OnUpdate", nil); self:RequestSync() end
        end)
    end,
    PLAYER_GUILD_UPDATE  = function(self) self:LoadGuildState(); if self._ui then self:Refresh() end end,
    GUILD_ROSTER_UPDATE  = function(self)
        M._rankCacheTime = 0

        if M._suspendGuildRefresh then
            return
        end

        -- Intentar vaciar notas pendientes cuando el roster cambie
        self:FlushPendingOfficerNotes()

        if self._ui then
            self:Refresh()
        end
    end,
    RAID_ROSTER_UPDATE   = function(self)
        -- Auto-end raid if player leaves raid group
        if self.state and self.state.activeRaid and GetNumRaidMembers() == 0 then
            self:EndRaid()
        end
    end,
    COMBAT_LOG_EVENT_UNFILTERED = function(self, ...)
        local _, event, _, _, _, _, _, _, destName = ...
        if event == "UNIT_DIED" and STARTER_BOSSES[destName] then
            if not self.state.activeRaid then
                self:StartRaid(STARTER_BOSSES[destName] .. " (" .. date("%d/%m") .. ")")
            end
        end
    end,
}

-- ---------- slash ----------
function M:OnSlash(arg)
    arg = (arg or ""):gsub("^%s+",""):gsub("%s+$","")
    if arg == "sync"  then return self:RequestSync() end
    if arg == "reset" then return self:Reset()       end
    RMS.UI:Show("dkp")
end

-- =============================================================
-- UI
-- =============================================================

local function CLASS_HEX(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return "ffffffff"
end

function M:BuildUI(parent)
    local Skin = RMS.Skin
    local C    = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local status = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(status, 11, true)
    status:SetTextColor(unpack(C.accent))
    status:SetPoint("TOPLEFT", 8, -8)
    status:SetPoint("RIGHT", -8, 0)
    status:SetJustifyH("LEFT")

    local LIST_W = 340
    local listHdr = Skin:Header(panel, "Lista de Miembros")
    listHdr:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -4, -6)
    listHdr:SetWidth(LIST_W)

    -- [NEW] Fila de checkboxes de filtrado (debajo del header)
    local filterRow = CreateFrame("Frame", nil, panel)
    filterRow:SetPoint("TOPLEFT", listHdr, "BOTTOMLEFT", 0, -2)
    filterRow:SetSize(LIST_W, 20)

    local onlyOnline = CreateFrame("CheckButton", nil, filterRow, "UICheckButtonTemplate")
    onlyOnline:SetSize(20, 20)
    onlyOnline:SetPoint("LEFT", 4, 0)
    local ooFs = onlyOnline:CreateFontString(nil, "OVERLAY")
    Skin:Font(ooFs, 10, false); ooFs:SetPoint("LEFT", onlyOnline, "RIGHT", 4, 0)
    ooFs:SetText("Online")
    onlyOnline:SetScript("OnClick", function(s)
        M.filterOnlyOnline = s:GetChecked()
        M:Refresh()
    end)
    M._onlyOnlineCheck = onlyOnline

    local viewOffline = CreateFrame("CheckButton", nil, filterRow, "UICheckButtonTemplate")
    viewOffline:SetSize(20, 20)
    viewOffline:SetPoint("LEFT", ooFs, "RIGHT", 12, 0)
    local voFs = viewOffline:CreateFontString(nil, "OVERLAY")
    Skin:Font(voFs, 10, false); voFs:SetPoint("LEFT", viewOffline, "RIGHT", 4, 0)
    voFs:SetText("Mains Offline")
    viewOffline:SetScript("OnClick", function(s)
        M.filterViewOffline = s:GetChecked()
        M:Refresh()
    end)
    M._viewOfflineCheck = viewOffline

    local onlyRaid = CreateFrame("CheckButton", nil, filterRow, "UICheckButtonTemplate")
    onlyRaid:SetSize(20, 20)
    onlyRaid:SetPoint("LEFT", voFs, "RIGHT", 12, 0)
    local orFs = onlyRaid:CreateFontString(nil, "OVERLAY")
    Skin:Font(orFs, 10, false); orFs:SetPoint("LEFT", onlyRaid, "RIGHT", 4, 0)
    orFs:SetText("Solo en Banda")
    onlyRaid:SetScript("OnClick", function(s)
        M.filterOnlyRaid = s:GetChecked()
        M:Refresh()
    end)
    M._onlyRaidCheck = onlyRaid

    local function buildRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(20)
        r:EnableMouse(true)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg
        local box = CreateFrame("Button", nil, r)
        box:SetSize(14, 14); box:SetPoint("LEFT", 4, 0)
        Skin:SetBackdrop(box, C.bgRow, C.border)
        local check = box:CreateTexture(nil, "OVERLAY")
        check:SetTexture(Skin.TEX_WHITE); check:SetVertexColor(unpack(C.accent))
        check:SetPoint("TOPLEFT", 3, -3); check:SetPoint("BOTTOMRIGHT", -3, 3); check:Hide()
        box._check = check
        r.box = box
        local who = r:CreateFontString(nil, "OVERLAY"); Skin:Font(who, 11, true)
        who:SetPoint("LEFT", box, "RIGHT", 6, 0); who:SetWidth(110)
        who:SetJustifyH("LEFT"); who:SetWordWrap(false); who:SetNonSpaceWrap(false)
        r.who = who
        local bal = r:CreateFontString(nil, "OVERLAY"); Skin:Font(bal, 11, true)
        bal:SetPoint("LEFT", who, "RIGHT", 4, 0); bal:SetWidth(48)
        bal:SetJustifyH("RIGHT"); bal:SetTextColor(unpack(C.accent)); r.bal = bal
        local earn = r:CreateFontString(nil, "OVERLAY"); Skin:Font(earn, 10, false)
        earn:SetPoint("LEFT", bal, "RIGHT", 4, 0); earn:SetWidth(46)
        earn:SetJustifyH("RIGHT"); earn:SetTextColor(unpack(C.textDim)); r.earn = earn
        local spent = r:CreateFontString(nil, "OVERLAY"); Skin:Font(spent, 10, false)
        spent:SetPoint("LEFT", earn, "RIGHT", 4, 0); spent:SetWidth(46)
        spent:SetJustifyH("RIGHT"); spent:SetTextColor(unpack(C.textDim)); r.spent = spent
        local online = r:CreateFontString(nil, "OVERLAY"); Skin:Font(online, 9, false)
        online:SetPoint("RIGHT", -6, 0); online:SetWidth(28)
        online:SetJustifyH("RIGHT"); r.online = online
        return r
    end

    local function updateRow(r, item, idx, alt)
        if not item then return end
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
        r.who:SetText(("|c%s%s|r"):format(CLASS_HEX(item.class), item.name))
        r.bal:SetText(tostring(item.balance or 0))
        r.earn:SetText("+"..(item.earned or 0))
        r.spent:SetText("-"..(item.spent or 0))
        r.online:SetText(item.online and "|cff60ff60on|r" or "|cff666666off|r")
        if M.selected[item.name] then r.box._check:Show() else r.box._check:Hide() end
        r:SetScript("OnEnter", function(s)
            s.bg:SetVertexColor(0.2, 0.2, 0.25, 0.8)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local name = item.name
            local main = item.resolvedMain
            local alts = M.altIndex and M.altIndex.mainToAlts[main]

            if item.isAlt then
                GameTooltip:AddLine("|cffFFAA00Personaje Alter|r", 1, 0.8, 0)
                GameTooltip:AddDoubleLine("Main Principal:", main, 0.7, 0.7, 0.7, 1, 1, 1)
            else
                GameTooltip:AddLine("|cffFFAA00Personaje Principal (Main)|r", 1, 0.8, 0)
            end

            if alts and #alts > 0 then
                GameTooltip:AddLine("Lista de Alters:", 1, 0.8, 0)
                for i, altName in ipairs(alts) do 
                    local color = (altName == name) and "|cffffffff" or "|cffaaaaaa"
                    GameTooltip:AddLine(i..".- "..color..altName.."|r", 0.7, 0.7, 0.7) 
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("DKP del Main:", item.balance or 0, 1, 1, 1, 0.9, 0.74, 0.4)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(s)
            r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.6)
            GameTooltip:Hide()
        end)
        r.box:SetScript("OnClick", function()
            M.selected[item.name] = not M.selected[item.name] or nil
            M:Refresh()
        end)
    end

    local listScroll = Skin:ScrollList(panel, 20, buildRow, updateRow)
    listScroll:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -2)
    listScroll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    listScroll:SetWidth(LIST_W)

    local actHdr = Skin:Header(panel, "Asignar / Descontar")
    actHdr:SetPoint("TOPLEFT", listHdr, "TOPRIGHT", 8, 0)
    actHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

    local actBody = Skin:Panel(panel)
    actBody:SetPoint("TOPLEFT", actHdr, "BOTTOMLEFT", 0, -2)
    actBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    actBody:SetHeight(240)

    local selFs = actBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(selFs, 11, false); selFs:SetTextColor(unpack(C.text))
    selFs:SetPoint("TOPLEFT", 8, -6); selFs:SetPoint("RIGHT", -8, 0)
    selFs:SetJustifyH("LEFT"); selFs:SetWordWrap(false); selFs:SetNonSpaceWrap(false)

    local rsnLabel = actBody:CreateFontString(nil, "OVERLAY"); Skin:Font(rsnLabel, 10, false)
    rsnLabel:SetTextColor(unpack(C.textDim))
    rsnLabel:SetPoint("TOPLEFT", selFs, "BOTTOMLEFT", 0, -8); rsnLabel:SetWidth(50)
    rsnLabel:SetText("Motivo:")
    local rsnEdit = Skin:EditBox(actBody, 1, 22)
    rsnEdit:SetPoint("LEFT", rsnLabel, "RIGHT", 4, 0)
    rsnEdit:SetPoint("RIGHT", actBody, "RIGHT", -8, 0)

    local amtLabel = actBody:CreateFontString(nil, "OVERLAY"); Skin:Font(amtLabel, 10, false)
    amtLabel:SetTextColor(unpack(C.textDim))
    amtLabel:SetPoint("TOPLEFT", rsnLabel, "BOTTOMLEFT", 0, -10); amtLabel:SetWidth(50)
    amtLabel:SetText("Cantidad:")
    local amtEdit = Skin:EditBox(actBody, 50, 22)
    amtEdit:SetPoint("LEFT", amtLabel, "RIGHT", 4, 0)
    amtEdit:SetNumeric(true); amtEdit:SetText("10")

    local function selectedNames()
        local out = {}
        for nm in pairs(M.selected) do out[#out+1] = nm end
        table.sort(out); return out
    end

    local awardBtn = Skin:Button(actBody, "Asignar (+)", 80, 22)
    awardBtn:SetPoint("LEFT", amtEdit, "RIGHT", 6, 0)
    awardBtn:SetScript("OnMouseUp", function()
        local v = tonumber(amtEdit:GetText() or "")
        if not v or v <= 0 then RMS:Print("Bad amount.") return end
        self:Award(selectedNames(), v, rsnEdit:GetText())
    end)
    local dedBtn = Skin:Button(actBody, "Descontar (-)", 80, 22)
    dedBtn:SetPoint("LEFT", awardBtn, "RIGHT", 4, 0)
    dedBtn:SetScript("OnMouseUp", function()
        local v = tonumber(amtEdit:GetText() or "")
        if not v or v <= 0 then RMS:Print("Bad amount.") return end
        self:Award(selectedNames(), -v, rsnEdit:GetText())
    end)

    local presetLbl = actBody:CreateFontString(nil, "OVERLAY"); Skin:Font(presetLbl, 10, false)
    presetLbl:SetTextColor(unpack(C.textDim))
    presetLbl:SetPoint("TOPLEFT", amtLabel, "BOTTOMLEFT", 0, -14); presetLbl:SetWidth(50)
    presetLbl:SetText("Atajos:")

    local p1 = Skin:Button(actBody, "Puntualidad +50", 110, 22)
    p1:SetPoint("LEFT", presetLbl, "RIGHT", 4, 0)
    p1:SetScript("OnMouseUp", function() self:Award(selectedNames(), 50, "Puntualidad") end)
    local p2 = Skin:Button(actBody, "Frasco +50", 90, 22)
    p2:SetPoint("LEFT", p1, "RIGHT", 4, 0)
    p2:SetScript("OnMouseUp", function() self:Award(selectedNames(), 50, "Frasco / Consumibles") end)
    local p3 = Skin:Button(actBody, "Fallo -50", 80, 22)
    p3:SetPoint("LEFT", p2, "RIGHT", 4, 0)
    p3:SetScript("OnMouseUp", function() self:Award(selectedNames(), -50, "Fallo Mec\195\161nica / Wipe") end)

    local bulkLbl = actBody:CreateFontString(nil, "OVERLAY"); Skin:Font(bulkLbl, 10, false)
    bulkLbl:SetTextColor(unpack(C.textDim))
    bulkLbl:SetPoint("TOPLEFT", presetLbl, "BOTTOMLEFT", 0, -14); bulkLbl:SetWidth(50)
    bulkLbl:SetText("Selecc.:")

    local selRaid = Skin:Button(actBody, "En Banda", 80, 22)
    selRaid:SetPoint("LEFT", bulkLbl, "RIGHT", 4, 0)
    selRaid:SetScript("OnMouseUp", function()
        local roster = RMS:GetRosterNames()
        wipe(M.selected)
        for _, nm in ipairs(roster) do M.selected[nm] = true end
        self:Refresh()
    end)
    local selG15 = Skin:Button(actBody, "Banda 1-5", 80, 22)
    selG15:SetPoint("LEFT", selRaid, "RIGHT", 4, 0)
    selG15:SetScript("OnMouseUp", function()
        wipe(M.selected)
        for i = 1, GetNumRaidMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name and subgroup <= 5 then M.selected[name] = true end
        end
        self:Refresh()
    end)
    local selNone = Skin:Button(actBody, "Limpiar", 60, 22)
    selNone:SetPoint("LEFT", selG15, "RIGHT", 4, 0)
    selNone:SetScript("OnMouseUp", function() wipe(M.selected); self:Refresh() end)

    local syncBtn = Skin:Button(actBody, "Sincronizar Notas", 120, 22)
    syncBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    syncBtn:SetScript("OnMouseUp", function() self:ImportFromNotes() end)
    local exportBtn = Skin:Button(actBody, "Exportar Discord", 110, 22)
    exportBtn:SetPoint("RIGHT", syncBtn, "LEFT", -4, 0)
    exportBtn:SetScript("OnMouseUp", function()
        local json = self:ExportJSON()
        self:ShowExportPopup(json)
    end)
    local importBtn = Skin:Button(actBody, "Importar JSON", 110, 22)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetScript("OnMouseUp", function() self:ShowImportPopup() end)

    -- [NEW] Botón Deshacer
    local undoBtn = Skin:Button(actBody, "Deshacer", 80, 22)
    undoBtn:SetPoint("BOTTOMLEFT", 8, 8)
    undoBtn:SetScript("OnMouseUp", function() self:Undo() end)

    local logHdr = Skin:Header(panel, "Registro Reciente")
    logHdr:SetPoint("TOPLEFT", actBody, "BOTTOMLEFT", 0, -8)
    logHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

    local startRaidBtn = Skin:Button(panel, "Iniciar Raid", 90, 20)
    startRaidBtn:SetPoint("RIGHT", logHdr, "RIGHT", -120, 0)
    startRaidBtn:SetScript("OnMouseUp", function() self:StartRaid() end)
    local endRaidBtn = Skin:Button(panel, "Finalizar", 80, 20)
    endRaidBtn:SetPoint("LEFT", startRaidBtn, "RIGHT", 4, 0)
    endRaidBtn:SetScript("OnMouseUp", function() self:EndRaid() end)

    local viewDropdown = Skin:Button(panel, "Ver: Historial Completo", 160, 20)
    viewDropdown:SetPoint("RIGHT", startRaidBtn, "LEFT", -10, 0)
    viewDropdown:SetScript("OnMouseUp", function()
        local menu = { { text = "Historial Completo", func = function() self.viewRaid = nil; self:Refresh() end } }
        for i, r in ipairs(self.state.raids) do
            table.insert(menu, { text = r.name, func = function() self.viewRaid = i; self:Refresh() end })
        end
        RMS:ShowMenu(menu)
    end)

    local function buildLogRow(parent)
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(20)
        r:EnableMouse(true)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(Skin.TEX_WHITE); r.bg = bg
        local fs = r:CreateFontString(nil, "OVERLAY"); Skin:Font(fs, 11, false)
        fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false); fs:SetNonSpaceWrap(false)
        r.fs = fs
        return r
    end
    local function updateLogRow(r, item, idx, alt)
        if not item then return end
        r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.5)
        local hhmm = date("%m/%d %H:%M", item.time or 0)
        local delta = item.delta or 0
        local color = (delta > 0 and "|cff60ff60+") or (delta < 0 and "|cffff6060") or "|cffffffff"
        
        -- Truncar visualmente los nombres si son demasiados para la fila, pero mostrarlos en tooltip
        local players = item.players or "?"
        r.fs:SetText(("|cff999999%s|r %s%d|r  |cff60ff60%s|r  |cffcccccc%s|r  |cff666666(by %s)|r"):format(
            hhmm, color, delta, item.reason or "Acción", players, item.by or "?"))
            
        r:SetScript("OnEnter", function(s)
            s.bg:SetVertexColor(0.2, 0.2, 0.25, 0.8)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Detalle del Registro", 1, 0.8, 0)
            GameTooltip:AddDoubleLine("Fecha:", hhmm, 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Acción:", (item.delta or 0) > 0 and "Asignación" or "Descuento", 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Cantidad:", color..(item.delta or 0).." DKP", 0.7, 0.7, 0.7)
            GameTooltip:AddDoubleLine("Motivo:", item.reason or "Sin motivo", 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Oficial:", item.by or "?", 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Jugadores Afectados:", 1, 1, 1)
            local pList = {}
            for p in players:gmatch("[^,]+") do table.insert(pList, p) end
            table.sort(pList)
            for i, pName in ipairs(pList) do
                GameTooltip:AddLine(i..".- "..pName, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(s)
            r.bg:SetVertexColor(alt and 0.10 or 0.13, alt and 0.10 or 0.13, alt and 0.12 or 0.15, 0.5)
            GameTooltip:Hide()
        end)
    end

    local logScroll = Skin:ScrollList(panel, 20, buildLogRow, updateLogRow)
    logScroll:SetPoint("TOPLEFT", logHdr, "BOTTOMLEFT", 0, -2)
    logScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    self._ui = {
        panel = panel, status = status, selFs = selFs,
        listScroll = listScroll, logScroll = logScroll,
        amtEdit = amtEdit, rsnEdit = rsnEdit,
        awardBtn = awardBtn, dedBtn = dedBtn,
        p1 = p1, p2 = p2, p3 = p3,
        selRaid = selRaid, selG15 = selG15, selNone = selNone,
        syncBtn = syncBtn, exportBtn = exportBtn, importBtn = importBtn,
        undoBtn = undoBtn,
        startRaidBtn = startRaidBtn, endRaidBtn = endRaidBtn,
        viewDropdown = viewDropdown,
        filterRow = filterRow,
        onlyRaid = onlyRaid, orFs = orFs,
        viewOffline = viewOffline, voFs = voFs,
        onlyOnline = onlyOnline, ooFs = ooFs,
    }
    self:Refresh()
    return panel
end

-- MODIFICACION HIBRIDA: Ventana Emergente para copiar JSON
function M:ShowExportPopup(text)
    local Skin = RMS.Skin
    local f = self.exportPopup
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(500, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        Skin:SetBackdrop(f, Skin.COLOR.bgMain, Skin.COLOR.borderHi)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        
        local title = Skin:Header(f, "Exportar Datos para Discord Bot")
        title:SetPoint("TOPLEFT", 8, -8)
        title:SetPoint("TOPRIGHT", -8, -8)
        
        local desc = f:CreateFontString(nil, "OVERLAY")
        Skin:Font(desc, 11, false)
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        desc:SetText("Copia el código y pégalo en tu canal de Discord:")
        desc:SetTextColor(0.8, 0.8, 0.8)
        
        local ebScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        ebScroll:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
        ebScroll:SetPoint("BOTTOMRIGHT", -30, 40)
        Skin:SetBackdrop(ebScroll, Skin.COLOR.bgPanel, Skin.COLOR.border)
        
        local eb = CreateFrame("EditBox", nil, ebScroll)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(10000) -- [FIXED: FIX-DKP-4]
        eb:SetFont(Skin.FONT, 12, "")
        eb:SetWidth(440)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        ebScroll:SetScrollChild(eb)
        f.eb = eb
        
        local close = Skin:Button(f, "Cerrar", 100, 24)
        close:SetPoint("BOTTOM", 0, 8)
        close:SetScript("OnMouseUp", function() f:Hide() end)
        
        self.exportPopup = f
    end
    f.eb:SetText(text)
    f.eb:HighlightText()
    f:Show()
end

function M:Refresh()
    if not self._ui then return end
    local C = RMS.Skin.COLOR

    local rosterStandings = GetRosterStandings()
    local state = self.state

    -- header status
    if not state then
        self._ui.status:SetText("|cffff6060Sin hermandad|r")
    else
        local role = self:IsOfficer() and "|cff60ff60Oficial|r" or "|cffaaaaaaMiembro|r"
        -- Es posible que IsOfficer haya alterado self.state por eventos síncronos, actualizamos state local
        state = self.state 
        if not state then return end -- Cortafuegos de seguridad
        
        local mainCount = 0
        for name, _ in pairs(rosterStandings) do
            if self:GetResolvedMain(name) == name then
                mainCount = mainCount + 1
            end
        end
        
        local statusText = ("Hermandad: %s | %s | Mains: |cffffffff%d|r"):format(self.guild, role, mainCount)
        if not state.altIndexSeeded then
            statusText = statusText .. " | |cffff6060(Sin sincronizaci\195\179n administrativa)|r"
        end
        if self._waitingForRoster then
            statusText = statusText .. " | |cffffff00(Actualizando roster...)|r"
        end
        self._ui.status:SetText(statusText)
    end

    -- selection summary
    local sel = {}
    for nm in pairs(self.selected) do sel[#sel+1] = nm end
    table.sort(sel)
    self._ui.selFs:SetText(("Seleccionados: %d (%s)"):format(#sel,
        #sel == 0 and "ninguno" or table.concat(sel, ", "):sub(1, 100)))

    -- enable/disable officer-only controls
    local canWrite = state and self:IsOfficer()
    for _, b in ipairs({ self._ui.awardBtn, self._ui.dedBtn,
                         self._ui.p1, self._ui.p2, self._ui.p3, self._ui.undoBtn }) do
        if canWrite then b:Enable() else b:Disable() end
    end

    -- merge guild roster + standings into unified list
    local rows = {}
    if state then
        local roster
        if self.filterOnlyRaid then
            -- Mostrar solo raid
            roster = {}
            for i = 1, GetNumRaidMembers() do
                local name, _, _, _, _, class = GetRaidRosterInfo(i)
                if name then
                    table.insert(roster, { name = name, class = class, online = true })
                end
            end
        else
            roster = self:GuildMembers()
        end

        local seen = {}
        for _, m in ipairs(roster) do
            local resolvedMain = self:GetResolvedMain(m.name)
            local s = rosterStandings[resolvedMain] or { balance = 0, earned = 0, spent = 0 }
            rows[#rows+1] = {
                name = m.name, class = m.class, online = m.online,
                balance = s.balance or 0, earned = s.earned or 0, spent = s.spent or 0,
                resolvedMain = resolvedMain,
                isAlt = (resolvedMain ~= m.name)
            }
            seen[m.name] = true
        end
        
        -- [NEW] Agregar mains offline que SALIERON del guild si "Mains Offline" está activado
        if not self.filterOnlyRaid and self.filterViewOffline then
            for name, s in pairs(rosterStandings) do
                if not seen[name] then
                    local isMain = (self:GetResolvedMain(name) == name)
                    if isMain then
                        local cls = state.altIndex and state.altIndex.classes[name] or "UNKNOWN"
                        rows[#rows+1] = { name = name, class = cls, online = false,
                                          balance = s.balance or 0, earned = s.earned or 0, spent = s.spent or 0,
                                          resolvedMain = name, isAlt = false }
                        seen[name] = true
                    end
                end
            end
        end
        
        -- [NEW] Filtrar solo conectados si "Online" está activado
        if self.filterOnlyOnline then
            local filtered = {}
            for _, row in ipairs(rows) do
                if row.online == true then
                    table.insert(filtered, row)
                end
            end
            rows = filtered
        end
        -- sort: balance desc, then name
        table.sort(rows, function(a, b)
            if (a.balance or 0) ~= (b.balance or 0) then return (a.balance or 0) > (b.balance or 0) end
            return a.name < b.name
        end)
    end
    self._ui.listScroll:SetData(rows)

    -- log
    local logData = state and state.log or {}
    if self.viewRaid and state and state.raids[self.viewRaid] then
        logData = state.raids[self.viewRaid].entries
        self._ui.viewDropdown:SetText("Ver: " .. state.raids[self.viewRaid].name)
    else
        self._ui.viewDropdown:SetText("Ver: Historial Completo")
    end
    self._ui.logScroll:SetData(logData)
end
