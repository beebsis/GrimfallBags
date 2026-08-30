local B = GrimfallBags
local ioWindow

local function BuildIOWindow()
    local w = CreateFrame("Frame", "GrimfallBagsIOWindow", UIParent)
    w:SetWidth(560); w:SetHeight(380)
    w:SetPoint("CENTER")
    B.StyleWindow(w)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    tinsert(UISpecialFrames, "GrimfallBagsIOWindow")
    B.MakeMovable(w, "GrimfallBagsIOWindow")

    w:SetResizable(true)
    w:SetMinResize(380, 220)
    local grip = CreateFrame("Button", nil, w)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() w:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
        local cfg = B.Config()
        cfg.winWidth["GrimfallBagsIOWindow"] = w:GetWidth()
        cfg.ioWindowHeight = w:GetHeight()
    end)

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOP", w, "TOP", 0, -10)

    w.countText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.countText:SetPoint("TOPRIGHT", w, "TOPRIGHT", -30, -12)
    w.countText:SetTextColor(0.55, 0.55, 0.55)

    w.nameLabel = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.nameLabel:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -30)
    w.nameLabel:SetTextColor(0.7, 0.7, 0.7)
    w.nameBox = CreateFrame("EditBox", "GrimfallBagsIOWindowName", w, "InputBoxTemplate")
    w.nameBox:SetWidth(160); w.nameBox:SetHeight(20)
    w.nameBox:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -44)
    w.nameBox:SetAutoFocus(false); w.nameBox:SetMaxLetters(24)
    w.nameBox:SetScript("OnEscapePressed", w.nameBox.ClearFocus)
    B.SkinEdit(w.nameBox)

    w.strLabel = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.strLabel:SetTextColor(0.7, 0.7, 0.7)

    local sf = CreateFrame("ScrollFrame", "GrimfallBagsIOWindowScroll", w, "UIPanelScrollFrameTemplate")
    sf:SetBackdrop(B.PANEL_BD)
    sf:SetBackdropColor(0, 0, 0, 0.4)
    sf:EnableMouse(true)
    w.scroll = sf
    B.SkinScrollBar(_G[sf:GetName().."ScrollBar"])

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(8, 16, 6, 6)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
        w.countText:SetText(#self:GetText().." characters")
    end)
    sf:SetScrollChild(eb)
    w.editBox = eb
    B.SkinEdit(eb)

    w.okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.okBtn:SetWidth(120); w.okBtn:SetHeight(22)
    w.okBtn:SetPoint("BOTTOM", w, "BOTTOM", 0, 12)
    B.SkinButton(w.okBtn)

    local function Reflow()
        local target = math.max(100, w:GetWidth() - 14 - 32 - 56)
        eb:Hide()
        eb:SetWidth(target)
        eb:Show()
    end
    w:SetScript("OnSizeChanged", Reflow)
    w.Reflow = Reflow

    return w
end

function B.ShowIOWindow(cfg)
    if not ioWindow then ioWindow = BuildIOWindow() end
    local w = ioWindow

    w:SetWidth(B.Config().winWidth["GrimfallBagsIOWindow"] or 560)
    w:SetHeight(B.Config().ioWindowHeight or 380)
    w:Show()

    w.title:SetText(cfg.title or "")
    w.countText:SetText(#(cfg.text or "").." characters")

    if cfg.showName then
        w.nameLabel:Show(); w.nameBox:Show()
        w.nameLabel:SetText(cfg.nameLabel or "Name")
        w.nameBox:SetText(cfg.nameText or "")
        w.strLabel:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -70)
        w.scroll:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -86)
    else
        w.nameLabel:Hide(); w.nameBox:Hide()
        w.strLabel:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -30)
        w.scroll:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -46)
    end
    w.scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -32, 44)
    w.strLabel:SetText(cfg.strLabel or "")

    w.Reflow()
    w.editBox:SetText(cfg.text or "")

    w.okBtn:SetText(cfg.okText or (cfg.mode == "export" and (CLOSE or "Close") or "Import"))
    if cfg.mode == "export" then
        w.okBtn:SetScript("OnClick", function() w:Hide() end)
        w.editBox:SetFocus()
        w.editBox:HighlightText()
    else
        w.okBtn:SetScript("OnClick", function()
            local str = w.editBox:GetText()
            local name = cfg.showName and w.nameBox:GetText() or nil
            local ok, msg = cfg.onImport(str, name)
            if ok then w:Hide() end
            if msg then print(msg) end
        end)
        w.editBox:SetFocus()
    end
end
