local B = GrimfallBags
local S = Syndicator335
local Log, Guard = B.Log, B.Guard

B.GuildBankView = {}

local GB_COLS = 14
local BTN     = 37
local BTN_PAD = 2
local PAD     = 10

local frame
local buttons = {}
local currentTab = 1
local atGuildBank = false
local gbResizeDirty = false
local initialized = false

local SEARCH_ROW_Y = -(PAD + 18 + 36 + 4)

B.GuildBankView.IsOpen = function() return atGuildBank end

local function Initialize()
    if initialized then return end
    frame = _G["GrimfallBagsGuildBank"]
    if not frame then return end
    initialized = true

    B.MakeMovable(frame, "GrimfallBagsGuildBank")
    B.MakeResizable(frame, "GrimfallBagsGuildBank", PAD * 2 + 4 * (BTN + BTN_PAD), function()
        gbResizeDirty = true
    end)
    B.RestoreWidth(frame, "GrimfallBagsGuildBank", PAD * 2 + GB_COLS * (BTN + BTN_PAD))
    B.StyleWindow(frame)
    tinsert(UISpecialFrames, "GrimfallBagsGuildBank")

    frame.title = _G["GrimfallBagsGuildBankTitle"]
    frame.moneyText = _G["GrimfallBagsGuildBankMoney"]
    frame.depositBtn = _G["GrimfallBagsGuildBankDepositBtn"]
    frame.withdrawBtn = _G["GrimfallBagsGuildBankWithdrawBtn"]
    frame.sortBtn = _G["GrimfallBagsGuildBankSortBtn"]

    B.SkinClose(_G["GrimfallBagsGuildBankClose"])

    frame.title:SetText(GUILD_BANK or "Guild Bank")
    frame.depositBtn:SetText(GUILDBANK_DEPOSIT_BUTTON or "Deposit")
    frame.withdrawBtn:SetText(GUILDBANK_WITHDRAW_BUTTON or "Withdraw")
    B.SkinButton(frame.depositBtn)
    B.SkinButton(frame.withdrawBtn)

    local viewBtn = _G["GrimfallBagsGuildBankViewBtn"]
    B.SkinButton(viewBtn)
    viewBtn:SetScript("OnClick", function()
        local cfg = B.Config()
        cfg.gbCategoryView = not cfg.gbCategoryView
        B.GuildBankView.Refresh()
    end)
    viewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Switch view (category/grid)")
        GameTooltip:Show()
    end)
    viewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sortBtn = frame.sortBtn
    sortBtn.icon = _G["GrimfallBagsGuildBankSortBtnIcon"]
    B.SkinButton(sortBtn)
    sortBtn:SetScript("OnClick", function()
        if atGuildBank then B.SortManager.Start(currentTab) end
    end)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Aktuellen Tab sortieren")
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.depositBtn:SetScript("OnClick", function() B.TransferManager.ShowDeposit() end)
    frame.withdrawBtn:SetScript("OnClick", function() B.TransferManager.ShowWithdraw() end)

    frame.headers = {}
    frame.nHdr = 0
    function frame.AcquireHeader()
        frame.nHdr = frame.nHdr + 1
        local h = frame.headers[frame.nHdr]
        if not h then
            h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetTextColor(unpack(B.COLOR_ACCENT))
            frame.headers[frame.nHdr] = h
        end
        h:Show()
        return h
    end

    frame.tabBtns = {}
    for t = 1, 6 do
        local tb = CreateFrame("Button", "GrimfallBagsGBTab"..t, frame, "GrimfallBagsGBTabButtonTemplate")
        tb:SetWidth(32); tb:SetHeight(32)
        if t == 1 then tb:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + 18))
        else tb:SetPoint("LEFT", frame.tabBtns[t-1], "RIGHT", 4, 0) end
        tb.icon = _G["GrimfallBagsGBTab"..t.."Icon"]
        tb.sel  = _G["GrimfallBagsGBTab"..t.."Sel"]
        if tb.sel then tb.sel:SetBlendMode("ADD"); tb.sel:Hide() end
        tb.tab = t
        tb:SetScript("OnClick", function(self)
            currentTab = self.tab
            if atGuildBank then
                B.GuildBankAPI.SetCurrentTab(self.tab)
                B.GuildBankAPI.QueryTab(self.tab)
            end
            B.GuildBankView.Refresh()
        end)
        tb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tabName or ((GUILD_BANK or "Tab").." "..self.tab))
            GameTooltip:Show()
        end)
        tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tb:Hide()
        frame.tabBtns[t] = tb
    end

    local gridTop = SEARCH_ROW_Y - B.SearchChromeExtra()
    for i = 1, B.GuildBankAPI.NUM_SLOTS do
        local btn = CreateFrame("Button", "GrimfallBagsGBItem"..i, frame, "GrimfallBagsGBItemButtonTemplate")
        btn:SetWidth(BTN); btn:SetHeight(BTN)
        local col = (i - 1) % GB_COLS
        local row = math.floor((i - 1) / GB_COLS)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                     PAD + col * (BTN + BTN_PAD), gridTop - row * (BTN + BTN_PAD))
        btn.slot = i
        btn.qborder = _G["GrimfallBagsGBItem"..i.."QBorder"]
        if btn.qborder then btn.qborder:SetBlendMode("ADD"); btn.qborder:Hide() end
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnClick", function(self, mouse)
            if not atGuildBank then return end
            if mouse == "RightButton" then
                B.GuildBankAPI.AutoStoreItem(currentTab, self.slot)
            else
                B.GuildBankAPI.PickupItem(currentTab, self.slot)
            end
        end)
        btn:SetScript("OnDragStart", function(self)
            if atGuildBank then B.GuildBankAPI.PickupItem(currentTab, self.slot) end
        end)
        btn:SetScript("OnReceiveDrag", function(self)
            if atGuildBank then B.GuildBankAPI.PickupItem(currentTab, self.slot) end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = Guard("GBItemTooltip", function()
                if atGuildBank then
                    GameTooltip:SetGuildBankItem(currentTab, self.slot)
                elseif self.link then
                    GameTooltip:SetHyperlink(self.link)
                end
            end)
            if not ok or GameTooltip:NumLines() == 0 then
                GameTooltip:Hide()
                return
            end
            B.AnchorItemTooltip(self)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = btn
    end

    local searchFilter = B.BuildSearchFilter(frame, frame, function()
        B.GuildBankView.Refresh()
    end, "GrimfallBagsGuildBank", SEARCH_ROW_Y)
    frame.searchFilter = searchFilter

    local searchBtn = B.TitleIconButton(frame, B.ASSETS.."Search",
        "Show/hide search & filters", function()
            B.ToggleSearchFilters()
        end)
    searchBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)

    local depositBtn = B.TitleIconButton(frame, B.ASSETS.."Transfer",
        "Deposit matching items into this tab", function()
            B.DepositGuildMatching(frame.searchStr)
        end)
    depositBtn:SetPoint("RIGHT", searchBtn, "LEFT", -3, 0)
    depositBtn:Hide()
    frame.depositItemsBtn = depositBtn
end

function B.GuildBankView.Refresh()
    if not (frame and frame:IsShown()) then return end
    Guard("GuildBankView.Refresh", function()
        GB_COLS = math.max(1, math.floor((frame:GetWidth() - PAD * 2 + BTN_PAD) / (BTN + BTN_PAD)))

        local guild = S.Guild()

        local numTabs = atGuildBank and B.GuildBankAPI.GetNumTabs() or 0
        if not atGuildBank and guild then
            for t in pairs(guild.tabs or {}) do
                if t > numTabs then numTabs = t end
            end
        end
        for t, tb in ipairs(frame.tabBtns) do
            if t <= numTabs then
                local name, icon
                if atGuildBank then
                    name, icon = B.GuildBankAPI.GetTabInfo(t)
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

        local gname = GetGuildInfo("player") or (GUILD or "Guild")
        frame.title:SetText(atGuildBank and (gname.." - "..(GUILD_BANK or "Guild Bank"))
            or (gname.." - "..(GUILD_BANK or "Guild Bank").."  (Cache)"))

        local cachedTab = guild and guild.tabs and guild.tabs[currentTab]
        local entries = {}
        for i = 1, B.GuildBankAPI.NUM_SLOTS do
            local link, tex, cnt
            if atGuildBank then
                link = B.GuildBankAPI.GetItemLink(currentTab, i)
                tex, cnt = B.GuildBankAPI.GetSlotInfo(currentTab, i)
            elseif cachedTab and cachedTab[i] then
                link = cachedTab[i].l
                tex  = cachedTab[i].t
                cnt  = cachedTab[i].c
            end
            entries[i] = {l=link, t=tex, c=cnt}
        end

        local query = (frame.searchStr or ""):lower()
        local function Fill(btn, e)
            btn.link = e.l
            SetItemButtonTexture(btn, e.t)
            SetItemButtonCount(btn, e.c)
            local quality = e.l and select(3, GetItemInfo(e.l))
            local qborder = btn.qborder
            if quality and quality > 1 then
                local r, g, bcol = GetItemQualityColor(quality)
                qborder:SetVertexColor(r, g, bcol, 0.8)
                qborder:Show()
            else
                qborder:Hide()
            end
            if e.l and query ~= "" then
                btn:SetAlpha(S.Search.Matches({l=e.l, c=e.c}, query) and 1 or 0.25)
            else
                btn:SetAlpha(1)
            end
        end

        for i = 1, frame.nHdr do frame.headers[i]:Hide() end
        frame.nHdr = 0

        frame.sortBtn.icon:SetDesaturated(not atGuildBank)

        local gridTop = SEARCH_ROW_Y - B.SearchChromeExtra()
        if not B.Config().gbCategoryView then
            for i, btn in ipairs(buttons) do
                local col = (i - 1) % GB_COLS
                local row = math.floor((i - 1) / GB_COLS)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                             PAD + col * (BTN + BTN_PAD),
                             gridTop - row * (BTN + BTN_PAD))
                Fill(btn, entries[i])
            end
            frame:SetHeight(120 + B.SearchChromeExtra() + math.ceil(B.GuildBankAPI.NUM_SLOTS / GB_COLS) * (BTN + BTN_PAD))
        else
            local groups, order = {}, {}
            for i = 1, B.GuildBankAPI.NUM_SLOTS do
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
                if ea ~= eb then return eb end
                return a < b
            end)
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

            local HEADER_H   = 16
            local BLOCK_GAP  = 14
            local availWidth = frame:GetWidth() - PAD * 2
            local maxBlockCols = math.max(1, math.floor((availWidth + BTN_PAD) / (BTN + BTN_PAD)))
            local y = gridTop
            local rowX, rowH = 0, 0
            for _, cat in ipairs(order) do
                local slotList = groups[cat]
                local n = #slotList
                local blockCols = math.min(n, maxBlockCols)
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

        local money = atGuildBank and B.GuildBankAPI.GetMoney() or (guild and guild.money)
        frame.moneyText:SetText(B.MoneyString(money))
        if atGuildBank then
            frame.depositBtn:Show()
            frame.withdrawBtn:Show()
        else
            frame.depositBtn:Hide()
            frame.withdrawBtn:Hide()
        end
        if frame.depositItemsBtn then
            if atGuildBank then frame.depositItemsBtn:Show() else frame.depositItemsBtn:Hide() end
        end

        local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and owner.slot then
            local onEnter = owner:GetScript("OnEnter")
            if onEnter then onEnter(owner) end
        end
    end)
end

function B.GuildBankView.Toggle()
    Initialize()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        B.GuildBankView.Refresh()
    end
end

function B.OpenGuildBank()
    Initialize()
    if not frame then return end
    if not frame:IsShown() then
        frame:Show()
        B.GuildBankView.Refresh()
    end
end

local resizeTicker = CreateFrame("Frame")
resizeTicker:SetScript("OnUpdate", function(self, elapsed)
    if not gbResizeDirty then return end
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.1 then return end
    self.t = 0
    gbResizeDirty = false
    B.GuildBankView.Refresh()
end)

local queryQueue = {}
local queryTimer = CreateFrame("Frame")
queryTimer:Hide()
queryTimer:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.5 then return end
    self.t = 0
    local tab = table.remove(queryQueue, 1)
    if tab and atGuildBank then
        B.GuildBankAPI.QueryTab(tab)
        Log("QueryGuildBankTab("..tab..")")
    end
    if #queryQueue == 0 then self:Hide() end
end)

local function QueueTabQueries()
    wipe(queryQueue)
    for tab = 1, B.GuildBankAPI.GetNumTabs() do
        queryQueue[#queryQueue+1] = tab
    end
    queryTimer.t = 0.5
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
        Initialize()
        if not frame then return end
        B.RestorePosition(frame, "GrimfallBagsGuildBank",
            {"TOPLEFT", UIParent, "TOPLEFT", 40, -80})
        frame:Show()
        currentTab = B.GuildBankAPI.GetCurrentTab()
        QueueTabQueries()
        B.GuildBankView.Refresh()
        Log("Guild bank opened (live)")

    elseif event == "GUILDBANKFRAME_CLOSED" then
        atGuildBank = false
        B.SortManager.Stop()
        queryTimer:Hide()
        if frame then frame:Hide() end

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_MONEY" then
        B.GuildBankView.Refresh()

    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_GuildBankUI" then
        if B.Config().replaceGuildBank and GuildBankFrame then
            local repositioning = false
            local function PushOffscreen(f)
                if repositioning then return end
                repositioning = true
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
                repositioning = false
            end
            GuildBankFrame:HookScript("OnShow", PushOffscreen)
            hooksecurefunc(GuildBankFrame, "SetPoint", function(f)
                if not repositioning then PushOffscreen(f) end
            end)
            Log("Blizzard guild bank moved off-screen")
        end
    end
end)

S.OnDataChanged = function(what)
    if what == "guild" then B.GuildBankView.Refresh() end
    if B.InvalidateCrossCharCounts then B.InvalidateCrossCharCounts() end
end
