---------------------------------------------------------------------------
-- AscensionBags - Sorting
-- Asynchronous sorter: first merges partial stacks, then physically
-- swaps items into the target order (method: type, quality, or item
-- level; configurable in options). One move per tick, waits for
-- server locks - loss-safe.
---------------------------------------------------------------------------
local B = AscensionBags
local S = Syndicator335
local Log = B.Log

local sorter = CreateFrame("Frame")
sorter:Hide()

---------------------------------------------------------------------------
-- Sort key per method
---------------------------------------------------------------------------
function B.SortKey(link)
    local name, _, quality, iLvl, _, itemType, subType = GetItemInfo(link or "")
    name, quality, iLvl = name or "", quality or 0, iLvl or 0
    itemType, subType = itemType or "", subType or ""
    local method = B.Config().sortMethod
    if method == "quality" then
        return string.format("%02d|%s|%s|%s", 9 - quality, itemType, subType, name)
    elseif method == "ilvl" then
        return string.format("%04d|%s", 9999 - iLvl, name)
    else -- "type"
        return string.format("%s|%s|%02d|%s", itemType, subType, 9 - quality, name)
    end
end

---------------------------------------------------------------------------
-- One sort step; true = continue, false = done
---------------------------------------------------------------------------
local function SortStep(bags)
    -- Take stock
    local slots = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local _, count, locked = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if locked then return true end   -- wait
            slots[#slots+1] = {
                bag = bag, slot = slot, link = link,
                id = S.ItemID(link), count = count or 0,
                max = link and (select(8, GetItemInfo(link)) or 1) or 1,
            }
        end
    end

    -- 1) Merge partial stacks of identical items
    local partial = {}
    for _, s in ipairs(slots) do
        if s.id and s.count < s.max then
            local o = partial[s.id]
            if o then
                PickupContainerItem(o.bag, o.slot)
                PickupContainerItem(s.bag, s.slot)
                return true
            end
            partial[s.id] = s
        end
    end

    -- 2) Determine target order: sort all items by key, then place
    --    them in order from the front (selection sort, one swap per tick)
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
        local target = slots[pos]   -- target slot for position pos
        if not target then break end
        if target.bag ~= want.bag or target.slot ~= want.slot then
            -- swap the desired item into the target slot
            PickupContainerItem(want.bag, want.slot)
            PickupContainerItem(target.bag, target.slot)
            return true
        end
    end
    return false
end

sorter:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.15 then return end
    self.t = 0
    if CursorHasItem() then return end
    self.steps = (self.steps or 0) + 1
    if self.steps > 400 then   -- emergency brake
        Log("Sort aborted (too many steps)")
        self:Hide()
        return
    end
    local ok, more = pcall(SortStep, self.bags)
    if not ok or not more then
        if not ok then Log("ERROR while sorting: "..tostring(more)) end
        self:Hide()
        Log("Sort finished ("..(self.steps or 0).." steps)")
    end
end)

function B.StartSort(bags)
    if sorter:IsShown() then return end
    sorter.bags  = bags
    sorter.t     = 0
    sorter.steps = 0
    sorter:Show()
    Log("Sort started (method: "..B.Config().sortMethod..")")
end
