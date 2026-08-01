---------------------------------------------------------------------------
-- AscensionBags - Views
-- Bag and bank windows: category view (flow layout) and single view,
-- search (Syndicator335 syntax), character selector with offline view,
-- bag-slot row, money, "New" category, icon details.
---------------------------------------------------------------------------
local B = AscensionBags
local S = Syndicator335
local Log, Guard = B.Log, B.Guard

-- Layout constants. BTN (icon size) matches the standard in-game bag
-- icon size and isn't user-configurable. COLS is derived live from the
-- window's width (flexbox-style wrap, see SyncLayoutConstants), uncapped -
-- widening the window just fits more per row.
local COLS, BTN = 12, 37
local BTN_PAD   = 2
local PAD       = 10
local TITLE_H   = 24
local SEARCH_H  = 24
local FILTER_H  = 22
local HEADER_H  = 16
local WIDTH     = 0

local bagView, bankView   -- created at PLAYER_LOGIN

---------------------------------------------------------------------------
-- "New" detection: if an itemID's count goes up, it counts as new for
-- recentSecs (green border + temp category at the top)
---------------------------------------------------------------------------
-- Both are persisted PER CHARACTER in the config, so not everything
-- counts as "new" after a relog. Expiry uses time() (epoch), not
-- GetTime() (session uptime, doesn't survive a restart).
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
    baseline    = st.baseline   -- direkte Referenzen -> speichert automatisch
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
        -- very first scan of this character: adopt as the baseline,
        -- mark NOTHING as new
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

---------------------------------------------------------------------------
-- View-Fabrik
---------------------------------------------------------------------------
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

    -- One parent frame per bag with SetID(bag): this makes Blizzard's
    -- template handlers (tooltip, use, move, sell at a merchant) work
    -- without any custom code.
    for _, bag in ipairs(bagIDs) do
        local p = CreateFrame("Frame", name.."Bag"..bag, f)
        p:SetID(bag)
        view.bagParents[bag] = p
    end

    return view
end

---------------------------------------------------------------------------
-- Button-Pools
---------------------------------------------------------------------------
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
        -- IMPORTANT: do NOT override OnClick here. ContainerFrameItemButton-
        -- Template is one of Blizzard's own secure-adjacent templates -
        -- replacing its OnClick (even just to pass through to the original
        -- handler) taints that button's entire click path permanently,
        -- including totally unrelated clicks later (this caused a real
        -- "tainted UseContainerItem" block when opening an unrelated loot
        -- bag). Sell protection only touches OUR OWN frames instead: the
        -- category header's right-click-sell and the toolbar bulk-sell
        -- button, see Transfers.lua - individual click-to-sell at a
        -- merchant can't be safely intercepted this way.
        view.buttons[view.nBtn] = btn
    else
        btn:SetParent(view.bagParents[bag])
    end
    btn:Show()
    return btn
end

-- Offline display buttons: icon/count/border/tooltip, not clickable
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

-- Category headers are buttons: dragging an item onto one assigns its
-- tags to that category (= the item moves into this category).
-- Section headers (super-groups): full width, collapse arrow,
-- divider line - like the "Equipment"/"Crafting" rows in the original
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
                -- Right-click a category header at a merchant to sell
                -- everything in it. Shift skips the confirmation popup.
                if not B.IsAtMerchant or not B.IsAtMerchant() then return end
                if not self.cat or not self.items or #self.items == 0 then return end
                if B.IsCategoryProtected and B.IsCategoryProtected(self.cat) then
                    print("|cffff5555[AscensionBags]|r '"..self.cat.."' is a protected category - can't sell from it.")
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

---------------------------------------------------------------------------
-- Fill buttons
---------------------------------------------------------------------------
-- Quality/new border as its own overlay texture.
-- IMPORTANT (3.3.5a/Ascension): GetNormalTexture() is unreliable on this
-- client (returns nil) -> never rely on it.
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

---------------------------------------------------------------------------
-- Transmog dot (purple, top right): item appearance not yet in the
-- collection. Detected via tooltip scan: Ascension writes the collected
-- status as a text line into the tooltip ("You've collected this
-- appearance" / "Hold CTRL + ALT and Click to collect this appearance
-- ..."). A hidden scan tooltip reads those lines out.
---------------------------------------------------------------------------
local scanTip
local tmogCache = {}   -- [itemID] = "collected" | "missing" | "none"

function B.WipeTmogCache()
    wipe(tmogCache)
end

local function GetTmogState(link)
    local id = S.ItemID(link)
    if not id then return nil end
    local cached = tmogCache[id]
    if cached then return cached end

    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "AscensionBagsScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)

    local state = "none"   -- no appearance line = not transmoggable
    for i = 1, scanTip:NumLines() do
        local line = _G["AscensionBagsScanTipTextLeft"..i]
        local text = line and line:GetText()
        if text then
            text = text:lower()
            -- order matters: "collected this appearance" is NOT a
            -- substring of the "collect this appearance" line
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
        t:SetTexture(0.7, 0.25, 0.95, 1)   -- purple
        t:Hide()
        btn.tmogDot = t
    end
    if link and B.Config().showTmogDot and GetTmogState(link) == "missing" then
        btn.tmogDot:Show()
    else
        btn.tmogDot:Hide()
    end
end
B.ApplyTmogDot = ApplyTmogDot   -- also used by the guild bank window

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

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
-- COLS (used by the flat single-list/grid view, where there are no
-- category blocks to pack) is derived from the frame's current width,
-- uncapped - recomputed on every refresh, including live during a
-- resize drag. The category view computes its own per-block cap the
-- same way, see maxBlockCols below.
local function SyncLayoutConstants(view)
    COLS = math.max(1, math.floor((view.f:GetWidth() - PAD * 2 + BTN_PAD) / (BTN + BTN_PAD)))
end

local function RefreshImpl(view)
    if not view.f:IsShown() then return end
    SyncLayoutConstants(view)
    local cfg = B.Config()

    for i = 1, view.nBtn  do view.buttons[i]:Hide()  end
    for i = 1, view.nOBtn do view.obuttons[i]:Hide() end
    for i = 1, view.nHdr  do view.headers[i]:Hide()  end
    for i = 1, view.nSHdr do view.sheaders[i]:Hide() end
    view.nBtn, view.nOBtn, view.nHdr, view.nSHdr = 0, 0, 0, 0

    -- Resolve offline data
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
    local startY = -(PAD + TITLE_H + SEARCH_H + FILTER_H)
    local y      = startY

    ------------------------------------------------------------------
    -- Gather data -> groups/order (+free slots)
    ------------------------------------------------------------------
    local groups, order = {}, {}
    local freeSlots, totalSlots = 0, 0
    local singleList   -- single view only (live)

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

    ------------------------------------------------------------------
    -- Layout
    ------------------------------------------------------------------
    if singleList then
        -- SINGLE: every slot including empty ones, bag order
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
        -- CATEGORIES: sort items within each group VISUALLY -
        -- by the configured sort method (type/quality/ilvl),
        -- independent of the item's physical position in the bag
        for _, cat in ipairs(order) do
            table.sort(groups[cat], function(a, b)
                local ka, kb = B.SortKey(a.l), B.SortKey(b.l)
                if ka ~= kb then return ka < kb end
                if a.sortName ~= b.sortName then return a.sortName < b.sortName end
                return false
            end)
        end

        -- Empty group
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

        -- Display order: "New" first, then the rules in PRIORITY
        -- order (the editor list!), rules sharing a super-group
        -- (section) as one collapsible block together, then unknown
        -- fallback categories alphabetically, "Empty" last.
        local cfgRules = B.Config().rules
        local present, usedCat, usedSection = {}, {}, {}
        for _, c in ipairs(order) do present[c] = true end

        local seq = {}   -- blocks: {cat=...} or {section=..., cats={...}}
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

        -- Flow layout: real CSS-flexbox-style wrap. Each category is
        -- its own block (header + icon grid), only wrapped internally
        -- to a second row if it has more items than fit across the
        -- whole window in one go. Blocks pack left to right using the
        -- window's actual width and only drop to a new row when the
        -- next block no longer fits in the remaining space - NOT one
        -- category per row like a plain column grid would give you.
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

        -- Only live, real items (not offline-cache entries, not the
        -- placeholder entries used for the "Empty" group) can actually
        -- be sold by right-clicking a header.
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
                -- Super-group: divider line + collapsible header row
                -- (full window width - always its own row)
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

---------------------------------------------------------------------------
-- Tracked currency: shown inline in the bottom bar next to the money
-- display, icon+count per currency reading right-to-left toward the
-- window's edge, money furthest right - matches how the real Baganator
-- addon (and Blizzard's own pre-replacement backpack) lays this out,
-- rather than a separate side panel.
---------------------------------------------------------------------------
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

-- Called with the bag view (bank has no money row today, so nothing to
-- anchor a currency row to there either).
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
                -- Built manually (name + count we already have) rather
                -- than GameTooltip:SetCurrencyToken - that call doesn't
                -- reliably show the currency's name on this client.
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

---------------------------------------------------------------------------
-- Mass-collect transmog appearances from every bag item in one click -
-- same underlying Ascension API (C_AppearanceCollection) as the /run
-- one-liner floating around, just as a toolbar button. Skips legendary+
-- quality (quality >= 5), matching that macro's own filter.
---------------------------------------------------------------------------
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
    B.WipeTmogCache()   -- collected status just changed - refresh the purple dots
    B.RefreshAll()
end

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------
local function AddToolbar(view, isBank)
    local f = view.f
    local tmogBtn   -- set below (bag window only), referenced later by bagsBtn's anchor

    -- Icons on the right: sort, view, categories, options
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

    -- Transfer button (context-sensitive visibility, see Transfers.lua)
    local transBtn = B.TitleIconButton(f, B.ASSETS.."Transfer",
        "Transfer: sell/deposit matching items", function()
            if view.offline then return end
            B.DoTransfer(view)
        end)
    transBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)
    transBtn:Hide()
    view.transferBtn = transBtn

    -- Collect all transmog appearances from bag items (bag window only -
    -- this is a live bag operation, not something offline character
    -- views or the bank window need). Uses the built-in "INV_Misc_Statue_02"
    -- icon since no custom asset was made for this button - renders fine,
    -- just looks like a small golden urn/sack at this size.
    if not isBank then
        tmogBtn = B.TitleIconButton(f, "Interface\\Icons\\INV_Misc_Statue_02",
            "Collect all transmog appearances from bags", function()
                if view.offline then return end
                B.Guard("CollectAllTransmog", CollectAllTransmog)
            end)
        tmogBtn:SetPoint("RIGHT", transBtn, "LEFT", -3, 0)
    end

    -- Character selector (bag window only)
    if not isBank then
        local charMenu = CreateFrame("Frame", "AscensionBagsCharMenu", UIParent, "UIDropDownMenuTemplate")
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

    -- Search field spanning the full width, with a placeholder, a
    -- magnifying-glass icon, and a clear ("x") button that only shows
    -- once there's text to clear.
    local rowY = -(PAD + TITLE_H - 2)
    local sbox = CreateFrame("EditBox", f:GetName().."Search", f, "InputBoxTemplate")
    sbox:SetHeight(20)
    sbox:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD + 6, rowY)
    sbox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + 4), rowY)
    sbox:SetAutoFocus(false)
    sbox:SetMaxLetters(60)
    -- Room on both sides for the icon/clear-button so typed text never
    -- runs under either of them.
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
    -- Quick-filter row (quality swatches + item-type shortcuts, GudaBags-
    -- style): built below, but UpdateFilterHighlights is referenced here
    -- as a forward declaration so typing a matching word by hand also
    -- lights up the corresponding button.
    local UpdateFilterHighlights

    sbox:SetScript("OnTextChanged", function(self)
        view.searchStr = self:GetText()
        local hasText = self:GetText() ~= ""
        placeholder:SetShown(not hasText)
        clearBtn:SetShown(hasText)
        if UpdateFilterHighlights then UpdateFilterHighlights() end
        Refresh(view)
    end)
    sbox:SetScript("OnEscapePressed", sbox.ClearFocus)
    view.searchBox = sbox
    B.SkinEdit(sbox)

    -- Defensive: an EditBox can retain keyboard focus across a Hide/Show
    -- cycle on some clients even with SetAutoFocus(false) (which only
    -- suppresses focus-on-FIRST-show), so typing right after opening the
    -- window could land in the search box without ever clicking it.
    -- Explicitly drop focus every time the window becomes visible.
    f:HookScript("OnShow", function() sbox:ClearFocus() end)

    -- Quick-filter row: quality swatches + item-type shortcuts. Click
    -- to set the search box to that term; click the SAME one again (or
    -- type over it) to clear. All of these ride on the existing search
    -- vocabulary (Syndicator335/Search.lua) - no separate filter engine.
    local filterRowY = rowY - SEARCH_H
    local filterBtns = {}
    local prevF

    local function PlaceFilterBtn(b, gap)
        if prevF then
            b:SetPoint("LEFT", prevF, "RIGHT", gap or 4, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 6, filterRowY)
        end
        prevF = b
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
        for _, b in ipairs(filterBtns) do
            b.sel:SetShown(b.word == cur)
        end
    end

    local QUALITY_FILTERS = {
        {word="poor", q=0}, {word="common", q=1}, {word="uncommon", q=2},
        {word="rare", q=3}, {word="epic", q=4}, {word="legendary", q=5},
    }
    for _, qf in ipairs(QUALITY_FILTERS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(14, 14)
        PlaceFilterBtn(b, 3)

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
        filterBtns[#filterBtns+1] = b
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
        PlaceFilterBtn(b, i == 1 and 10 or 4)

        local sel = b:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetTexture(0.3, 0.55, 0.85, 0.35)
        sel:Hide()
        b.sel = sel
        b.word = tf.word

        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() ApplyQuickFilter(tf.word) end)
        filterBtns[#filterBtns+1] = b
    end

    -- Bag-slot row above the window (toggled via a button)
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

        local bagsBtn = B.TitleIconButton(f, B.ASSETS.."Bags",
            "Show/hide bag slots", function()
                local cfg = B.Config()
                cfg.showBagRow = not cfg.showBagRow
                view.UpdateBagRow()
            end)
        bagsBtn:SetPoint("RIGHT", tmogBtn, "LEFT", -3, 0)
    end

    -- Money (bag window only)
    if not isBank then
        local money = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 4), PAD - 2)
        view.moneyText = money
    end
end

---------------------------------------------------------------------------
-- Open/close + replace Blizzard bags
---------------------------------------------------------------------------
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

-- Asked once: which addon should own bags/bank/guild bank when ElvUI is
-- also installed (ElvUI has its own bag windows - see the note above
-- PLAYER_ENTERING_WORLD's handler for why they'd otherwise both open).
-- Reuses the existing replaceBags/replaceBank/replaceGuildBank toggles -
-- "keep ElvUI's" is just those three flipped false, same as a player
-- unchecking them by hand in Options. hideOnEscape is deliberately off:
-- Blizzard's popup framework routes an Escape dismissal through OnCancel,
-- same as clicking button2, and button2 here has a real side effect
-- (switching to ElvUI) that an accidental Escape shouldn't trigger.
StaticPopupDialogs["ASCBAGS_ELVUI_CHOICE"] = {
    text = "ElvUI's own bag/bank windows were detected.\nUse AscensionBags, or keep ElvUI's?",
    button1 = "Use AscensionBags",
    button2 = "Keep ElvUI's",
    OnAccept = function() B.Config().elvuiPromptShown = true end,
    OnCancel = function()
        local cfg = B.Config()
        cfg.replaceBags, cfg.replaceBank, cfg.replaceGuildBank = false, false, false
        cfg.elvuiPromptShown = true
        print("|cff33aaff[AscensionBags]|r Switched to ElvUI's bags/bank - /reload to apply.")
    end,
    timeout = 0, whileDead = 1, hideOnEscape = false,
}

local function HookBagFunctions()
    if not B.Config().replaceBags then return end
    _G["ToggleBackpack"] = B.ToggleBags
    _G["OpenBackpack"]   = OpenBags
    _G["CloseBackpack"]  = CloseBags
    -- OpenAllBags aliased to the toggle (not a one-way open): the
    -- Shift+B keybind calls OpenAllBags() on every press regardless of
    -- state (Blizzard's own "are bags open" check looks at its own
    -- hidden default bag frames, which we replace, so that check
    -- always says "closed"). CloseAllBags must stay a plain one-way
    -- close, though - Blizzard calls it defensively in other places
    -- (e.g. Escape's "close everything" handler) expecting it to safely
    -- do nothing when bags are already closed; making it a toggle too
    -- meant Escape POPPED bags open instead of leaving them alone.
    _G["OpenAllBags"]    = B.ToggleBags
    _G["CloseAllBags"]   = CloseBags
    _G["ToggleBag"]      = B.ToggleBags
end

-- Blizzard's personal bank window (BankFrame) is part of the always-
-- loaded core UI, unlike the guild bank (a separate lazy addon), so no
-- ADDON_LOADED gate is needed. Same caution as the guild bank: do NOT
-- Hide() it (could end the server-side banking session).
--
-- IMPORTANT: unlike the guild bank, do NOT use SetAlpha(0)/EnableMouse
-- (false) here - confirmed by testing that this breaks tooltips for
-- bank-slot items entirely (GameTooltip:SetBagItem on bank bag IDs
-- apparently depends on BankFrame being genuinely shown/interactive to
-- succeed, not just logically "open"). Instead, physically relocate it
-- off-screen: it stays fully real/functional from the game's
-- perspective (nothing disabled), just somewhere you'll never see or
-- click it, which avoids the tooltip issue entirely.
local function HideBlizzardBank()
    if B.Config().replaceBank and BankFrame then
        BankFrame:HookScript("OnShow", function(f)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
        end)
        Log("Blizzard bank moved off-screen")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
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
    if not bagView then return end   -- vor PLAYER_LOGIN nichts tun
    expireTick = expireTick + (elapsed or 0)
    if expireTick > 5 then
        expireTick = 0
        if ExpireRecent() then dirty = true end
    end
    if dirty then
        dirty = false
        Guard("UpdateRecent", UpdateRecent)
        B.WipeTmogCache()   -- Sammel-Status kann sich geaendert haben
        Refresh(bagView)
        Refresh(bankView)
    end

    -- Live column reflow while dragging the resize grip, throttled so
    -- a full re-layout doesn't run every single frame during a drag.
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
            -- initial/fallback width only (used when no saved winWidth
            -- exists yet); actual column count is always derived from
            -- the frame's live width from here on, see SyncLayoutConstants
            WIDTH = PAD * 2 + 12 * (BTN + BTN_PAD)
            Log("Init: Config ok")

            -- Hook B/Shift+B FIRST, before any window/toolbar building
            -- below (which includes ElvUI skin calls and other more
            -- exploratory code) - that way a failure further down this
            -- function can never take the bag keybind down with it.
            HookBagFunctions()
            HideBlizzardBank()
            Log("Init: hooks ok")

            local me = UnitName("player")
            bagView  = CreateView("AscensionBagsBackpack",
                                  me.." - "..(BACKPACK_TOOLTIP or "Backpack"), B.PLAYER_BAGS)
            bankView = CreateView("AscensionBagsBank",
                                  me.." - "..(BANK or "Bank"), B.BANK_BAGS)
            B.bagView, B.bankView = bagView, bankView
            Log("Init: views created")

            AddToolbar(bagView, false)
            AddToolbar(bankView, true)
            Log("Init: toolbars ok")

            RefreshCurrencyRow(bagView)
            Log("Init: currency row ok")

            B.RestorePosition(bagView.f, "AscensionBagsBackpack",
                {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100})
            B.RestorePosition(bankView.f, "AscensionBagsBank",
                {"TOPLEFT", UIParent, "TOPLEFT", 50, -104})
            B.RestoreWidth(bagView.f, "AscensionBagsBackpack", WIDTH)
            B.RestoreWidth(bankView.f, "AscensionBagsBank", WIDTH)

            if IsAddOnLoaded("ElvUI") and not B.Config().elvuiPromptShown then
                StaticPopup_Show("ASCBAGS_ELVUI_CHOICE")
            end

            -- load the persistent "new" tracking state; the baseline
            -- scan happens on the first BAG_UPDATE (links are often
            -- still nil right at PLAYER_LOGIN)
            LoadRecentState()
            Log("Init: recent-item state loaded")

            -- seed the default categories as editable rules on first
            -- start (visible/editable in the category editor)
            B.SeedDefaultCategories()
            B.SeedBiSCategory()

            -- initialize transmog detection (see log)
            B.InitTmogAPI()
        end)
        Log("PLAYER_LOGIN: end")
        print("|cff33aaff[AscensionBags]|r loaded  |cffffcc00/ascbags|r opens it, /ascbags log shows the log.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-assert our replacement of OpenBackpack/ToggleBag/etc. AFTER
        -- everything else has had a chance to run theirs. Some addons
        -- (e.g. ElvUI's Bags module) use hooksecurefunc-style hooking,
        -- which WRAPS whatever function is currently in the global slot
        -- instead of replacing it - if their hook installs after ours,
        -- calling e.g. OpenBackpack() ends up calling both bag UIs
        -- (ours AND theirs), which is exactly the double-bag-window bug.
        -- Our own HookBagFunctions does a plain overwrite, so as long as
        -- we run LAST, any such wrapper gets discarded and only our
        -- window opens. PLAYER_ENTERING_WORLD reliably fires after every
        -- addon's PLAYER_LOGIN handling is done, so re-running here wins
        -- the race regardless of addon load order. Cheap/idempotent, so
        -- safe to re-run on every zone change too.
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

-- Syndicator335 reports data changes (e.g. guild bank scan finished)
S.OnDataChanged = function(what)
    if what == "guild" and B.RefreshGuildBank then B.RefreshGuildBank() end
end
