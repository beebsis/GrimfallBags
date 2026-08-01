---------------------------------------------------------------------------
-- AscensionBags - Guild Bank
-- Custom guild bank window: tab bar, 98-slot grid per tab, gold
-- deposit/withdraw, search. Fully interactive at the guild bank (items
-- in/out via the Blizzard API), read-only from the Syndicator335 cache
-- ("remote view") when away from it.
---------------------------------------------------------------------------
local B = AscensionBags
local S = Syndicator335
local Log, Guard = B.Log, B.Guard

local GB_COLS   = 14
local GB_MAX_COLS = 6   -- columns are width-driven but capped, see RefreshGuildBank
local GB_SLOTS  = 98
local BTN       = 37    -- matches the standard in-game bag icon size, fixed
local BTN_PAD   = 2
local PAD       = 10

local frame          -- Fenster
local buttons = {}   -- Live-Buttons (interaktiv)
local currentTab = 1
local atGuildBank = false
local gbResizeDirty = false

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------
local function Build()
    local w = CreateFrame("Frame", "AscensionBagsGuildBank", UIParent)
    local width = PAD * 2 + GB_COLS * (BTN + BTN_PAD)
    w:SetWidth(width)
    w:SetHeight(120 + math.ceil(GB_SLOTS / GB_COLS) * (BTN + BTN_PAD))
    B.MakeMovable(w, "AscensionBagsGuildBank")
    B.MakeResizable(w, "AscensionBagsGuildBank", PAD * 2 + 4 * (BTN + BTN_PAD), function()
        gbResizeDirty = true
    end)
    B.RestoreWidth(w, "AscensionBagsGuildBank", width)
    w:SetFrameStrata("HIGH")
    B.StyleWindow(w)
    w:Hide()
    tinsert(UISpecialFrames, "AscensionBagsGuildBank")
    frame = w

    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOP", w, "TOP", 0, -(PAD - 2))
    w.title:SetText(GUILD_BANK or "Guild Bank")

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    -- Titel-Icons: Sortieren (nur live) + Ansicht umschalten
    local viewBtn = B.TitleIconButton(w, B.ASSETS.."GuildTabText",
        "Switch view (category/grid)", function()
            local cfg = B.Config()
            cfg.gbCategoryView = not cfg.gbCategoryView
            B.RefreshGuildBank()
        end)
    viewBtn:SetPoint("TOPRIGHT", w, "TOPRIGHT", -28, -(PAD - 2))

    local sortBtn = B.TitleIconButton(w, B.ASSETS.."Sorting",
        "Aktuellen Tab sortieren", function()
            if atGuildBank then B.StartGuildBankSort() end
        end)
    sortBtn:SetPoint("RIGHT", viewBtn, "LEFT", -3, 0)
    w.sortBtn = sortBtn

    -- Header pool for the category view
    w.headers = {}
    w.nHdr = 0
    function w.AcquireHeader()
        w.nHdr = w.nHdr + 1
        local h = w.headers[w.nHdr]
        if not h then
            h = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetTextColor(1, 0.82, 0)
            w.headers[w.nHdr] = h
        end
        h:Show()
        return h
    end

    -- Tab bar (up to 6 tabs in 3.3.5a)
    w.tabBtns = {}
    for t = 1, 6 do
        local tb = CreateFrame("Button", "AscensionBagsGBTab"..t, w)
        tb:SetWidth(32); tb:SetHeight(32)
        if t == 1 then tb:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -(PAD + 18))
        else tb:SetPoint("LEFT", w.tabBtns[t-1], "RIGHT", 4, 0) end
        local icon = tb:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        tb.icon = icon
        local sel = tb:CreateTexture(nil, "OVERLAY")
        sel:SetAllPoints()
        sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        sel:SetBlendMode("ADD")
        sel:Hide()
        tb.sel = sel
        tb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        tb.tab = t
        tb:SetScript("OnClick", function(self)
            currentTab = self.tab
            if atGuildBank then
                SetCurrentGuildBankTab(self.tab)
                QueryGuildBankTab(self.tab)
            end
            B.RefreshGuildBank()
        end)
        tb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tabName or ((GUILD_BANK or "Tab").." "..self.tab))
            GameTooltip:Show()
        end)
        tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tb:Hide()
        w.tabBtns[t] = tb
    end

    -- Item grid: buttons with guild bank interaction
    local gridTop = -(PAD + 18 + 36 + 4)
    for i = 1, GB_SLOTS do
        local btn = CreateFrame("Button", "AscensionBagsGBItem"..i, w, "ItemButtonTemplate")
        btn:SetWidth(BTN); btn:SetHeight(BTN)
        local col = (i - 1) % GB_COLS
        local row = math.floor((i - 1) / GB_COLS)
        btn:SetPoint("TOPLEFT", w, "TOPLEFT",
                     PAD + col * (BTN + BTN_PAD), gridTop - row * (BTN + BTN_PAD))
        btn.slot = i
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnClick", function(self, mouse)
            if not atGuildBank then return end   -- Remote: nur ansehen
            if mouse == "RightButton" then
                AutoStoreGuildBankItem(currentTab, self.slot)   -- into bags
            else
                PickupGuildBankItem(currentTab, self.slot)      -- pick up/place
            end
        end)
        btn:SetScript("OnDragStart", function(self)
            if atGuildBank then PickupGuildBankItem(currentTab, self.slot) end
        end)
        btn:SetScript("OnReceiveDrag", function(self)
            if atGuildBank then PickupGuildBankItem(currentTab, self.slot) end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if atGuildBank then
                GameTooltip:SetGuildBankItem(currentTab, self.slot)
            elseif self.link then
                GameTooltip:SetHyperlink(self.link)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = btn
    end

    -- Money row + deposit/withdraw
    w.moneyText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.moneyText:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -(PAD + 4), PAD)

    w.depositBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.depositBtn:SetWidth(90); w.depositBtn:SetHeight(20)
    w.depositBtn:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", PAD, PAD - 2)
    w.depositBtn:SetText(GUILDBANK_DEPOSIT_BUTTON or "Deposit")
    w.depositBtn:SetScript("OnClick", function()
        StaticPopup_Show("ASCBAGS_GB_DEPOSIT")
    end)
    B.SkinButton(w.depositBtn)

    w.withdrawBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.withdrawBtn:SetWidth(90); w.withdrawBtn:SetHeight(20)
    w.withdrawBtn:SetPoint("LEFT", w.depositBtn, "RIGHT", 6, 0)
    w.withdrawBtn:SetText(GUILDBANK_WITHDRAW_BUTTON or "Withdraw")
    w.withdrawBtn:SetScript("OnClick", function()
        StaticPopup_Show("ASCBAGS_GB_WITHDRAW")
    end)
    B.SkinButton(w.withdrawBtn)
end

-- Gold dialogs (amount in gold)
StaticPopupDialogs["ASCBAGS_GB_DEPOSIT"] = {
    text = (GUILDBANK_DEPOSIT_BUTTON or "Deposit").." (Gold):",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 8,
    OnAccept = function(self)
        local g = tonumber(_G[self:GetName().."EditBox"]:GetText())
        if g and g > 0 then GuildBankDepositMoney(g * 10000) end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}
StaticPopupDialogs["ASCBAGS_GB_WITHDRAW"] = {
    text = (GUILDBANK_WITHDRAW_BUTTON or "Withdraw").." (Gold):",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 8,
    OnAccept = function(self)
        local g = tonumber(_G[self:GetName().."EditBox"]:GetText())
        if g and g > 0 then WithdrawGuildBankMoney(g * 10000) end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

---------------------------------------------------------------------------
-- Rendering (live at the guild bank or remote from the cache)
---------------------------------------------------------------------------
function B.RefreshGuildBank()
    if not (frame and frame:IsShown()) then return end
    Guard("RefreshGuildBank", function()
        -- GB_COLS (used only by the flat GRID mode below) is derived
        -- from the frame's live width, uncapped. The category-view
        -- packing further down uses GB_MAX_COLS separately.
        GB_COLS = math.max(1, math.floor((frame:GetWidth() - PAD * 2 + BTN_PAD) / (BTN + BTN_PAD)))

        local guild = S.Guild()

        -- Tab bar
        local numTabs = atGuildBank and (GetNumGuildBankTabs() or 0) or 0
        if not atGuildBank and guild then
            for t in pairs(guild.tabs or {}) do
                if t > numTabs then numTabs = t end
            end
        end
        for t, tb in ipairs(frame.tabBtns) do
            if t <= numTabs then
                local name, icon
                if atGuildBank then
                    name, icon = GetGuildBankTabInfo(t)
                elseif guild and guild.tabs[t] then
                    name = guild.tabs[t].name
                end
                tb.tabName = name
                tb.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Bag_10")
                if t == currentTab then tb.sel:Show() else tb.sel:Hide() end
                tb:Show()
            else
                tb:Hide()
            end
        end

        -- Title: live or remote indicator
        local gname = GetGuildInfo("player") or (GUILD or "Guild")
        frame.title:SetText(atGuildBank and (gname.." - "..(GUILD_BANK or "Guild Bank"))
            or ("|cffaaaaff"..gname.." - "..(GUILD_BANK or "Guild Bank").."  (Cache)|r"))

        -- Collect slot data (live or cache)
        local cachedTab = guild and guild.tabs and guild.tabs[currentTab]
        local entries = {}
        for i = 1, GB_SLOTS do
            local link, tex, cnt
            if atGuildBank then
                link = GetGuildBankItemLink(currentTab, i)
                tex, cnt = GetGuildBankItemInfo(currentTab, i)
            elseif cachedTab and cachedTab[i] then
                link = cachedTab[i].l
                tex  = cachedTab[i].t
                cnt  = cachedTab[i].c
            end
            entries[i] = {l=link, t=tex, c=cnt}
        end

        -- Fill button (position is handled by the layout below)
        local function Fill(btn, e)
            btn.link = e.l
            SetItemButtonTexture(btn, e.t)
            SetItemButtonCount(btn, e.c)
            local quality = e.l and select(3, GetItemInfo(e.l))
            if not btn.qborder then
                local t = btn:CreateTexture(nil, "OVERLAY")
                t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                t:SetBlendMode("ADD")
                t:SetWidth(BTN * 1.7); t:SetHeight(BTN * 1.7)
                t:SetPoint("CENTER")
                btn.qborder = t
            end
            if quality and quality > 1 then
                local r, g, bcol = GetItemQualityColor(quality)
                btn.qborder:SetVertexColor(r, g, bcol, 0.8)
                btn.qborder:Show()
            else
                btn.qborder:Hide()
            end
        end

        -- Reset headers
        for i = 1, frame.nHdr do frame.headers[i]:Hide() end
        frame.nHdr = 0

        frame.sortBtn.icon:SetDesaturated(not atGuildBank)

        local gridTop = -(PAD + 18 + 36 + 4)
        if not B.Config().gbCategoryView then
            -- GRID: classic 98-slot layout
            for i, btn in ipairs(buttons) do
                local col = (i - 1) % GB_COLS
                local row = math.floor((i - 1) / GB_COLS)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                             PAD + col * (BTN + BTN_PAD),
                             gridTop - row * (BTN + BTN_PAD))
                Fill(btn, entries[i])
            end
            frame:SetHeight(120 + math.ceil(GB_SLOTS / GB_COLS) * (BTN + BTN_PAD))
        else
            -- CATEGORIES: grouped like the bag window; empty slots as
            -- an "Empty" group at the end (they remain drop targets)
            local groups, order = {}, {}
            for i = 1, GB_SLOTS do
                local e = entries[i]
                local cat
                if e.l then
                    cat = B.Categorize({l=e.l})
                else
                    cat = EMPTY or "Empty"
                end
                if not groups[cat] then groups[cat] = {}; order[#order+1] = cat end
                groups[cat][#groups[cat]+1] = i
            end
            table.sort(order, function(a, b)
                local ea, eb = (a == (EMPTY or "Empty")), (b == (EMPTY or "Empty"))
                if ea ~= eb then return eb end   -- Empty goes last
                return a < b
            end)
            -- Sort items visually within the groups
            for _, slotList in pairs(groups) do
                table.sort(slotList, function(a, b)
                    local la, lb = entries[a].l, entries[b].l
                    if la and lb then
                        local ka, kb = B.SortKey(la), B.SortKey(lb)
                        if ka ~= kb then return ka < kb end
                    end
                    return a < b
                end)
            end

            -- Flow layout: same left-to-right packing as the bag
            -- window - each category is its own block (header + grid
            -- wrapped internally at GB_MAX_COLS wide), blocks pack
            -- side by side using the window's actual width and only
            -- drop to a new row when the next block no longer fits.
            local HEADER_H   = 16
            local BLOCK_GAP  = 14
            local availWidth = frame:GetWidth() - PAD * 2
            local y = gridTop
            local rowX, rowH = 0, 0
            for _, cat in ipairs(order) do
                local slotList = groups[cat]
                local n = #slotList
                local blockCols = math.min(n, GB_MAX_COLS)
                local rows = math.ceil(n / blockCols)

                local hdr = frame.AcquireHeader()
                hdr:ClearAllPoints()
                hdr:SetText(cat.."  |cff666666("..n..")|r")

                local blockWidth  = math.max(blockCols * (BTN + BTN_PAD), hdr:GetWidth() + 4)
                local blockHeight = HEADER_H + rows * (BTN + BTN_PAD)

                if rowX > 0 and rowX + blockWidth > availWidth then
                    y = y - rowH - 5
                    rowX, rowH = 0, 0
                end

                hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + rowX + 2, y)
                for i, slotIdx in ipairs(slotList) do
                    local col = (i - 1) % blockCols
                    local row = math.floor((i - 1) / blockCols)
                    local btn = buttons[slotIdx]
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                                 PAD + rowX + col * (BTN + BTN_PAD),
                                 y - HEADER_H - row * (BTN + BTN_PAD))
                    Fill(btn, entries[slotIdx])
                end

                rowH = math.max(rowH, blockHeight)
                rowX = rowX + blockWidth + BLOCK_GAP
            end
            if rowX > 0 then y = y - rowH - 5 end
            frame:SetHeight(-y + 40)
        end

        -- Geld + Buttons
        local money = atGuildBank and GetGuildBankMoney() or (guild and guild.money)
        frame.moneyText:SetText(B.MoneyString(money))
        if atGuildBank then
            frame.depositBtn:Show()
            frame.withdrawBtn:Show()
        else
            frame.depositBtn:Hide()
            frame.withdrawBtn:Hide()
        end
    end)
end

function B.ToggleGuildBank()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        B.RefreshGuildBank()
    end
end

---------------------------------------------------------------------------
-- Events: auto-open at the guild bank, suppress the Blizzard window
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Guild bank sorter: current tab, same logic as the bags (merge
-- stacks, then swap items into the target order).
---------------------------------------------------------------------------
local gbSorter = CreateFrame("Frame")
gbSorter:Hide()

local function GBSortStep()
    if not atGuildBank then return false end
    local tab = currentTab
    local slots = {}
    for i = 1, GB_SLOTS do
        local _, cnt, locked = GetGuildBankItemInfo(tab, i)
        if locked then return true end   -- wait
        local link = GetGuildBankItemLink(tab, i)
        slots[#slots+1] = {
            slot = i, link = link, id = S.ItemID(link), count = cnt or 0,
            max = link and (select(8, GetItemInfo(link)) or 1) or 1,
        }
    end

    -- merge partial stacks
    local partial = {}
    for _, s in ipairs(slots) do
        if s.id and s.count < s.max then
            local o = partial[s.id]
            if o then
                PickupGuildBankItem(tab, o.slot)
                PickupGuildBankItem(tab, s.slot)
                return true
            end
            partial[s.id] = s
        end
    end

    -- swap items into the target order
    local items = {}
    for _, s in ipairs(slots) do
        if s.link then items[#items+1] = s end
    end
    table.sort(items, function(a, b)
        local ka, kb = B.SortKey(a.link), B.SortKey(b.link)
        if ka ~= kb then return ka < kb end
        if a.count ~= b.count then return a.count > b.count end
        return false
    end)
    for pos, want in ipairs(items) do
        if want.slot ~= pos then
            PickupGuildBankItem(tab, want.slot)
            PickupGuildBankItem(tab, pos)
            return true
        end
    end
    return false
end

gbSorter:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.25 then return end
    self.t = 0
    if CursorHasItem() then return end
    self.steps = (self.steps or 0) + 1
    if self.steps > 300 then
        Log("GB sort aborted (too many steps)")
        self:Hide()
        return
    end
    local ok, more = pcall(GBSortStep)
    if not ok or not more then
        if not ok then Log("ERROR during GB sort: "..tostring(more)) end
        self:Hide()
        Log("GB sort finished ("..(self.steps or 0).." steps)")
    end
end)

function B.StartGuildBankSort()
    if gbSorter:IsShown() or not atGuildBank then return end
    gbSorter.t, gbSorter.steps = 0, 0
    gbSorter:Show()
    Log("GB sort started (tab "..currentTab..")")
end

-- Live column reflow while dragging the resize grip, throttled so a
-- full re-layout doesn't run every single frame during a drag.
local resizeTicker = CreateFrame("Frame")
resizeTicker:SetScript("OnUpdate", function(self, elapsed)
    if not gbResizeDirty then return end
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.1 then return end
    self.t = 0
    gbResizeDirty = false
    B.RefreshGuildBank()
end)

-- Stagger tab queries: one every half second. Querying every tab at
-- once can confuse custom servers (Ascension).
local queryQueue = {}
local queryTimer = CreateFrame("Frame")
queryTimer:Hide()
queryTimer:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.5 then return end
    self.t = 0
    local tab = table.remove(queryQueue, 1)
    if tab and atGuildBank then
        QueryGuildBankTab(tab)
        Log("QueryGuildBankTab("..tab..")")
    end
    if #queryQueue == 0 then self:Hide() end
end)

local function QueueTabQueries()
    wipe(queryQueue)
    for tab = 1, GetNumGuildBankTabs() or 0 do
        queryQueue[#queryQueue+1] = tab
    end
    queryTimer.t = 0.5   -- erster Query sofort
    queryTimer:Show()
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("GUILDBANKFRAME_OPENED")
evt:RegisterEvent("GUILDBANKFRAME_CLOSED")
evt:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
evt:RegisterEvent("GUILDBANK_UPDATE_MONEY")
evt:RegisterEvent("ADDON_LOADED")

evt:SetScript("OnEvent", function(self, event, arg1)
    if event == "GUILDBANKFRAME_OPENED" then
        atGuildBank = true
        if not frame then Build() end
        B.RestorePosition(frame, "AscensionBagsGuildBank",
            {"TOPLEFT", UIParent, "TOPLEFT", 40, -80})
        frame:Show()
        currentTab = GetCurrentGuildBankTab() or 1
        QueueTabQueries()
        B.RefreshGuildBank()
        Log("Guild bank opened (live)")

    elseif event == "GUILDBANKFRAME_CLOSED" then
        atGuildBank = false
        queryTimer:Hide()
        if frame then frame:Hide() end

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_MONEY" then
        B.RefreshGuildBank()

    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_GuildBankUI" then
        -- Do NOT Hide() Blizzard's guild bank (that could end the
        -- server-side session), instead make it invisible/unclickable.
        if B.Config().replaceGuildBank and GuildBankFrame then
            GuildBankFrame:HookScript("OnShow", function(f)
                f:SetAlpha(0)
                f:EnableMouse(false)
            end)
            Log("Blizzard guild bank made invisible")
        end
    end
end)
