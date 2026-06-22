-- MVP By Jude -- MRT Integration Core
-- Wrapper to access Method Raid Tools (MRT) as the main raid engine.
-- Exposes clean interfaces for loot history, attendance, etc.

local RMS = MVPByJude
RMS.MRT = RMS.MRT or {}

-- ---------- Difficulty Mapping ----------
local DIFFICULTY_NAMES = {
    [1]  = "10 Player",
    [2]  = "25 Player",
    [3]  = "10 Player (Heroic)",
    [4]  = "25 Player (Heroic)",
    [8]  = "5 Player",
    [14] = "Mythic+",
    [15] = "Normal",
    [16] = "Heroic",
    [23] = "Mythic",
}

local function GetDifficultyName(difficulty)
    difficulty = tonumber(difficulty) or 0
    local name = DIFFICULTY_NAMES[difficulty]
    if name then return name end
    if GetDifficultyInfo then
        return GetDifficultyInfo(difficulty) or tostring(difficulty)
    end
    return tostring(difficulty)
end

-- ---------- Detection & Availability ----------
function RMS.MRT:Detect()
    -- Attempt to locate the MRT global object
    if _G.VMRT then return _G.VMRT end
    if _G.MRT then return _G.MRT end
    if _G.MethodRaidTools then return _G.MethodRaidTools end
    return nil
end

function RMS.MRT:IsAvailable()
    local vmrt = self:Detect()
    if not vmrt then return false end
    if not vmrt.LootHistory then return false end
    if not vmrt.LootHistory.list then return false end
    return true
end

-- ---------- Loot History Access ----------
function RMS.MRT:GetLootHistory()
    -- Returns normalized loot history from MRT.
    -- Each entry has: time, instance, boss, difficulty, player, items (array)
    
    if not self:IsAvailable() then return {} end
    
    local vmrt = self:Detect()
    local rawList = vmrt.LootHistory.list or {}
    local instanceNames = vmrt.LootHistory.instanceNames or {}
    local bossNames = vmrt.LootHistory.bossNames or {}
    
    local result = {}
    
    for i = 1, #rawList do
        local record = rawList[i]
        if type(record) == "string" then
            local timeRec, encounterID, instanceID, difficulty, playerName, classID, quantity, itemLink, rollType
            
            -- Parse the encoded record string
            timeRec, encounterID, instanceID, difficulty, playerName, classID, quantity, itemLink, rollType = strsplit("#", record)
            
            -- Normalize fields
            timeRec = tonumber(timeRec) or 0
            encounterID = tonumber(encounterID) or 0
            instanceID = tonumber(instanceID) or 0
            difficulty = tonumber(difficulty) or 0
            classID = tonumber(classID) or 0
            quantity = tonumber(quantity) or 1
            playerName = playerName or ""
            itemLink = itemLink or ""
            rollType = rollType or ""
            
            -- Resolve names
            local instanceName = instanceNames[instanceID] or ""
            local bossName = ""
            if encounterID > 0 then
                bossName = bossNames[encounterID] or tostring(encounterID)
            end
            
            -- Build normalized entry
            local entry = {
                time       = timeRec,
                timestamp  = timeRec,
                instance   = instanceName,
                instanceID = instanceID,
                boss       = bossName,
                encounterID = encounterID,
                difficulty = difficulty,
                difficultyName = GetDifficultyName(difficulty),
                player     = playerName,
                classID    = classID,
                quantity   = quantity,
                items      = {
                    { link = itemLink, id = tonumber(itemLink:match("item:(%d+)")) or 0, count = quantity }
                },
                rollType   = rollType,
            }
            
            table.insert(result, entry)
        end
    end
    
    return result
end

function RMS.MRT:GetRecentLoot(hours)
    -- Returns only loot entries from the last N hours (default 4).
    hours = hours or 4
    
    local history = self:GetLootHistory()
    if not history or #history == 0 then return {} end
    
    local cutoff = time() - (hours * 3600)
    local recent = {}
    
    for i = 1, #history do
        local entry = history[i]
        if entry.time >= cutoff then
            table.insert(recent, entry)
        end
    end
    
    return recent
end

-- TODO: Future functions for other MRT modules
-- function RMS.MRT:GetAttendance() ... end
-- function RMS.MRT:GetNotes() ... end
-- function RMS.MRT:GetDKPHistory() ... end

return true
