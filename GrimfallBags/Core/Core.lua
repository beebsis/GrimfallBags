local B = {}
_G["GrimfallBags"] = B

B.VERSION = "2.0.0"

-- Keybinding labels for Bindings.xml (shown in the Key Bindings UI).
BINDING_HEADER_GRIMFALLBAGS = "Grimfall Bags"
BINDING_NAME_GFBAGS_TOGGLEBAGS = "Toggle Bags"
BINDING_NAME_GFBAGS_OPENBANK   = "Open Bank"
BINDING_NAME_GFBAGS_OPENGB     = "Open Guild Bank"
BINDING_NAME_GFBAGS_SORT       = "Sort Bags"
BINDING_NAME_GFBAGS_SEARCH     = "Search"

local LOG_MAX = 200
B.log = {}

function B.Log(msg)
    local t = B.log
    t[#t+1] = date("%H:%M:%S").."  "..tostring(msg)
    if #t > LOG_MAX then table.remove(t, 1) end
end

function B.Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        B.Log("ERROR in "..label..": "..tostring(err))
        if not B.errorNotified then
            B.errorNotified = true
            print("|cffff3333[GrimfallBags]|r Error - |cffffcc00/gfbags log|r")
        end
    end
    return ok
end

local DEFAULTS = {
    viewType     = "category",
    showBagRow   = false,
    showSearchFilters = true,
    greyJunk     = true,
    showILvl     = true,
    showCrossCharCount = true,
    mergeStacks  = true,
    recentSecs   = 120,
    sortMethod   = "type",
    replaceBags  = true,
    replaceBank  = true,
    replaceGuildBank = true,
    gbCategoryView = false,
    showTmogDot  = true,
    autoRepair       = false,
    autoSellJunk     = false,
    elvuiPromptShown = false,
    elvuiBagsMigrationPrompted = false,
    skin             = "flat",
    pos          = {},
    winWidth     = {},
    rules        = {},
    sections     = {},
    hiddenCats   = {},
    sectionCollapsed = {},
    ignoredSlots = {},
    profiles     = {},
}

function B.Config()
    GrimfallBagsConfig = GrimfallBagsConfig or {}
    local c = GrimfallBagsConfig
    for k, v in pairs(DEFAULTS) do
        if c[k] == nil then
            if type(v) == "table" then c[k] = {} else c[k] = v end
        end
    end
    -- Retire the old elvuiSkin boolean in favor of the skin dropdown value.
    if c.elvuiSkin ~= nil then c.elvuiSkin = nil end
    return c
end

B.PLAYER_BAGS = {0, 1, 2, 3, 4}
B.BANK_BAGS   = {-1, 5, 6, 7, 8, 9, 10, 11}

function B.MoneyString(money)
    money = money or 0
    if GetCoinTextureString then return GetCoinTextureString(money) end
    local g = math.floor(money / 10000)
    local s = math.floor((money % 10000) / 100)
    return g.."|cffffd700g|r "..s.."|cffc7c7cfs|r "..(money % 100).."|cffeda55fc|r"
end

SLASH_GrimfallBags1 = "/gfbags"
SLASH_GrimfallBags2 = "/gbags"
SLASH_GrimfallBags3 = "/GrimfallBags"
SlashCmdList["GrimfallBags"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "log" then
        if #B.log == 0 then print("|cff33aaff[GrimfallBags]|r Log is empty.") end
        for _, line in ipairs(B.log) do print("  "..line) end
    elseif msg == "clearlog" then
        wipe(B.log)
        B.errorNotified = nil
        print("|cff33aaff[GrimfallBags]|r Log cleared.")
    elseif msg == "junk" or msg == "junkdebug" then
        if B.DebugJunk then
            B.DebugJunk()
        else
            print("|cffff3333[GrimfallBags]|r DebugJunk not available.")
        end
    elseif msg == "options" then
        if B.ToggleOptions then B.ToggleOptions() end
    elseif msg == "disableelvuibags" then
        if not IsAddOnLoaded("ElvUI") then
            print("|cffff3333[GrimfallBags]|r ElvUI isn't loaded.")
        elseif not (B.DisableElvUIBags and B.DisableElvUIBags()) then
            print("|cffff3333[GrimfallBags]|r Couldn't disable ElvUI's bags.")
        end
    elseif msg == "currencydebug" then
        if not B.GetWatchedCurrencies then
            print("|cff33aaff[GrimfallBags]|r GetWatchedCurrencies not available.")
        else
            local list = B.GetWatchedCurrencies()
            B.Log("currencydebug: "..#list.." watched currenc"..(#list == 1 and "y" or "ies"))
            for i, cur in ipairs(list) do
                B.Log(string.format("  [%d] index=%s name=%s count=%s icon=%s",
                    i, tostring(cur.index), tostring(cur.name), tostring(cur.count), tostring(cur.icon)))
            end
            print("|cff33aaff[GrimfallBags]|r Dumped "..#list.." watched currenc"..(#list == 1 and "y" or "ies").." -- see /gfbags log")
        end
    else
        if B.ToggleBags then B.ToggleBags() end
    end
end
