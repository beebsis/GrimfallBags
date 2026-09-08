local B = GrimfallBags
local S = Syndicator335

B.RECENT_LABEL = "Neu"

function B.GetItemTags(link)
    local _, _, _, _, _, itemType, subType, _, equipLoc = GetItemInfo(link or "")
    local tags = {}
    if itemType and itemType ~= "" then tags[#tags+1] = itemType:lower() end
    if subType and subType ~= "" and subType:lower() ~= (itemType or ""):lower() then
        tags[#tags+1] = subType:lower()
    end
    if equipLoc and equipLoc ~= "" then
        local slotName = _G[equipLoc]
        if slotName and slotName ~= "" then tags[#tags+1] = slotName:lower() end
    end
    return tags
end

local function ShowItemTooltipInfo(tt, link)
    local cfg = B.Config()
    local shown = false
    local id = S.ItemID(link)
    if cfg.showItemID and id then
        tt:AddLine("|cff33aaffItem ID:|r "..id, 1, 1, 1)
        shown = true
    end
    if cfg.showTagTooltip then
        local tags = B.GetItemTags(link)
        if #tags > 0 then
            tt:AddLine("|cff33aaffGrimfallBags tags:|r "..table.concat(tags, ", "), 1, 1, 1, true)
            shown = true
        end
    end
    if B.IsItemSellProtected and B.IsItemSellProtected(link) then
        tt:AddLine("|cffff8888Protected - skipped by category/bulk sell|r", 1, 1, 1, true)
        shown = true
    end
    if shown then tt:Show() end
end

hooksecurefunc(GameTooltip, "SetBagItem", function(tt)
    B.Guard("TooltipHook:SetBagItem", function()
        local _, link = tt:GetItem()
        if link then ShowItemTooltipInfo(tt, link) end
    end)
end)
hooksecurefunc(GameTooltip, "SetInventoryItem", function(tt)
    B.Guard("TooltipHook:SetInventoryItem", function()
        local _, link = tt:GetItem()
        if link then ShowItemTooltipInfo(tt, link) end
    end)
end)
hooksecurefunc(GameTooltip, "SetHyperlink", function(tt, link)
    B.Guard("TooltipHook:SetHyperlink", function()
        if not link then return end
        local _, itemLink = tt:GetItem()
        if itemLink then ShowItemTooltipInfo(tt, itemLink) end
    end)
end)

local DEFAULT_CLASS_ENGLISH = {"weapon", "armor", "container", "consumable",
    "glyph", "trade goods", "projectile", "quiver", "recipe", "gem",
    "miscellaneous", "quest"}
local DEFAULT_CLASS_SECTION = {
    weapon = "Equipment", armor = "Equipment",
    glyph = "Crafting", ["trade goods"] = "Crafting",
    recipe = "Crafting", gem = "Crafting",
}

function B.SeedDefaultCategories()
    local cfg = B.Config()
    local classes = {GetAuctionItemClasses()}
    local sectionByLocName = {}
    for i, locName in ipairs(classes) do
        local sec = DEFAULT_CLASS_SECTION[DEFAULT_CLASS_ENGLISH[i]]
        if sec then sectionByLocName[locName] = sec end
    end

    if not cfg.defaultsSeeded then
        local existing = {}
        for _, r in ipairs(cfg.rules) do existing[r.name] = true end
        for _, locName in ipairs(classes) do
            if not existing[locName] then
                cfg.rules[#cfg.rules+1] = {name = locName, tags = {locName:lower()},
                                           section = sectionByLocName[locName]}
            end
        end
        cfg.defaultsSeeded = true
        B.Log("Default categories seeded ("..#classes..")")
    end

    if not cfg.defaultSectionsSeeded then
        for _, r in ipairs(cfg.rules) do
            if not r.section and sectionByLocName[r.name] then
                r.section = sectionByLocName[r.name]
            end
        end
        cfg.defaultSectionsSeeded = true
        B.Log("Default category sections backfilled")
    end

    if not cfg.defaultsBackfilled then
        local existing = {}
        for _, r in ipairs(cfg.rules) do existing[r.name] = true end
        for _, locName in ipairs(classes) do
            if not existing[locName] then
                cfg.rules[#cfg.rules+1] = {name = locName, tags = {locName:lower()},
                                           section = sectionByLocName[locName]}
            end
        end
        cfg.defaultsBackfilled = true
        B.Log("Default categories backfilled")
    end
end

function B.SeedBiSCategory()
    local cfg = B.Config()
    if cfg.bisSeeded then return end
    cfg.bisSeeded = true
    for _, r in ipairs(cfg.rules) do
        if r.name == "BiS" then return end
    end
    table.insert(cfg.rules, 1, {name = "BiS", tags = {}, protected = true})
    B.Log("BiS category seeded (sell-protected)")
end

function B.SeedJunkCategory()
    local cfg = B.Config()
    if cfg.junkSeeded then return end
    cfg.junkSeeded = true
    for _, r in ipairs(cfg.rules) do
        if r.name == "Junk" then return end
    end
    table.insert(cfg.rules, 1, {name = "Junk", query = "junk", sortLast = true})
    B.Log("Junk category seeded (sorts last)")
end

local function RuleHasTag(rule, tag)
    for _, t in ipairs(rule.tags or {}) do
        if t == tag then return true end
    end
    return false
end

local function FindOrCreateRule(catName)
    local rules = B.Config().rules
    for _, r in ipairs(rules) do
        if r.name == catName then return r end
    end
    local r = {name = catName, tags = {}}
    rules[#rules+1] = r
    return r
end

function B.AssignCursorToCategory(catName)
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" or not itemID then return false end
    for _, r in ipairs(B.Config().rules) do
        if r.items then r.items[itemID] = nil end
    end
    local rule = FindOrCreateRule(catName)
    rule.items = rule.items or {}
    rule.items[itemID] = true
    ClearCursor()
    B.Log("Item pinned: "..(link and link:match("%[(.-)%]") or itemID)
          .." -> category '"..catName.."'")
    if B.RefreshAll then B.RefreshAll() end
    return true
end

function B.Categorize(entry)
    local cfg = B.Config()
    local id = S.ItemID(entry.l)

    if id then
        for _, rule in ipairs(cfg.rules) do
            if rule.items and rule.items[id] then return rule.name end
        end
    end

    local itemTags
    for _, rule in ipairs(cfg.rules) do
        local hasTags  = rule.tags and #rule.tags > 0
        local hasQuery = rule.query and rule.query ~= ""
        if hasTags or hasQuery then
            local tagMatch = true
            if hasTags then
                itemTags = itemTags or B.GetItemTags(entry.l)
                tagMatch = false
                for _, tag in ipairs(itemTags) do
                    if RuleHasTag(rule, tag) then tagMatch = true; break end
                end
            end
            local queryMatch = not hasQuery or S.Search.Matches(entry, rule.query)
            if tagMatch and queryMatch then return rule.name end
        end
    end

    local _, _, _, _, _, itemType = GetItemInfo(entry.l or "")
    return itemType or (MISCELLANEOUS or "Miscellaneous")
end

function B.IsCategoryHidden(cat)
    return B.Config().hiddenCats[cat] == true
end

function B.IsCategoryProtected(catName)
    for _, r in ipairs(B.Config().rules) do
        if r.name == catName then return r.protected == true end
    end
    return false
end

function B.IsItemSellProtected(link)
    if not link then return false end
    return B.IsCategoryProtected(B.Categorize({l = link}))
end

function B.RulesToArray()
    local arr = {}
    for _, r in ipairs(B.Config().rules) do
        local obj = {name = r.name}
        if r.tags and #r.tags > 0 then obj.tags = r.tags end
        if r.query and r.query ~= "" then obj.query = r.query end
        if r.items then
            local ids = {}
            for id in pairs(r.items) do ids[#ids+1] = id end
            table.sort(ids)
            if #ids > 0 then obj.items = ids end
        end
        if r.section and r.section ~= "" then obj.section = r.section end
        if r.protected then obj.protected = true end
        if r.sortLast then obj.sortLast = true end
        arr[#arr+1] = obj
    end
    return arr
end

function B.ExportRules()
    return B.Json.Encode(B.RulesToArray())
end

local function ImportRulesLegacy(str)
    local rules = B.Config().rules
    local count = 0
    for chunk in (str or ""):gmatch("[^;][^;]*") do
        local name, tagStr, query, idStr, secStr, protStr =
            chunk:match("^(.-)||(.-)||(.-)||(.-)||(.-)||(.*)$")
        if not name then
            name, tagStr, query, idStr, secStr =
                chunk:match("^(.-)||(.-)||(.-)||(.-)||(.*)$")
        end
        if not name then
            name, tagStr, query, idStr = chunk:match("^(.-)||(.-)||(.-)||(.*)$")
        end
        if not name then
            name, tagStr, query = chunk:match("^(.-)||(.-)||(.*)$")
        end
        if not name then
            name, query = chunk:match("^(.-)=(.+)$")
            tagStr = ""
        end
        if name and name ~= "" then
            local tags = {}
            for tag in (tagStr or ""):gmatch("[^,]+") do
                tags[#tags+1] = tag:lower():match("^%s*(.-)%s*$")
            end
            local items
            for id in (idStr or ""):gmatch("[^:]+") do
                items = items or {}
                if tonumber(id) then items[tonumber(id)] = true end
            end
            rules[#rules+1] = {name = name, tags = tags, items = items,
                               query = (query and query ~= "" and query:lower() or nil),
                               section = (secStr and secStr ~= "" and secStr or nil),
                               protected = (protStr == "1") or nil}
            count = count + 1
        end
    end
    return count
end

function B.ImportRulesArray(arr)
    local rules = B.Config().rules
    local count = 0
    for _, obj in ipairs(arr or {}) do
        if type(obj) == "table" and obj.name and obj.name ~= "" then
            local items
            if obj.items then
                items = {}
                for _, id in ipairs(obj.items) do items[id] = true end
            end
            rules[#rules+1] = {
                name = obj.name,
                tags = obj.tags or {},
                query = obj.query,
                items = items,
                section = obj.section,
                protected = obj.protected or nil,
                sortLast = obj.sortLast or nil,
            }
            count = count + 1
        end
    end
    return count
end

function B.ImportRules(str)
    local arr = B.Json.Decode(str)
    if type(arr) ~= "table" then
        return ImportRulesLegacy(str)
    end
    return B.ImportRulesArray(arr)
end

local RULE_ROWS  = 14
local RULE_ROW_H = 20
local dialog
local editIdx
local editSection
local draggingIdx

local dragGhost
local function ShowDragGhost(label)
    if not dragGhost then
        local g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("TOOLTIP")
        g:SetSize(160, 22)
        g:EnableMouse(false)
        local bg = g:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0, 0, 0, 0.75)
        local txt = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER")
        txt:SetTextColor(1, 0.82, 0)
        g.text = txt
        g:SetScript("OnUpdate", function(self)
            local scale = UIParent:GetEffectiveScale()
            local x, y = GetCursorPosition()
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale + 16)
        end)
        dragGhost = g
    end
    dragGhost.text:SetText(label or "")
    dragGhost:Show()
end
local function HideDragGhost()
    if dragGhost then dragGhost:Hide() end
end

local RefreshDialog

StaticPopupDialogs["GFBAGS_NEW_SECTION"] = {
    text = "Section name:",
    button1 = ACCEPT or "Ok",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 30,
    OnAccept = function(self)
        local name = _G[self:GetName().."EditBox"]:GetText()
        if name and name ~= "" then
            local cfg = B.Config()
            local exists = false
            for _, s in ipairs(cfg.sections) do
                if s == name then exists = true; break end
            end
            if not exists then cfg.sections[#cfg.sections+1] = name end
            editSection = name
            editIdx = nil
            RefreshDialog()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local function RegisterKnownSections()
    local cfg = B.Config()
    local known = {}
    for _, s in ipairs(cfg.sections) do known[s] = true end
    for _, r in ipairs(cfg.rules) do
        if r.section and r.section ~= "" and not known[r.section] then
            known[r.section] = true
            cfg.sections[#cfg.sections+1] = r.section
        end
    end
end

local function GetBlocks()
    RegisterKnownSections()
    local cfg = B.Config()
    local rules = cfg.rules
    local usedSection, usedIdx = {}, {}
    local blocks = {}
    for i, r in ipairs(rules) do
        if r.section and r.section ~= "" then
            if not usedSection[r.section] then
                usedSection[r.section] = true
                local indices = {}
                for j, r2 in ipairs(rules) do
                    if r2.section == r.section and not usedIdx[j] then
                        indices[#indices+1] = j
                        usedIdx[j] = true
                    end
                end
                blocks[#blocks+1] = {section = r.section, indices = indices}
            end
        elseif not usedIdx[i] then
            blocks[#blocks+1] = {idx = i}
            usedIdx[i] = true
        end
    end
    for _, sec in ipairs(cfg.sections) do
        if not usedSection[sec] then
            blocks[#blocks+1] = {section = sec, indices = {}}
        end
    end
    return blocks
end

local function ComputeDisplayRows()
    local disp = {}
    for _, b in ipairs(GetBlocks()) do
        if b.section then
            disp[#disp+1] = {header = b.section}
            for _, idx in ipairs(b.indices) do
                disp[#disp+1] = {idx = idx}
            end
        else
            disp[#disp+1] = {idx = b.idx}
        end
    end
    return disp
end

local function MoveSection(sectionName, delta)
    local blocks = GetBlocks()
    local pos
    for i, b in ipairs(blocks) do
        if b.section == sectionName then pos = i; break end
    end
    local target = pos and (pos + delta)
    if not pos or not blocks[target] then return end
    blocks[pos], blocks[target] = blocks[target], blocks[pos]

    local rules = B.Config().rules
    local editedName = editIdx and rules[editIdx] and rules[editIdx].name
    local newRules = {}
    for _, b in ipairs(blocks) do
        if b.section then
            for _, idx in ipairs(b.indices) do newRules[#newRules+1] = rules[idx] end
        else
            newRules[#newRules+1] = rules[b.idx]
        end
    end
    B.Config().rules = newRules
    if editedName then
        for i2, r in ipairs(newRules) do
            if r.name == editedName then editIdx = i2; break end
        end
    end
    RefreshDialog()
    if B.RefreshAll then B.RefreshAll() end
end

local function MoveRule(idx, delta)
    local rules = B.Config().rules
    local target = idx + delta
    if rules[idx] and rules[target] then
        rules[idx], rules[target] = rules[target], rules[idx]
        if editIdx == idx then editIdx = target
        elseif editIdx == target then editIdx = idx end
        RefreshDialog()
        if B.RefreshAll then B.RefreshAll() end
    end
end

local function LoadEditPane()
    local d = dialog
    if not d then return end

    if editSection then
        for _, w in ipairs(d.ruleOnlyWidgets) do w:Hide() end
        d.nameLabel:SetText("Section name")
        d.nameBox:SetText(editSection)
        d.saveBtn:SetText("Rename")
        d.delBtn:SetText("|cffff3333Ungroup|r")
        d.delBtn:Show()
        return
    end
    for _, w in ipairs(d.ruleOnlyWidgets) do w:Show() end
    d.nameLabel:SetText("Name")

    local r = editIdx and B.Config().rules[editIdx]
    if r then
        d.nameBox:SetText(r.name)
        d.tagBox:SetText(table.concat(r.tags or {}, ", "))
        d.qBox:SetText(r.query or "")
        d.secBox:SetText(r.section or "")
        local ids = {}
        for id in pairs(r.items or {}) do ids[#ids+1] = id end
        table.sort(ids)
        d.idBox:SetText(table.concat(ids, ", "))
        d.hiddenCB:SetChecked(B.Config().hiddenCats[r.name] and true or false)
        d.protectedCB:SetChecked(r.protected == true)
        d.sortLastCB:SetChecked(r.sortLast == true)
        d.saveBtn:SetText(SAVE or "Save")
        d.delBtn:Show()
        local n = 0
        for _ in pairs(r.items or {}) do n = n + 1 end
        if n > 0 then
            d.pinText:SetText("Pinned items: "..n)
            d.pinClear:Show()
        else
            d.pinText:SetText("Pinned items: none")
            d.pinClear:Hide()
        end
    else
        d.nameBox:SetText("")
        d.tagBox:SetText("")
        d.qBox:SetText("")
        d.secBox:SetText("")
        d.idBox:SetText("")
        d.hiddenCB:SetChecked(false)
        d.protectedCB:SetChecked(false)
        d.sortLastCB:SetChecked(false)
        d.saveBtn:SetText(ADD or "Add")
        d.delBtn:Hide()
        d.pinText:SetText("")
        d.pinClear:Hide()
    end
end

RefreshDialog = function()
    local d = dialog
    if not (d and d:IsShown()) then return end
    local rules  = B.Config().rules
    local disp   = ComputeDisplayRows()
    local offset = FauxScrollFrame_GetOffset(d.scroll)
    FauxScrollFrame_Update(d.scroll, #disp, RULE_ROWS, RULE_ROW_H)
    for i = 1, RULE_ROWS do
        local row   = d.rows[i]
        local entry = disp[i + offset]
        if entry and entry.header then
            row.idx = nil
            row.headerName = entry.header
            row.up:Show(); row.down:Show()
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.down, "RIGHT", 5, 0)
            local color = (entry.header == editSection) and "|cff33ff33" or "|cffffd200"
            row.text:SetText(color..entry.header.."|r")
            row:Show()
        elseif entry then
            local r = rules[entry.idx]
            row.idx = entry.idx
            row.headerName = nil
            row.up:Show(); row.down:Show()
            row.text:ClearAllPoints()
            local indent = (r.section and r.section ~= "") and 14 or 0
            row.text:SetPoint("LEFT", row.down, "RIGHT", 5 + indent, 0)
            local hidden = B.Config().hiddenCats[r.name]
            local color = hidden and "|cff777777" or
                          (row.idx == editIdx and "|cff33ff33" or "|cffffcc00")
            local suffix = (hidden and " |cffff5555(hidden)|r" or "")
                         ..(r.protected and " |cffff8888(protected)|r" or "")
            row.text:SetText(color..r.name.."|r"..suffix)
            row:Show()
        else
            row:Hide()
        end
    end
    LoadEditPane()
end

function B.BuildCategoriesPanel(parent)
    if dialog then return end
    local d = CreateFrame("Frame", "GrimfallBagsCatPanel", parent)
    d:SetAllPoints(parent)
    dialog = d

    local listTop = -6
    local listBG = CreateFrame("Frame", nil, d)
    listBG:SetPoint("TOPLEFT", d, "TOPLEFT", 12, listTop)
    listBG:SetWidth(268)
    listBG:SetHeight(RULE_ROWS * RULE_ROW_H + 8)
    listBG:SetBackdrop(B.PANEL_BD)
    listBG:SetBackdropColor(0, 0, 0, 0.5)
    listBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local scroll = CreateFrame("ScrollFrame", "GrimfallBagsCatScroll", listBG, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listBG, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBG, "BOTTOMRIGHT", -24, 4)
    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, RULE_ROW_H, RefreshDialog)
    end)
    d.scroll = scroll
    B.SkinScrollBar(_G[scroll:GetName().."ScrollBar"])

    d.rows = {}
    for i = 1, RULE_ROWS do
        local row = CreateFrame("Button", nil, listBG)
        row:SetWidth(238); row:SetHeight(RULE_ROW_H)
        row:SetPoint("TOPLEFT", listBG, "TOPLEFT", 6, -4 - (i-1) * RULE_ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local up = CreateFrame("Button", nil, row)
        up:SetWidth(16); up:SetHeight(16)
        up:SetPoint("LEFT", row, "LEFT", 0, 0)
        up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        up:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        up:SetScript("OnClick", function()
            if row.headerName then MoveSection(row.headerName, -1)
            else MoveRule(row.idx, -1) end
        end)

        local down = CreateFrame("Button", nil, row)
        down:SetWidth(16); down:SetHeight(16)
        down:SetPoint("LEFT", up, "RIGHT", 0, 0)
        down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        down:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        down:SetScript("OnClick", function()
            if row.headerName then MoveSection(row.headerName, 1)
            else MoveRule(row.idx, 1) end
        end)
        row.up, row.down = up, down

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetJustifyH("LEFT")
        row.text = text

        local function RowAction(self)
            if self.headerName then
                if CursorHasItem() then return end
                editSection = self.headerName
                editIdx = nil
                RefreshDialog()
                return
            end
            local r = B.Config().rules[self.idx]
            if not r then return end
            if CursorHasItem() then
                B.AssignCursorToCategory(r.name)
            else
                editIdx = self.idx
                editSection = nil
            end
            RefreshDialog()
        end
        row:SetScript("OnClick", RowAction)
        row:SetScript("OnReceiveDrag", RowAction)

        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            if self.idx then
                draggingIdx = self.idx
                local r = B.Config().rules[self.idx]
                ShowDragGhost(r and r.name)
            end
        end)
        row:SetScript("OnDragStop", function(self)
            HideDragGhost()
            local srcIdx = draggingIdx
            draggingIdx = nil
            if not srcIdx then return end

            local mf = GetMouseFocus and GetMouseFocus()
            local targetRow
            for _, rr in ipairs(d.rows) do
                if rr == mf or rr.up == mf or rr.down == mf or rr.text == mf then
                    targetRow = rr
                    break
                end
            end
            if not targetRow or targetRow == self then return end

            local rules = B.Config().rules
            local srcRule = rules[srcIdx]
            if not srcRule then return end

            if targetRow.headerName then
                srcRule.section = targetRow.headerName
            else
                return
            end
            RefreshDialog()
            if B.RefreshAll then B.RefreshAll() end
        end)

        row:Hide()
        d.rows[i] = row
    end

    local function ShowIO(mode)
        if mode == "export" then
            B.ShowIOWindow({
                title = "Categories export - Ctrl+C to copy",
                mode = "export",
                strLabel = "String (Ctrl+A, Ctrl+C):",
                text = B.ExportRules(),
            })
        else
            B.ShowIOWindow({
                title = "Categories import",
                mode = "import",
                strLabel = "Paste the exported string here:",
                onImport = function(str)
                    local n = B.ImportRules(str)
                    RefreshDialog()
                    if B.RefreshAll then B.RefreshAll() end
                    return true, "|cff33aaff[GrimfallBags]|r "..n.." rule(s) imported."
                end,
            })
        end
    end

    local impBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    impBtn:SetWidth(90); impBtn:SetHeight(20)
    impBtn:SetPoint("TOPLEFT", listBG, "BOTTOMLEFT", 0, -8)
    impBtn:SetText("Import")
    impBtn:SetScript("OnClick", function() ShowIO("import") end)
    B.SkinButton(impBtn)

    local expBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    expBtn:SetWidth(90); expBtn:SetHeight(20)
    expBtn:SetPoint("LEFT", impBtn, "RIGHT", 6, 0)
    expBtn:SetText("Export")
    expBtn:SetScript("OnClick", function() ShowIO("export") end)
    B.SkinButton(expBtn)

    local paneX = 300
    local editTitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editTitle:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 100, listTop - 2)
    editTitle:SetText("Edit")

    d.ruleOnlyWidgets = {}
    local function Track(w) d.ruleOnlyWidgets[#d.ruleOnlyWidgets+1] = w; return w end

    local function Label(text, dy)
        local l = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, dy)
        l:SetText(text)
        l:SetTextColor(0.7, 0.7, 0.7)
        return l
    end

    d.nameLabel = Label("Name", listTop - 24)
    d.nameBox = CreateFrame("EditBox", "GrimfallBagsCatName", d, "InputBoxTemplate")
    d.nameBox:SetWidth(280); d.nameBox:SetHeight(20)
    d.nameBox:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 6, listTop - 38)
    d.nameBox:SetAutoFocus(false); d.nameBox:SetMaxLetters(30)

    Track(Label("Tags (comma-separated, e.g. head, plate, weapon)", listTop - 64))
    d.tagBox = Track(CreateFrame("EditBox", "GrimfallBagsCatTags", d, "InputBoxTemplate"))
    d.tagBox:SetWidth(280); d.tagBox:SetHeight(20)
    d.tagBox:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 6, listTop - 78)
    d.tagBox:SetAutoFocus(false); d.tagBox:SetMaxLetters(150)

    Track(Label("Search (optional, e.g. potion | food, >200 & boe, spirit)", listTop - 104))
    d.qBox = Track(CreateFrame("EditBox", "GrimfallBagsCatQuery", d, "InputBoxTemplate"))
    d.qBox:SetWidth(280); d.qBox:SetHeight(20)
    d.qBox:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 6, listTop - 118)
    d.qBox:SetAutoFocus(false); d.qBox:SetMaxLetters(80)

    Track(Label("Super-group (optional, e.g. Equipment, Crafting)", listTop - 144))
    d.secBox = Track(CreateFrame("EditBox", "GrimfallBagsCatSection", d, "InputBoxTemplate"))
    d.secBox:SetWidth(280); d.secBox:SetHeight(20)
    d.secBox:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 6, listTop - 158)
    d.secBox:SetAutoFocus(false); d.secBox:SetMaxLetters(30)

    Track(Label("Item IDs (comma-separated, pins them here - e.g. for a BiS list)", listTop - 184))
    d.idBox = Track(CreateFrame("EditBox", "GrimfallBagsCatItemIDs", d, "InputBoxTemplate"))
    d.idBox:SetWidth(280); d.idBox:SetHeight(20)
    d.idBox:SetPoint("TOPLEFT", d, "TOPLEFT", paneX + 6, listTop - 198)
    d.idBox:SetAutoFocus(false); d.idBox:SetMaxLetters(500)
    d.idBox:SetNumeric(false)

    d.hiddenCB = Track(CreateFrame("CheckButton", nil, d))
    d.hiddenCB:SetWidth(20); d.hiddenCB:SetHeight(20)
    d.hiddenCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    d.hiddenCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    d.hiddenCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    d.hiddenCB:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, listTop - 224)
    local hlbl = Track(d.hiddenCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    hlbl:SetPoint("LEFT", d.hiddenCB, "RIGHT", 4, 0)
    hlbl:SetText("Hide (don't show this category)")
    d.hiddenCB:SetHitRectInsets(0, -(hlbl:GetStringWidth() + 8), 0, 0)
    B.SkinCheck(d.hiddenCB)

    d.protectedCB = Track(CreateFrame("CheckButton", nil, d))
    d.protectedCB:SetWidth(20); d.protectedCB:SetHeight(20)
    d.protectedCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    d.protectedCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    d.protectedCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    d.protectedCB:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, listTop - 250)
    local plbl = Track(d.protectedCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    plbl:SetPoint("LEFT", d.protectedCB, "RIGHT", 4, 0)
    plbl:SetText("|cffff8888Protect (can't sell items in this category)|r")
    d.protectedCB:SetHitRectInsets(0, -(plbl:GetStringWidth() + 8), 0, 0)
    B.SkinCheck(d.protectedCB)

    d.sortLastCB = Track(CreateFrame("CheckButton", nil, d))
    d.sortLastCB:SetWidth(20); d.sortLastCB:SetHeight(20)
    d.sortLastCB:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    d.sortLastCB:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    d.sortLastCB:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    d.sortLastCB:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, listTop - 276)
    local slbl = Track(d.sortLastCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    slbl:SetPoint("LEFT", d.sortLastCB, "RIGHT", 4, 0)
    slbl:SetText("Sort last (always show this category at the bottom)")
    d.sortLastCB:SetHitRectInsets(0, -(slbl:GetStringWidth() + 8), 0, 0)
    B.SkinCheck(d.sortLastCB)

    local drop = Track(CreateFrame("Button", nil, d))
    drop:SetWidth(280); drop:SetHeight(26)
    drop:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, listTop - 302)
    drop:SetBackdrop(B.PANEL_BD)
    drop:SetBackdropColor(0.1, 0.2, 0.1, 0.8)
    drop:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local dropLbl = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropLbl:SetPoint("CENTER")
    dropLbl:SetText("Drag an item here -> pin it to this category")
    dropLbl:SetTextColor(0.6, 0.9, 0.6)

    d.pinText = Track(d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    d.pinText:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 2, -4)
    d.pinText:SetTextColor(0.6, 0.6, 0.6)
    d.pinClear = Track(CreateFrame("Button", nil, d, "UIPanelButtonTemplate"))
    d.pinClear:SetWidth(60); d.pinClear:SetHeight(16)
    d.pinClear:SetPoint("LEFT", d.pinText, "RIGHT", 8, 0)
    d.pinClear:SetText("Clear")
    d.pinClear:SetScript("OnClick", function()
        local r = editIdx and B.Config().rules[editIdx]
        if r then
            r.items = nil
            RefreshDialog()
            if B.RefreshAll then B.RefreshAll() end
        end
    end)
    d.pinClear:Hide()
    B.SkinButton(d.pinClear)
    local function DropItem()
        local name = d.nameBox:GetText()
        if name == "" then
            print("|cff33aaff[GrimfallBags]|r Select a category or enter a name first.")
            return
        end
        if B.AssignCursorToCategory(name) then
            for i, r in ipairs(B.Config().rules) do
                if r.name == name then editIdx = i end
            end
            RefreshDialog()
        end
    end
    drop:SetScript("OnReceiveDrag", DropItem)
    drop:SetScript("OnClick", DropItem)

    local newBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    newBtn:SetWidth(70); newBtn:SetHeight(20)
    newBtn:SetPoint("TOPLEFT", d, "TOPLEFT", paneX, listTop - 350)
    newBtn:SetText(NEW or "Neu")
    newBtn:SetScript("OnClick", function()
        editIdx = nil
        editSection = nil
        RefreshDialog()
        d.nameBox:SetFocus()
    end)
    B.SkinButton(newBtn)

    local newSectionBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    newSectionBtn:SetWidth(110); newSectionBtn:SetHeight(20)
    newSectionBtn:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -6)
    newSectionBtn:SetText("New Section")
    newSectionBtn:SetScript("OnClick", function()
        StaticPopup_Show("GFBAGS_NEW_SECTION")
    end)
    B.SkinButton(newSectionBtn)

    d.saveBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.saveBtn:SetWidth(100); d.saveBtn:SetHeight(20)
    d.saveBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
    local function SaveRule()
        if editSection then
            local newName = d.nameBox:GetText()
            if newName == "" then return end
            local cfg = B.Config()
            for i2, s in ipairs(cfg.sections) do
                if s == editSection then cfg.sections[i2] = newName end
            end
            for _, r in ipairs(cfg.rules) do
                if r.section == editSection then r.section = newName end
            end
            editSection = newName
            RefreshDialog()
            if B.RefreshAll then B.RefreshAll() end
            return
        end
        local name = d.nameBox:GetText()
        if name == "" then return end
        local tags = {}
        for tag in d.tagBox:GetText():gmatch("[^,]+") do
            local t = tag:lower():match("^%s*(.-)%s*$")
            if t ~= "" then tags[#tags+1] = t end
        end
        local query = d.qBox:GetText()
        local rules = B.Config().rules
        local rule
        if editIdx and rules[editIdx] then
            rule = rules[editIdx]
            if rule.name ~= name then
                B.Config().hiddenCats[name] = B.Config().hiddenCats[rule.name]
                B.Config().hiddenCats[rule.name] = nil
            end
        else
            rule = {}
            rules[#rules+1] = rule
            editIdx = #rules
        end
        rule.name  = name
        rule.tags  = tags
        rule.query = (query ~= "" and query:lower() or nil)
        local sec  = d.secBox:GetText()
        rule.section = (sec ~= "" and sec or nil)
        rule.protected = d.protectedCB:GetChecked() and true or nil
        rule.sortLast = d.sortLastCB:GetChecked() and true or nil

        local ids = {}
        for numStr in d.idBox:GetText():gmatch("[^,]+") do
            local id = tonumber(numStr:match("^%s*(.-)%s*$"))
            if id then ids[#ids+1] = id end
        end
        for _, r2 in ipairs(rules) do
            if r2 ~= rule and r2.items then
                for _, id in ipairs(ids) do r2.items[id] = nil end
            end
        end
        if #ids > 0 then
            rule.items = {}
            for _, id in ipairs(ids) do rule.items[id] = true end
        else
            rule.items = nil
        end

        B.Config().hiddenCats[name] = d.hiddenCB:GetChecked() and true or nil
        RefreshDialog()
        if B.RefreshAll then B.RefreshAll() end
    end
    d.saveBtn:SetScript("OnClick", SaveRule)
    B.SkinButton(d.saveBtn)
    d.nameBox:SetScript("OnEnterPressed", SaveRule)
    d.tagBox:SetScript("OnEnterPressed", SaveRule)
    d.qBox:SetScript("OnEnterPressed", SaveRule)
    d.idBox:SetScript("OnEnterPressed", SaveRule)
    d.nameBox:SetScript("OnEscapePressed", d.nameBox.ClearFocus)
    d.tagBox:SetScript("OnEscapePressed", d.tagBox.ClearFocus)
    d.idBox:SetScript("OnEscapePressed", d.idBox.ClearFocus)
    d.qBox:SetScript("OnEscapePressed", d.qBox.ClearFocus)

    d.delBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.delBtn:SetWidth(90); d.delBtn:SetHeight(20)
    d.delBtn:SetPoint("LEFT", d.saveBtn, "RIGHT", 6, 0)
    d.delBtn:SetText("|cffff3333"..(DELETE or "Delete").."|r")
    d.delBtn:SetScript("OnClick", function()
        if editSection then
            local cfg = B.Config()
            for _, r in ipairs(cfg.rules) do
                if r.section == editSection then r.section = nil end
            end
            for i2 = #cfg.sections, 1, -1 do
                if cfg.sections[i2] == editSection then table.remove(cfg.sections, i2) end
            end
            editSection = nil
            RefreshDialog()
            if B.RefreshAll then B.RefreshAll() end
            return
        end
        if editIdx and B.Config().rules[editIdx] then
            table.remove(B.Config().rules, editIdx)
            editIdx = nil
            RefreshDialog()
            if B.RefreshAll then B.RefreshAll() end
        end
    end)
    B.SkinButton(d.delBtn)

    local hint = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", paneX, 14)
    hint:SetWidth(290)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Order = priority (top wins). Pinned items override all rules - drag an item onto the category title, or type item IDs above. Tags + Search together must BOTH match (e.g. mail armor that's also spirit gear). Search also scans tooltip text, so stats like 'spirit' work. Super-groups (Equipment, Crafting, ...): click 'New Section' to create one, then drag categories onto its header (or type its name in the Super-group field above) to add them. Click a group's header to rename or ungroup it.")

    d:SetScript("OnShow", RefreshDialog)
end

B.RefreshCatDialog = function() RefreshDialog() end

function B.ToggleCatDialog()
    if B.OpenOptions then B.OpenOptions("categories") end
end
