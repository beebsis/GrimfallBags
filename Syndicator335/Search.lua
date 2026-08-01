---------------------------------------------------------------------------
-- Syndicator335 - Search
-- Query language (own implementation):
--   Free text         substring of the item name
--   a & b             both must match
--   a | b             either must match
--   !a                must not match
--   ( ... )           parentheses
--   >200 <100 =150    item-level comparison
--   200-210           item-level range
--   quality words      poor, common, uncommon, rare, epic, legendary
--   Keywords          boe, bop, soulbound, bou, junk, equipment,
--                     reagent, food, potion, quest, recipe, weapon, armor
--
-- Item data format for Matches: {l=Link, c=Count, t=Texture, q=Quality}
-- Extra info is lazily pulled from GetItemInfo(link).
---------------------------------------------------------------------------
local S = Syndicator335

S.Search = {}

---------------------------------------------------------------------------
-- Prepare item info for search (with a small per-entry cache)
---------------------------------------------------------------------------
local infoCache = setmetatable({}, {__mode = "k"})

local function GetInfo(entry)
    local info = infoCache[entry]
    if info then return info end
    local link = entry.l
    local name, _, quality, iLvl, minLvl, itemType, subType,
          stack, equipLoc = GetItemInfo(link or "")
    info = {
        name     = (name or S.ItemName(link)):lower(),
        quality  = entry.q or quality or 1,
        ilvl     = iLvl or 0,
        minLvl   = minLvl or 0,
        itemType = (itemType or ""):lower(),
        subType  = (subType or ""):lower(),
        equipLoc = equipLoc or "",
    }
    infoCache[entry] = info
    return info
end

---------------------------------------------------------------------------
-- Quality words: localized Blizzard strings + English names
---------------------------------------------------------------------------
local QUALITY_WORDS = {}
do
    local english = {"poor", "common", "uncommon", "rare", "epic",
                     "legendary", "artifact", "heirloom"}
    for q = 0, 7 do
        local loc = _G["ITEM_QUALITY"..q.."_DESC"]
        if loc then QUALITY_WORDS[loc:lower()] = q end
        if english[q+1] then QUALITY_WORDS[english[q+1]] = q end
    end
end

---------------------------------------------------------------------------
-- Keywords: name (aliases) -> check function(info, entry)
---------------------------------------------------------------------------
-- Bind-status is a property of the item definition, not of a
-- particular stack, so we cache the tooltip-scan result per itemID
-- (not per entry). This matters a lot for "search everywhere": the
-- same itemID can appear in dozens of stacks across many tracked
-- characters, and without this cache each one would trigger its own
-- synchronous SetHyperlink() tooltip scan.
local bindLineCache = {}   -- [itemID] = {[pattern] = true/false}

local function TooltipHasLine(link, pattern)
    local id = S.ItemID(link)
    local cached = id and bindLineCache[id] and bindLineCache[id][pattern]
    if cached ~= nil then return cached end

    -- hidden scan tooltip for bind checks
    local tt = S.scanTip
    if not tt then
        tt = CreateFrame("GameTooltip", "Syndicator335ScanTip", nil, "GameTooltipTemplate")
        tt:SetOwner(UIParent, "ANCHOR_NONE")
        S.scanTip = tt
    end
    tt:ClearLines()
    tt:SetHyperlink(link)
    local found = false
    for i = 1, math.min(tt:NumLines(), 5) do
        local line = _G["Syndicator335ScanTipTextLeft"..i]
        local text = line and line:GetText()
        if text and text:find(pattern, 1, true) then found = true; break end
    end

    if id then
        bindLineCache[id] = bindLineCache[id] or {}
        bindLineCache[id][pattern] = found
    end
    return found
end

-- Full tooltip text (stats, "of the X" suffixes, socket colors, flavor
-- text, ...), not just the first 5 lines used for bind-status above -
-- this is what lets free-text search match something like "spirit" on
-- an item whose NAME doesn't contain that word. Same per-itemID caching
-- rationale: tooltip content is intrinsic to the item definition, not
-- the stack, so one scan covers every copy of that item everywhere.
local tooltipTextCache = {}   -- [itemID] = "all tooltip lines, lowercased, newline-joined"

local function GetTooltipText(link)
    local id = S.ItemID(link)
    if not id then return nil end
    local cached = tooltipTextCache[id]
    if cached then return cached end

    local tt = S.scanTip
    if not tt then
        tt = CreateFrame("GameTooltip", "Syndicator335ScanTip", nil, "GameTooltipTemplate")
        tt:SetOwner(UIParent, "ANCHOR_NONE")
        S.scanTip = tt
    end
    tt:ClearLines()
    tt:SetHyperlink(link)
    local parts = {}
    for i = 1, tt:NumLines() do
        local line = _G["Syndicator335ScanTipTextLeft"..i]
        local text = line and line:GetText()
        if text then parts[#parts+1] = text:lower() end
    end
    local joined = table.concat(parts, "\n")
    tooltipTextCache[id] = joined
    return joined
end

-- Bind status/tooltip text can't change without a relog/item swap, but
-- wipe on login just in case a custom server changes item data underfoot.
local wiper = CreateFrame("Frame")
wiper:RegisterEvent("PLAYER_LOGIN")
wiper:SetScript("OnEvent", function()
    wipe(bindLineCache)
    wipe(tooltipTextCache)
end)

local KEYWORDS = {}
local function AddKeyword(check, ...)
    for i = 1, select("#", ...) do
        local word = select(i, ...)
        if word and word ~= "" then KEYWORDS[word:lower()] = check end
    end
end

AddKeyword(function(info) return info.equipLoc ~= "" and info.equipLoc ~= "INVTYPE_BAG" end,
    "equipment", "gear")
AddKeyword(function(info) return info.quality == 0 end,
    "junk", "grey", "gray")
AddKeyword(function(info, entry)
    return entry.l and TooltipHasLine(entry.l, ITEM_BIND_ON_EQUIP or "Bind on Equip")
end, "boe", "bwe")
AddKeyword(function(info, entry)
    return entry.l and TooltipHasLine(entry.l, ITEM_SOULBOUND or "Soulbound")
end, "soulbound", "bop")
AddKeyword(function(info, entry)
    return entry.l and TooltipHasLine(entry.l, ITEM_BIND_ON_USE or "Bind on Use")
end, "bou")
AddKeyword(function(info, entry) return entry.isNew == true end, "new")

-- Item-type keywords via the localized Auction House classes: works
-- automatically in any language and with CoA customisations
do
    local classes = {GetAuctionItemClasses()}
    -- English aliases in order of the 3.3.5a class IDs
    local english = {"weapon", "armor", "container", "consumable", "glyph",
                     "trade goods", "projectile", "quiver", "recipe",
                     "gem", "miscellaneous", "quest"}
    for i, locName in ipairs(classes) do
        local target = locName:lower()
        local check = function(info) return info.itemType == target end
        AddKeyword(check, locName, english[i])
    end
end

---------------------------------------------------------------------------
-- Evaluate a single term
---------------------------------------------------------------------------
local function MatchTerm(entry, term)
    local info = GetInfo(entry)

    -- Item level: >n, <n, =n, n-m
    local op, num = term:match("^([<>=])(%d+)$")
    if op then
        num = tonumber(num)
        if op == ">" then return info.ilvl > num end
        if op == "<" then return info.ilvl < num end
        return info.ilvl == num
    end
    local lo, hi = term:match("^(%d+)%-(%d+)$")
    if lo then
        return info.ilvl >= tonumber(lo) and info.ilvl <= tonumber(hi)
    end

    -- Quality
    local q = QUALITY_WORDS[term]
    if q ~= nil then return info.quality == q end

    -- Keyword
    local kw = KEYWORDS[term]
    if kw then return kw(info, entry) or false end

    -- Free text: name, type, subtype, or anywhere in the tooltip (stats
    -- like "spirit", set/suffix names, socket colors, ...)
    if info.name:find(term, 1, true) or info.itemType:find(term, 1, true)
       or info.subType:find(term, 1, true) then
        return true
    end
    if entry.l then
        local tip = GetTooltipText(entry.l)
        if tip and tip:find(term, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Query parser: recursive descent over |, &, !, ( )
--   expr   := andExp { "|" andExp }
--   andExp := unary  { "&" unary }
--   unary  := "!" unary | "(" expr ")" | term
---------------------------------------------------------------------------
local function Tokenize(query)
    local tokens = {}
    local buf = ""
    local function flush()
        local w = buf:match("^%s*(.-)%s*$")
        if w ~= "" then tokens[#tokens+1] = w end
        buf = ""
    end
    for i = 1, #query do
        local ch = query:sub(i, i)
        if ch == "&" or ch == "|" or ch == "!" or ch == "(" or ch == ")" then
            flush()
            tokens[#tokens+1] = ch
        else
            buf = buf..ch
        end
    end
    flush()
    return tokens
end

local ParseExpr   -- forward

local function ParseUnary(tokens, pos, entry)
    local tok = tokens[pos]
    if tok == "!" then
        local val, np = ParseUnary(tokens, pos + 1, entry)
        return not val, np
    elseif tok == "(" then
        local val, np = ParseExpr(tokens, pos + 1, entry)
        if tokens[np] == ")" then np = np + 1 end
        return val, np
    elseif tok == nil or tok == ")" or tok == "&" or tok == "|" then
        return true, pos   -- empty term matches everything
    else
        return MatchTerm(entry, tok:lower()), pos + 1
    end
end

local function ParseAnd(tokens, pos, entry)
    local val, np = ParseUnary(tokens, pos, entry)
    while tokens[np] == "&" do
        local v2
        v2, np = ParseUnary(tokens, np + 1, entry)
        val = val and v2
    end
    return val, np
end

ParseExpr = function(tokens, pos, entry)
    local val, np = ParseAnd(tokens, pos, entry)
    while tokens[np] == "|" do
        local v2
        v2, np = ParseAnd(tokens, np + 1, entry)
        val = val or v2
    end
    return val, np
end

---------------------------------------------------------------------------
-- Public search API
---------------------------------------------------------------------------
-- entry = {l=Link, c=Count, t=Texture, q=Quality}
function S.Search.Matches(entry, query)
    if not query or query == "" then return true end
    if not entry or not entry.l then return false end
    local ok, result = pcall(function()
        local tokens = Tokenize(query)
        local val = ParseExpr(tokens, 1, entry)
        return val
    end)
    return ok and result or false
end

-- Search everywhere: all characters/sources, result as a list
-- { {char=..., source=..., entry=...}, ... }
function S.Search.Everywhere(query)
    local results = {}
    local function scanSet(charKey, source, set)
        for _, b in pairs(set or {}) do
            for slot, e in pairs(b) do
                if type(slot) == "number" and type(e) == "table" and e.l then
                    if S.Search.Matches(e, query) then
                        results[#results+1] = {char=charKey, source=source, entry=e}
                    end
                end
            end
        end
    end
    for key, c in pairs(S.Data().chars) do
        scanSet(key, BACKPACK_TOOLTIP or "Bags", c.bags)
        scanSet(key, BANK or "Bank", c.bank)
        for _, e in ipairs(c.mail or {}) do
            if S.Search.Matches(e, query) then
                results[#results+1] = {char=key, source=MAIL_LABEL or "Mail", entry=e}
            end
        end
        for _, e in ipairs(c.auctions or {}) do
            if S.Search.Matches(e, query) then
                results[#results+1] = {char=key, source=AUCTIONS or "Auctions", entry=e}
            end
        end
    end
    for key, g in pairs(S.Data().guilds) do
        for tabIdx, tab in pairs(g.tabs or {}) do
            for slot, e in pairs(tab) do
                if type(slot) == "number" and type(e) == "table" and e.l then
                    if S.Search.Matches(e, query) then
                        results[#results+1] = {char=key, source=(GUILD or "Guild").." "..tabIdx, entry=e}
                    end
                end
            end
        end
    end
    return results
end
