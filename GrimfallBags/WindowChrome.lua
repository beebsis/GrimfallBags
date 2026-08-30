local B = GrimfallBags

B.ASSETS = "Interface\\AddOns\\GrimfallBags\\Assets\\"

B.PANEL_BD = {
    bgFile=B.ASSETS.."Skins\\dark-backgroundfile",
    edgeFile=B.ASSETS.."Skins\\dark-edgefile",
    tile=true, tileSize=16, edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3},
}

function B.StyleWindow(f)
    if B.SkinWindow(f) then return end
    f:SetBackdrop(B.PANEL_BD)
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.93)
    f:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
end

function B.MakeMovable(f, name)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        local x, y = left, top - UIParent:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        B.Config().pos[name] = {"TOPLEFT", "TOPLEFT", x, y}
    end)
end

local function ToTopLeftOffset(point, x, y, w, h)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if point:find("RIGHT") then x = uw + x - w end
    if point:find("BOTTOM") then y = y + h - uh end
    return x, y
end

function B.RestorePosition(f, name, defaultPoint)
    local p = B.Config().pos[name]
    local point, x, y
    if p then
        point, x, y = p[1], p[3], p[4]
    else
        point, x, y = defaultPoint[1], defaultPoint[4], defaultPoint[5]
    end

    x, y = ToTopLeftOffset(point, x, y, f:GetWidth(), f:GetHeight())
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

function B.MakeResizable(f, name, minWidth, onResize)
    f:SetResizable(true)
    f:SetMinResize(minWidth or 200, 100)
    local grip = CreateFrame("Button", nil, f)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("RIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        B.Config().winWidth[name] = f:GetWidth()
    end)
    if onResize then
        f:SetScript("OnSizeChanged", onResize)
    end
end

function B.RestoreWidth(f, name, defaultWidth)
    f:SetWidth(B.Config().winWidth[name] or defaultWidth)
end

function B.TitleIconButton(parent, icon, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(16); b:SetHeight(16)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = tex
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    B.SkinButton(b)
    return b
end
