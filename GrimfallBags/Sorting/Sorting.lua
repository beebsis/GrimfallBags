local B = GrimfallBags
local S = Syndicator335
local Log = B.Log

local sorter = CreateFrame("Frame")
sorter:Hide()

function B.SortKey(link)
    local name, _, quality, iLvl, _, itemType, subType = GetItemInfo(link or "")
    name, quality, iLvl = name or "", quality or 0, iLvl or 0
    itemType, subType = itemType or "", subType or ""
    local id = S.ItemID(link) or 0
    local method = B.Config().sortMethod
    if method == "quality" then
        return string.format("%02d|%s|%s|%s", 9 - quality, itemType, subType, name)
    elseif method == "ilvl" then
        return string.format("%04d|%s", 9999 - iLvl, name)
    elseif method == "name" then
        return name:lower()
    elseif method == "id" then
        return string.format("%08d", id)
    else
        return string.format("%s|%s|%02d|%s", itemType, subType, 9 - quality, name)
    end
end

local function Record(st, msg)
    st.recent[#st.recent + 1] = msg
    if #st.recent > 12 then table.remove(st.recent, 1) end
end

local function Describe(bag, slot, id, count)
    local name = id and GetItemInfo(id)
    return string.format("%d:%d[%s x%d]", bag, slot, name or tostring(id), count)
end

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

local function SortStep(st, bags)
    local slots = {}
    for _, bag in ipairs(bags) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local _, count, locked = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            if locked then return true end
            if link and not GetItemInfo(link) then return true end
            slots[#slots+1] = {
                bag = bag, slot = slot, link = link,
                id = S.ItemID(link), count = count or 0,
                max = link and (select(8, GetItemInfo(link)) or 1) or 1,
                key = link and B.SortKey(link) or nil,
                ignored = B.IsSlotIgnored(bag, slot),
            }
        end
    end

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

    local partial = {}
    for _, s in ipairs(slots) do
        if not s.ignored and s.id and s.count < s.max and not st.badMergeIds[s.id] then
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

    local items = {}
    for _, s in ipairs(slots) do
        if s.link and not s.ignored then items[#items+1] = s end
    end
    table.sort(items, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        if a.count ~= b.count then return a.count > b.count end
        return a.id < b.id
    end)

    -- Non-ignored slots, in physical order, are the target positions for the
    -- sorted items; ignored slots stay put and are never swapped into.
    local targets = {}
    for _, s in ipairs(slots) do
        if not s.ignored then targets[#targets+1] = s end
    end

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
            local t = targets[p]
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
                local t = targets[p]
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
    if self.steps > 400 then
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

function B.SortBags()
    B.StartSort(B.PLAYER_BAGS)
end
