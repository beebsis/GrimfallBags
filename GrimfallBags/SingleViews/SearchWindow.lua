local B = GrimfallBags
local S = Syndicator335

local ROW_H    = 22
local MAX_ROWS = 20

local win, content, results
local rows = {}

local BAGS_SRC     = BACKPACK_TOOLTIP or "Bags"
local BANK_SRC     = BANK or "Bank"
local MAIL_SRC     = MAIL_LABEL or "Mail"
local AUCTIONS_SRC = AUCTIONS or "Auctions"

local function SourcePriority(src)
    if src == BAGS_SRC then return 1 end
    if src == BANK_SRC then return 2 end
    if src == MAIL_SRC then return 3 end
    if src == AUCTIONS_SRC then return 4 end
    return 5
end

local function LinkRGB(link)
    local rr, gg, bb = link:match("^|cff(%x%x)(%x%x)(%x%x)")
    if not rr then return 1, 1, 1 end
    return tonumber(rr, 16) / 255, tonumber(gg, 16) / 255, tonumber(bb, 16) / 255
end

local function UpdateVisible(offset)
    if not content then return end
    offset = offset or 0
    local first = math.floor(offset / ROW_H) + 1
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local idx = first + i - 1
        local r = results[idx]
        if r then
            local e = r.entry
            local cr, cg, cb = LinkRGB(e.l)
            row.icon:SetTexture(e.t or select(10, GetItemInfo(e.l or ""))
                                or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.nameFS:SetText(S.ItemName(e.l))
            row.nameFS:SetTextColor(cr, cg, cb)
            row.countFS:SetText((e.c and e.c > 1) and ("x"..e.c) or "")
            row.whereFS:SetText(r.char.."  ("..r.source..")")
            row.link = e.l
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(idx - 1) * ROW_H)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function Build()
    local w = CreateFrame("Frame", "GrimfallBagsSearchWindow", UIParent)
    w:SetWidth(560)
    w:SetHeight(440)
    w:SetPoint("CENTER")
    B.StyleWindow(w)
    w:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "GrimfallBagsSearchWindow")
    B.MakeMovable(w, "SearchWindow")
    w:Hide()
    win = w

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", w, "TOP", 0, -10)
    title:SetText("Search all characters")
    w.title = title

    local countFS = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFS:SetPoint("TOPRIGHT", w, "TOPRIGHT", -30, -12)
    countFS:SetTextColor(0.6, 0.6, 0.6)
    w.count = countFS

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 2, 2)
    B.SkinClose(xb)

    local sf = CreateFrame("ScrollFrame", "GrimfallBagsSearchScroll", w, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -32)
    sf:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -30, 14)
    sf:SetBackdrop(B.PANEL_BD)
    sf:SetBackdropColor(0, 0, 0, 0.35)
    sf:SetBackdropBorderColor(unpack(B.COLOR_BORDER))
    B.SkinScrollBar(_G[sf:GetName().."ScrollBar"])
    w.scroll = sf

    content = CreateFrame("Frame", nil, sf)
    content:SetWidth(496)

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, content)
        row:SetWidth(488)
        row:SetHeight(ROW_H - 2)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.icon = icon

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFS:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameFS:SetWidth(220)
        nameFS:SetJustifyH("LEFT")
        row.nameFS = nameFS

        local countFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countFS:SetPoint("LEFT", nameFS, "RIGHT", 2, 0)
        countFS:SetTextColor(0.7, 0.7, 0.7)
        row.countFS = countFS

        local whereFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        whereFS:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        whereFS:SetTextColor(0.6, 0.6, 0.6)
        whereFS:SetJustifyH("RIGHT")
        row.whereFS = whereFS

        row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        row:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.link then
                ChatEdit_InsertLink(self.link)
            end
        end)

        row:Hide()
        rows[i] = row
    end

    sf:SetScript("OnVerticalScroll", function(self, offset)
        UpdateVisible(offset)
    end)

    return w
end

function B.SearchEverywhere(query)
    query = (query or ""):gsub("^%s*(.-)%s*$", "%1")
    if query == "" then
        print("|cff33aaff[GrimfallBags]|r Type a search term first "
              .."(e.g. |cffffcc66potion|r or |cffffcc66boe & epic|r).")
        return
    end

    local found
    B.Guard("SearchEverywhere", function()
        found = S.Search.Everywhere(query)
    end)
    found = found or {}

    table.sort(found, function(a, b)
        if a.char ~= b.char then return a.char < b.char end
        local pa, pb = SourcePriority(a.source), SourcePriority(b.source)
        if pa ~= pb then return pa < pb end
        return a.source < b.source
    end)

    results = found

    if not win then Build() end
    win.title:SetText("Search all characters")
    win.count:SetText(#results.." hit"..(#results == 1 and "" or "s"))
    content:SetHeight(math.max(1, #results * ROW_H))
    win.scroll:SetScrollChild(content)
    win.scroll:SetVerticalScroll(0)
    UpdateVisible(0)
    win:Show()

    B.Log("SearchEverywhere '"..query.."': "..#results.." hits")
end
