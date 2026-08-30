local S = Syndicator335

local SOURCE_LABELS = {
    bags     = BACKPACK_TOOLTIP or "Bags",
    bank     = BANK or "Bank",
    mail     = MAIL_LABEL or "Mail",
    equipped = STATUS_TEXT_TARGET and "Equipped" or "Equipped",
    auctions = AUCTIONS or "AH",
}
SOURCE_LABELS.equipped = EQUIPPED or "Equipped"

local SOURCE_ORDER = {"bags", "bank", "mail", "equipped", "auctions"}

local function AddCounts(tt)
    local _, link = tt:GetItem()
    local id = S.ItemID(link)
    if not id then return end

    local shown = false
    local total = 0

    for _, key in ipairs(S.API.GetAllCharacters()) do
        local c = S.Data().chars[key]
        local counts = c.counts and c.counts[id]
        if counts then
            local parts, sum = {}, 0
            for _, src in ipairs(SOURCE_ORDER) do
                local n = counts[src]
                if n and n > 0 then
                    parts[#parts+1] = SOURCE_LABELS[src]..": "..n
                    sum = sum + n
                end
            end
            if sum > 0 then
                local r, g, b = 0.35, 0.7, 1
                local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
                if cc then r, g, b = cc.r, cc.g, cc.b end
                local shortName = key:match("^(.-) %- ") or key
                tt:AddDoubleLine(shortName, table.concat(parts, ", "),
                                 r, g, b, 0.8, 0.8, 0.8)
                shown = true
                total = total + sum
            end
        end
    end

    for _, key in ipairs(S.API.GetAllGuilds()) do
        local g = S.Data().guilds[key]
        local n = g.counts and g.counts[id]
        if n and n > 0 then
            local shortName = key:match("^(.-) %- ") or key
            tt:AddDoubleLine("<"..shortName..">", (GUILD_BANK or "Guild Bank")..": "..n,
                             0.25, 0.9, 0.4, 0.8, 0.8, 0.8)
            shown = true
            total = total + n
        end
    end

    if shown and total > 0 then
        tt:AddDoubleLine(TOTAL or "Total", total, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        tt:Show()
    end
end

local hooked = {}
local function HookTooltip(tt)
    if tt and not hooked[tt] then
        hooked[tt] = true
        tt:HookScript("OnTooltipSetItem", function(self)
            S.Guard("TooltipCounts", AddCounts, self)
        end)
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
    S.Log("Tooltips hooked")
    print("|cff33aaff[Syndicator335]|r loaded - tracking + tooltips active.")
end)
