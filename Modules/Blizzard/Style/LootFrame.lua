---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local LootFrame = _G.LootFrame
local GroupLootHistoryFrame = _G.GroupLootHistoryFrame

---------------------------------------------------------------------
-- shared item rows
---------------------------------------------------------------------
local function StyleItemButton(button)
    if button._BFILootStyled then return end
    button._BFILootStyled = true

    S.StyleSpellItemButton(button)

    local icon = button.icon or button.Icon
    if icon and button.BFIBackdrop then
        AF.SetOnePixelInside(icon, button.BFIBackdrop)
    end
end

local function StyleInteractionTexture(texture, color, alpha, relativeTo)
    if not texture then return end

    texture:SetTexture(AF.GetPlainTexture())
    texture:SetVertexColor(AF.GetColorRGB(color, alpha))
    AF.SetOnePixelInside(texture, relativeTo)
end

---------------------------------------------------------------------
-- loot
---------------------------------------------------------------------
local function StyleLootElement(frame)
    if frame._BFILootElementStyled or not frame.Item then return end
    frame._BFILootElementStyled = true

    frame.NameFrame:SetAlpha(0)
    frame.BorderFrame:SetAlpha(0)
    if frame.QualityStripe then frame.QualityStripe:SetAlpha(0) end

    S.CreateBackdrop(frame, nil, nil, -1)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    StyleInteractionTexture(frame.HighlightNameFrame, "white", 0.08, frame.BFIBackdrop)
    StyleInteractionTexture(frame.PushedNameFrame, "BFI", 0.18, frame.BFIBackdrop)
    StyleItemButton(frame.Item)
end

local function MakeLootFrameMovable()
    -- Blizzard reapplies the Edit Mode anchor after showing LootFrame, while
    -- loot-under-mouse intentionally places it at the cursor. Restore a BFI
    -- title-bar position only when neither of those native paths is active.
    LootFrame._BFIMovableCanRestore = function(frame)
        return not frame.isInEditMode and not GetCVarBool("lootUnderMouse")
    end
    S.MakeMovable(LootFrame, LootFrame.BFIHeader)

    hooksecurefunc(LootFrameMixin, "Open", function(frame)
        S.RestoreMovableFramePosition(frame)
    end)

    -- Entering Edit Mode is an explicit request to use Blizzard's layout
    -- position again, so discard any position previously saved by BFI.
    hooksecurefunc(LootFrame, "OnEditModeEnter", function(frame)
        S.ClearMovableFramePosition(frame)
    end)
end

local function StyleLootFrame()
    S.StyleTitledFrame(LootFrame, false)
    MakeLootFrameMovable()
    S.StyleScrollBar(LootFrame.ScrollBar)

    local upperShadow = LootFrame.ScrollBox:GetUpperShadowTexture()
    local lowerShadow = LootFrame.ScrollBox:GetLowerShadowTexture()
    if upperShadow then upperShadow:SetAlpha(0) end
    if lowerShadow then lowerShadow:SetAlpha(0) end

    hooksecurefunc(LootFrameElementMixin, "Init", StyleLootElement)
    LootFrame:HookScript("OnShow", function(frame)
        frame.ScrollBox:ForEachFrame(StyleLootElement)
    end)
end

---------------------------------------------------------------------
-- /loot history
---------------------------------------------------------------------
local function HistoryElement_OnEnter(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_highlight"))
end

local function HistoryElement_OnLeave(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
end

local function StyleLootHistoryElement(frame)
    if frame._BFILootHistoryElementStyled or not frame.Item then return end
    frame._BFILootHistoryElementStyled = true

    local art = frame.BackgroundArtFrame
    art.NameFrame:SetAlpha(0)
    art.BorderFrame:SetAlpha(0)

    S.CreateBackdrop(frame, nil, nil, -1)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
    frame:HookScript("OnEnter", HistoryElement_OnEnter)
    frame:HookScript("OnLeave", HistoryElement_OnLeave)

    StyleItemButton(frame.Item)
end

local function StyleLootHistoryTimer(timer)
    timer.Background:SetAlpha(0)
    timer.Border:SetAlpha(0)
    timer.Fill:SetTexture(BFI.media.bar)
    timer.Fill:SetVertexColor(AF.GetColorRGB("BFI"))

    S.CreateBackdrop(timer)
    timer.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))
end

local function StyleLootHistoryFrame()
    S.StyleTitledFrame(GroupLootHistoryFrame)
    S.StyleDropdownButton(GroupLootHistoryFrame.EncounterDropdown)
    S.StyleScrollBar(GroupLootHistoryFrame.ScrollBar)
    StyleLootHistoryTimer(GroupLootHistoryFrame.Timer)

    -- Preserve Blizzard's resize scripts while replacing only the grip art.
    S.RemoveTextures(GroupLootHistoryFrame.ResizeButton)
    S.CreateBackdrop(GroupLootHistoryFrame.ResizeButton)
    GroupLootHistoryFrame.ResizeButton.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    hooksecurefunc(LootHistoryElementMixin, "Init", StyleLootHistoryElement)
    GroupLootHistoryFrame:HookScript("OnShow", function(frame)
        frame.ScrollBox:ForEachFrame(StyleLootHistoryElement)
    end)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleLootFrame()
    StyleLootHistoryFrame()
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
