local B = GrimfallBags

-- A docked panel on the left edge of the backpack window listing every
-- currency the player has flagged "Show on Backpack" in Blizzard's own
-- Currency tab (see GetWatchedCurrencies in Views.lua) -- the same set
-- already driving the compact bottom-row icons, just shown as a proper
-- name+count list instead of icon-only. Parented to bagView.f (not just
-- anchored to it) so it shows/hides/moves together with the backpack
-- window automatically, without needing separate visibility hooks.
-- Off by default (cfg.showCurrencyPanel) and toggled from the toolbar,
-- same pattern as the bag-slot row toggle right next to it.

local PANEL_WIDTH = 170
local ROW_HEIGHT = 20
local ROW_GAP = 4
local PAD = 8

local panel
local rows = {}

local function EnsurePanel()
    if panel then
        return panel
    end
    local view = B.bagView
    if not view or not view.f then
        return nil
    end

    local p = CreateFrame("Frame", "GrimfallBagsCurrencyPanel", view.f)
    p:SetWidth(PANEL_WIDTH)
    p:SetHeight(60)
    p:SetPoint("TOPRIGHT", view.f, "TOPLEFT", -4, 0)
    B.StyleWindow(p)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", p, "TOP", 0, -(PAD - 2))
    p.title:SetText(CURRENCY or "Currency")

    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.empty:SetPoint("TOP", p.title, "BOTTOM", 0, -10)
    p.empty:SetPoint("LEFT", p, "LEFT", PAD, 0)
    p.empty:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    p.empty:SetJustifyH("CENTER")
    p.empty:SetText("No tracked currencies -- right-click one in Blizzard's Currency tab and check \"Show on Backpack\".")

    p:Hide()
    panel = p
    return p
end

local function AcquireRow(index)
    local r = rows[index]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, panel)
    r:SetHeight(ROW_HEIGHT)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)

    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.count:SetJustifyH("RIGHT")

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
    r.name:SetJustifyH("LEFT")

    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.currencyName, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[index] = r
    return r
end

function B.RefreshCurrencyPanel()
    local p = EnsurePanel()
    if not p then
        return
    end

    local list = B.GetWatchedCurrencies and B.GetWatchedCurrencies() or {}
    p.empty:SetShown(#list == 0)

    local prevAnchor
    for i, cur in ipairs(list) do
        local r = AcquireRow(i)
        r.icon:SetTexture(cur.icon)
        r.name:SetText(cur.name)
        r.count:SetText(cur.count)
        r.currencyName = cur.name

        r:ClearAllPoints()
        r:SetPoint("LEFT", p, "LEFT", PAD, 0)
        r:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
        if prevAnchor then
            r:SetPoint("TOP", prevAnchor, "BOTTOM", 0, -ROW_GAP)
        else
            r:SetPoint("TOP", p.title, "BOTTOM", 0, -10)
        end
        r:Show()
        prevAnchor = r
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end

    local contentHeight = (#list == 0) and 30 or (#list * (ROW_HEIGHT + ROW_GAP))
    p:SetHeight(30 + 10 + contentHeight + PAD)
end

function B.ToggleCurrencyPanel()
    local p = EnsurePanel()
    if not p then
        return
    end
    local cfg = B.Config()
    cfg.showCurrencyPanel = not cfg.showCurrencyPanel
    if cfg.showCurrencyPanel then
        B.RefreshCurrencyPanel()
        p:Show()
    else
        p:Hide()
    end
end

function B.InitCurrencyPanel()
    local p = EnsurePanel()
    if not p then
        return
    end
    if B.Config().showCurrencyPanel then
        B.RefreshCurrencyPanel()
        p:Show()
    end
end

-- Toggling "Show on Backpack" in Blizzard's own Currency tab context menu
-- (TokenFramePopup) calls SetCurrencyBackpack() directly -- confirmed
-- live, CURRENCY_DISPLAY_UPDATE doesn't reliably fire for that specific
-- change, only for amount changes, so the panel/bottom row were only
-- ever catching up on the next window open. Hooking the Blizzard
-- function itself guarantees a refresh exactly when the checkbox
-- changes, regardless of what event (if any) accompanies it.
if type(SetCurrencyBackpack) == "function" then
    hooksecurefunc("SetCurrencyBackpack", function()
        if B.RefreshCurrencyRow and B.bagView then
            B.RefreshCurrencyRow(B.bagView)
        end
        B.RefreshCurrencyPanel()
    end)
end
