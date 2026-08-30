local B = GrimfallBags

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
        print("|cff33aaff[GrimfallBags]|r Also imported "..catCount.." categor"..(catCount == 1 and "y" or "ies")..".")
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
        print("|cff33aaff[GrimfallBags]|r Also imported "..catCount.." categor"..(catCount == 1 and "y" or "ies")..".")
    end
    return true
end

local LINK_TYPE = "gfbags"
local MARKER = "GFBagsProfile:"

function B.ProfileShareText(name)
    local jsonStr = B.ExportProfile(name)
    if jsonStr == "" then return nil end
    return MARKER..jsonStr
end

local function BuildHyperlink(name, data)
    return "|cff33aaff|H"..LINK_TYPE..":"..name..":"..data.."|h["..name.."]|h|r"
end

StaticPopupDialogs["GFBAGS_PROFILE_IMPORT_LINK"] = {
    text = "Import GrimfallBags profile '%s' shared in chat?\n(Overwrites any existing profile with that name.)",
    button1 = ACCEPT or "Ok",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        if B.ImportProfile(data.name, data.str) then
            print("|cff33aaff[GrimfallBags]|r Profile '"..data.name.."' imported from chat link.")
        else
            print("|cff33aaff[GrimfallBags]|r Import failed.")
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
    local ltype, name, str = link:match("^("..LINK_TYPE.."):([^:]*):(.*)$")
    if ltype == LINK_TYPE then
        StaticPopup_Show("GFBAGS_PROFILE_IMPORT_LINK", name, nil, {name = name, str = str})
        return
    end
    origSetItemRef(link, text, button, chatFrame)
end

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
