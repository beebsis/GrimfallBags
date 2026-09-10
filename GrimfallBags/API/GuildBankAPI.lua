local B = GrimfallBags

B.GuildBankAPI = {}

local API = B.GuildBankAPI

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

function API.GetTabInfo(tab)
    return GetGuildBankTabInfo(tab)
end

function API.GetItemLink(tab, slot)
    return GetGuildBankItemLink(tab, slot)
end

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
