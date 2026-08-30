local S = {}
_G["Syndicator335"] = S

S.VERSION = "1.0.0"

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

S.API = {}

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

function S.API.CountsForItem(charData, itemID)
    local c = charData and charData.counts and charData.counts[itemID]
    return c
end

function S.ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

function S.ItemName(link)
    return link and link:match("%[(.-)%]") or ""
end

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
