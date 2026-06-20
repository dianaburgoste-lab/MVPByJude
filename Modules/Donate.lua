-- MVP By Jude -- Donate / Support
-- Informational tab: how to support the project.

local RMS = MVPByJude
local M = RMS:RegisterModule("donate", { title = "Donar", order = 50 })

-- Enlaces actualizados y protegidos
M.AUTHOR_CHAR  = "Siouxie"
M.AUTHOR_REALM = "Thalassa"
M.GITHUB_URL   = "https://github.com/MVPByJude"
M.PAYPAL_URL   = "https://www.paypal.me/MVPByJude"

-- ---------- chat helpers ----------
function M:PrintInfoToChat()
    RMS:Print("|cffffd070--- Apoyo a MVP By Jude ---|r")
    RMS:Print("Si quieres apoyar este proyecto, puedes enviarme una propina:")
    RMS:Print("Oro por correo interno: |cffffff00%s|r (Reino: %s)",
        self.AUTHOR_CHAR, self.AUTHOR_REALM)
    RMS:Print("GitHub: %s", self.GITHUB_URL)
end

function M:OpenMailToAuthor()
    if not MailFrame or not MailFrame:IsShown() then
        RMS:Print("Abre un buzón de correo primero y vuelve a hacer clic.")
        return
    end
    if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(self.AUTHOR_CHAR)
        SendMailNameEditBox:ClearFocus()
    end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText("Donación MVP By Jude, gracias! <3")
    end
end

function M:OnSlash(arg)
    arg = (arg or ""):lower()
    if arg == "chat"  then return self:PrintInfoToChat() end
    if arg == "mail"  then return self:OpenMailToAuthor() end
    RMS.UI:Show("donate")
end

-- =============================================================================
-- UI
-- =============================================================================

function M:BuildUI(parent)
    local Skin = RMS.Skin; local C = Skin.COLOR
    local panel = CreateFrame("Frame", nil, parent)

    local header = Skin:Header(panel, "Donaciones y Soporte")
    header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8)

    local thanks = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(thanks, 12, false); thanks:SetTextColor(unpack(C.text))
    thanks:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -10); thanks:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -10)
    thanks:SetHeight(40); thanks:SetJustifyH("LEFT"); thanks:SetJustifyV("TOP"); thanks:SetWordWrap(true)
    thanks:SetText("¡Gracias por usar MVP By Jude! Las donaciones son 100% opcionales y ayudan a mantener el addon actualizado. Elige el método que prefieras:")

    -- ===== PayPal block =====
    local paypalHdr = Skin:Header(panel, "Donación por PayPal")
    paypalHdr:SetPoint("TOPLEFT", thanks, "BOTTOMLEFT", 0, -14); paypalHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local paypalBody = Skin:Panel(panel); paypalBody:SetPoint("TOPLEFT", paypalHdr, "BOTTOMLEFT", 0, -2); paypalBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0); paypalBody:SetHeight(180)

    local qr = paypalBody:CreateTexture(nil, "ARTWORK")
    qr:SetTexture(Skin.TEX_QR); qr:SetTexCoord(0, 1, 0.15, 1); qr:SetSize(140, 119); qr:SetPoint("LEFT", 20, 0)

    local ppIntro = paypalBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(ppIntro, 11, false); ppIntro:SetTextColor(unpack(C.text)); ppIntro:SetPoint("TOPLEFT", qr, "TOPRIGHT", 20, -20); ppIntro:SetPoint("RIGHT", -8, 0); ppIntro:SetJustifyH("LEFT")
    ppIntro:SetText("Escanea el código QR con tu móvil para donar vía PayPal.")

    local ppName = paypalBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(ppName, 14, true); ppName:SetTextColor(unpack(C.accent)); ppName:SetPoint("TOPLEFT", ppIntro, "BOTTOMLEFT", 0, -8); ppName:SetText("Soporte MVP By Jude")

    local ppLink = Skin:EditBox(paypalBody, 1, 22)
    ppLink:SetPoint("TOPLEFT", ppName, "BOTTOMLEFT", 0, -6); ppLink:SetPoint("RIGHT", -12, 0)
    ppLink:SetText("Enlace de PayPal (Clic para copiar)"); ppLink:SetTextColor(unpack(C.accent))
    ppLink:SetScript("OnMouseUp", function(s) s:SetText(M.PAYPAL_URL); s:HighlightText() end)
    ppLink:SetScript("OnEditFocusGained", function(s) s:SetText(M.PAYPAL_URL); s:HighlightText() end)

    -- ===== Gold Mail block =====
    local goldHdr = Skin:Header(panel, "Oro en el Juego")
    goldHdr:SetPoint("TOPLEFT", paypalBody, "BOTTOMLEFT", 0, -10); goldHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local goldBody = Skin:Panel(panel); goldBody:SetPoint("TOPLEFT", goldHdr, "BOTTOMLEFT", 0, -2); goldBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0); goldBody:SetHeight(110)

    local goldIntro = goldBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(goldIntro, 11, false); goldIntro:SetTextColor(unpack(C.text)); goldIntro:SetPoint("TOPLEFT", 8, -8); goldIntro:SetPoint("TOPRIGHT", -8, -8)
    goldIntro:SetHeight(28); goldIntro:SetJustifyH("LEFT"); goldIntro:SetJustifyV("TOP"); goldIntro:SetWordWrap(true)
    goldIntro:SetText("Puedes enviarme oro por correo interno (mismo reino). También acepto propinas de oro tras las raids ;)")

    local mailLbl = goldBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(mailLbl, 11, false); mailLbl:SetTextColor(unpack(C.textDim)); mailLbl:SetPoint("TOPLEFT", goldIntro, "BOTTOMLEFT", 0, -10); mailLbl:SetWidth(140); mailLbl:SetText("Destinatario:")

    local mailVal = goldBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(mailVal, 14, true); mailVal:SetTextColor(unpack(C.accent)); mailVal:SetPoint("LEFT", mailLbl, "RIGHT", 4, 0); mailVal:SetJustifyH("LEFT")
    mailVal:SetText(("%s  -  %s"):format(M.AUTHOR_CHAR, M.AUTHOR_REALM))

    local fillBtn = Skin:Button(goldBody, "Rellenar correo automáticamente", 240, 22)
    fillBtn:SetPoint("TOPLEFT", mailLbl, "BOTTOMLEFT", 0, -10); fillBtn:SetScript("OnMouseUp", function() self:OpenMailToAuthor() end)

    -- ===== GitHub / Issues =====
    local ghHdr = Skin:Header(panel, "GitHub / Reporte de Errores")
    ghHdr:SetPoint("TOPLEFT", goldBody, "BOTTOMLEFT", 0, -10); ghHdr:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    local ghBody = Skin:Panel(panel); ghBody:SetPoint("TOPLEFT", ghHdr, "BOTTOMLEFT", 0, -2); ghBody:SetPoint("RIGHT", panel, "RIGHT", -8, 0); ghBody:SetHeight(70)

    local ghIntro = ghBody:CreateFontString(nil, "OVERLAY")
    Skin:Font(ghIntro, 11, false); ghIntro:SetTextColor(unpack(C.text)); ghIntro:SetPoint("TOPLEFT", 8, -8); ghIntro:SetJustifyH("LEFT"); ghIntro:SetText("Código fuente, rastreador de errores y versiones:")

    local urlEdit = Skin:EditBox(ghBody, 1, 22)
    urlEdit:SetPoint("TOPLEFT", ghIntro, "BOTTOMLEFT", 0, -4); urlEdit:SetPoint("TOPRIGHT", -8, 0)
    urlEdit:SetText(M.GITHUB_URL); urlEdit:SetTextColor(unpack(C.accent))
    urlEdit:SetScript("OnMouseUp", function(s) s:HighlightText() end)
    urlEdit:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)

    -- ===== Print to chat =====
    local printBtn = Skin:Button(panel, "Imprimir info en el chat", 240, 22)
    printBtn:SetPoint("TOPLEFT", ghBody, "BOTTOMLEFT", 0, -10); printBtn:SetScript("OnMouseUp", function() self:PrintInfoToChat() end)

    local foot = panel:CreateFontString(nil, "OVERLAY")
    Skin:Font(foot, 10, false); foot:SetTextColor(unpack(C.textDim)); foot:SetPoint("TOPLEFT", printBtn, "BOTTOMLEFT", 0, -14); foot:SetPoint("TOPRIGHT", -8, 0)
    foot:SetText("Todas las donaciones son opcionales. Los reportes de errores son igualmente apreciados. <3")

    self._ui = { panel = panel }; return panel
end
