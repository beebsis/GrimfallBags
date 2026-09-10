local B = GrimfallBags

local dialog
local tabs = {}
local activeTab

StaticPopupDialogs["GFBAGS_PROFILE_NEW"] = {
    text = "Profile name:",
    button1 = ACCEPT or "Ok",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 24,
    OnAccept = function(self)
        local name = _G[self:GetName().."EditBox"]:GetText()
        if name and name ~= "" then
            B.SaveCurrentAsProfile(name)
            print("|cff33aaff[GrimfallBags]|r Profile '"..name.."' saved.")
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GFBAGS_SKIN_CHANGED"] = {
    text = "Skin changed. Reload the UI to apply?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local function MakeCheck(parent, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetWidth(20); cb:SetHeight(20)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    cb:SetHitRectInsets(0, -(lbl:GetStringWidth() + 8), 0, 0)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        B.RefreshAll()
    end)
    B.SkinCheck(cb)
    return cb
end

local function MakeSlider(parent, label, minV, maxV, step, get, set)
    local name = "GrimfallBagsSlider"..label:gsub("%W", "")
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetWidth(200); sl:SetHeight(16)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    _G[name.."Low"]:SetText(minV)
    _G[name.."High"]:SetText(maxV)
    local text = _G[name.."Text"]
    sl:SetScript("OnShow", function(self)
        self:SetValue(get())
        text:SetText(label..": "..get())
    end)
    sl:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        text:SetText(label..": "..value)
        set(value)
        B.RefreshAll()
    end)
    B.SkinSlider(sl)
    return sl
end

local function BuildGeneralTab(c)
    local cfg = B.Config()
    local yL = -10
    local yR = -10
    local RX = 360

    local function PlaceLeft(w, gap)
        w:SetPoint("TOPLEFT", c, "TOPLEFT", 14, yL)
        yL = yL - (gap or 26)
    end
    local function PlaceRight(w, gap)
        w:SetPoint("TOPLEFT", c, "TOPLEFT", RX, yR)
        yR = yR - (gap or 26)
    end

    -- Left column: display toggles.
    PlaceLeft(MakeCheck(c, "Show bag-slot row",
        function() return cfg.showBagRow end,
        function(v) cfg.showBagRow = v end))
    PlaceLeft(MakeCheck(c, "Grey out junk",
        function() return cfg.greyJunk end,
        function(v) cfg.greyJunk = v end))
    PlaceLeft(MakeCheck(c, "Show item level on equipment",
        function() return cfg.showILvl end,
        function(v) cfg.showILvl = v end))
    PlaceLeft(MakeCheck(c, "Show cross-character count on items (bags + bank + mail)",
        function() return cfg.showCrossCharCount end,
        function(v) cfg.showCrossCharCount = v end))
    PlaceLeft(MakeCheck(c, "Merge stacks",
        function() return cfg.mergeStacks end,
        function(v) cfg.mergeStacks = v end))
    PlaceLeft(MakeCheck(c, "Auto-repair at merchants (prefers guild funds)",
        function() return cfg.autoRepair end,
        function(v) cfg.autoRepair = v end))
    PlaceLeft(MakeCheck(c, "Auto-sell Junk category items at merchants",
        function() return cfg.autoSellJunk end,
        function(v) cfg.autoSellJunk = v end))

    -- Right column: skin, sort method, 'new' duration.
    local SKINS = { {value="flat", label="Flat dark"} }
    if IsAddOnLoaded("ElvUI") then SKINS[#SKINS+1] = {value="elvui", label="ElvUI"} end
    local skinLbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skinLbl:SetPoint("TOPLEFT", c, "TOPLEFT", RX, yR)
    skinLbl:SetTextColor(unpack(B.COLOR_TEXTDIM))
    skinLbl:SetText("Skin (/reload to apply):")
    yR = yR - 20
    local skinDD = CreateFrame("Frame", "GrimfallBagsSkinDD", c, "UIDropDownMenuTemplate")
    skinDD:SetPoint("TOPLEFT", c, "TOPLEFT", RX - 14, yR)
    UIDropDownMenu_SetWidth(skinDD, 150)
    B.SkinDropDown(skinDD, 150)
    UIDropDownMenu_Initialize(skinDD, function(self, level)
        for _, s in ipairs(SKINS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = s.label
            info.value   = s.value
            info.checked = (cfg.skin == s.value)
            info.func    = function(btn)
                cfg.skin = btn.value
                UIDropDownMenu_SetSelectedValue(skinDD, btn.value)
                UIDropDownMenu_SetText(skinDD, s.label)
                StaticPopup_Show("GFBAGS_SKIN_CHANGED")
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local cur = cfg.skin
    for _, s in ipairs(SKINS) do
        if s.value == cur then
            UIDropDownMenu_SetSelectedValue(skinDD, cur)
            UIDropDownMenu_SetText(skinDD, s.label)
            break
        end
    end
    yR = yR - 34

    local sortLbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortLbl:SetPoint("TOPLEFT", c, "TOPLEFT", RX, yR)
    sortLbl:SetTextColor(unpack(B.COLOR_TEXTDIM))
    sortLbl:SetText("Sort method:")
    yR = yR - 22
    local METHODS = {
        {value="type",    label="Type (default)"},
        {value="name",    label="Name"},
        {value="id",      label="Item ID"},
        {value="quality", label="Quality"},
        {value="ilvl",    label="Item level"},
    }
    local dd = CreateFrame("Frame", "GrimfallBagsSortDD", c, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", c, "TOPLEFT", RX - 14, yR)
    UIDropDownMenu_SetWidth(dd, 160)
    B.SkinDropDown(dd, 160)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, m in ipairs(METHODS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = m.label
            info.value   = m.value
            info.checked = (cfg.sortMethod == m.value)
            info.func    = function(btn)
                cfg.sortMethod = btn.value
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
                UIDropDownMenu_SetText(dd, m.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    c:SetScript("OnShow", function()
        for _, m in ipairs(METHODS) do
            if m.value == cfg.sortMethod then
                UIDropDownMenu_SetSelectedValue(dd, m.value)
                UIDropDownMenu_SetText(dd, m.label)
            end
        end
    end)
    yR = yR - 40

    PlaceRight(MakeSlider(c, "'New' duration in seconds", 30, 600, 30,
        function() return cfg.recentSecs end,
        function(v) cfg.recentSecs = v end), 40)
end

local function BuildProfilesTab(c)
    local selectedProfile

    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -14)
    lbl:SetText("Choose a profile (applies the display settings):")

    local dd = CreateFrame("Frame", "GrimfallBagsProfileDD", c, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -30)
    UIDropDownMenu_SetWidth(dd, 150)
    B.SkinDropDown(dd, 150)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, name in ipairs(B.ProfileNames()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = name
            info.value   = name
            info.checked = (selectedProfile == name)
            info.func    = function(btn)
                selectedProfile = btn.value
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
                UIDropDownMenu_SetText(dd, btn.value)
                B.ApplyProfile(btn.value)
                print("|cff33aaff[GrimfallBags]|r Profile '"..btn.value.."' active (columns/size: /reload).")
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    c:SetScript("OnShow", function()
        local active = B.Config().activeProfile
        if active and B.Config().profiles[active] then
            selectedProfile = active
            UIDropDownMenu_SetSelectedValue(dd, active)
            UIDropDownMenu_SetText(dd, active)
        else
            selectedProfile = nil
            UIDropDownMenu_SetText(dd, "-")
        end
    end)

    local newBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    newBtn:SetWidth(90); newBtn:SetHeight(20)
    newBtn:SetPoint("LEFT", dd, "RIGHT", -8, 2)
    newBtn:SetText("Save as...")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("GFBAGS_PROFILE_NEW") end)
    B.SkinButton(newBtn)

    local delBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    delBtn:SetWidth(70); delBtn:SetHeight(20)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    delBtn:SetText(DELETE or "Delete")
    delBtn:SetScript("OnClick", function()
        if selectedProfile then
            B.DeleteProfile(selectedProfile)
            print("|cff33aaff[GrimfallBags]|r Profile '"..selectedProfile.."' deleted.")
            selectedProfile = nil
            UIDropDownMenu_SetText(dd, "-")
        end
    end)
    B.SkinButton(delBtn)

    local function ShowIO(mode)
        if mode == "export" then
            B.ShowIOWindow({
                title = "Profile export - Ctrl+C to copy",
                mode = "export",
                showName = true,
                nameLabel = "Name",
                nameText = selectedProfile or "",
                strLabel = "String (Ctrl+A, Ctrl+C):",
                text = selectedProfile and B.ExportProfile(selectedProfile) or "",
            })
        else
            B.ShowIOWindow({
                title = "Profile import",
                mode = "import",
                showName = true,
                nameLabel = "Rename to (optional)",
                strLabel = "Paste the exported string here:",
                onImport = function(str, name)
                    if name == "" then
                        local obj = B.Json.Decode(str)
                        name = type(obj) == "table" and obj.name or nil
                    end
                    if not name or name == "" then
                        return false, "|cff33aaff[GrimfallBags]|r Couldn't find a name in that string - type one in the Name box."
                    end
                    if B.ImportProfile(name, str) then
                        return true, "|cff33aaff[GrimfallBags]|r Profile '"..name.."' imported."
                    end
                    return false, "|cff33aaff[GrimfallBags]|r Import failed (check the string)."
                end,
            })
        end
    end

    local expBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    expBtn:SetWidth(80); expBtn:SetHeight(20)
    expBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -70)
    expBtn:SetText("Export")
    expBtn:SetScript("OnClick", function() ShowIO("export") end)
    B.SkinButton(expBtn)

    local impBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    impBtn:SetWidth(80); impBtn:SetHeight(20)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    impBtn:SetText("Import")
    impBtn:SetScript("OnClick", function() ShowIO("import") end)
    B.SkinButton(impBtn)

    local linkBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    linkBtn:SetWidth(90); linkBtn:SetHeight(20)
    linkBtn:SetPoint("LEFT", impBtn, "RIGHT", 6, 0)
    linkBtn:SetText("Chat Link")
    linkBtn:SetScript("OnClick", function()
        if not selectedProfile then
            print("|cff33aaff[GrimfallBags]|r Select a profile first.")
            return
        end
        local link = B.ProfileShareText(selectedProfile)
        if not link then return end
        if #link > 220 then
            print("|cffff5555[GrimfallBags]|r That profile+categories string is "
                  ..#link.." characters - too long for chat to carry reliably. "
                  .."Use the Export box instead (Ctrl+C) and share it via Discord.")
            return
        end
        ChatEdit_InsertLink(link)
    end)
    B.SkinButton(linkBtn)

    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -104)
    hint:SetWidth(560)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.55, 0.55, 0.55)
    hint:SetText("A profile stores: view, bag-slot row, junk greying, iLvl, new duration, sort method, guild bank view - AND your full category setup (rules, tags, pinned item IDs, protected flags). Export/Chat Link include everything; applying a saved profile only changes the display settings above, categories stay as they are.")
end

local function BuildGuideTab(c)
    local sf = CreateFrame("ScrollFrame", "GrimfallBagsGuideScroll", c, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -14)
    sf:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -30, 14)
    sf:SetBackdrop(B.PANEL_BD)
    sf:SetBackdropColor(0, 0, 0, 0.35)
    sf:SetBackdropBorderColor(unpack(B.COLOR_BORDER))
    sf:EnableMouse(true)
    B.SkinScrollBar(_G[sf:GetName().."ScrollBar"])

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetAutoFocus(false)
    -- Read-only: drop focus the moment it's gained so nothing can be typed in.
    eb:SetScript("OnEditFocusGained", function(self) self:ClearFocus() end)
    eb:SetTextInsets(12, 16, 10, 10)
    sf:SetScrollChild(eb)
    B.SkinEdit(eb)

    local function Reflow()
        local target = math.max(200, sf:GetWidth() - 36)
        eb:Hide()
        eb:SetWidth(target)
        eb:Show()
    end

    local GUIDE = [[
|cff0cd29dHOW A CATEGORY MATCHES|r
A category matches an item when BOTH of its fields agree.
  |cff7ec8e3Tags|r   - any of the tags match (OR together)
  |cff7ec8e3Search|r - an optional query (see operators below)

|cff0cd29dTAGS|r   (comma-separated)
|cff7ec8e3Item classes|r
  weapon, armor, container, consumable, glyph, trade goods,
  projectile, quiver, recipe, gem, miscellaneous, quest

|cff7ec8e3Equip slots|r
  head, neck, shoulder, back, chest, shirt, tabard, wrist,
  hands, waist, legs, feet, finger, trinket, mainhand, offhand,
  ranged, weapon

|cff7ec8e3Item types|r
  sword, axe, mace, dagger, staff, polearm, bow, gun, mail,
  leather, cloth, plate, shield, potion, food, ...

|cff7ec8e3Flags|r
  soulbound (bop), boe, bou, heroic, new, junk, equipment (gear)

|cff0cd29dSEARCH OPERATORS|r
  |cffffcc66&|r    AND     |cffffcc66potion & food|r
  |cffffcc66|||r   OR      |cffffcc66potion || food|r
  |cffffcc66!|r    NOT     |cffffcc66!soulbound|r
  |cffffcc66( )|r  group   |cffffcc66(sword || axe) & heroic|r

|cff7ec8e3Quality words|r
  |cffffcc66poor, common, uncommon, rare, epic, legendary, heirloom|r

|cff7ec8e3Item level|r
  |cffffcc66>200|r       above 200
  |cffffcc66<200|r       below 200
  |cffffcc66=200|r       exactly 200
  |cffffcc66200-300|r    range (inclusive)

|cff7ec8e3Special keywords|r
  |cffffcc66junk|r / |cffffcc66grey|r         grey vendor trash
  |cffffcc66equipment|r / |cffffcc66gear|r     equippable items
  |cffffcc66boe|r                 bind-on-equip
  |cffffcc66soulbound|r / |cffffcc66bop|r     bound to you
  |cffffcc66bou|r                 bind-on-use
  |cffffcc66heroic|r              "Heroic x/5" tooltip line
  |cffffcc66new|r                 recently looted

|cff7ec8e3Plain text|r
  Matches the item name AND its full tooltip text.
  Examples: |cffffcc66spirit|r, |cffffcc66crit|r, |cffffcc66of the|r, |cffffcc66embersilk|r

|cff0cd29dEXAMPLES|r
  Tags:  |cffffcc66potion, food|r
  Tags:  |cffffcc66weapon, armor|r
  Search: |cffffcc66heroic|r

  Search: |cffffcc66>200 & boe|r
  Search: |cffffcc66(sword || axe) & !soulbound|r
  Search: |cffffcc66boe & epic & !heroic|r
  Search: |cffffcc66gem & rare|r
  Search: |cffffcc66of the|r           (random-suffix names)
  Search: |cffffcc66!junk & !quest|r

|cff0cd29dNOTES|r
|cff9aa0a6- Order = priority: the first category from the top that matches wins.
- Pinned item IDs always beat every rule.
- Junk is built-in: grey items always go to Junk, and Junk is always
  shown last. It cannot be renamed or moved.|r
]]

    c:SetScript("OnShow", function()
        Reflow()
        eb:SetText(GUIDE)
        sf:SetVerticalScroll(0)
    end)
end

local function SelectTab(key)
    activeTab = key
    for k, t in pairs(tabs) do
        if k == key then
            t.content:Show()
            t.btn.bg:Show()
            t.btn.lbl:SetTextColor(1, 1, 1)
        else
            t.content:Hide()
            t.btn.bg:Hide()
            t.btn.lbl:SetTextColor(unpack(B.COLOR_TEXTDIM))
        end
    end
    if key == "categories" and B.RefreshCatDialog then
        B.RefreshCatDialog()
    end
end

local SIDEBAR_W = 140

local function Build()
    local d = CreateFrame("Frame", "GrimfallBagsOptions", UIParent)
    d:SetWidth(660 + SIDEBAR_W + 12); d:SetHeight(570)
    d:SetPoint("CENTER")
    B.StyleWindow(d)
    if B.Config().skin ~= "elvui" then
        -- Fully opaque options window (flat skin uses a ~96% backdrop by default).
        d:SetBackdropColor(B.COLOR_BG[1], B.COLOR_BG[2], B.COLOR_BG[3], 1)
    end
    B.MakeMovable(d, "Options")
    d:SetFrameStrata("DIALOG")
    d:Hide()
    tinsert(UISpecialFrames, "GrimfallBagsOptions")
    dialog = d

    local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", d, "TOP", 0, -10)
    title:SetText("GrimfallBags customize")

    local xb = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", d, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    local sidebar = CreateFrame("Frame", nil, d)
    sidebar:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -34)
    sidebar:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 10)
    sidebar:SetWidth(SIDEBAR_W)

    local TABS = {
        {key="general",    label="General",    build=BuildGeneralTab},
        {key="profiles",   label="Profiles",   build=BuildProfilesTab},
        {key="categories", label="Categories", build=B.BuildCategoriesPanel},
        {key="guide",      label="Guide",      build=BuildGuideTab},
    }
    local ROW_H = 24
    local prevBtn
    for _, def in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetWidth(SIDEBAR_W); btn:SetHeight(ROW_H)
        if prevBtn then btn:SetPoint("TOPLEFT", prevBtn, "BOTTOMLEFT", 0, -2)
        else btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0) end
        prevBtn = btn

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(B.COLOR_ACCENT[1], B.COLOR_ACCENT[2], B.COLOR_ACCENT[3], 0.36)
        bg:Hide()
        btn.bg = bg

        -- Hover: a soft teal wash that matches the active-tab fill, instead of
        -- the stock bluish highlight square - keeps the whole rail on-theme.
        local hover = btn:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetTexture(B.COLOR_ACCENT[1], B.COLOR_ACCENT[2], B.COLOR_ACCENT[3], 0.14)
        hover:Hide()
        btn.hover = hover

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
        lbl:SetText(def.label)
        btn.lbl = lbl

        btn:SetScript("OnEnter", function(self) self.hover:Show() end)
        btn:SetScript("OnLeave", function(self) self.hover:Hide() end)
        btn:SetScript("OnClick", function() SelectTab(def.key) end)

        local content = CreateFrame("Frame", nil, d)
        content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
        content:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -10, 10)
        content:Hide()

        def.build(content)
        tabs[def.key] = {btn = btn, content = content}
    end
end

function B.OpenOptions(tab)
    if not dialog then Build() end
    dialog:Show()
    SelectTab(tab or activeTab or "general")
end

function B.ToggleOptions()
    if dialog and dialog:IsShown() then
        dialog:Hide()
    else
        B.OpenOptions()
    end
end
