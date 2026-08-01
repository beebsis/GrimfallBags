---------------------------------------------------------------------------
-- AscensionBags - Profiles
-- Save a snapshot of the display settings under a name, apply it, delete
-- it, share it as a string or clickable chat link (guild/whisper
-- friendly). Split out of Core.lua for SoC - this is all profile/
-- sharing logic, unrelated to config bootstrap or window chrome.
---------------------------------------------------------------------------
local B = AscensionBags

local PROFILE_KEYS = {
    "viewType", "showBagRow", "greyJunk",
    "showILvl", "recentSecs", "sortMethod", "gbCategoryView",
}

function B.ProfileNames()
    local names = {}
    for name in pairs(B.Config().profiles) do names[#names+1] = name end
    table.sort(names)
    return names
end

function B.SaveCurrentAsProfile(name)
    local cfg = B.Config()
    local p = {}
    for _, k in ipairs(PROFILE_KEYS) do p[k] = cfg[k] end
    cfg.profiles[name] = p
    cfg.activeProfile = name
end

function B.ApplyProfile(name)
    local cfg = B.Config()
    local p = cfg.profiles[name]
    if not p then return false end
    for _, k in ipairs(PROFILE_KEYS) do
        if p[k] ~= nil then cfg[k] = p[k] end
    end
    cfg.activeProfile = name
    if B.RefreshAll then B.RefreshAll() end
    return true
end

function B.DeleteProfile(name)
    local cfg = B.Config()
    cfg.profiles[name] = nil
    if cfg.activeProfile == name then cfg.activeProfile = nil end
end

-- A profile export bundles the display settings AND the full category
-- ruleset (rules, tags, search expressions, pinned item IDs, protected
-- flags) so sharing one string/link hands over the whole setup, not
-- just view/column preferences. Wire format (JSON):
--   {"name": "...", "settings": {...}, "rules": [...]}
-- rules uses the exact same shape as B.RulesToArray()/ImportRulesArray().
-- name travels WITH the string (not just in the Chat Link marker) so
-- Import can auto-detect it - see ImportBoxName() in Options.lua.
function B.ExportProfile(name)
    local p = B.Config().profiles[name]
    if not p then return "" end
    local settings = {}
    for _, k in ipairs(PROFILE_KEYS) do
        if p[k] ~= nil then settings[k] = p[k] end
    end
    local obj = {name = name, settings = settings}
    if B.RulesToArray then
        local rulesArr = B.RulesToArray()
        if next(rulesArr) ~= nil then obj.rules = rulesArr end
    end
    return B.Json.Encode(obj)
end

-- Old formats still floating around from before the JSON switch:
-- "key=value;key=value" (settings only), or that plus a "##RULES##"
-- marker followed by the (then pipe-delimited) rules string - see
-- B.ImportRules, which itself still falls back to the pipe format.
local function ImportProfileLegacy(name, str)
    local settingsStr, rulesStr = str:match("^(.-)##RULES##(.*)$")
    settingsStr = settingsStr or str

    local p = {}
    for pair in settingsStr:gmatch("[^;]+") do
        local k, v = pair:match("^%s*(%w+)%s*=%s*(.-)%s*$")
        if k and v then
            if v == "true" then p[k] = true
            elseif v == "false" then p[k] = false
            elseif tonumber(v) then p[k] = tonumber(v)
            else p[k] = v end
        end
    end
    if next(p) == nil and not rulesStr then return false end
    if next(p) ~= nil then
        B.Config().profiles[name] = p
    end
    local catCount = 0
    if rulesStr and rulesStr ~= "" and B.ImportRules then
        catCount = B.ImportRules(rulesStr)
    end
    if catCount > 0 then
        print("|cff33aaff[AscensionBags]|r Also imported "..catCount.." categor"..(catCount == 1 and "y" or "ies")..".")
    end
    return true
end

function B.ImportProfile(name, str)
    str = str or ""
    local obj = B.Json.Decode(str)
    if type(obj) ~= "table" then
        return ImportProfileLegacy(name, str)
    end

    local settings = obj.settings
    local hasSettings = type(settings) == "table" and next(settings) ~= nil
    if not hasSettings and not obj.rules then return false end
    if hasSettings then
        B.Config().profiles[name] = settings
    end

    local catCount = 0
    if obj.rules and B.ImportRulesArray then
        catCount = B.ImportRulesArray(obj.rules)
    end
    if catCount > 0 then
        print("|cff33aaff[AscensionBags]|r Also imported "..catCount.." categor"..(catCount == 1 and "y" or "ies")..".")
    end
    return true
end

---------------------------------------------------------------------------
-- Share profiles as clickable chat links (guild/whisper friendly)
--
-- IMPORTANT: we never send a real |H hyperlink over the wire. Ascension
-- (like most 3.3.5 cores) validates outgoing |H links against a whitelist
-- of Blizzard link types and silently drops the whole message if it sees
-- an unrecognized one (e.g. "ascbags") - not even echoed back to sender.
-- So the wire format is plain text with no pipes at all; each recipient's
-- client rewrites it into a real hyperlink locally, purely for display,
-- via a chat message filter - that rewritten text is never re-
-- transmitted, so it never hits the server's link validator.
--
-- NOT bracket-wrapped ("[MARKER:...]") like the old version: the payload
-- is now JSON, which legitimately contains "[" and "]" (arrays), so a
-- bracket-balanced wrapper would truncate at the first internal "]".
-- Instead: find the marker via a plain substring search (no pattern,
-- no escaping needed), and treat everything after it, to the end of
-- the message, as the JSON blob - the profile name travels inside
-- that JSON (see B.ProfileShareText) rather than as a separate field.
---------------------------------------------------------------------------
local LINK_TYPE = "ascbags"
local MARKER = "AscBagsProfile:"

-- Plain-text marker to type/insert into chat - safe to send.
-- B.ExportProfile already embeds "name" in the JSON, so this just
-- prefixes the marker onto it.
function B.ProfileShareText(name)
    local jsonStr = B.ExportProfile(name)
    if jsonStr == "" then return nil end
    return MARKER..jsonStr
end

-- Real hyperlink, used only for local (received-message) display.
local function BuildHyperlink(name, data)
    return "|cff33aaff|H"..LINK_TYPE..":"..name..":"..data.."|h["..name.."]|h|r"
end

StaticPopupDialogs["ASCBAGS_PROFILE_IMPORT_LINK"] = {
    text = "Import AscensionBags profile '%s' shared in chat?\n(Overwrites any existing profile with that name.)",
    button1 = ACCEPT or "Ok",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        if B.ImportProfile(data.name, data.str) then
            print("|cff33aaff[AscensionBags]|r Profile '"..data.name.."' imported from chat link.")
        else
            print("|cff33aaff[AscensionBags]|r Import failed.")
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
    local ltype, name, str = link:match("^("..LINK_TYPE.."):([^:]*):(.*)$")
    if ltype == LINK_TYPE then
        StaticPopup_Show("ASCBAGS_PROFILE_IMPORT_LINK", name, nil, {name = name, str = str})
        return
    end
    origSetItemRef(link, text, button, chatFrame)
end

-- Rewrite our plain marker into a clickable link, locally, on display
-- only. Finds the marker via plain substring search and treats
-- everything after it (to end of message) as the JSON payload - see
-- the note above on why this can't be a bracket-balanced pattern match.
local function LinkifyFilter(self, event, msg, ...)
    local pos = msg:find(MARKER, 1, true)
    if not pos then return false end
    local jsonPart = msg:sub(pos + #MARKER)
    local obj = B.Json.Decode(jsonPart)
    if type(obj) ~= "table" or not obj.name then return false end
    local newMsg = msg:sub(1, pos - 1)..BuildHyperlink(obj.name, jsonPart)
    return false, newMsg, ...
end

local LINKIFY_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
}
for _, evt in ipairs(LINKIFY_EVENTS) do
    ChatFrame_AddMessageEventFilter(evt, LinkifyFilter)
end
