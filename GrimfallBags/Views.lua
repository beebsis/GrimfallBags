local B = GrimfallBags
local S = Syndicator335
local Log, Guard = B.Log, B.Guard

local COLS, BTN = 12, 37
local BTN_PAD   = 2
local PAD       = 10
local TITLE_H   = 24
local SEARCH_H  = 24
local FILTER_H  = 22
local HEADER_H  = 16
local WIDTH     = 0

local bagView, bankView

local recentItems = {}
local baseline    = {}

local function LoadRecentState()
    local cfg = B.Config()
    cfg.newState = cfg.newState or {}
    local key = Syndicator335.CharKey()
    local st = cfg.newState[key]
    if not st then
        st = {baseline = {}, recent = {}}
        cfg.newState[key] = st
    end
    baseline    = st.baseline
    recentItems = st.recent
end

local function CountBagItems()
    local t = {}
    for _, bag in ipairs(B.PLAYER_BAGS) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            local id = S.ItemID(link)
            if id then
                local _, cnt = GetContainerItemInfo(bag, slot)
                t[id] = (t[id] or 0) + (cnt or 1)
            end
        end
    end
    return t
end

local function UpdateRecent()
    local counts = CountBagItems()
    if next(baseline) == nil then
        for id, cnt in pairs(counts) do baseline[id] = cnt end
        return
    end
    for id, cnt in pairs(counts) do
        if cnt > (baseline[id] or 0) then
            recentItems[id] = time() + B.Config().recentSecs
        end
        baseline[id] = cnt
    end
end

local function IsRecent(id)
    local exp = id and recentItems[id]
    return exp and exp > time()
end

local function ExpireRecent()
    local now, changed = time(), false
    for id, exp in pairs(recentItems) do
        if exp <= now then recentItems[id] = nil; changed = true end
    end
    return changed
end

local function CreateView(name, titleText, bagIDs)
    local view = { bags = bagIDs, buttons = {}, obuttons = {}, headers = {},
                   sheaders = {}, bagParents = {},
                   nBtn = 0, nOBtn = 0, nHdr = 0, nSHdr = 0,
                   defaultTitle = titleText }

    local f = CreateFrame("Frame", name, UIParent)
    f:SetWidth(WIDTH)
    f:SetHeight(200)
    B.MakeMovable(f, name)
    B.MakeResizable(f, name, PAD * 2 + 4 * (BTN + BTN_PAD), function()
        view.resizeDirty = true
    end)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    B.StyleWindow(f)
    f:Hide()
    view.f = f
    tinsert(UISpecialFrames, name)

    view.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.title:SetPoint("TOP", f, "TOP", 0, -(PAD - 2))
    view.title:SetText(titleText)

    view.freeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.freeText:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 24, -(PAD - 1))
    view.freeText:SetTextColor(0.6, 0.6, 0.6)

    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    for _, bag in ipairs(bagIDs) do
        local p = CreateFrame("Frame", name.."Bag"..bag, f)
        p:SetID(bag)
        view.bagParents[bag] = p
    end

    return view
end

local function AcquireButton(view, bag)
    view.nBtn = view.nBtn + 1
    local btn = view.buttons[view.nBtn]
    if not btn then
        btn = CreateFrame("Button", view.f:GetName().."Item"..view.nBtn,
                          view.bagParents[bag], "ContainerFrameItemButtonTemplate")
        btn:SetWidth(BTN); btn:SetHeight(BTN)
        local ilvl = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        ilvl:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        ilvl:Hide()
        btn.ilvl = ilvl
        btn:SetScript("OnEnter", function(self)
            if not self.bag then return end
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == self
               and self.tooltipLink == self.link then
                return
            end
            self.tooltipLink = self.link
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip.updateTooltip = nil
            -- SetBagItem(-1, slot) never works here and still leaves the tooltip auto-hiding after; skip it for the main bank container.
            if self.bag ~= -1 then
                Guard("BagItemTooltip", function()
                    GameTooltip:SetBagItem(self.bag, self:GetID())
                end)
            end
            if GameTooltip:NumLines() == 0 then
                if self.link then
                    Guard("BagItemTooltipFallback", function()
                        GameTooltip:SetHyperlink(self.link)
                    end)
                end
                if GameTooltip:NumLines() == 0 then GameTooltip:Hide() end
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        view.buttons[view.nBtn] = btn
    else
        btn:SetParent(view.bagParents[bag])
    end
    btn.bag = bag
    btn:Show()
    return btn
end

local function AcquireOfflineButton(view)
    view.nOBtn = view.nOBtn + 1
    local btn = view.obuttons[view.nOBtn]
    if not btn then
        btn = CreateFrame("Button", view.f:GetName().."OItem"..view.nOBtn,
                          view.f, "ItemButtonTemplate")
        btn:SetWidth(BTN); btn:SetHeight(BTN)
        btn:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        view.obuttons[view.nOBtn] = btn
    end
    btn:Show()
    return btn
end

local function AcquireSectionHeader(view)
    view.nSHdr = view.nSHdr + 1
    local h = view.sheaders[view.nSHdr]
    if not h then
        h = CreateFrame("Button", nil, view.f)
        h:SetHeight(20)
        h.line = h:CreateTexture(nil, "ARTWORK")
        h.line:SetHeight(1)
        h.line:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
        h.line:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
        h.line:SetTexture(0.4, 0.4, 0.45, 0.6)
        h.lbl = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.lbl:SetPoint("LEFT", h, "LEFT", 2, -2)
        h.lbl:SetTextColor(1, 0.82, 0)
        h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        h:SetScript("OnClick", function(self)
            local cc = B.Config().sectionCollapsed
            cc[self.section] = not cc[self.section] or nil
            B.RefreshAll()
        end)
        view.sheaders[view.nSHdr] = h
    end
    h:Show()
    return h
end

local function AcquireHeader(view)
    view.nHdr = view.nHdr + 1
    local h = view.headers[view.nHdr]
    if not h then
        h = CreateFrame("Button", nil, view.f)
        h:SetHeight(HEADER_H)
        h.lbl = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.lbl:SetPoint("LEFT", h, "LEFT", 0, 0)
        h.lbl:SetTextColor(1, 0.82, 0)
        h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        h.SetText = function(self, text)
            self.lbl:SetText(text)
            self:SetWidth(math.max(40, self.lbl:GetStringWidth() + 8))
        end
        h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        h:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if not B.IsAtMerchant or not B.IsAtMerchant() then return end
                if not self.cat or not self.items or #self.items == 0 then return end
                if B.IsCategoryProtected and B.IsCategoryProtected(self.cat) then
                    print("|cffff5555[GrimfallBags]|r '"..self.cat.."' is a protected category - can't sell from it.")
                    return
                end
                if IsShiftKeyDown() then
                    B.SellCategoryConfirmed(self.items, self.cat)
                else
                    B.SellCategory(self.items, self.cat)
                end
                return
            end
            if self.cat and self.catAssignable and CursorHasItem() then
                B.AssignCursorToCategory(self.cat)
            end
        end)
        h:SetScript("OnReceiveDrag", function(self)
            if self.cat and self.catAssignable and CursorHasItem() then
                B.AssignCursorToCategory(self.cat)
            end
        end)
        h:SetScript("OnEnter", function(self)
            if self.cat and B.IsAtMerchant and B.IsAtMerchant() and self.items and #self.items > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.cat)
                if B.IsCategoryProtected and B.IsCategoryProtected(self.cat) then
                    GameTooltip:AddLine("Protected - can't sell from this category", 1, 0.4, 0.4, true)
                else
                    GameTooltip:AddLine("Right-click to sell all "..#self.items.." items here",
                                         0.6, 0.9, 0.6, true)
                    GameTooltip:AddLine("Shift-right-click to sell instantly, no confirmation",
                                         0.6, 0.6, 0.6, true)
                end
                GameTooltip:Show()
            end
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        view.headers[view.nHdr] = h
    end
    h:Show()
    return h
end

local function EnsureBorder(btn)
    if btn.qborder then return btn.qborder end
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    t:SetBlendMode("ADD")
    t:SetWidth(BTN * 1.7); t:SetHeight(BTN * 1.7)
    t:SetPoint("CENTER")
    t:Hide()
    btn.qborder = t
    return t
end

local function ApplyBorder(btn, quality, isNew)
    local t = EnsureBorder(btn)
    if isNew then
        t:SetVertexColor(0.2, 1, 0.2, 0.9)
        t:Show()
    elseif quality and quality > 1 then
        local r, g, b = GetItemQualityColor(quality)
        t:SetVertexColor(r, g, b, 0.8)
        t:Show()
    else
        t:Hide()
    end
end

local scanTip
local tmogCache = {}

function B.WipeTmogCache()
    wipe(tmogCache)
end

local function GetTmogState(link)
    local id = S.ItemID(link)
    if not id then return nil end
    local cached = tmogCache[id]
    if cached then return cached end

    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "GrimfallBagsScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)

    local state = "none"
    for i = 1, scanTip:NumLines() do
        local line = _G["GrimfallBagsScanTipTextLeft"..i]
        local text = line and line:GetText()
        if text then
            text = text:lower()
            if text:find("collected this appearance", 1, true) then
                state = "collected"
                break
            elseif text:find("collect this appearance", 1, true) then
                state = "missing"
                break
            end
        end
    end
    tmogCache[id] = state
    return state
end

function B.InitTmogAPI()
    Log("Transmog: tooltip scan active")
end

local function ApplyTmogDot(btn, link)
    if not btn.tmogDot then
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetWidth(8); t:SetHeight(8)
        t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
        t:SetTexture(0.7, 0.25, 0.95, 1)
        t:Hide()
        btn.tmogDot = t
    end
    if link and B.Config().showTmogDot and GetTmogState(link) == "missing" then
        btn.tmogDot:Show()
    else
        btn.tmogDot:Hide()
    end
end
B.ApplyTmogDot = ApplyTmogDot

local function ApplyILvl(btn, link, quality)
    if not btn.ilvl then return end
    if B.Config().showILvl then
        local _, _, _, iLvl, _, _, _, _, equipLoc = GetItemInfo(link or "")
        if iLvl and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" then
            local r, g, b = GetItemQualityColor(quality or 1)
            btn.ilvl:SetText(iLvl)
            btn.ilvl:SetTextColor(r, g, b)
            btn.ilvl:Show()
            return
        end
    end
    btn.ilvl:Hide()
end

local function FillLiveButton(btn, bag, slot, query)
    btn:SetID(slot)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    btn.link = link

    SetItemButtonTexture(btn, texture)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked or (B.Config().greyJunk and quality == 0))

    ApplyBorder(btn, quality, IsRecent(S.ItemID(link)))
    ApplyILvl(btn, link, quality)
    ApplyTmogDot(btn, link)

    local cd = _G[btn:GetName().."Cooldown"]
    if cd then
        CooldownFrame_SetTimer(cd, GetContainerItemCooldown(bag, slot))
    end

    if query and query ~= "" then
        btn:SetAlpha(link and S.Search.Matches(
            {l=link, c=count, q=quality, isNew=IsRecent(S.ItemID(link))}, query) and 1 or 0.25)
    else
        btn:SetAlpha(1)
    end
end

local function FillOfflineButton(btn, it, query)
    btn.link = it.l
    if it.isEmpty then
        SetItemButtonTexture(btn, nil)
        local cnt = _G[btn:GetName().."Count"]
        if cnt then cnt:SetText(it.free); cnt:Show() end
    else
        SetItemButtonTexture(btn, it.t or "Interface\\Icons\\INV_Misc_QuestionMark")
        SetItemButtonCount(btn, it.c)
    end
    ApplyBorder(btn, it.q, false)
    ApplyTmogDot(btn, it.l)
    if query and query ~= "" and not it.isEmpty then
        btn:SetAlpha(S.Search.Matches(it, query) and 1 or 0.25)
    else
        btn:SetAlpha(1)
    end
end

local function SyncLayoutConstants(view)
    COLS = math.max(1, math.floor((view.f:GetWidth() - PAD * 2 + BTN_PAD) / (BTN + BTN_PAD)))
end

local function ChromeExtraHeight(cfg)
    return cfg.showSearchFilters and (SEARCH_H + FILTER_H) or 0
end

local function RefreshImpl(view)
    if not view.f:IsShown() then return end
    SyncLayoutConstants(view)
    local cfg = B.Config()

    -- Skip hiding whatever button GameTooltip is anchored to, so a refresh doesn't invalidate its owner.
    local keepBtn = GameTooltip:IsShown() and GameTooltip:GetOwner()
    for i = 1, view.nBtn do
        if view.buttons[i] ~= keepBtn then view.buttons[i]:Hide() end
    end
    for i = 1, view.nOBtn do view.obuttons[i]:Hide() end
    for i = 1, view.nHdr  do view.headers[i]:Hide()  end
    for i = 1, view.nSHdr do view.sheaders[i]:Hide() end
    view.nBtn, view.nOBtn, view.nHdr, view.nSHdr = 0, 0, 0, 0

    local off
    if view.offline then
        off = S.API.GetCharacter(view.offline.key)
        if not off then view.offline = nil end
    end
    if view.offline then
        view.title:SetText("|cffaaaaff"..view.offline.key..
            (view.offline.which == "bank" and "  ("..(BANK or "Bank")..")" or "").."|r")
    else
        view.title:SetText(view.defaultTitle)
    end

    local query  = (view.searchStr or ""):lower()
    local startY = -(PAD + TITLE_H + ChromeExtraHeight(cfg))
    local y      = startY

    local groups, order = {}, {}
    local freeSlots, totalSlots = 0, 0
    local singleList

    if off then
        local src = (view.offline.which == "bank") and off.bank or off.bags
        for _, b in pairs(src or {}) do
            totalSlots = totalSlots + (b.size or 0)
            local filled = 0
            for slot, e in pairs(b) do
                if type(slot) == "number" and type(e) == "table" and e.l then
                    filled = filled + 1
                    local cat = B.Categorize(e)
                    if not B.IsCategoryHidden(cat) then
                        if not groups[cat] then groups[cat] = {}; order[#order+1] = cat end
                        local it = {offline=true, l=e.l, c=e.c, t=e.t,
                                    q=e.q or 0,
                                    sortName=S.ItemName(e.l):lower()}
                        groups[cat][#groups[cat]+1] = it
                    end
                end
            end
            freeSlots = freeSlots + math.max(0, (b.size or 0) - filled)
        end
    elseif cfg.viewType == "single" then
        singleList = true
        for _, bag in ipairs(view.bags) do
            local n = GetContainerNumSlots(bag) or 0
            totalSlots = totalSlots + n
            for slot = 1, n do
                if not GetContainerItemLink(bag, slot) then
                    freeSlots = freeSlots + 1
                end
            end
        end
    else
        for _, bag in ipairs(view.bags) do
            local n = GetContainerNumSlots(bag) or 0
            totalSlots = totalSlots + n
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, count, _, quality = GetContainerItemInfo(bag, slot)
                    local entry = {l=link, c=count, q=quality}
                    local cat
                    if IsRecent(S.ItemID(link)) then
                        cat = B.RECENT_LABEL
                    else
                        cat = B.Categorize(entry)
                    end
                    if not B.IsCategoryHidden(cat) then
                        if not groups[cat] then groups[cat] = {}; order[#order+1] = cat end
                        groups[cat][#groups[cat]+1] = {
                            bag=bag, slot=slot, l=link, q=quality or 0,
                            sortName=S.ItemName(link):lower(),
                        }
                    end
                else
                    freeSlots = freeSlots + 1
                end
            end
        end
    end
    view.freeText:SetText(freeSlots.."/"..totalSlots)

    if singleList then
        local col = 0
        for _, bag in ipairs(view.bags) do
            for slot = 1, GetContainerNumSlots(bag) or 0 do
                local btn = AcquireButton(view, bag)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", view.f, "TOPLEFT",
                             PAD + col * (BTN + BTN_PAD), y)
                FillLiveButton(btn, bag, slot, query)
                col = col + 1
                if col >= COLS then col = 0; y = y - (BTN + BTN_PAD) end
            end
        end
        if col > 0 then y = y - (BTN + BTN_PAD) end
    else
        for _, cat in ipairs(order) do
            table.sort(groups[cat], function(a, b)
                local ka, kb = B.SortKey(a.l), B.SortKey(b.l)
                if ka ~= kb then return ka < kb end
                if a.sortName ~= b.sortName then return a.sortName < b.sortName end
                return false
            end)
        end

        local emptyGroup = {}
        if off then
            if freeSlots > 0 then
                emptyGroup[1] = {offline=true, isEmpty=true, free=freeSlots, q=0}
            end
        else
            local seen = {}
            for _, bag in ipairs(view.bags) do
                local free, family = GetContainerNumFreeSlots(bag)
                family = family or 0
                if free and free > 0 then
                    local e = seen[family]
                    if not e then
                        local firstSlot
                        for slot = 1, GetContainerNumSlots(bag) or 0 do
                            if not GetContainerItemLink(bag, slot) then
                                firstSlot = slot; break
                            end
                        end
                        e = {bag=bag, slot=firstSlot, free=0, isEmpty=true, q=0}
                        seen[family] = e
                        emptyGroup[#emptyGroup+1] = e
                    end
                    e.free = e.free + free
                end
            end
        end
        local EMPTY_LABEL = EMPTY or "Empty"
        if #emptyGroup > 0 then
            groups[EMPTY_LABEL] = emptyGroup
            order[#order+1] = EMPTY_LABEL
        end

        local cfgRules = B.Config().rules
        local present, usedCat, usedSection = {}, {}, {}
        for _, c in ipairs(order) do present[c] = true end

        local seq = {}
        if present[B.RECENT_LABEL] then
            seq[#seq+1] = {cat = B.RECENT_LABEL}
            usedCat[B.RECENT_LABEL] = true
        end
        for _, r in ipairs(cfgRules) do
            if r.section and r.section ~= "" then
                if not usedSection[r.section] then
                    usedSection[r.section] = true
                    local cats = {}
                    for _, r2 in ipairs(cfgRules) do
                        if r2.section == r.section and present[r2.name]
                           and not usedCat[r2.name] then
                            cats[#cats+1] = r2.name
                            usedCat[r2.name] = true
                        end
                    end
                    if #cats > 0 then
                        seq[#seq+1] = {section = r.section, cats = cats}
                    end
                end
            elseif present[r.name] and not usedCat[r.name] then
                seq[#seq+1] = {cat = r.name}
                usedCat[r.name] = true
            end
        end
        local rest = {}
        for _, c in ipairs(order) do
            if not usedCat[c] and c ~= EMPTY_LABEL then rest[#rest+1] = c end
        end
        table.sort(rest)
        for _, c in ipairs(rest) do seq[#seq+1] = {cat = c} end
        if present[EMPTY_LABEL] then seq[#seq+1] = {cat = EMPTY_LABEL} end

        local availWidth  = view.f:GetWidth() - PAD * 2
        local maxBlockCols = math.max(1, math.floor((availWidth + BTN_PAD) / (BTN + BTN_PAD)))
        local BLOCK_GAP  = 14
        local rowX, rowH = 0, 0
        local function NewRow()
            y = y - rowH - 5
            rowX, rowH = 0, 0
        end
        local function PlaceItem(it, x, yy)
            local btn
            if it.offline then
                btn = AcquireOfflineButton(view)
                FillOfflineButton(btn, it, query)
            else
                btn = AcquireButton(view, it.bag)
                FillLiveButton(btn, it.bag, it.slot, it.isEmpty and "" or query)
                if it.isEmpty then
                    local cnt = _G[btn:GetName().."Count"]
                    if cnt then cnt:SetText(it.free); cnt:Show() end
                end
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", view.f, "TOPLEFT", x, yy)
        end

        local function SellableItems(items)
            local out = {}
            for _, it in ipairs(items) do
                if it.bag and it.slot and it.l and not it.offline and not it.isEmpty then
                    out[#out+1] = {bag = it.bag, slot = it.slot, link = it.l}
                end
            end
            return out
        end

        local function RenderCat(cat)
            local items = groups[cat]
            local n = items and #items or 0
            if n == 0 then return end

            local blockCols = math.min(n, maxBlockCols)
            local rows = math.ceil(n / blockCols)

            local hdr = AcquireHeader(view)
            hdr:ClearAllPoints()
            hdr:SetText(cat)
            hdr.cat = cat
            hdr.catAssignable = (cat ~= B.RECENT_LABEL and cat ~= EMPTY_LABEL)
            hdr.items = (cat ~= EMPTY_LABEL) and SellableItems(items) or nil

            local blockWidth  = math.max(blockCols * (BTN + BTN_PAD), hdr:GetWidth() + 4)
            local blockHeight = HEADER_H + rows * (BTN + BTN_PAD)

            if rowX > 0 and rowX + blockWidth > availWidth then NewRow() end

            hdr:SetPoint("TOPLEFT", view.f, "TOPLEFT", PAD + rowX + 2, y)
            for i, it in ipairs(items) do
                local col = (i - 1) % blockCols
                local row = math.floor((i - 1) / blockCols)
                PlaceItem(it, PAD + rowX + col * (BTN + BTN_PAD),
                          y - HEADER_H - row * (BTN + BTN_PAD))
            end

            rowH = math.max(rowH, blockHeight)
            rowX = rowX + blockWidth + BLOCK_GAP
        end

        local collapsed = B.Config().sectionCollapsed
        for _, block in ipairs(seq) do
            if block.cat then
                RenderCat(block.cat)
            else
                if rowX > 0 then NewRow() end
                local sh = AcquireSectionHeader(view)
                sh.section = block.section
                sh:ClearAllPoints()
                sh:SetPoint("TOPLEFT",  view.f, "TOPLEFT",  PAD, y)
                sh:SetPoint("TOPRIGHT", view.f, "TOPRIGHT", -PAD, y)
                local isCollapsed = collapsed[block.section]
                sh.lbl:SetText((isCollapsed and "|cffaaaaaa> |r" or "|cffaaaaaav |r")
                               ..block.section)
                y = y - 22
                if not isCollapsed then
                    for _, c in ipairs(block.cats) do RenderCat(c) end
                    if rowX > 0 then NewRow() end
                end
            end
        end
        if rowX > 0 then NewRow() end
    end

    view.f:SetHeight(-y + PAD + (view.moneyText and 16 or 0))

    if view.moneyText then
        view.moneyText:SetText(B.MoneyString(off and off.money or GetMoney()))
    end
    if view.UpdateBagRow then view.UpdateBagRow() end
end

local function Refresh(view)
    if not view then return end
    Guard("Refresh:"..view.f:GetName(), RefreshImpl, view)
end

function B.RefreshAll()
    Refresh(bagView)
    Refresh(bankView)
    if B.RefreshGuildBank then B.RefreshGuildBank() end
end

local function GetWatchedCurrencies()
    local list = {}
    for i = 1, GetCurrencyListSize() do
        local name, isHeader, _, _, isWatched, count, _, icon = GetCurrencyListInfo(i)
        if not isHeader and isWatched then
            list[#list+1] = {name = name, count = count, icon = icon, index = i}
        end
    end
    return list
end

local function RefreshCurrencyRow(view)
    if not view.moneyText then return end
    view.currencyPairs = view.currencyPairs or {}
    local list = GetWatchedCurrencies()
    local prevAnchor = view.moneyText

    for i, cur in ipairs(list) do
        local pair = view.currencyPairs[i]
        if not pair then
            pair = CreateFrame("Button", nil, view.f)
            pair:SetHeight(16)
            local icon = pair:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("RIGHT", pair, "RIGHT", 0, 0)
            pair.icon = icon
            local txt = pair:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("RIGHT", icon, "LEFT", -2, 0)
            pair.txt = txt
            pair:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.currencyName, 1, 0.82, 0)
                GameTooltip:AddLine(tostring(self.currencyCount), 1, 1, 1)
                GameTooltip:Show()
            end)
            pair:SetScript("OnLeave", function() GameTooltip:Hide() end)
            view.currencyPairs[i] = pair
        end
        pair.icon:SetTexture(cur.icon)
        pair.txt:SetText(cur.count)
        pair.currencyName = cur.name
        pair.currencyCount = cur.count
        pair:SetWidth(14 + 2 + pair.txt:GetStringWidth() + 6)
        pair:ClearAllPoints()
        pair:SetPoint("RIGHT", prevAnchor, "LEFT", -8, 0)
        pair:Show()
        prevAnchor = pair
    end
    for i = #list + 1, #view.currencyPairs do
        view.currencyPairs[i]:Hide()
    end
end
B.RefreshCurrencyRow = RefreshCurrencyRow

-- Toggling "Show on Backpack" in Blizzard's own Currency tab context menu
-- (TokenFramePopup) calls SetCurrencyBackpack() directly -- confirmed
-- live, CURRENCY_DISPLAY_UPDATE doesn't reliably fire for that specific
-- change, only for amount changes, so the bottom currency row was only
-- ever catching up on the next window open. Hooking the Blizzard
-- function itself guarantees a refresh exactly when the checkbox
-- changes, regardless of what event (if any) accompanies it.
if type(SetCurrencyBackpack) == "function" then
    hooksecurefunc("SetCurrencyBackpack", function()
        if bagView then RefreshCurrencyRow(bagView) end
    end)
end

local function CollectAllTransmog()
    for _, bag in ipairs(B.PLAYER_BAGS) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local quality = select(3, GetItemInfo(itemID))
                if quality and quality < 5 then
                    C_AppearanceCollection.CollectItemAppearance(GetContainerItemGUID(bag, slot))
                end
            end
        end
    end
    B.WipeTmogCache()
    B.RefreshAll()
end

local function AddToolbar(view, isBank)
    local f = view.f
    local tmogBtn

    local gear = B.TitleIconButton(f, B.ASSETS.."Cog",
        "Options", function() B.ToggleOptions() end)
    gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -(PAD - 2))

    local catBtn = B.TitleIconButton(f, B.ASSETS.."SavedSearches",
        "Edit categories", function() B.ToggleCatDialog() end)
    catBtn:SetPoint("RIGHT", gear, "LEFT", -3, 0)

    local viewBtn = B.TitleIconButton(f, B.ASSETS.."GuildTabText",
        "Switch view (category/single)", function()
            local cfg = B.Config()
            cfg.viewType = (cfg.viewType == "category") and "single" or "category"
            B.RefreshAll()
        end)
    viewBtn:SetPoint("RIGHT", catBtn, "LEFT", -3, 0)

    local sortBtn = B.TitleIconButton(f, B.ASSETS.."Sorting",
        "Sort", function()
            if view.offline then return end
            B.StartSort(view.bags)
        end)
    sortBtn:SetPoint("RIGHT", viewBtn, "LEFT", -3, 0)

    local transBtn = B.TitleIconButton(f, B.ASSETS.."Transfer",
        "Transfer: sell/deposit matching items", function()
            if view.offline then return end
            B.DoTransfer(view)
        end)
    transBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)
    transBtn:Hide()
    view.transferBtn = transBtn

    -- Grimfall doesn't have a transmog system (this was Ascension-only
    -- functionality) -- left commented rather than deleted in case
    -- Grimfall adds one later, since CollectAllTransmog/B.InitTmogAPI/
    -- the tmog-dot item overlay logic above are otherwise untouched and
    -- ready to reactivate. bagsBtn below anchors to transBtn instead of
    -- tmogBtn while this stays off, so the toolbar doesn't leave a gap
    -- (or worse, anchor to a nil frame and error).
    --[[
    if not isBank then
        tmogBtn = B.TitleIconButton(f, "Interface\\Icons\\INV_Misc_Statue_02",
            "Collect all transmog appearances from bags", function()
                if view.offline then return end
                B.Guard("CollectAllTransmog", CollectAllTransmog)
            end)
        tmogBtn:SetPoint("RIGHT", transBtn, "LEFT", -3, 0)
    end
    --]]

    if not isBank then
        local charMenu = CreateFrame("Frame", "GrimfallBagsCharMenu", UIParent, "UIDropDownMenuTemplate")
        local charBtn = B.TitleIconButton(f, B.ASSETS.."All_Characters",
            "Characters: view bags/bank offline", function()
                local myKey = S.CharKey()
                local menu = {
                    {text = "Characters", isTitle = true, notCheckable = true},
                    {text = myKey.."  |cff33ff33(live)|r", notCheckable = true,
                     func = function() view.offline = nil; Refresh(view) end},
                }
                for _, key in ipairs(S.API.GetAllCharacters()) do
                    if key ~= myKey then
                        local c = S.API.GetCharacter(key)
                        local color = "|cffcccccc"
                        local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
                        if cc then
                            color = string.format("|cff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255)
                        end
                        menu[#menu+1] = {text = color..key.."|r", notCheckable = true,
                            func = function()
                                view.offline = {key = key, which = "bags"}
                                Refresh(view)
                            end}
                        if c.bank then
                            menu[#menu+1] = {text = "    "..(BANK or "Bank"), notCheckable = true,
                                func = function()
                                    view.offline = {key = key, which = "bank"}
                                    Refresh(view)
                                end}
                        end
                    end
                end
                EasyMenu(menu, charMenu, "cursor", 0, 0, "MENU")
            end)
        charBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2, -(PAD - 2))
    end

    local rowY = -(PAD + TITLE_H - 2)
    local sbox = CreateFrame("EditBox", f:GetName().."Search", f, "InputBoxTemplate")
    sbox:SetHeight(20)
    sbox:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD + 6, rowY)
    sbox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + 4), rowY)
    sbox:SetAutoFocus(false)
    sbox:SetMaxLetters(60)
    sbox:SetTextInsets(16, 16, 0, 0)

    local searchIcon = sbox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(12, 12)
    searchIcon:SetPoint("LEFT", sbox, "LEFT", 2, 0)
    searchIcon:SetTexture(B.ASSETS.."Search")
    searchIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    searchIcon:SetAlpha(0.6)

    local clearBtn = CreateFrame("Button", nil, sbox)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", sbox, "RIGHT", -2, 0)
    local clearTex = clearBtn:CreateTexture(nil, "OVERLAY")
    clearTex:SetAllPoints()
    clearTex:SetTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:SetScript("OnClick", function()
        sbox:SetText("")
        sbox:ClearFocus()
    end)
    clearBtn:Hide()

    local placeholder = sbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("LEFT", sbox, "LEFT", 16, 0)
    placeholder:SetTextColor(0.45, 0.45, 0.45)
    placeholder:SetText((SEARCH or "Search").."  (e.g. potion | food, >200 & boe, !junk)")
    local UpdateFilterHighlights

    sbox:SetScript("OnTextChanged", function(self)
        view.searchStr = self:GetText()
        local hasText = self:GetText() ~= ""
        if hasText then placeholder:Hide() else placeholder:Show() end
        if hasText then clearBtn:Show() else clearBtn:Hide() end
        if UpdateFilterHighlights then UpdateFilterHighlights() end
        Refresh(view)
    end)
    sbox:SetScript("OnEscapePressed", sbox.ClearFocus)
    view.searchBox = sbox
    B.SkinEdit(sbox)

    f:HookScript("OnShow", function() sbox:ClearFocus() end)

    local qualityBtns, typeBtns = {}, {}

    local function RelayoutFilterRow()
        local shown = B.Config().showSearchFilters
        local y = rowY - SEARCH_H
        local prev
        local function place(b, gap)
            b:ClearAllPoints()
            if prev then
                b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
            else
                b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 6, y)
            end
            prev = b
        end
        for _, b in ipairs(qualityBtns) do
            if shown then b:Show(); place(b, 3) else b:Hide() end
        end
        for i, b in ipairs(typeBtns) do
            if shown then b:Show(); place(b, i == 1 and 10 or 4) else b:Hide() end
        end
    end

    local function ApplyQuickFilter(word)
        if sbox:GetText():lower() == word then
            sbox:SetText("")
        else
            sbox:SetText(word)
        end
    end

    UpdateFilterHighlights = function()
        local cur = sbox:GetText():lower()
        for _, b in ipairs(qualityBtns) do
            if b.word == cur then b.sel:Show() else b.sel:Hide() end
        end
        for _, b in ipairs(typeBtns) do
            if b.word == cur then b.sel:Show() else b.sel:Hide() end
        end
    end

    local QUALITY_FILTERS = {
        {word="poor", q=0}, {word="common", q=1}, {word="uncommon", q=2},
        {word="rare", q=3}, {word="epic", q=4}, {word="legendary", q=5},
    }
    for _, qf in ipairs(QUALITY_FILTERS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(14, 14)

        local r, g, bl = GetItemQualityColor(qf.q)
        local swatch = b:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", 1, -1)
        swatch:SetPoint("BOTTOMRIGHT", -1, 1)
        swatch:SetTexture(r, g, bl)

        local sel = b:CreateTexture(nil, "OVERLAY")
        sel:SetAllPoints()
        sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        sel:SetBlendMode("ADD")
        sel:SetVertexColor(1, 1, 1, 0.9)
        sel:Hide()
        b.sel = sel
        b.word = qf.word

        b:SetScript("OnClick", function() ApplyQuickFilter(qf.word) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((qf.word:gsub("^%l", string.upper)))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        qualityBtns[#qualityBtns+1] = b
    end

    local TYPE_FILTERS = {
        {label="Wpn", word="weapon"},   {label="Arm", word="armor"},
        {label="Con", word="consumable"}, {label="Trd", word="trade goods"},
        {label="Qst", word="quest"},    {label="Jnk", word="junk"},
        {label="BoE", word="boe"},      {label="New", word="new"},
    }
    for i, tf in ipairs(TYPE_FILTERS) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(FILTER_H - 4)
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(tf.label)
        b:SetWidth(lbl:GetStringWidth() + 10)

        local sel = b:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetTexture(0.3, 0.55, 0.85, 0.35)
        sel:Hide()
        b.sel = sel
        b.word = tf.word

        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() ApplyQuickFilter(tf.word) end)
        typeBtns[#typeBtns+1] = b
    end

    local function UpdateSearchBarVisibility()
        if B.Config().showSearchFilters then sbox:Show() else sbox:Hide() end
    end

    local function UpdateFilterVisibility()
        UpdateSearchBarVisibility()
        RelayoutFilterRow()
        Refresh(view)
    end
    UpdateFilterVisibility()

    local filtersBtn = B.TitleIconButton(f, B.ASSETS.."Search",
        "Show/hide search & filters", function()
            local cfg = B.Config()
            cfg.showSearchFilters = not cfg.showSearchFilters
            UpdateFilterVisibility()
        end)

    local bagsBtn
    if not isBank then
        local slotBtns = {}
        local prev
        for _, bag in ipairs(B.PLAYER_BAGS) do
            local b = CreateFrame("Button", f:GetName().."BagSlot"..bag, f)
            b:SetWidth(28); b:SetHeight(28)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            else b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, 1) end
            prev = b
            b.bag = bag
            local icon = b:CreateTexture(nil, "BACKGROUND")
            icon:SetAllPoints()
            b.iconTex = icon
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                if self.bag == 0 then
                    GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack")
                else
                    GameTooltip:SetInventoryItem("player", ContainerIDToInventoryID(self.bag))
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                if self.bag == 0 then return end
                local invID = ContainerIDToInventoryID(self.bag)
                if CursorHasItem() then PutItemInBag(invID)
                else PickupBagFromSlot(invID) end
            end)
            b:Hide()
            slotBtns[#slotBtns+1] = b
        end

        function view.UpdateBagRow()
            local shown = B.Config().showBagRow
            for _, b in ipairs(slotBtns) do
                if shown then
                    b:Show()
                    if b.bag == 0 then
                        b.iconTex:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
                    else
                        local tex = GetInventoryItemTexture("player", ContainerIDToInventoryID(b.bag))
                        b.iconTex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                        b.iconTex:SetDesaturated(not tex)
                    end
                else
                    b:Hide()
                end
            end
        end

        bagsBtn = B.TitleIconButton(f, B.ASSETS.."Bags",
            "Show/hide bag slots", function()
                local cfg = B.Config()
                cfg.showBagRow = not cfg.showBagRow
                view.UpdateBagRow()
            end)

        -- transBtn is hidden by default (Transfers.lua shows it only at
        -- a merchant/bank with matching items) but its anchor slot is
        -- always reserved, which left a visible gap in the toolbar
        -- whenever it wasn't shown. Reflow bagsBtn onto sortBtn directly
        -- when transBtn is hidden, and back onto transBtn when it
        -- reappears, instead of always reserving its space.
        local function RelayoutBagsBtn()
            bagsBtn:ClearAllPoints()
            if transBtn:IsShown() then
                bagsBtn:SetPoint("RIGHT", transBtn, "LEFT", -3, 0)
            else
                bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)
            end
        end
        RelayoutBagsBtn()
        view.RelayoutBagsBtn = RelayoutBagsBtn
    else
        local slotBtns = {}
        local prev
        local numSlots = #B.BANK_BAGS - 1
        for slotNum = 1, numSlots do
            local bag = 4 + slotNum
            local b = CreateFrame("Button", f:GetName().."BagSlot"..bag, f)
            b:SetWidth(28); b:SetHeight(28)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            else b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, 1) end
            prev = b
            b.bag = bag
            b.slotNum = slotNum
            local icon = b:CreateTexture(nil, "BACKGROUND")
            icon:SetAllPoints()
            b.iconTex = icon
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                local purchased = GetNumBankSlots() or 0
                if self.slotNum <= purchased then
                    GameTooltip:SetInventoryItem("player", ContainerIDToInventoryID(self.bag))
                elseif self.slotNum == purchased + 1 then
                    GameTooltip:SetText("Buy Bank Bag Slot")
                    local cost = GetBankSlotCost(purchased)
                    if cost then SetTooltipMoney(GameTooltip, cost) end
                else
                    GameTooltip:SetText("Bank Bag Slot (locked)")
                    GameTooltip:AddLine("Purchase the previous slot first.", 0.6, 0.6, 0.6, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                local purchased = GetNumBankSlots() or 0
                if self.slotNum <= purchased then
                    local invID = ContainerIDToInventoryID(self.bag)
                    if CursorHasItem() then PutItemInBag(invID)
                    else PickupBagFromSlot(invID) end
                elseif self.slotNum == purchased + 1 then
                    StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
                end
            end)
            slotBtns[#slotBtns+1] = b
        end

        function view.UpdateBagRow()
            local purchased = GetNumBankSlots() or 0
            for _, b in ipairs(slotBtns) do
                local tex = b.slotNum <= purchased
                    and GetInventoryItemTexture("player", ContainerIDToInventoryID(b.bag))
                    or nil
                b.iconTex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                if b.slotNum <= purchased then
                    b.iconTex:SetDesaturated(not tex)
                    b.iconTex:SetAlpha(1)
                elseif b.slotNum == purchased + 1 then
                    b.iconTex:SetDesaturated(false)
                    b.iconTex:SetAlpha(0.7)
                else
                    b.iconTex:SetDesaturated(true)
                    b.iconTex:SetAlpha(0.35)
                end
            end
        end
    end

    local function RelayoutFiltersBtn()
        filtersBtn:ClearAllPoints()
        if bagsBtn then
            filtersBtn:SetPoint("RIGHT", bagsBtn, "LEFT", -3, 0)
        elseif transBtn:IsShown() then
            filtersBtn:SetPoint("RIGHT", transBtn, "LEFT", -3, 0)
        else
            filtersBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)
        end
    end
    RelayoutFiltersBtn()
    if isBank then view.RelayoutFiltersBtn = RelayoutFiltersBtn end

    if not isBank then
        local money = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 4), PAD - 2)
        view.moneyText = money
    end
end

local function OpenBags()
    if not bagView then return end
    bagView.f:Show()
    Refresh(bagView)
end
local function CloseBags()
    if bagView then bagView.f:Hide() end
end
function B.ToggleBags()
    if not bagView then return end
    if bagView.f:IsShown() then CloseBags() else OpenBags() end
end
B.OpenBags = OpenBags

local function DisableElvUIBags()
    local disabled = false
    if IsAddOnLoaded("ElvUI") then
        pcall(function()
            local E = unpack(ElvUI)
            if E.private and E.private.bags then
                E.private.bags.enable = false
                disabled = true
            end
        end)
    end
    if disabled then
        print("|cff33aaff[GrimfallBags]|r Disabled ElvUI's bags/bank windows - /reload to apply.")
    end
    return disabled
end
B.DisableElvUIBags = DisableElvUIBags

local function ElvUIBagsStillEnabled()
    if not IsAddOnLoaded("ElvUI") then return false end
    local ok, enabled = pcall(function()
        local E = unpack(ElvUI)
        return E.private and E.private.bags and E.private.bags.enable
    end)
    return ok and enabled
end

StaticPopupDialogs["GFBAGS_ELVUI_CHOICE"] = {
    text = "ElvUI's own bag/bank windows were detected.\nUse GrimfallBags, or keep ElvUI's?",
    button1 = "Use GrimfallBags",
    button2 = "Keep ElvUI's",
    OnAccept = function()
        local cfg = B.Config()
        cfg.elvuiPromptShown = true
        cfg.elvuiBagsMigrationPrompted = true
        DisableElvUIBags()
    end,
    OnCancel = function()
        local cfg = B.Config()
        cfg.replaceBags, cfg.replaceBank, cfg.replaceGuildBank = false, false, false
        cfg.elvuiPromptShown = true
        cfg.elvuiBagsMigrationPrompted = true
        print("|cff33aaff[GrimfallBags]|r Switched to ElvUI's bags/bank - /reload to apply.")
    end,
    timeout = 0, whileDead = 1, hideOnEscape = false,
}

StaticPopupDialogs["GFBAGS_ELVUI_STILL_ENABLED"] = {
    text = "GrimfallBags is set to replace your bags, but ElvUI's own bag/bank windows are still enabled.\nDisable ElvUI's bags/bank windows now?",
    button1 = "Yes, disable ElvUI's",
    button2 = "No, leave as-is",
    OnAccept = function()
        B.Config().elvuiBagsMigrationPrompted = true
        DisableElvUIBags()
    end,
    OnCancel = function()
        B.Config().elvuiBagsMigrationPrompted = true
    end,
    timeout = 0, whileDead = 1, hideOnEscape = false,
}

local function HookBagFunctions()
    if not B.Config().replaceBags then return end
    _G["ToggleBackpack"] = B.ToggleBags
    _G["OpenBackpack"]   = OpenBags
    _G["CloseBackpack"]  = CloseBags
    _G["OpenAllBags"]    = B.ToggleBags
    _G["CloseAllBags"]   = CloseBags
    _G["ToggleBag"]      = B.ToggleBags
end

local function HideBlizzardBank()
    if B.Config().replaceBank and BankFrame then
        -- Hide() would trigger OnHide -> CloseBankFrame(), ending the bank
        -- interaction server-side, so keep it shown but pin it off-screen.
        local repositioning = false
        local function PushOffscreen(f)
            if repositioning then return end
            repositioning = true
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
            repositioning = false
        end
        BankFrame:HookScript("OnShow", PushOffscreen)
        hooksecurefunc(BankFrame, "SetPoint", function(f)
            if not repositioning then PushOffscreen(f) end
        end)
        Log("Blizzard bank moved off-screen")
    end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("BAG_UPDATE")
evt:RegisterEvent("ITEM_LOCK_CHANGED")
evt:RegisterEvent("BAG_UPDATE_COOLDOWN")
evt:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
evt:RegisterEvent("BANKFRAME_OPENED")
evt:RegisterEvent("BANKFRAME_CLOSED")
evt:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

local dirty = false
local expireTick = 0
local resizeTick = 0
evt:SetScript("OnUpdate", function(self, elapsed)
    if not bagView then return end
    expireTick = expireTick + (elapsed or 0)
    if expireTick > 5 then
        expireTick = 0
        if ExpireRecent() then dirty = true end
    end
    if dirty then
        dirty = false
        Guard("UpdateRecent", UpdateRecent)
        B.WipeTmogCache()
        Refresh(bagView)
        Refresh(bankView)
    end

    if bagView.resizeDirty or bankView.resizeDirty then
        resizeTick = resizeTick + (elapsed or 0)
        if resizeTick > 0.1 then
            resizeTick = 0
            if bagView.resizeDirty  then bagView.resizeDirty  = nil; Refresh(bagView)  end
            if bankView.resizeDirty then bankView.resizeDirty = nil; Refresh(bankView) end
        end
    end
end)

evt:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Log("PLAYER_LOGIN: start")
        Guard("Init", function()
            WIDTH = PAD * 2 + 12 * (BTN + BTN_PAD)
            Log("Init: Config ok")

            HookBagFunctions()
            HideBlizzardBank()
            Log("Init: hooks ok")

            local me = UnitName("player")
            bagView  = CreateView("GrimfallBagsBackpack",
                                  me.." - "..(BACKPACK_TOOLTIP or "Backpack"), B.PLAYER_BAGS)
            bankView = CreateView("GrimfallBagsBank",
                                  me.." - "..(BANK or "Bank"), B.BANK_BAGS)
            B.bagView, B.bankView = bagView, bankView
            Log("Init: views created")

            AddToolbar(bagView, false)
            AddToolbar(bankView, true)
            Log("Init: toolbars ok")

            RefreshCurrencyRow(bagView)
            Log("Init: currency row ok")

            B.RestorePosition(bagView.f, "GrimfallBagsBackpack",
                {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100})
            B.RestorePosition(bankView.f, "GrimfallBagsBank",
                {"TOPLEFT", UIParent, "TOPLEFT", 50, -104})
            B.RestoreWidth(bagView.f, "GrimfallBagsBackpack", WIDTH)
            B.RestoreWidth(bankView.f, "GrimfallBagsBank", WIDTH)

            local ecfg = B.Config()
            if IsAddOnLoaded("ElvUI") and not ecfg.elvuiPromptShown then
                StaticPopup_Show("GFBAGS_ELVUI_CHOICE")
            elseif ecfg.replaceBags and not ecfg.elvuiBagsMigrationPrompted
                   and ElvUIBagsStillEnabled() then
                StaticPopup_Show("GFBAGS_ELVUI_STILL_ENABLED")
            end

            LoadRecentState()
            Log("Init: recent-item state loaded")

            B.SeedDefaultCategories()
            B.SeedBiSCategory()

            B.InitTmogAPI()
        end)
        Log("PLAYER_LOGIN: end")
        print("|cff33aaff[GrimfallBags]|r loaded  |cffffcc00/gfbags|r opens it, /gfbags log shows the log.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        Guard("ReassertBagHooks", HookBagFunctions)

    elseif event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED"
        or event == "BAG_UPDATE_COOLDOWN" or event == "PLAYERBANKSLOTS_CHANGED" then
        dirty = true

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        Guard("RefreshCurrency", RefreshCurrencyRow, bagView)

    elseif event == "BANKFRAME_OPENED" then
        if bankView then
            bankView.f:Show()
            Refresh(bankView)
        end
        OpenBags()
        if B.UpdateTransferButtons then B.UpdateTransferButtons() end

    elseif event == "BANKFRAME_CLOSED" then
        if bankView then bankView.f:Hide() end
        if B.UpdateTransferButtons then B.UpdateTransferButtons() end
    end
end)

S.OnDataChanged = function(what)
    if what == "guild" and B.RefreshGuildBank then B.RefreshGuildBank() end
end
