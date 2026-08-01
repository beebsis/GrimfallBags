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
-- Ring buffer of recent actions, dumped to the log if the emergency
-- brake trips - lets us see the actual repeating pattern from a report
-- instead of having to guess at it.
---------------------------------------------------------------------------
local function Record(st, msg)
    st.recent[#st.recent + 1] = msg
    if #st.recent > 12 then table.remove(st.recent, 1) end
end

local function Describe(bag, slot, id, count)
    local name = id and GetItemInfo(id)
    return string.format("%d:%d[%s x%d]", bag, slot, name or tostring(id), count)
end

-- On abort, dump every slot whose item id appears more than once - if a
-- prior buggy run fragmented a stack (e.g. an item that refuses to
-- re-merge), this shows it directly instead of us guessing at it.
local function DumpDuplicates(bags)
    local byId = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = S.ItemID(link)
                local _, count = GetContainerItemInfo(bag, slot)
                byId[id] = byId[id] or {}
                table.insert(byId[id], Describe(bag, slot, id, count or 0))
            end
        end
    end
    for id, list in pairs(byId) do
        if #list > 1 then
            Log("Sort: duplicate stacks of "..tostring(id).." - "..table.concat(list, ", "))
        end
    end
end

---------------------------------------------------------------------------
-- One sort step; true = continue, false = done
---------------------------------------------------------------------------
local function SortStep(st, bags)
    -- Take stock
    local slots = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local _, count, locked = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if locked then return true end   -- wait
            -- GetItemInfo() returns nil until the client has actually
            -- cached that item's data, which can still be in flight the
            -- first time this item's been seen this session. Wait for
            -- it rather than computing a sort key from incomplete data -
            -- otherwise that key is wrong on this tick and right again
            -- once it's cached, and the item's rank silently changes
            -- between ticks, which shows up as two items endlessly
            -- trading places (each tick "corrects" the other's mistake).
            if link and not GetItemInfo(link) then return true end
            -- Sort key computed once here, not inside the comparator -
            -- a comparator that isn't consistent from call to call
            -- within a single table.sort corrupts the sort too.
            slots[#slots+1] = {
                bag = bag, slot = slot, link = link,
                id = S.ItemID(link), count = count or 0,
                max = link and (select(8, GetItemInfo(link)) or 1) or 1,
                key = link and B.SortKey(link) or nil,
            }
        end
    end

    -- If the merge attempted last tick didn't actually change anything,
    -- some items (e.g. Ascension's "Travel Permit") report count < max
    -- stack but the server silently refuses to merge them. Without this
    -- check the same pair gets re-picked forever, since nothing about
    -- the bag state ever changes - stop retrying that item for the rest
    -- of this sort so it can't loop.
    local lm = st.lastMerge
    st.lastMerge = nil
    if lm then
        local function stillAt(bag, slot, id, count)
            for _, s in ipairs(slots) do
                if s.bag == bag and s.slot == slot then
                    return s.id == id and s.count == count
                end
            end
            return false
        end
        if stillAt(lm.aBag, lm.aSlot, lm.id, lm.aCount)
           and stillAt(lm.bBag, lm.bSlot, lm.id, lm.bCount) then
            st.badMergeIds[lm.id] = true
            Log("Sort: item "..tostring(lm.id).." would not merge (server "..
                "rejected it), skipping further merge attempts for it")
        end
    end

    -- 1) Merge partial stacks of identical items
    local partial = {}
    for _, s in ipairs(slots) do
        if s.id and s.count < s.max and not st.badMergeIds[s.id] then
            local o = partial[s.id]
            if o then
                st.lastMerge = {
                    id = s.id,
                    aBag = o.bag, aSlot = o.slot, aCount = o.count,
                    bBag = s.bag, bSlot = s.slot, bCount = s.count,
                }
                Record(st, "merge "..Describe(o.bag, o.slot, o.id, o.count)..
                    " + "..Describe(s.bag, s.slot, s.id, s.count))
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
        if a.key ~= b.key then return a.key < b.key end
        if a.count ~= b.count then return a.count > b.count end
        -- Final tiebreak: item id is static (parsed from the link
        -- string, no server/cache dependency), so this is guaranteed
        -- consistent call to call - nothing left ambiguous for
        -- table.sort to disagree with itself about.
        return a.id < b.id
    end)

    -- Items with the same key+count are interchangeable (e.g. several
    -- separate stacks of an item that refuses to merge, like Travel
    -- Permit) - pairing items[pos] to slots[pos] by index breaks when
    -- there's more than one such duplicate: table.sort doesn't promise
    -- a stable order for ties, so WHICH specific duplicate lands at
    -- which index can flip between ticks even though the item's fine
    -- either way, causing two duplicates (or a duplicate and whatever
    -- displaced it) to swap back and forth forever.
    --
    -- Instead, each run of tied items is treated as a group that needs
    -- to occupy a contiguous range of positions, not specific ones
    -- within it. A group is only "wrong" if some instance of it is
    -- currently sitting outside its range - fixed by moving that one
    -- instance into whichever slot in the range isn't already holding
    -- a member of the group.
    local pos = 1
    while pos <= #items do
        local first = items[pos]
        local rangeStart = pos
        while pos <= #items and items[pos].key == first.key
              and items[pos].count == first.count do
            pos = pos + 1
        end
        local rangeEnd = pos - 1

        local inRange = {}
        for p = rangeStart, rangeEnd do
            local t = slots[p]
            if not t then break end
            inRange[t.bag..":"..t.slot] = true
        end

        local misplaced
        for i = rangeStart, rangeEnd do
            local it = items[i]
            if not inRange[it.bag..":"..it.slot] then
                misplaced = it
                break
            end
        end

        if misplaced then
            for p = rangeStart, rangeEnd do
                local t = slots[p]
                if not t then break end
                local memberOfGroup = t.link and t.key == first.key and t.count == first.count
                if not memberOfGroup then
                    Record(st, "swap want="..Describe(misplaced.bag, misplaced.slot, misplaced.id, misplaced.count)..
                        " target="..Describe(t.bag, t.slot, t.id, t.count))
                    PickupContainerItem(misplaced.bag, misplaced.slot)
                    PickupContainerItem(t.bag, t.slot)
                    return true
                end
            end
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
        Log("Sort aborted (too many steps) - last actions:")
        for _, msg in ipairs(self.recent) do Log("  "..msg) end
        DumpDuplicates(self.bags)
        self:Hide()
        return
    end
    local ok, more = pcall(SortStep, self, self.bags)
    if not ok or not more then
        if not ok then Log("ERROR while sorting: "..tostring(more)) end
        self:Hide()
        Log("Sort finished ("..(self.steps or 0).." steps)")
    end
end)

function B.StartSort(bags)
    if sorter:IsShown() then return end
    sorter.bags        = bags
    sorter.t           = 0
    sorter.steps       = 0
    sorter.lastMerge   = nil
    sorter.badMergeIds = {}
    sorter.recent      = {}
    sorter:Show()
    Log("Sort started (method: "..B.Config().sortMethod..")")
end
