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
    local y = -10
    local function Place(w, gap)
        w:SetPoint("TOPLEFT", c, "TOPLEFT", 14, y)
        y = y - (gap or 26)
    end

    Place(MakeCheck(c, "Category view (off = single view)",
        function() return cfg.viewType == "category" end,
        function(v) cfg.viewType = v and "category" or "single" end))
    Place(MakeCheck(c, "Show bag-slot row",
        function() return cfg.showBagRow end,
        function(v) cfg.showBagRow = v end))
    Place(MakeCheck(c, "Grey out junk",
        function() return cfg.greyJunk end,
        function(v) cfg.greyJunk = v end))
    Place(MakeCheck(c, "Show item level on equipment",
        function() return cfg.showILvl end,
        function(v) cfg.showILvl = v end))
    Place(MakeCheck(c, "Merge stacks (combine partial stacks of an item for display)",
        function() return cfg.mergeStacks end,
        function(v) cfg.mergeStacks = v end))
    Place(MakeCheck(c, "Guild bank in category view",
        function() return cfg.gbCategoryView end,
        function(v) cfg.gbCategoryView = v end))
    Place(MakeCheck(c, "Show category tags on item tooltips",
        function() return cfg.showTagTooltip end,
        function(v) cfg.showTagTooltip = v end))
    Place(MakeCheck(c, "Show item ID on tooltips",
        function() return cfg.showItemID end,
        function(v) cfg.showItemID = v end))
    Place(MakeCheck(c, "Replace Blizzard bags (/reload)",
        function() return cfg.replaceBags end,
        function(v) cfg.replaceBags = v end))
    Place(MakeCheck(c, "Replace Blizzard bank (/reload)",
        function() return cfg.replaceBank end,
        function(v) cfg.replaceBank = v end))
    Place(MakeCheck(c, "Replace Blizzard guild bank (/reload)",
        function() return cfg.replaceGuildBank end,
        function(v) cfg.replaceGuildBank = v end), 30)

    if IsAddOnLoaded("ElvUI") then
        local elvHint = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        elvHint:SetWidth(560)
        elvHint:SetJustifyH("LEFT")
        elvHint:SetTextColor(0.5, 0.75, 1)
        elvHint:SetText("ElvUI detected - the three checkboxes above are also how to hand bags/bank/guild bank back to ElvUI (uncheck them, then /reload).")
        Place(elvHint, 22)
    end

    Place(MakeCheck(c, "Auto-open bags at merchants",
        function() return cfg.autoOpenMerchant end,
        function(v) cfg.autoOpenMerchant = v end))
    Place(MakeCheck(c, "Auto-open bags at mailboxes",
        function() return cfg.autoOpenMailbox end,
        function(v) cfg.autoOpenMailbox = v end))
    Place(MakeCheck(c, "Auto-repair at merchants (prefers guild funds)",
        function() return cfg.autoRepair end,
        function(v) cfg.autoRepair = v end))
    Place(MakeCheck(c, "Auto-sell Junk category items at merchants",
        function() return cfg.autoSellJunk end,
        function(v) cfg.autoSellJunk = v end))
    Place(MakeCheck(c, "Match ElvUI's look (requires ElvUI, /reload)",
        function() return cfg.elvuiSkin end,
        function(v) cfg.elvuiSkin = v end), 40)

    Place(MakeSlider(c, "'New' duration in seconds", 30, 600, 30,
        function() return cfg.recentSecs end,
        function(v) cfg.recentSecs = v end), 44)

    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", 14, y - 4)
    hint:SetWidth(560)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.55, 0.55, 0.55)
    hint:SetText("Icon size matches the standard in-game bag icons. Drag the bottom-right corner of the bags/bank/guild bank window to resize it - columns reflow to fit, up to a maximum per row.")
end

local function BuildSortingTab(c)
    local cfg = B.Config()
    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -14)
    lbl:SetText("Sort method (bags, bank, and guild bank):")

    local METHODS = {
        {value="type",    label="Type (default)"},
        {value="quality", label="Quality"},
        {value="ilvl",    label="Item level"},
    }
    local dd = CreateFrame("Frame", "GrimfallBagsSortDD", c, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -30)
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

    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -70)
    hint:SetWidth(560)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.55, 0.55, 0.55)
    hint:SetText("The broom button sorts asynchronously: first merges stacks, then swaps items into the target order. One move per server confirmation - loss-safe.")
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
            t.btn.lbl:SetTextColor(1, 0.82, 0)
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
    B.MakeMovable(d, "Options")
    d:SetFrameStrata("DIALOG")
    d:Hide()
    tinsert(UISpecialFrames, "GrimfallBagsOptions")
    dialog = d

    local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", d, "TOP", 0, -10)
    title:SetText("|cff33aaffGrimfallBags|r customize")

    local xb = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", d, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    local sidebar = CreateFrame("Frame", nil, d)
    sidebar:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -34)
    sidebar:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 10)
    sidebar:SetWidth(SIDEBAR_W)

    local TABS = {
        {key="general",    label="General",    build=BuildGeneralTab},
        {key="sorting",    label="Sorting",    build=BuildSortingTab},
        {key="profiles",   label="Profiles",   build=BuildProfilesTab},
        {key="categories", label="Categories", build=B.BuildCategoriesPanel},
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
        bg:SetTexture(0.3, 0.55, 0.85, 0.3)
        bg:Hide()
        btn.bg = bg

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
        lbl:SetText(def.label)
        btn.lbl = lbl

        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
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
