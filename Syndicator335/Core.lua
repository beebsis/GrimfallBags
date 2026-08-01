---------------------------------------------------------------------------
-- Syndicator335 - Core
-- Data layer for WoW 3.3.5a / Ascension: Conquest of Azeroth.
-- Independent reimplementation following the operating principle of
-- Syndicator (see ANALYSE.txt) - no third-party code.
--
-- Stores per character: bags, bank, mail, equipment, auctions, gold;
-- per guild: guild bank. Provides search and tooltip lines.
---------------------------------------------------------------------------
local S = {}
_G["Syndicator335"] = S

S.VERSION = "1.0.0"

---------------------------------------------------------------------------
-- Log:  /syn335 log
---------------------------------------------------------------------------
local LOG_MAX = 200
S.log = {}

function S.Log(msg)
    local t = S.log
    t[#t+1] = date("%H:%M:%S").."  "..tostring(msg)
    if #t > LOG_MAX then table.remove(t, 1) end
end

function S.Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        S.Log("ERROR in "..label..": "..tostring(err))
        if not S.errorNotified then
            S.errorNotified = true
            print("|cffff3333[Syndicator335]|r Error - |cffffcc00/syn335 log|r")
        end
    end
    return ok
end

---------------------------------------------------------------------------
-- Data access
-- Syndicator335Data = {
--   chars  = { ["Name - Realm"] = {
--       class, faction, money, lastSeen,
--       bags   = { [bagID]  = {size=n, [slot]={l,c,t,q}} },
--       bank   = { [bagID]  = {size=n, [slot]={l,c,t,q}} },
--       mail   = { {l,c,t,q}, ... },
--       equipped = { [invSlot] = {l,c,t,q} },
--       auctions = { {l,c,t,q}, ... },
--       counts = { [itemID] = {bags=n, bank=n, mail=n, equipped=n, auctions=n} },
--   } },
--   guilds = { ["Guild - Realm"] = {
--       money, tabs = { [tab] = {name=..., [slot]={l,c,t,q}} },
--       counts = { [itemID] = n },
--   } },
-- }
---------------------------------------------------------------------------
function S.CharKey()
    return UnitName("player").." - "..GetRealmName()
end

function S.GuildKey()
    local gname = GetGuildInfo("player")
    if not gname then return nil end
    return gname.." - "..GetRealmName()
end

function S.Data()
    Syndicator335Data        = Syndicator335Data or {}
    Syndicator335Data.chars  = Syndicator335Data.chars or {}
    Syndicator335Data.guilds = Syndicator335Data.guilds or {}
    return Syndicator335Data
end

function S.Char(key)
    local d = S.Data()
    key = key or S.CharKey()
    local c = d.chars[key]
    if not c then
        c = {}
        d.chars[key] = c
    end
    return c
end

function S.Guild(key)
    key = key or S.GuildKey()
    if not key then return nil end
    local d = S.Data()
    local g = d.guilds[key]
    if not g then
        g = {tabs = {}}
        d.guilds[key] = g
    end
    return g
end

---------------------------------------------------------------------------
-- Public API (for AscensionBags and other addons)
---------------------------------------------------------------------------
S.API = {}

-- Sorted list of all known character keys
function S.API.GetAllCharacters()
    local keys = {}
    for key in pairs(S.Data().chars) do keys[#keys+1] = key end
    table.sort(keys)
    return keys
end

function S.API.GetCharacter(key)
    return S.Data().chars[key]
end

function S.API.GetAllGuilds()
    local keys = {}
    for key in pairs(S.Data().guilds) do keys[#keys+1] = key end
    table.sort(keys)
    return keys
end

function S.API.GetGuild(key)
    return S.Data().guilds[key]
end

function S.API.DeleteCharacter(key)
    S.Data().chars[key] = nil
end

-- Total count of an item across all sources of a character
function S.API.CountsForItem(charData, itemID)
    local c = charData and charData.counts and charData.counts[itemID]
    return c
end

---------------------------------------------------------------------------
-- Item ID from link
---------------------------------------------------------------------------
function S.ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

function S.ItemName(link)
    return link and link:match("%[(.-)%]") or ""
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
SLASH_SYNDICATOR3351 = "/syn335"
SLASH_SYNDICATOR3352 = "/syndicator335"
SlashCmdList["SYNDICATOR335"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "log" then
        if #S.log == 0 then print("|cff33aaff[Syndicator335]|r Log is empty.") end
        for _, line in ipairs(S.log) do print("  "..line) end
    elseif msg == "clearlog" then
        wipe(S.log)
        S.errorNotified = nil
        print("|cff33aaff[Syndicator335]|r Log cleared.")
    elseif msg:match("^forget ") then
        local key = msg:gsub("^forget%s+", "")
        -- case-insensitive match
        for k in pairs(S.Data().chars) do
            if k:lower() == key then
                S.Data().chars[k] = nil
                print("|cff33aaff[Syndicator335]|r '"..k.."' removed.")
                return
            end
        end
        print("|cff33aaff[Syndicator335]|r Unknown. Known characters:")
        for _, k in ipairs(S.API.GetAllCharacters()) do print("  "..k) end
    else
        print("|cff33aaff[Syndicator335]|r Commands: /syn335 log | clearlog | forget <Name - Realm>")
    end
end
