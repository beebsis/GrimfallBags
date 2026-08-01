---------------------------------------------------------------------------
-- AscensionBags - Window chrome
-- Shared window/widget plumbing: styling, move/resize/position
-- persistence, and the small title-bar icon button factory. Split out of
-- Core.lua for SoC - this is all generic UI chrome, unrelated to config
-- bootstrap or profile logic.
---------------------------------------------------------------------------
local B = AscensionBags

-- Custom art (converted from the PNGs dropped into Assets/ - WotLK only
-- loads .blp/.tga, so those were converted to uncompressed 32-bit TGA;
-- the .tga files already in there were already game-ready).
--
-- IMPORTANT: texture paths are a literal filesystem/virtual-path lookup
-- by the client's renderer, NOT resolved through the addon manager the
-- way .toc file lists or "RequiredDeps: Syndicator335" are - those go
-- through addon-metadata resolution, which can legitimately work with
-- just "Syndicator335" even though it sits a level deeper on disk than
-- a bare Interface\AddOns\ entry would suggest. Textures get no such
-- help: the path has to match the real folder layout on disk under the
-- client root exactly, which here is Interface\AddOns\AscensionBags\
-- Assets\ (a single AscensionBags folder directly under Interface\AddOns\,
-- matching how the addon is actually installed).
B.ASSETS = "Interface\\AddOns\\AscensionBags\\Assets\\"

B.PANEL_BD = {
    bgFile=B.ASSETS.."Skins\\dark-backgroundfile",
    edgeFile=B.ASSETS.."Skins\\dark-edgefile",
    tile=true, tileSize=16, edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3},
}

-- Standard window frame (retail look: flat, dark, thin border) - or, if
-- ElvUI is installed and its skin option is on, ElvUI's own look instead.
function B.StyleWindow(f)
    if B.SkinWindow(f) then return end
    f:SetBackdrop(B.PANEL_BD)
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.93)
    f:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
end

-- Make movable + save/load position
function B.MakeMovable(f, name)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Confirmed via /ascbags posdebug: WoW's own StartMoving/
        -- StopMovingOrSizing re-anchors the frame via CENTER once
        -- dragged, regardless of what point it had before - NOT
        -- preserved as TOPLEFT like the rest of this code assumed.
        -- Left uncorrected, the frame stays CENTER-anchored for the
        -- rest of the session (SetHeight then grows/shrinks symmetrically
        -- from both edges - the reported "jumps both up and down" bug),
        -- and only gets fixed again on the next /reload when
        -- RestorePosition reruns. GetLeft/GetTop ARE reliable here
        -- (unlike at PLAYER_LOGIN on a still-hidden frame) since the
        -- frame has been visible and rendered this whole drag - so
        -- immediately re-anchor the LIVE frame to TOPLEFT too, not just
        -- what gets saved for next login.
        local left, top = self:GetLeft(), self:GetTop()
        local x, y = left, top - UIParent:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        B.Config().pos[name] = {"TOPLEFT", "TOPLEFT", x, y}
    end)
end

-- Normalize any corner-anchored (point, x, y) - all relative to UIParent
-- using the SAME corner as relativePoint, which is how every point this
-- addon uses (saved or default) is expressed - into an equivalent
-- TOPLEFT-relative (x, y). Plain arithmetic, not GetLeft()/GetTop():
-- those resolve through the anchor-layout system and aren't reliable on
-- a frame that hasn't been through a layout pass yet (these windows are
-- still freshly-created and hidden at the point this runs), whereas
-- width/height were just explicitly set by the caller and UIParent's
-- dimensions are always available.
local function ToTopLeftOffset(point, x, y, w, h)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if point:find("RIGHT") then x = uw + x - w end
    if point:find("BOTTOM") then y = y + h - uh end
    return x, y
end

-- Resizing a frame only ever moves the edge OPPOSITE its anchor, so a
-- bottom-anchored window (the original default here) grows/shrinks from
-- the TOP - meaning expanding/collapsing a category (which changes the
-- window's content height on every refresh) visually jumped the whole
-- window instead of just extending past the bottom. Every window is
-- normalized to TOPLEFT here regardless of what corner it was saved or
-- defaulted from, so SetHeight only ever moves the BOTTOM edge from now
-- on. Idempotent - a no-op once a window is already TOPLEFT (which it
-- always will be after its first login post-fix, since MakeMovable's
-- drag-save just persists whatever GetPoint() reports).
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

-- Resizable windows: only WIDTH is user-controlled and persisted -
-- height is always content-driven (rows of items), so we only ever
-- drag-resize horizontally (StartSizing("RIGHT")), then let the
-- caller's own layout recompute height on the next refresh. onResize
-- fires continuously while dragging (for live column reflow) and the
-- final width is only written to SavedVariables on mouse-up.
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

-- Small icon button for title bars.
-- IMPORTANT (3.3.5a): GetNormalTexture() returns nil after
-- SetNormalTexture(path) on this client -> use our own texture.
function B.TitleIconButton(parent, icon, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(20); b:SetHeight(20)

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
