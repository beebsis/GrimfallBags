-- GrimfallBags
-- API/GuildBankAPI.lua
--
-- The single source of truth for every Blizzard guild-bank API call. Views,
-- sorting, and transfers talk to the guild bank through B.GuildBankAPI only;
-- they never call GetGuildBank* / GuildBank* / SetCurrentGuildBankTab /
-- QueryGuildBankTab / PickupGuildBankItem / AutoStoreGuildBankItem directly.

local B = GrimfallBags

B.GuildBankAPI = {}

local API = B.GuildBankAPI

-- Fixed slot count per guild-bank tab (WoW 3.3.5).
API.NUM_SLOTS = 98

function API.GetNumTabs()
    return GetNumGuildBankTabs() or 0
end

function API.GetCurrentTab()
    return GetCurrentGuildBankTab() or 1
end

function API.SetCurrentTab(tab)
    SetCurrentGuildBankTab(tab)
end

function API.QueryTab(tab)
    QueryGuildBankTab(tab)
end

-- Returns: name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals
function API.GetTabInfo(tab)
    return GetGuildBankTabInfo(tab)
end

function API.GetItemLink(tab, slot)
    return GetGuildBankItemLink(tab, slot)
end

-- Wraps GetGuildBankItemInfo: returns texture, count, locked.
function API.GetSlotInfo(tab, slot)
    return GetGuildBankItemInfo(tab, slot)
end

function API.GetMoney()
    return GetGuildBankMoney()
end

function API.DepositMoney(amount)
    GuildBankDepositMoney(amount)
end

function API.WithdrawMoney(amount)
    WithdrawGuildBankMoney(amount)
end

function API.AutoStoreItem(tab, slot)
    AutoStoreGuildBankItem(tab, slot)
end

function API.PickupItem(tab, slot)
    PickupGuildBankItem(tab, slot)
end
