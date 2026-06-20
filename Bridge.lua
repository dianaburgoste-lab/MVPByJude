-- MVPByJude Bridge -> integra módulos MRT dentro de MVP tabbar
local RMS = MVPByJude
local Skin = RMS.Skin
local C = Skin and Skin.COLOR

local MRT_MODULES = {
    { mvpId = "mrt_note",           mrtName = "Note",           title = "Notas" },
    { mvpId = "mrt_excd2",          mrtName = "ExCD2",          title = "CDs de Banda" },
    { mvpId = "mrt_inspect",        mrtName = "Inspect",        title = "Inspección" },
    { mvpId = "mrt_visnote",        mrtName = "VisNote",        title = "Nota Visual" },
    { mvpId = "mrt_reminder",       mrtName = "Reminder",       title = "Recordatorio" },
    { mvpId = "mrt_bosswatcher",    mrtName = "BossWatcher",    title = "Registro de Combate" },
    { mvpId = "mrt_interrupts",     mrtName = "Interrupts",     title = "Interrupciones" },
    { mvpId = "mrt_battleres",      mrtName = "BattleRes",      title = "Resurrecciones" },
    { mvpId = "mrt_whopulled",      mrtName = "WhoPulled",      title = "Quién Pulleó" },
    { mvpId = "mrt_inspectviewer",  mrtName = "InspectViewer",  title = "Inspección de Banda" },
    { mvpId = "mrt_raidcheck",      mrtName = "RaidCheck",      title = "Revisión de Banda" },
    { mvpId = "mrt_invitetool",     mrtName = "InviteTool",     title = "Herramientas Invitación" },
    { mvpId = "mrt_raidgroups",     mrtName = "RaidGroups",     title = "Grupos de Banda" },
    { mvpId = "mrt_marksbar",       mrtName = "MarksBar",       title = "Barra de Marcas" },
    { mvpId = "mrt_marks",          mrtName = "Marks",          title = "Marcas" },
    { mvpId = "mrt_markssimple",    mrtName = "MarksSimple",    title = "Auto-Marcas" },
    { mvpId = "mrt_timers",         mrtName = "Timers",         title = "Temporizadores" },
    { mvpId = "mrt_raidattendance", mrtName = "RaidAttendance", title = "Asistencia Raid" },
    { mvpId = "mrt_encounter",      mrtName = "Encounter",      title = "Estadísticas Jefes" },
    { mvpId = "mrt_loothistory",    mrtName = "LootHistory",    title = "Historial Botín" },
    { mvpId = "mrt_autologging",    mrtName = "AutoLogging",    title = "Guardando Registro" },
    { mvpId = "mrt_lootlink",       mrtName = "LootLink",       title = "Botín al Chat" },
    { mvpId = "mrt_wachecker",      mrtName = "WAChecker",      title = "Revisión WeakAuras" },
    { mvpId = "mrt_profiles",       mrtName = "Profiles",       title = "Perfiles MRT" },
}

local function ApplyMVPSkin(frame)
    if not frame or not Skin then return end
    pcall(function() Skin:SetBackdrop(frame, C.bgPanel, C.border) end)
end

local function CreateMRTWrapper(mvpId, mrtName, title)
    local mod = {
        title = title,
        order = 50,
        BuildUI = function(self, parent)
            local panel = CreateFrame("Frame", nil, parent)
            panel:SetAllPoints()
            if Skin then ApplyMVPSkin(panel) end

            local header = Skin and Skin.Header(panel, title)
            if header then header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8) end

            local openMRT = Skin and Skin.Button(panel, "Abrir en MRT", 120, 22)
            if openMRT and header then
                openMRT:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -3)
                openMRT:SetScript("OnMouseUp", function()
                    if MRT and MRT.A and MRT.A[mrtName] and MRT.A[mrtName].options then
                        if MRT.Options and MRT.Options.Open then
                            MRT.Options:Open(MRT.A[mrtName].options)
                        end
                    end
                end)
            end

            local container = CreateFrame("Frame", nil, panel)
            container:SetPoint("TOPLEFT", header or panel, "BOTTOMLEFT", 0, -4)
            container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

            local mrtMod = MRT and MRT.A and MRT.A[mrtName]
            if mrtMod and mrtMod.options then
                local opts = mrtMod.options
                if not opts.isLoaded and opts.Load then
                    local ok, err = pcall(opts.Load, opts)
                    if ok then opts.isLoaded = true else RMS:Print("Error cargando opciones MRT %s: %s", mrtName, tostring(err)) end
                end
                if opts.SetParent then
                    opts:SetParent(container)
                    opts:ClearAllPoints()
                    opts:SetAllPoints(container)
                    ApplyMVPSkin(opts)
                    opts:Show()
                else
                    -- fallback: try to anchor to container
                    opts:ClearAllPoints(); opts:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
                end
            else
                local msg = container:CreateFontString(nil, "OVERLAY")
                if Skin then Skin.Font(msg, 13, false) end
                msg:SetTextColor(0.7,0.7,0.7)
                msg:SetPoint("CENTER")
                msg:SetText("Módulo MRT '" .. mrtName .. "' no disponible.")
            end
            return panel
        end,
    }
    RMS:RegisterModule(mvpId, mod)
end

for _, def in ipairs(MRT_MODULES) do
    CreateMRTWrapper(def.mvpId, def.mrtName, def.title)
end

-- notify
RMS:Print("Bridge: registrados %d módulos MRT.", #MRT_MODULES)
