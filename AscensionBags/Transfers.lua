---------------------------------------------------------------------------
-- AscensionBags - Transfers
-- Context-aware transfer button (in the window title bar):
--   at a merchant:  sells every item matching the current search
--                   (empty search = grey junk only), with a profit report
--   at the bank:    deposits every matching bag item into the bank
--                   (bank window: withdraws matching items from the bank)
-- Asynchronous, one move per tick, waits for locks.
--
-- Right-clicking a category header sells everything in that category
-- (with a confirmation popup); shift-right-click skips the popup and
-- sells instantly. See SellCategory()/SellCategoryConfirmed() below.
---------------------------------------------------------------------------
local B = AscensionBags
local S = Syndicator335
local Log = B.Log

local atMerchant = false
local atBank     = false

---------------------------------------------------------------------------
-- Auto-repair: prefers guild bank funds when the player is authorized
-- (CanGuildBankRepair may not exist on this core - guarded), falls back
-- to personal gold, skips silently if nothing is damaged.
---------------------------------------------------------------------------
local function DoAutoRepair()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost = GetRepairAllCost and GetRepairAllCost() or 0
    if not cost or cost <= 0 then return end

    if type(CanGuildBankRepair) == "function" and CanGuildBankRepair() then
        RepairAllItems(true)
        print("|cff33aaff[AscensionBags]|r Auto-repaired for "..B.MoneyString(cost).." (guild funds).")
    elseif GetMoney() >= cost then
        RepairAllItems(false)
        print("|cff33aaff[AscensionBags]|r Auto-repaired for "..B.MoneyString(cost)..".")
    else
        print("|cff33aaff[AscensionBags]|r Auto-repair skipped - need "..B.MoneyString(cost)..".")
    end
end

---------------------------------------------------------------------------
-- Collect matching items from a set of bags
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Asynchronous transfer runner
---------------------------------------------------------------------------
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
        -- Explicit list of {bag,slot,link} entries (category sell)
        local list = job.items
        while #list > 0 do
            local it = list[1]
            local curLink = GetContainerItemLink(it.bag, it.slot)
            if curLink ~= it.link then
                table.remove(list, 1)   -- item moved/gone, skip it safely
            else
                local _, _, locked = GetContainerItemInfo(it.bag, it.slot)
                if locked then return end   -- wait for this tick
                UseContainerItem(it.bag, it.slot)
                table.remove(list, 1)
                return
            end
        end
        self:Hide()
        local profit = GetMoney() - (job.startMoney or GetMoney())
        if profit > 0 then
            print("|cff33aaff[AscensionBags]|r Sold from '"..(job.catName or "?").."': +"..B.MoneyString(profit))
        end
        Log("Category sell finished")
        return
    end

    local items = MatchingItems(job.srcBags, job.query, job.junkOnly)
    if job.mode == "vendor" and B.IsItemSellProtected then
        -- Protection only blocks SELLING - moving to/from the bank is fine.
        for i = #items, 1, -1 do
            if B.IsItemSellProtected(items[i].link) then table.remove(items, i) end
        end
    end
    if #items == 0 then
        self:Hide()
        if job.mode == "vendor" then
            local profit = GetMoney() - (job.startMoney or GetMoney())
            if profit > 0 then
                print("|cff33aaff[AscensionBags]|r Sold: +"..B.MoneyString(profit))
            end
        end
        Log("Transfer finished")
        return
    end

    local it = items[1]
    if job.mode == "vendor" then
        UseContainerItem(it.bag, it.slot)   -- at a merchant = sell
    else
        local tBag, tSlot = FirstEmptySlot(job.dstBags)
        if not tBag then
            print("|cff33aaff[AscensionBags]|r No room at the destination.")
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

---------------------------------------------------------------------------
-- Public: called from the transfer button in the title bar
---------------------------------------------------------------------------
function B.DoTransfer(view)
    local query = (view.searchStr or ""):lower()
    local isBankView = (view == B.bankView)

    if atMerchant and not isBankView then
        -- Sell: empty search -> junk only; otherwise everything matching
        StartJob({
            mode = "vendor", srcBags = B.PLAYER_BAGS,
            query = query, junkOnly = (query == ""),
            startMoney = GetMoney(),
        })
    elseif atBank then
        if isBankView then
            -- from the bank into the bags
            StartJob({mode="move", srcBags=B.BANK_BAGS, dstBags=B.PLAYER_BAGS, query=query})
        else
            -- from the bags into the bank
            StartJob({mode="move", srcBags=B.PLAYER_BAGS, dstBags=B.BANK_BAGS, query=query})
        end
    end
end

---------------------------------------------------------------------------
-- Sell everything in one category, shown via right-click on a category
-- header in the bag view. Confirmed = skip the popup (shift-right-click).
---------------------------------------------------------------------------
function B.SellCategory(items, catName)
    if not atMerchant or not items or #items == 0 then return end
    if B.IsCategoryProtected and B.IsCategoryProtected(catName) then return end
    StaticPopup_Show("ASCBAGS_SELL_CATEGORY", #items, catName,
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

StaticPopupDialogs["ASCBAGS_SELL_CATEGORY"] = {
    text = "Sell all %d items in \"%s\" to the vendor?",
    button1 = SELL or "Sell",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        B.SellCategoryConfirmed(data.items, data.catName)
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

---------------------------------------------------------------------------
-- Visibility of the transfer buttons per context
---------------------------------------------------------------------------
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
        -- no state to clear; present for symmetry/future use
    end
    B.UpdateTransferButtons()
end)
