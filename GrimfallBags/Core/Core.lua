local B = {}
_G["GrimfallBags"] = B

B.VERSION = "2.1.0"

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

-- Live diagnostic window. Created lazily on first use so it can share the
-- addon's window chrome (B.StyleWindow / B.MakeMovable live in WindowChrome.lua,
-- which loads after Core.lua). The body is a chat-style ScrollingMessageFrame
-- (native wheel scroll); a "Copy" button opens a selectable EditBox with the
-- full text so it can be copied. Toggle: /gfbags diag.
local DIAG_MAX_LINES = 500
local diagLines = {}
local diagFrame, diagScroll, copyFrame, copyEdit

local function DiagEnsure()
    if diagFrame then return end

    diagFrame = CreateFrame("Frame", "GrimfallBagsDiag", UIParent)
    diagFrame:SetSize(520, 300)
    diagFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    diagFrame:SetFrameStrata("DIALOG")
    if B.StyleWindow then B.StyleWindow(diagFrame) end
    if B.MakeMovable then B.MakeMovable(diagFrame, "GrimfallBagsDiag") end

    local title = diagFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", diagFrame, "TOPLEFT", 8, -6)
    title:SetText("|cff33aaffGrimfallBags|r diagnostics  (wheel to scroll, /gfbags diag to close)")

    -- Chat-style scrolling message frame: reliable wheel scroll.
    diagScroll = CreateFrame("ScrollingMessageFrame", "GrimfallBagsDiagText", diagFrame)
    diagScroll:SetPoint("TOPLEFT", diagFrame, "TOPLEFT", 8, -26)
    diagScroll:SetPoint("BOTTOMRIGHT", diagFrame, "BOTTOMRIGHT", -8, -34)
    diagScroll:SetFontObject(GameFontNormalSmall)
    diagScroll:SetMaxLines(500)
    diagScroll:SetFading(false)
    diagScroll:SetJustifyH("LEFT")
    diagScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    -- Copy button: opens a selectable EditBox with the full log.
    local copyBtn = CreateFrame("Button", nil, diagFrame, "UIPanelButtonTemplate")
    copyBtn:SetWidth(64); copyBtn:SetHeight(22)
    copyBtn:SetPoint("BOTTOMRIGHT", diagFrame, "BOTTOMRIGHT", -8, 7)
    copyBtn:SetText("Copy")
    copyBtn:SetScript("OnClick", function()
        DiagEnsure()
        if not copyEdit then return end
        copyEdit:SetText(#diagLines > 0 and table.concat(diagLines, "\n") or "(empty)")
        copyEdit:HighlightText()
        copyFrame:Show()
        copyEdit:SetFocus()
    end)
    if B.SkinButton then B.SkinButton(copyBtn) end

    -- Copy popup.
    copyFrame = CreateFrame("Frame", "GrimfallBagsDiagCopy", UIParent)
    copyFrame:SetSize(520, 300)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    if B.StyleWindow then B.StyleWindow(copyFrame) end
    if B.MakeMovable then B.MakeMovable(copyFrame, "GrimfallBagsDiagCopy") end

    local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copyTitle:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 8, -6)
    copyTitle:SetText("|cff33aaffGrimfallBags|r diagnostics - Ctrl+A then Ctrl+C to copy, Esc to close")

    copyEdit = CreateFrame("EditBox", "GrimfallBagsDiagCopyEdit", copyFrame)
    copyEdit:SetMultiLine(true)
    copyEdit:SetAutoFocus(false)
    copyEdit:SetFontObject(GameFontNormalSmall)
    copyEdit:SetTextColor(1, 1, 1)
    copyEdit:SetTextInsets(4, 4, 4, 4)
    copyEdit:SetMaxLetters(0)
    copyEdit:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 8, -26)
    copyEdit:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -8, 8)
    copyEdit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)

    copyFrame:Hide()
    diagFrame:Hide()
end

function B.DiagLog(msg)
    DiagEnsure()
    local line = date("%H:%M:%S").."  "..tostring(msg)
    diagLines[#diagLines + 1] = line
    while #diagLines > DIAG_MAX_LINES do table.remove(diagLines, 1) end
    if diagScroll then diagScroll:AddMessage(line, 1, 1, 1) end
    B.Log(msg)
end

function B.ToggleDiag()
    DiagEnsure()
    if diagFrame:IsShown() then
        diagFrame:Hide()
        print("|cff33aaff[GrimfallBags]|r Diagnostics window hidden.")
    else
        if #diagLines == 0 and diagScroll then
            diagScroll:AddMessage("|cff888888(no diagnostic events yet - run a transfer or hover items)|r", 1, 1, 1)
        end
        diagFrame:Show()
        print("|cff33aaff[GrimfallBags]|r Diagnostics window shown - drag it clear of the bags.")
    end
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
    showItemID   = true,
    showTags     = true,
    showCategory = true,
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
    elseif msg == "diag" or msg == "diaglog" or msg == "diagwindow" then
        if B.ToggleDiag then B.ToggleDiag() end
    elseif msg == "clickdebug" then
        B.clickDebug = not B.clickDebug
        B.Log("clickdebug "..(B.clickDebug and "ON" or "OFF"))
        print("|cff33aaff[GrimfallBags]|r Item click debug "
              ..(B.clickDebug and "ON" or "OFF").." - click some bag items, then /gfbags log.")
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
