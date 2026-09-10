local B = GrimfallBags
local Log = B.Log

local function HideBlizzardBank()
    if B.Config().replaceBank and BankFrame then
        -- Hide() would trigger OnHide -> CloseBankFrame(), ending the bank
        -- interaction server-side, so keep it shown but pin it off-screen.
        local repositioning = false
        local function PushOffscreen(f)
            if repositioning then return end
            repositioning = true
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 10000, 10000)
            repositioning = false
        end
        BankFrame:HookScript("OnShow", PushOffscreen)
        hooksecurefunc(BankFrame, "SetPoint", function(f)
            if not repositioning then PushOffscreen(f) end
        end)
        Log("Blizzard bank moved off-screen")
    end
end

local function BuildBankSlotRow(view, f, transBtn, sortBtn)
    local slotBtns = {}
    local prev
    local numSlots = #B.BANK_BAGS - 1
    for slotNum = 1, numSlots do
        local bag = 4 + slotNum
        local b = CreateFrame("Button", f:GetName().."BagSlot"..bag, f)
        b:SetWidth(28); b:SetHeight(28)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, 1) end
        prev = b
        b.bag = bag
        b.slotNum = slotNum
        local icon = b:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        b.iconTex = icon
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local purchased = GetNumBankSlots() or 0
            if self.slotNum <= purchased then
                GameTooltip:SetInventoryItem("player", ContainerIDToInventoryID(self.bag))
            elseif self.slotNum == purchased + 1 then
                GameTooltip:SetText("Buy Bank Bag Slot")
                local cost = GetBankSlotCost(purchased)
                if cost then SetTooltipMoney(GameTooltip, cost) end
            else
                GameTooltip:SetText("Bank Bag Slot (locked)")
                GameTooltip:AddLine("Purchase the previous slot first.", 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            local purchased = GetNumBankSlots() or 0
            if self.slotNum <= purchased then
                local invID = ContainerIDToInventoryID(self.bag)
                if CursorHasItem() then PutItemInBag(invID)
                else PickupBagFromSlot(invID) end
            elseif self.slotNum == purchased + 1 then
                StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
            end
        end)
        slotBtns[#slotBtns+1] = b
    end

    function view.UpdateBagRow()
        local purchased = GetNumBankSlots() or 0
        for _, b in ipairs(slotBtns) do
            local tex = b.slotNum <= purchased
                and GetInventoryItemTexture("player", ContainerIDToInventoryID(b.bag))
                or nil
            b.iconTex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            if b.slotNum <= purchased then
                b.iconTex:SetDesaturated(not tex)
                b.iconTex:SetAlpha(1)
            elseif b.slotNum == purchased + 1 then
                b.iconTex:SetDesaturated(false)
                b.iconTex:SetAlpha(0.7)
            else
                b.iconTex:SetDesaturated(true)
                b.iconTex:SetAlpha(0.35)
            end
        end
    end
end

function B.BuildBankView()
    local me = UnitName("player")
    local view = B.CreateView("GrimfallBagsBank",
                              me.." - "..(BANK or "Bank"), B.BANK_BAGS)
    B.bankView = view

    B.AddToolbar(view, { isBank = true, buildBagRow = BuildBankSlotRow })

    B.RestorePosition(view.f, "GrimfallBagsBank",
        {"TOPLEFT", UIParent, "TOPLEFT", 50, -104})
    B.RestoreWidth(view.f, "GrimfallBagsBank", B.DefaultViewWidth())

    HideBlizzardBank()
end

function B.OpenBank()
    if not B.bankView then return end
    B.bankView.f:Show()
    B.RefreshView(B.bankView)
end
