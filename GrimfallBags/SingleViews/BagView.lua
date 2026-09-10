local B = GrimfallBags
local S = Syndicator335
local Log, Guard = B.Log, B.Guard

-- Recent-item state (backpack-only tracking; bank bags share item IDs but
-- must not be flagged "New" from a bag<->bank transfer).
local recentItems = {}
local baseline    = {}

local function LoadRecentState()
    local cfg = B.Config()
    cfg.newState = cfg.newState or {}
    local key = Syndicator335.CharKey()
    local st = cfg.newState[key]
    if not st then
        st = {baseline = {}, recent = {}}
        cfg.newState[key] = st
    end
    baseline    = st.baseline
    recentItems = st.recent
end
B.LoadRecentState = LoadRecentState

local function CountBagItems()
    local t = {}
    for _, bag in ipairs(B.PLAYER_BAGS) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            local id = S.ItemID(link)
            if id then
                local _, cnt = GetContainerItemInfo(bag, slot)
                t[id] = (t[id] or 0) + (cnt or 1)
            end
        end
    end
    return t
end

local function UpdateRecent()
    local counts = CountBagItems()
    if next(baseline) == nil then
        for id, cnt in pairs(counts) do baseline[id] = cnt end
        return
    end
    for id, cnt in pairs(counts) do
        if cnt > (baseline[id] or 0) then
            recentItems[id] = time() + B.Config().recentSecs
        end
        baseline[id] = cnt
    end
end
B.UpdateRecent = UpdateRecent

local function IsRecent(id)
    local exp = id and recentItems[id]
    return exp and exp > time()
end

-- "Recent" only tracks backpack counts; a bank copy of the same item ID
-- would otherwise get flagged "New" just from moving it between bag/bank.
local function IsRecentInBag(id, bag)
    return bag >= 0 and bag <= 4 and IsRecent(id)
end
B.IsRecentInBag = IsRecentInBag

local function ExpireRecent()
    local now, changed = time(), false
    for id, exp in pairs(recentItems) do
        if exp <= now then recentItems[id] = nil; changed = true end
    end
    return changed
end
B.ExpireRecent = ExpireRecent

local function GetWatchedCurrencies()
    local list = {}
    for i = 1, GetCurrencyListSize() do
        local name, isHeader, _, _, isWatched, count, _, icon = GetCurrencyListInfo(i)
        if not isHeader and isWatched then
            list[#list+1] = {name = name, count = count, icon = icon, index = i}
        end
    end
    return list
end
B.GetWatchedCurrencies = GetWatchedCurrencies

local function RefreshCurrencyRow(view)
    if not view.moneyText then return end
    view.currencyPairs = view.currencyPairs or {}
    local list = GetWatchedCurrencies()
    local prevAnchor = view.moneyText

    for i, cur in ipairs(list) do
        local pair = view.currencyPairs[i]
        if not pair then
            pair = CreateFrame("Button", nil, view.f)
            pair:SetHeight(16)
            local icon = pair:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("RIGHT", pair, "RIGHT", 0, 0)
            pair.icon = icon
            local txt = pair:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("RIGHT", icon, "LEFT", -2, 0)
            pair.txt = txt
            pair:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.currencyName, 1, 0.82, 0)
                GameTooltip:AddLine(tostring(self.currencyCount), 1, 1, 1)
                GameTooltip:Show()
            end)
            pair:SetScript("OnLeave", function() GameTooltip:Hide() end)
            view.currencyPairs[i] = pair
        end
        pair.icon:SetTexture(cur.icon)
        pair.txt:SetText(cur.count)
        pair.currencyName = cur.name
        pair.currencyCount = cur.count
        pair:SetWidth(14 + 2 + pair.txt:GetStringWidth() + 6)
        pair:ClearAllPoints()
        pair:SetPoint("RIGHT", prevAnchor, "LEFT", -8, 0)
        pair:Show()
        prevAnchor = pair
    end
    for i = #list + 1, #view.currencyPairs do
        view.currencyPairs[i]:Hide()
    end
end
B.RefreshCurrencyRow = RefreshCurrencyRow

-- Toggling "Show on Backpack" in Blizzard's own Currency tab context menu
-- (TokenFramePopup) calls SetCurrencyBackpack() directly -- confirmed
-- live, CURRENCY_DISPLAY_UPDATE doesn't reliably fire for that specific
-- change, only for amount changes, so the bottom currency row was only
-- ever catching up on the next window open. Hooking the Blizzard
-- function itself guarantees a refresh exactly when the checkbox
-- changes, regardless of what event (if any) accompanies it.
if type(SetCurrencyBackpack) == "function" then
    hooksecurefunc("SetCurrencyBackpack", function()
        if B.bagView then B.RefreshCurrencyRow(B.bagView) end
    end)
end

local function CollectAllTransmog()
    for _, bag in ipairs(B.PLAYER_BAGS) do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local itemID = GetContainerItemID(bag, slot)
            if itemID then
                local quality = select(3, GetItemInfo(itemID))
                if quality and quality < 5 then
                    C_AppearanceCollection.CollectItemAppearance(GetContainerItemGUID(bag, slot))
                end
            end
        end
    end
    B.WipeTmogCache()
    B.RefreshAll()
end

local function BuildCharMenu(view, f)
    local charMenu = CreateFrame("Frame", "GrimfallBagsCharMenu", UIParent, "UIDropDownMenuTemplate")
    local charBtn = B.TitleIconButton(f, B.ASSETS.."All_Characters",
        "Characters: view bags/bank offline", function()
            local myKey = S.CharKey()
            -- Only list characters from the current realm; keys from other
            -- (e.g. test) servers end in a different realm suffix.
            local suffix = " - "..GetRealmName()
            local menu = {
                {text = "Characters", isTitle = true, notCheckable = true},
                {text = myKey.."  |cff33ff33(live)|r", notCheckable = true,
                 func = function() view.offline = nil; B.RefreshView(view) end},
            }
            for _, key in ipairs(S.API.GetAllCharacters()) do
                if key:sub(-#suffix) == suffix then
                    local c = S.API.GetCharacter(key)
                    local color = "|cffcccccc"
                    local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
                    if cc then
                        color = string.format("|cff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255)
                    end
                    if key ~= myKey then
                        menu[#menu+1] = {text = color..key.."|r - Bag", notCheckable = true,
                            func = function()
                                view.offline = {key = key, which = "bags"}
                                B.RefreshView(view)
                            end}
                    end
                    if c.bank then
                        menu[#menu+1] = {text = color..key.."|r - "..(BANK or "Bank"), notCheckable = true,
                            func = function()
                                view.offline = {key = key, which = "bank"}
                                B.RefreshView(view)
                            end}
                    end
                end
            end
            EasyMenu(menu, charMenu, "cursor", 0, 0, "MENU")
        end)
    charBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2, -(PAD - 2))
end

local function BuildBagSlotRow(view, f, transBtn, sortBtn)
    local slotBtns = {}
    local prev
    for _, bag in ipairs(B.PLAYER_BAGS) do
        local b = CreateFrame("Button", f:GetName().."BagSlot"..bag, f)
        b:SetWidth(28); b:SetHeight(28)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, 1) end
        prev = b
        b.bag = bag
        local icon = b:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        b.iconTex = icon
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if self.bag == 0 then
                GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack")
            else
                GameTooltip:SetInventoryItem("player", ContainerIDToInventoryID(self.bag))
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.bag == 0 then return end
            local invID = ContainerIDToInventoryID(self.bag)
            if CursorHasItem() then PutItemInBag(invID)
            else PickupBagFromSlot(invID) end
        end)
        b:Hide()
        slotBtns[#slotBtns+1] = b
    end

    function view.UpdateBagRow()
        local shown = B.Config().showBagRow
        for _, b in ipairs(slotBtns) do
            if shown then
                b:Show()
                if b.bag == 0 then
                    b.iconTex:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
                else
                    local tex = GetInventoryItemTexture("player", ContainerIDToInventoryID(b.bag))
                    b.iconTex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                    b.iconTex:SetDesaturated(not tex)
                end
            else
                b:Hide()
            end
        end
    end

    local bagsBtn = B.TitleIconButton(f, B.ASSETS.."Bags",
        "Show/hide bag slots", function()
            local cfg = B.Config()
            cfg.showBagRow = not cfg.showBagRow
            view.UpdateBagRow()
        end)

    -- transBtn is hidden by default (Transfers.lua shows it only at
    -- a merchant/bank with matching items) but its anchor slot is
    -- always reserved, which left a visible gap in the toolbar
    -- whenever it wasn't shown. Reflow bagsBtn onto sortBtn directly
    -- when transBtn is hidden, and back onto transBtn when it
    -- reappears, instead of always reserving its space.
    local function RelayoutBagsBtn()
        bagsBtn:ClearAllPoints()
        if transBtn:IsShown() then
            bagsBtn:SetPoint("RIGHT", transBtn, "LEFT", -3, 0)
        else
            bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -3, 0)
        end
    end
    RelayoutBagsBtn()
    view.RelayoutBagsBtn = RelayoutBagsBtn

    return bagsBtn
end

local function OpenBags()
    if not B.bagView then return end
    B.bagView.f:Show()
    B.RefreshView(B.bagView)
end
local function CloseBags()
    if B.bagView then B.bagView.f:Hide() end
end
function B.ToggleBags()
    if not B.bagView then return end
    if B.bagView.f:IsShown() then CloseBags() else OpenBags() end
end
B.OpenBags = OpenBags

function B.FocusSearch()
    if not B.bagView then return end
    OpenBags()
    if B.bagView.searchBox then B.bagView.searchBox:SetFocus() end
end

-- Map Blizzard's bag keybinds to the unified window. OpenAllBags must OPEN
-- (not toggle), otherwise a script/binding calling OpenAllBags() would close
-- an already-open window. Per-bag ToggleBag(id) is intentionally flattened to
-- the one unified window (a unified bag addon has no "just bag 2" window).
local function HookBagFunctions()
    if not B.Config().replaceBags then return end
    local hooks = {
        ToggleBackpack = B.ToggleBags,
        OpenBackpack   = OpenBags,
        CloseBackpack  = CloseBags,
        OpenAllBags    = OpenBags,
        CloseAllBags   = CloseBags,
        ToggleBag      = B.ToggleBags,
    }
    for name, fn in pairs(hooks) do
        if _G[name] ~= fn then _G[name] = fn end
    end
end
B.HookBagFunctions = HookBagFunctions

-- Re-assert the globals periodically so ElvUI's bag module (or a late-loading
-- addon) can't steal them after PLAYER_ENTERING_WORLD. Cheap: six comparisons
-- every 2s, reassigning only what was overwritten. Start only after
-- PLAYER_LOGIN so a saved replaceBags=false (the ElvUI "Keep ElvUI's" opt-out)
-- isn't stomped during the load window when the saved config isn't available.
local reassert = CreateFrame("Frame")
reassert:Hide()
reassert:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 2 then return end
    self.t = 0
    HookBagFunctions()
end)
reassert:RegisterEvent("PLAYER_LOGIN")
reassert:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        self:SetScript("OnEvent", nil)
        self:Show()
    end
end)

function B.BuildBagView()
    local me = UnitName("player")
    local view = B.CreateView("GrimfallBagsBackpack",
                              me.." - "..(BACKPACK_TOOLTIP or "Backpack"), B.PLAYER_BAGS)
    B.bagView = view

    B.AddToolbar(view, {
        isBank = false,
        buildCharMenu = BuildCharMenu,
        buildBagRow = BuildBagSlotRow,
    })

    B.RefreshCurrencyRow(view)

    B.RestorePosition(view.f, "GrimfallBagsBackpack",
        {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100})
    B.RestoreWidth(view.f, "GrimfallBagsBackpack", B.DefaultViewWidth())

    HookBagFunctions()
end
