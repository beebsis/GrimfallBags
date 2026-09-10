-- GrimfallBags
-- Sorting/SortManager.lua
--
-- Step-based sorter for the live guild bank. Each OnUpdate tick performs at most
-- one pair of PickupGuildBankItem moves so sorting never blocks the client or
-- exceeds Blizzard's per-frame motion limits. The view owns guild-bank state and
-- drives this module via Start(tab) / Stop(); this module holds no view state.

local B = GrimfallBags
local S = Syndicator335
local Log = B.Log

B.SortManager = {}

local driver = CreateFrame("Frame")
driver:Hide()

local function SortStep()
    local tab = driver.tab
    if not tab then return false end

    -- Snapshot the tab: link, id, count, and max stack size per slot.
    local slots = {}
    for i = 1, B.GuildBankAPI.NUM_SLOTS do
        local _, cnt, locked = B.GuildBankAPI.GetSlotInfo(tab, i)
        if locked then return true end
        local link = B.GuildBankAPI.GetItemLink(tab, i)
        slots[#slots + 1] = {
            slot  = i,
            link  = link,
            id    = S.ItemID(link),
            count = cnt or 0,
            max   = link and (select(8, GetItemInfo(link)) or 1) or 1,
        }
    end

    -- Pass 1: merge partial stacks of the same item.
    local partial = {}
    for _, s in ipairs(slots) do
        if s.id and s.count < s.max then
            local o = partial[s.id]
            if o then
                B.GuildBankAPI.PickupItem(tab, o.slot)
                B.GuildBankAPI.PickupItem(tab, s.slot)
                return true
            end
            partial[s.id] = s
        end
    end

    -- Pass 2: order by sort key, then by count, and swap out-of-place items.
    local items = {}
    for _, s in ipairs(slots) do
        if s.link then items[#items + 1] = s end
    end
    table.sort(items, function(a, b)
        local ka, kb = B.SortKey(a.link), B.SortKey(b.link)
        if ka ~= kb then return ka < kb end
        if a.count ~= b.count then return a.count > b.count end
        return false
    end)
    for pos, want in ipairs(items) do
        if want.slot ~= pos then
            B.GuildBankAPI.PickupItem(tab, want.slot)
            B.GuildBankAPI.PickupItem(tab, pos)
            return true
        end
    end
    return false
end

driver:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.25 then return end
    self.t = 0
    if CursorHasItem() then return end
    self.steps = (self.steps or 0) + 1
    if self.steps > 300 then
        Log("GB sort aborted (too many steps)")
        B.SortManager.Stop()
        return
    end
    local ok, more = pcall(SortStep)
    if not ok or not more then
        if not ok then Log("ERROR during GB sort: " .. tostring(more)) end
        B.SortManager.Stop()
        Log("GB sort finished (" .. (self.steps or 0) .. " steps)")
    end
end)

function B.SortManager.Start(tab)
    if driver:IsShown() or not tab then return end
    driver.tab = tab
    driver.t, driver.steps = 0, 0
    driver:Show()
    Log("GB sort started (tab " .. tab .. ")")
end

function B.SortManager.Stop()
    driver.tab = nil
    driver:Hide()
end

function B.SortManager.IsRunning()
    return driver:IsShown()
end
