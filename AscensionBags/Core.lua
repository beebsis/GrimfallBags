---------------------------------------------------------------------------
-- AscensionBags - Core
-- UI layer for WoW 3.3.5a / Ascension: Conquest of Azeroth.
-- Independent reimplementation following the operating principle of
-- Baganator (see ANALYSE.txt) - no third-party code. Data layer: Syndicator335.
--
-- This file is just the bootstrap: the shared B table, logging, config/
-- defaults, and the slash command. Everything else lives in its own
-- file by concern - Profiles.lua (profile save/share), WindowChrome.lua
-- (window styling/move/resize/position), ElvUISkin.lua (ElvUI skin
-- integration), IOWindow.lua (shared import/export popup) - split out
-- of what used to all be crammed into this one file.
---------------------------------------------------------------------------
local B = {}
_G["AscensionBags"] = B

B.VERSION = "1.0.0"

---------------------------------------------------------------------------
-- Log:  /ascbags log
---------------------------------------------------------------------------
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
            print("|cffff3333[AscensionBags]|r Error - |cffffcc00/ascbags log|r")
        end
    end
    return ok
end

---------------------------------------------------------------------------
-- Config with defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    viewType     = "category",   -- "category" | "single"
    showBagRow   = false,        -- show bag-slot row
    greyJunk     = true,         -- grey out junk
    showILvl     = true,         -- item level on equipment
    recentSecs   = 120,          -- "New" category: duration in seconds
    sortMethod   = "type",       -- "type" | "quality" | "ilvl"
    replaceBags  = true,         -- replace Blizzard bags
    replaceBank  = true,         -- replace Blizzard's personal bank window
    replaceGuildBank = true,     -- replace Blizzard guild bank
    gbCategoryView = false,      -- guild bank in category view
    showTmogDot  = true,         -- purple dot: transmog not yet collected
    showTagTooltip = true,       -- show computed category tags on item tooltips
    showItemID   = true,         -- show item ID on tooltips (built-in idtip)
    autoOpenMerchant = false,    -- auto-show bags when a vendor window opens
    autoOpenMailbox  = false,    -- auto-show bags when the mailbox opens
    autoRepair       = false,    -- auto-repair at merchants (prefers guild funds)
    elvuiPromptShown = false,    -- have we asked which addon owns bags/bank yet?
    elvuiSkin        = true,     -- match ElvUI's look when ElvUI is installed
    pos          = {},           -- window positions
    winWidth     = {},           -- window widths (columns are derived from this)
    rules        = {},           -- custom categories {name, tags={}, query}
    sections     = {},           -- ordered list of super-group names - exist
                                  -- as their own explicit entities (can have
                                  -- zero members) rather than being purely
                                  -- inferred from rules' .section field
    hiddenCats   = {},           -- {[catName]=true}
    sectionCollapsed = {},       -- {[sectionName]=true} collapsed
    profiles     = {},           -- {[profileName] = {settings}}
}

function B.Config()
    AscensionBagsConfig = AscensionBagsConfig or {}
    local c = AscensionBagsConfig
    for k, v in pairs(DEFAULTS) do
        if c[k] == nil then
            if type(v) == "table" then c[k] = {} else c[k] = v end
        end
    end
    return c
end

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
B.PLAYER_BAGS = {0, 1, 2, 3, 4}
B.BANK_BAGS   = {-1, 5, 6, 7, 8, 9, 10, 11}

function B.MoneyString(money)
    money = money or 0
    if GetCoinTextureString then return GetCoinTextureString(money) end
    local g = math.floor(money / 10000)
    local s = math.floor((money % 10000) / 100)
    return g.."|cffffd700g|r "..s.."|cffc7c7cfs|r "..(money % 100).."|cffeda55fc|r"
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
SLASH_AscensionBags1 = "/ascbags"
SLASH_AscensionBags2 = "/abags"
SLASH_AscensionBags3 = "/AscensionBags"
SlashCmdList["AscensionBags"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "log" then
        if #B.log == 0 then print("|cff33aaff[AscensionBags]|r Log is empty.") end
        for _, line in ipairs(B.log) do print("  "..line) end
    elseif msg == "clearlog" then
        wipe(B.log)
        B.errorNotified = nil
        print("|cff33aaff[AscensionBags]|r Log cleared.")
    elseif msg == "options" then
        if B.ToggleOptions then B.ToggleOptions() end
    else
        if B.ToggleBags then B.ToggleBags() end
    end
end
