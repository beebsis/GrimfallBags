---------------------------------------------------------------------------
-- AscensionBags - ElvUI skin
-- Optional cosmetic pass: when ElvUI is installed, match its look instead
-- of our own dark-panel styling. ElvUI mixes SetTemplate/StripTextures
-- onto every Frame's shared metatable at load time, so any frame we
-- create already has :SetTemplate() available - no per-frame setup.
-- Its Skins module additionally exposes a per-widget API (HandleButton,
-- HandleCheckBox, etc.) used below for standard form controls.
--
-- Every B.Skin* function here is a safe no-op when ElvUI isn't installed
-- or the "elvuiSkin" option is off, so call sites never need their own
-- guard. Every ElvUI-touching call is pcall-wrapped - some of these run
-- from inside Views.lua's PLAYER_LOGIN init sequence, and a skin failure
-- there must never be able to cascade into breaking anything else in
-- that sequence.
---------------------------------------------------------------------------
local B = AscensionBags
local elvSkins   -- ElvUI's Skins module, resolved lazily (false = checked, absent)

local function GetElvSkins()
    if elvSkins == nil then
        elvSkins = false
        if IsAddOnLoaded("ElvUI") then
            local ok, mod = pcall(function()
                local E = unpack(ElvUI)
                return E:GetModule("Skins")
            end)
            if ok and mod then elvSkins = mod end
        end
    end
    return B.Config().elvuiSkin and elvSkins or nil
end

-- Calls s[method](s, ...), logging (not printing) on failure so a broken
-- skin call degrades to "unskinned" instead of breaking anything else.
local function TryElvSkin(method, ...)
    local s = GetElvSkins()
    if not s then return false end
    local ok, err = pcall(s[method], s, ...)
    if not ok then
        B.Log("ElvUI skin ("..method.."): "..tostring(err))
        return false
    end
    return true
end

function B.SkinWindow(f)
    local s = GetElvSkins()
    if not s then return false end
    local ok, err = pcall(function()
        f:StripTextures()
        -- No template name -> ElvUI's opaque "Default" backdrop (same
        -- solid panel color/alpha its own top-level windows use, e.g.
        -- its options panel). "Transparent" is meant for nested panels
        -- sitting on top of an already-styled parent, not a standalone
        -- window floating over the game world - using it here is what
        -- made our windows look lighter/washed out instead of matching.
        f:SetTemplate()
    end)
    if not ok then
        B.Log("ElvUI skin (SkinWindow): "..tostring(err))
        return false
    end
    return true
end

function B.SkinButton(b)        TryElvSkin("HandleButton", b) end
function B.SkinCheck(cb)        TryElvSkin("HandleCheckBox", cb) end
function B.SkinEdit(eb)         TryElvSkin("HandleEditBox", eb) end
function B.SkinDropDown(dd, w)  TryElvSkin("HandleDropDownBox", dd, w) end
function B.SkinClose(cb)        TryElvSkin("HandleCloseButton", cb) end
function B.SkinScrollBar(sb)    TryElvSkin("HandleScrollBar", sb) end
function B.SkinSlider(sl)       TryElvSkin("HandleSliderFrame", sl) end
