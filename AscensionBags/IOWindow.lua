---------------------------------------------------------------------------
-- AscensionBags - Shared Import/Export window (WeakAuras-style): one
-- bigger, resizable box instead of the two small near-identical ones
-- Profiles and Categories used to each have. Full corner-resize (unlike
-- the bag windows, both dimensions matter here - there's no auto-
-- computed content height), the text box reflows to the window's width,
-- a character counter (useful since Chat Link has a hard length limit),
-- and export auto-selects the text so Ctrl+C works immediately.
---------------------------------------------------------------------------
local B = AscensionBags
local ioWindow

local function BuildIOWindow()
    local w = CreateFrame("Frame", "AscensionBagsIOWindow", UIParent)
    w:SetWidth(560); w:SetHeight(380)
    w:SetPoint("CENTER")
    B.StyleWindow(w)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    tinsert(UISpecialFrames, "AscensionBagsIOWindow")
    B.MakeMovable(w, "AscensionBagsIOWindow")

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
        cfg.winWidth["AscensionBagsIOWindow"] = w:GetWidth()
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
    w.nameBox = CreateFrame("EditBox", "AscensionBagsIOWindowName", w, "InputBoxTemplate")
    w.nameBox:SetWidth(160); w.nameBox:SetHeight(20)
    w.nameBox:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -44)
    w.nameBox:SetAutoFocus(false); w.nameBox:SetMaxLetters(24)
    w.nameBox:SetScript("OnEscapePressed", w.nameBox.ClearFocus)
    B.SkinEdit(w.nameBox)

    w.strLabel = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.strLabel:SetTextColor(0.7, 0.7, 0.7)

    local sf = CreateFrame("ScrollFrame", "AscensionBagsIOWindowScroll", w, "UIPanelScrollFrameTemplate")
    sf:SetBackdrop(B.PANEL_BD)
    sf:SetBackdropColor(0, 0, 0, 0.4)
    -- Without this, empty space below the actual text (whenever the
    -- pasted/exported string is short) has no mouse-enabled frame over
    -- it, so clicks fall through to the window underneath and start a
    -- drag-to-move instead of a text click - claim the whole box.
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
        -- Compute from w:GetWidth() directly, not sf:GetWidth() - sf's
        -- width is anchor-derived (TOPLEFT 14 / BOTTOMRIGHT -32 from w),
        -- and reading it back immediately after w was just resized in
        -- the same call risks a stale value. w:GetWidth() is a value we
        -- just set explicitly, so it's guaranteed current.
        local target = math.max(100, w:GetWidth() - 14 - 32 - 56)
        -- Hide/show forces the EditBox to drop any cached line-wrap /
        -- highlight-extent metrics from its previous width instead of
        -- silently keeping them, which plain SetWidth doesn't reliably
        -- do for this widget.
        eb:Hide()
        eb:SetWidth(target)
        eb:Show()
    end
    w:SetScript("OnSizeChanged", Reflow)
    w.Reflow = Reflow

    return w
end

-- cfg = {
--   title, mode = "export"|"import", text (initial string),
--   showName (bool), nameLabel, nameText, strLabel,
--   okText, onImport = function(str, name) -> ok(bool), msg(string|nil)
-- }
function B.ShowIOWindow(cfg)
    if not ioWindow then ioWindow = BuildIOWindow() end
    local w = ioWindow

    w:SetWidth(B.Config().winWidth["AscensionBagsIOWindow"] or 560)
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

    -- Settle the box's width BEFORE the text goes in, so the initial
    -- wrap/highlight layout is computed against the final width, not
    -- whatever it happened to be from the previous time this shared
    -- window was shown.
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
