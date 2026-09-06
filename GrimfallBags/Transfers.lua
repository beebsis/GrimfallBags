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
        print("|cff33aaff[GrimfallBags]|r Auto-repaired for "..B.MoneyString(cost).." (guild funds).")
    elseif GetMoney() >= cost then
        RepairAllItems(false)
        print("|cff33aaff[GrimfallBags]|r Auto-repaired for "..B.MoneyString(cost)..".")
    else
        print("|cff33aaff[GrimfallBags]|r Auto-repair skipped - need "..B.MoneyString(cost)..".")
    end
end

local function MatchingItems(bags, query, junkOnly)
    local list = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count, locked, quality = GetContainerItemInfo(bag, slot)
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
                table.remove(list, 1)
                return
            end
        end
        self:Hide()
        local profit = GetMoney() - (job.startMoney or GetMoney())
        if profit > 0 then
            print("|cff33aaff[GrimfallBags]|r Sold from '"..(job.catName or "?").."': +"..B.MoneyString(profit))
        end
        Log("Category sell finished")
        return
    end

    local items = MatchingItems(job.srcBags, job.query, job.junkOnly)
    if job.mode == "vendor" and B.IsItemSellProtected then
        for i = #items, 1, -1 do
            if B.IsItemSellProtected(items[i].link) then table.remove(items, i) end
        end
    end
    if #items == 0 then
        self:Hide()
        if job.mode == "vendor" then
            local profit = GetMoney() - (job.startMoney or GetMoney())
            if profit > 0 then
                print("|cff33aaff[GrimfallBags]|r Sold: +"..B.MoneyString(profit))
            end
        end
        Log("Transfer finished")
        return
    end

    local it = items[1]
    if job.mode == "vendor" then
        UseContainerItem(it.bag, it.slot)
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
end)

local function StartJob(job)
    if runner:IsShown() then return end
    runner.job = job
    runner.t = 0
    runner:Show()
    Log("Transfer started ("..job.mode..")")
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
        if isBankView then
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

StaticPopupDialogs["GFBAGS_SELL_CATEGORY"] = {
    text = "Sell all %d items in \"%s\" to the vendor?",
    button1 = SELL or "Sell",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        B.SellCategoryConfirmed(data.items, data.catName)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function B.IsAtMerchant() return atMerchant end

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
    set(B.bankView, atBank, "Withdraw matching items into your bags")
end

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
        if B.Config().autoOpenMerchant then B.OpenBags() end
        if B.Config().autoRepair then B.Guard("AutoRepair", DoAutoRepair) end
    elseif event == "MERCHANT_CLOSED" then
        atMerchant = false
        runner:Hide()
    elseif event == "BANKFRAME_OPENED" then
        atBank = true
    elseif event == "BANKFRAME_CLOSED" then
        atBank = false
        runner:Hide()
    elseif event == "MAIL_SHOW" then
        if B.Config().autoOpenMailbox then B.OpenBags() end
    elseif event == "MAIL_CLOSED" then
    end
    B.UpdateTransferButtons()
end)
