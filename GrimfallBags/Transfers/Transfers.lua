local B = GrimfallBags
local S = Syndicator335
local Log = B.Log

local atMerchant = false
local atBank     = false

local function DoAutoRepair()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost = GetRepairAllCost and GetRepairAllCost() or 0
    if not cost or cost <= 0 then return end

    if type(CanGuildBankRepair) == "function" and CanGuildBankRepair() then
        RepairAllItems(true)
        print("|cff33aaff[GrimfallBags]|r Repaired all items: -"..B.MoneyString(cost).." (guild funds).")
    elseif GetMoney() >= cost then
        RepairAllItems(false)
        print("|cff33aaff[GrimfallBags]|r Repaired all items: -"..B.MoneyString(cost)..".")
    else
        print("|cff33aaff[GrimfallBags]|r Repair skipped (need "..B.MoneyString(cost)..").")
    end
end

local function MatchingItems(bags, query, junkOnly)
    local list = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count, locked = GetContainerItemInfo(bag, slot)
                local quality = select(3, GetItemInfo(link or ""))
                if not locked then
                    local matches
                    if junkOnly then
                        matches = (quality == 0)
                    else
                        matches = S.Search.Matches({l=link, c=count, q=quality}, query)
                    end
                    if matches then
                        list[#list+1] = {bag=bag, slot=slot, link=link, count=count or 1}
                    end
                end
            end
        end
    end
    return list
end

local function FirstEmptySlot(bags)
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            if not GetContainerItemLink(bag, slot) then
                return bag, slot
            end
        end
    end
end

local function FirstEmptyGuildSlot(tab)
    for slot = 1, B.GuildBankAPI.NUM_SLOTS do
        if not B.GuildBankAPI.GetItemLink(tab, slot) then
            local _, _, locked = B.GuildBankAPI.GetSlotInfo(tab, slot)
            if not locked then return slot end
        end
    end
    return nil
end

local runner = CreateFrame("Frame")
runner:Hide()

runner:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.2 then return end
    self.t = 0
    if CursorHasItem() then return end

    local job = self.job
    if not job then self:Hide() return end

    if job.mode == "vendorList" then
        local list = job.items
        while #list > 0 do
            local it = list[1]
            local curLink = GetContainerItemLink(it.bag, it.slot)
            if curLink ~= it.link then
                table.remove(list, 1)
            else
                local _, _, locked = GetContainerItemInfo(it.bag, it.slot)
                if locked then return end
                UseContainerItem(it.bag, it.slot)
                job.moved = (job.moved or 0) + 1
                table.remove(list, 1)
                return
            end
        end
        self:Hide()
        local profit = GetMoney() - (job.startMoney or GetMoney())
        if profit > 0 then
            local sold = job.moved or 0
            if job.catName then
                print("|cff33aaff[GrimfallBags]|r Sold "..sold.." item"..(sold == 1 and "" or "s")
                    .." from '"..job.catName.."': +"..B.MoneyString(profit))
            else
                print("|cff33aaff[GrimfallBags]|r Sold "..sold.." item"..(sold == 1 and "" or "s")
                    ..": +"..B.MoneyString(profit))
            end
        end
        if B.DiagLog then B.DiagLog("Category sell finished") else Log("Category sell finished") end
        if B.RefreshAll then B.RefreshAll() end
        return
    end

    if job.mode == "moveList" then
        local list = job.items
        while #list > 0 do
            local it = list[1]
            local curLink = GetContainerItemLink(it.bag, it.slot)
            if curLink ~= it.link then
                table.remove(list, 1)
            elseif job.tab then
                local gbSlot = FirstEmptyGuildSlot(job.tab)
                if not gbSlot then
                    print("|cff33aaff[GrimfallBags]|r No room in the guild bank tab.")
                    self:Hide()
                    return
                end
                PickupContainerItem(it.bag, it.slot)
                B.GuildBankAPI.PickupItem(job.tab, gbSlot)
                table.remove(list, 1)
                job.moved = (job.moved or 0) + 1
                return
            else
                local tBag, tSlot = FirstEmptySlot(job.dstBags)
                if not tBag then
                    print("|cff33aaff[GrimfallBags]|r No room at the destination.")
                    self:Hide()
                    return
                end
                if it.bag == -1 then
                    PickupInventoryItem(BankButtonIDToInvSlotID(it.slot, false))
                else
                    PickupContainerItem(it.bag, it.slot)
                end
                PickupContainerItem(tBag, tSlot)
                table.remove(list, 1)
                job.moved = (job.moved or 0) + 1
                return
            end
        end
        self:Hide()
        local moved = job.moved or 0
        local msg = "Moved "..moved.." item"..(moved == 1 and "" or "s")
        if job.protectedCount and job.protectedCount > 0 then
            msg = msg.." ("..job.protectedCount.." protected item"
                ..(job.protectedCount == 1 and "" or "s").." skipped)"
        end
        print("|cff33aaff[GrimfallBags]|r "..msg..".")
        if B.DiagLog then B.DiagLog("Category deposit finished") else Log("Category deposit finished") end
        if B.RefreshAll then B.RefreshAll() end
        return
    end

    local items = MatchingItems(job.srcBags, job.query, job.junkOnly)
    if B.IsItemSellProtected then
        for i = #items, 1, -1 do
            if B.IsItemSellProtected(items[i].link) then table.remove(items, i) end
        end
    end
    if #items == 0 then
        self:Hide()
        local msg
        if job.mode == "vendor" then
            local profit = GetMoney() - (job.startMoney or GetMoney())
            local sold = job.moved or 0
            if profit > 0 then
                msg = "Sold "..sold.." item"..(sold == 1 and "" or "s")..": +"..B.MoneyString(profit)
            end
        else
            local moved = job.moved or 0
            msg = "Moved "..moved.." item"..(moved == 1 and "" or "s")
            if job.protectedCount and job.protectedCount > 0 then
                msg = msg.." ("..job.protectedCount.." protected item"
                    ..(job.protectedCount == 1 and "" or "s").." skipped)"
            end
        end
        if msg then print("|cff33aaff[GrimfallBags]|r "..msg..".") end
        if B.DiagLog then B.DiagLog("Transfer finished") else Log("Transfer finished") end
        if B.RefreshAll then B.RefreshAll() end
        return
    end

    local it = items[1]
    if job.mode == "vendor" then
        UseContainerItem(it.bag, it.slot)
    elseif job.mode == "guildDeposit" then
        local gbSlot = FirstEmptyGuildSlot(job.tab)
        if not gbSlot then
            print("|cff33aaff[GrimfallBags]|r No room in the guild bank tab.")
            self:Hide()
            return
        end
        PickupContainerItem(it.bag, it.slot)
        B.GuildBankAPI.PickupItem(job.tab, gbSlot)
    else
        local tBag, tSlot = FirstEmptySlot(job.dstBags)
        if not tBag then
            print("|cff33aaff[GrimfallBags]|r No room at the destination.")
            self:Hide()
            return
        end
        PickupContainerItem(it.bag, it.slot)
        PickupContainerItem(tBag, tSlot)
    end
    job.moved = (job.moved or 0) + 1
end)

local function StartJob(job)
    if runner:IsShown() then
        Log("Transfer skipped - a job is already running")
        return
    end
    runner.job = job
    runner.t = 0
    runner:Show()
    if B.DiagLog then B.DiagLog("Transfer started ("..job.mode..")") else Log("Transfer started ("..job.mode..")") end
end

function B.IsTransferRunning()
    return runner:IsShown()
end

local function ConfirmBulkMove(data)
    if runner:IsShown() then
        Log("Bulk move skipped - a transfer job is already running")
        return
    end
    local items = MatchingItems(data.srcBags, data.query, false)
    local protectedCount = 0
    for i = #items, 1, -1 do
        if B.IsItemSellProtected and B.IsItemSellProtected(items[i].link) then
            table.remove(items, i)
            protectedCount = protectedCount + 1
        end
    end
    local count = #items
    if count == 0 then
        local msg = "Nothing to move"
        if protectedCount > 0 then
            msg = msg.." ("..protectedCount.." protected item"
                ..(protectedCount == 1 and "" or "s").." skipped)"
        end
        print("|cff33aaff[GrimfallBags]|r "..msg..".")
        return
    end
    data.protectedCount = protectedCount
    StaticPopup_Show("GFBAGS_MOVE_CONFIRM", count, data.label, data)
end

local function StartBulkMove(data)
    if runner:IsShown() then return end
    runner.job = {
        mode = data.mode, srcBags = data.srcBags, dstBags = data.dstBags,
        query = data.query, junkOnly = false,
        protectedCount = data.protectedCount, tab = data.tab,
    }
    runner.t = 0
    runner:Show()
    if B.DiagLog then B.DiagLog("Bulk move started ("..(data.mode or "move")..")") else Log("Bulk move started ("..(data.mode or "move")..")") end
end

function B.DepositAll()
    ConfirmBulkMove({srcBags = B.PLAYER_BAGS, dstBags = B.BANK_BAGS,
                     query = "", mode = "move", label = "into the bank"})
end

function B.WithdrawAll()
    ConfirmBulkMove({srcBags = B.BANK_BAGS, dstBags = B.PLAYER_BAGS,
                     query = "", mode = "move", label = "from the bank"})
end

function B.DepositGuildMatching(query)
    query = (query or ""):lower()
    if query == "" then
        print("|cff33aaff[GrimfallBags]|r Type a search term first (guild-bank deposit moves matching items only).")
        return
    end
    if B.GuildBankView and B.GuildBankView.IsOpen and not B.GuildBankView.IsOpen() then
        return
    end
    ConfirmBulkMove({srcBags = B.PLAYER_BAGS, query = query, mode = "guildDeposit",
                     tab = B.GuildBankAPI.GetCurrentTab(), label = "into the guild bank"})
end

local function StartMoveList(data)
    if runner:IsShown() then return end
    local dstBags
    if data.dest == "bank" then
        dstBags = B.BANK_BAGS
    elseif data.dest == "bags" then
        dstBags = B.PLAYER_BAGS
    end
    runner.job = {
        mode = "moveList", items = data.items,
        dstBags = dstBags,
        tab = (data.dest == "guild") and B.GuildBankAPI.GetCurrentTab() or nil,
        protectedCount = data.protectedCount,
    }
    runner.t = 0
    runner:Show()
    local verb = (data.dest == "bags") and "withdraw" or "deposit"
    if B.DiagLog then B.DiagLog("Category "..verb.." started ("..(data.dest or "?")..")") else Log("Category "..verb.." started ("..(data.dest or "?")..")") end
end

function B.DepositCategory(items, catName, dest)
    if not items or #items == 0 then return end
    if runner:IsShown() then
        Log("Category deposit skipped - a job is already running")
        return
    end
    local list = {}
    local skipped = 0
    for _, it in ipairs(items) do
        if B.IsItemSellProtected and B.IsItemSellProtected(it.link) then
            skipped = skipped + 1
        else
            list[#list+1] = {bag = it.bag, slot = it.slot, link = it.link}
        end
    end
    if #list == 0 then
        local msg = "Nothing to move"
        if skipped > 0 then
            msg = msg.." ("..skipped.." protected item"..(skipped == 1 and "" or "s").." skipped)"
        end
        print("|cff33aaff[GrimfallBags]|r "..msg..".")
        return
    end
    StaticPopup_Show("GFBAGS_DEPOSIT_CATEGORY", #list, catName,
        {items = list, dest = dest, protectedCount = skipped})
end

function B.DoTransfer(view)
    local query = (view.searchStr or ""):lower()
    local isBankView = (view == B.bankView)

    if atMerchant and not isBankView then
        StartJob({
            mode = "vendor", srcBags = B.PLAYER_BAGS,
            query = query, junkOnly = (query == ""),
            startMoney = GetMoney(),
        })
    elseif atBank then
        if query == "" then
            if isBankView then B.WithdrawAll() else B.DepositAll() end
        elseif isBankView then
            StartJob({mode="move", srcBags=B.BANK_BAGS, dstBags=B.PLAYER_BAGS, query=query})
        else
            StartJob({mode="move", srcBags=B.PLAYER_BAGS, dstBags=B.BANK_BAGS, query=query})
        end
    end
end

function B.SellCategory(items, catName)
    if not atMerchant or not items or #items == 0 then return end
    if B.IsCategoryProtected and B.IsCategoryProtected(catName) then return end
    StaticPopup_Show("GFBAGS_SELL_CATEGORY", #items, catName,
        {items = items, catName = catName})
end

function B.SellCategoryConfirmed(items, catName)
    if not atMerchant or not items or #items == 0 then return end
    if B.IsCategoryProtected and B.IsCategoryProtected(catName) then return end
    if runner:IsShown() then return end
    local list = {}
    for _, it in ipairs(items) do
        list[#list+1] = {bag = it.bag, slot = it.slot, link = it.link}
    end
    runner.job = {mode = "vendorList", items = list, catName = catName,
                  startMoney = GetMoney()}
    runner.t = 0
    runner:Show()
    Log("Category sell started ('"..(catName or "?").."', "..#list.." items)")
end

function B.SellStacks(items)
    if not atMerchant or not items or #items == 0 then return end
    if runner:IsShown() then return end
    local list = {}
    for _, it in ipairs(items) do
        if it.bag and it.slot and it.l then
            list[#list+1] = {bag = it.bag, slot = it.slot, link = it.l}
        end
    end
    if #list == 0 then return end
    runner.job = {mode = "vendorList", items = list, startMoney = GetMoney()}
    runner.t = 0
    runner:Show()
    Log("Stack sell started ("..#list.." items)")
end

StaticPopupDialogs["GFBAGS_SELL_CATEGORY"] = {
    text = "Sell all %d items in \"%s\" to the vendor?",
    button1 = SELL or "Sell",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        B.SellCategoryConfirmed(data.items, data.catName)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GFBAGS_MOVE_CONFIRM"] = {
    text = "Move %d items %s?",
    button1 = YES or "Yes",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        StartBulkMove(data)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GFBAGS_DEPOSIT_CATEGORY"] = {
    text = "Move %d items in \"%s\"?",
    button1 = YES or "Yes",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        StartMoveList(data)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function B.IsAtMerchant() return atMerchant end
function B.IsAtBank() return atBank end

function B.UpdateTransferButtons()
    local function set(view, shown, tip)
        if view and view.transferBtn then
            if shown then
                view.transferBtn:Show()
                view.transferBtn.tooltipText = tip
            else
                view.transferBtn:Hide()
            end
            if view.RelayoutBagsBtn then view.RelayoutBagsBtn() end
            if view.RelayoutFiltersBtn then view.RelayoutFiltersBtn() end
        end
    end
    set(B.bagView, atMerchant or atBank,
        atMerchant and "Sell matching items (empty search = junk only)"
                    or "Deposit matching items into the bank")

    if B.bankView then
        for _, key in ipairs({"depositAllBtn", "withdrawAllBtn"}) do
            local b = B.bankView[key]
            if b then
                if atBank then b:Show() else b:Hide() end
            end
        end
    end
    set(B.bankView, atBank, "Withdraw matching items into your bags")
end

local merchantStartMoney = 0

local evt = CreateFrame("Frame")
evt:RegisterEvent("MERCHANT_SHOW")
evt:RegisterEvent("MERCHANT_CLOSED")
evt:RegisterEvent("BANKFRAME_OPENED")
evt:RegisterEvent("BANKFRAME_CLOSED")
evt:RegisterEvent("MAIL_SHOW")
evt:RegisterEvent("MAIL_CLOSED")
evt:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        atMerchant = true
        merchantStartMoney = GetMoney()
        B.OpenBags()
        if B.Config().autoRepair then B.Guard("AutoRepair", DoAutoRepair) end
        if B.Config().autoSellJunk then
            B.Guard("AutoSellJunk", function()
                StartJob({mode = "vendor", srcBags = B.PLAYER_BAGS,
                          query = "", junkOnly = true, startMoney = GetMoney()})
            end)
        end
    elseif event == "MERCHANT_CLOSED" then
        atMerchant = false
        runner:Hide()
        local net = GetMoney() - merchantStartMoney
        if net ~= 0 then
            print("|cff33aaff[GrimfallBags]|r Merchant: "
                ..(net > 0 and "+" or "-")..B.MoneyString(math.abs(net))..".")
        end
    elseif event == "BANKFRAME_OPENED" then
        atBank = true
    elseif event == "BANKFRAME_CLOSED" then
        atBank = false
        runner:Hide()
    elseif event == "MAIL_SHOW" then
        B.OpenBags()
    elseif event == "MAIL_CLOSED" then
    end
    B.UpdateTransferButtons()
end)
