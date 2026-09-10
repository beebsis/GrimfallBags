local B = GrimfallBags
local elvSkins

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
    return (B.Config().skin == "elvui") and elvSkins or nil
end

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
