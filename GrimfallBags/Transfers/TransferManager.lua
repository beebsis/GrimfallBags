local B = GrimfallBags

B.TransferManager = {}

StaticPopupDialogs["GFBAGS_GB_DEPOSIT"] = {
    text = (GUILDBANK_DEPOSIT_BUTTON or "Deposit").." (Gold):",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 8,
    OnAccept = function(self)
        local g = tonumber(_G[self:GetName().."EditBox"]:GetText())
        if g and g > 0 then B.GuildBankAPI.DepositMoney(g * 10000) end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GFBAGS_GB_WITHDRAW"] = {
    text = (GUILDBANK_WITHDRAW_BUTTON or "Withdraw").." (Gold):",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 8,
    OnAccept = function(self)
        local g = tonumber(_G[self:GetName().."EditBox"]:GetText())
        if g and g > 0 then B.GuildBankAPI.WithdrawMoney(g * 10000) end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function B.TransferManager.ShowDeposit()
    StaticPopup_Show("GFBAGS_GB_DEPOSIT")
end

function B.TransferManager.ShowWithdraw()
    StaticPopup_Show("GFBAGS_GB_WITHDRAW")
end
