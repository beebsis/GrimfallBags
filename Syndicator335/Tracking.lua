local S = Syndicator335
local Log, Guard = S.Log, S.Guard

local PLAYER_BAGS = {0, 1, 2, 3, 4}
local BANK_BAGS   = {-1, 5, 6, 7, 8, 9, 10, 11}

local bankIsOpen  = false
local mailIsOpen  = false

local function ScanContainers(bags)
    local t = {}
    for _, bag in ipairs(bags) do
        local n = GetContainerNumSlots(bag) or 0
        local b = {size = n}
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local tex, cnt, _, q = GetContainerItemInfo(bag, slot)
                b[slot] = {l=link, c=cnt or 1, t=tex, q=q}
            end
        end
        t[bag] = b
    end
    return t
end

local function ScanEquipped()
    local t = {}
    for inv = 1, 19 do
        local link = GetInventoryItemLink("player", inv)
        if link then
            t[inv] = {
                l = link, c = 1,
                t = GetInventoryItemTexture("player", inv),
                q = GetInventoryItemQuality("player", inv),
            }
        end
    end
    return t
end

local function ScanMail()
    local t = {}
    local n = GetInboxNumItems() or 0
    for i = 1, n do
        for att = 1, ATTACHMENTS_MAX_RECEIVE or 12 do
            local name, tex, cnt = GetInboxItem(i, att)
            if name then
                local link = GetInboxItemLink(i, att)
                if link then
                    t[#t+1] = {l=link, c=cnt or 1, t=tex}
                end
            end
        end
    end
    return t
end

local function ScanAuctions()
    local t = {}
    local n = GetNumAuctionItems("owner") or 0
    for i = 1, n do
        local name, tex, cnt = GetAuctionItemInfo("owner", i)
        local link = GetAuctionItemLink("owner", i)
        if link then
            t[#t+1] = {l=link, c=cnt or 1, t=tex}
        end
    end
    return t
end

local function CountInto(counts, source, entry)
    local id = S.ItemID(entry.l)
    if not id then return end
    local c = counts[id]
    if not c then c = {}; counts[id] = c end
    c[source] = (c[source] or 0) + (entry.c or 1)
end

local function RebuildCounts(char)
    local counts = {}
    for _, bagSet in ipairs({{char.bags, "bags"}, {char.bank, "bank"}}) do
        local set, label = bagSet[1], bagSet[2]
        for _, b in pairs(set or {}) do
            for slot, e in pairs(b) do
                if type(slot) == "number" and type(e) == "table" then
                    CountInto(counts, label, e)
                end
            end
        end
    end
    for _, e in pairs(char.equipped or {}) do CountInto(counts, "equipped", e) end
    for _, e in ipairs(char.mail or {})     do CountInto(counts, "mail", e) end
    for _, e in ipairs(char.auctions or {}) do CountInto(counts, "auctions", e) end
    char.counts = counts
end

local function RebuildGuildCounts(guild)
    local counts = {}
    for _, tab in pairs(guild.tabs or {}) do
        for slot, e in pairs(tab) do
            if type(slot) == "number" and type(e) == "table" then
                local id = S.ItemID(e.l)
                if id then counts[id] = (counts[id] or 0) + (e.c or 1) end
            end
        end
    end
    guild.counts = counts
end

local function UpdateBags()
    local c = S.Char()
    c.bags     = ScanContainers(PLAYER_BAGS)
    c.money    = GetMoney()
    c.class    = select(2, UnitClass("player"))
    c.faction  = UnitFactionGroup("player")
    c.lastSeen = time()
    if bankIsOpen then
        c.bank = ScanContainers(BANK_BAGS)
    end
    RebuildCounts(c)
end

local function UpdateEquipped()
    local c = S.Char()
    c.equipped = ScanEquipped()
    RebuildCounts(c)
end

local function UpdateMail()
    local c = S.Char()
    c.mail = ScanMail()
    RebuildCounts(c)
end

local function UpdateAuctions()
    local c = S.Char()
    c.auctions = ScanAuctions()
    RebuildCounts(c)
end

local function UpdateGuildBankTab(tab)
    local g = S.Guild()
    if not g then return end
    local name = GetGuildBankTabInfo(tab)
    local t = {name = name}
    for slot = 1, 98 do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local tex, cnt = GetGuildBankItemInfo(tab, slot)
            t[slot] = {l=link, c=cnt or 1, t=tex}
        end
    end
    g.tabs[tab] = t
    g.money = GetGuildBankMoney()
    RebuildGuildCounts(g)
end

local dirty = {}
local evt = CreateFrame("Frame")

evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("BAG_UPDATE")
evt:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
evt:RegisterEvent("BANKFRAME_OPENED")
evt:RegisterEvent("BANKFRAME_CLOSED")
evt:RegisterEvent("UNIT_INVENTORY_CHANGED")
evt:RegisterEvent("PLAYER_MONEY")
evt:RegisterEvent("MAIL_SHOW")
evt:RegisterEvent("MAIL_INBOX_UPDATE")
evt:RegisterEvent("MAIL_CLOSED")
evt:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
evt:RegisterEvent("GUILDBANKFRAME_OPENED")
evt:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
evt:RegisterEvent("GUILDBANK_UPDATE_MONEY")

local loggedIn = false

evt:SetScript("OnUpdate", function()
    if not loggedIn then return end
    if dirty.bags then
        dirty.bags = nil
        Guard("UpdateBags", UpdateBags)
        if S.OnDataChanged then S.OnDataChanged("bags") end
    end
    if dirty.equipped then
        dirty.equipped = nil
        Guard("UpdateEquipped", UpdateEquipped)
    end
    if dirty.mail then
        dirty.mail = nil
        Guard("UpdateMail", UpdateMail)
    end
    if dirty.auctions then
        dirty.auctions = nil
        Guard("UpdateAuctions", UpdateAuctions)
    end
    if dirty.guildTab then
        local tab = dirty.guildTab
        dirty.guildTab = nil
        Guard("UpdateGuildBank", UpdateGuildBankTab, tab)
        if S.OnDataChanged then S.OnDataChanged("guild") end
    end
end)

evt:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        dirty.bags, dirty.equipped = true, true
        Log("PLAYER_LOGIN: Tracking active")

    elseif event == "BAG_UPDATE" or event == "PLAYER_MONEY"
        or event == "PLAYERBANKSLOTS_CHANGED" then
        dirty.bags = true

    elseif event == "BANKFRAME_OPENED" then
        bankIsOpen = true
        dirty.bags = true
        Log("Bank opened -> scan")

    elseif event == "BANKFRAME_CLOSED" then
        bankIsOpen = false

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then dirty.equipped = true end

    elseif event == "MAIL_SHOW" then
        mailIsOpen = true
        dirty.mail = true
        Log("Mailbox opened -> scan")

    elseif event == "MAIL_INBOX_UPDATE" then
        if mailIsOpen then dirty.mail = true end

    elseif event == "MAIL_CLOSED" then
        mailIsOpen = false

    elseif event == "AUCTION_OWNED_LIST_UPDATE" then
        dirty.auctions = true

    elseif event == "GUILDBANKFRAME_OPENED" then
        Log("Guild bank opened")

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        dirty.guildTab = GetCurrentGuildBankTab() or 1

    elseif event == "GUILDBANK_UPDATE_MONEY" then
        local g = S.Guild()
        if g then g.money = GetGuildBankMoney() end
    end
end)
