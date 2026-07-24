---@type BFI
local BFI = select(2, ...)
local T = BFI.modules.Tooltip
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local GameTooltip = _G.GameTooltip
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local InCombatLockdown = _G.InCombatLockdown

local NATIVE_STATUS_BAR_HEIGHT = 8

local cursorAnchors = {
    cursor = "ANCHOR_CURSOR",
    cursor_left = "ANCHOR_CURSOR_LEFT",
    cursor_right = "ANCHOR_CURSOR_RIGHT",
}

local oppositePoints = {
    TOP = "BOTTOM",
    TOPLEFT = "BOTTOMLEFT",
    TOPRIGHT = "BOTTOMRIGHT",
    BOTTOM = "TOP",
    BOTTOMLEFT = "TOPLEFT",
    BOTTOMRIGHT = "TOPRIGHT",
    LEFT = "RIGHT",
    RIGHT = "LEFT",
    CENTER = "CENTER",
}

local tooltipAnchor

---------------------------------------------------------------------
-- anchor
---------------------------------------------------------------------
local function GetOwnerConfig(owner)
    if not owner then return end

    if type(owner.tooltip) == "table" then
        return owner.tooltip
    elseif type(owner.tooltipConfig) == "table" then
        return owner.tooltipConfig
    end
end

local function ApplyOwnerAnchor(tooltip, parent)
    local ownerConfig = GetOwnerConfig(parent)
    if not ownerConfig then return false end

    if ownerConfig.enabled == false or (ownerConfig.hideInCombat and InCombatLockdown()) then
        return true
    end

    local anchorTo = ownerConfig.anchorTo
    if anchorTo == "self_adaptive" then
        -- Keep placement inside the native anchor implementation. Reading the
        -- owner's screen geometry in Lua is not safe for restricted frames.
        tooltip:ClearAllPoints()
        tooltip:SetOwner(parent, "ANCHOR_TOP")
        return true
    elseif anchorTo == "self" then
        local position = ownerConfig.position
        if type(position) ~= "table" then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent, position[2], position[3], position[4])
        return true
    elseif anchorTo == "parent" then
        local position = ownerConfig.position
        if type(position) ~= "table" then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent:GetParent(), position[2], position[3], position[4])
        return true
    elseif anchorTo == "root" then
        local position = ownerConfig.position
        if type(position) ~= "table" or not parent.root then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent.root, position[2], position[3], position[4])
        return true
    end

    -- "default" and unknown values use the global BFI tooltip policy.
    return false
end

local function UpdateAnchor(tooltip, parent)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end

    if ApplyOwnerAnchor(tooltip, parent) then return end

    local config = T.config
    if not config or not config.enabled then return end

    local mode = config.anchorMode
    if mode == "default" then
        return
    elseif mode == "fixed" then
        local point = oppositePoints[config.anchorPoint] and config.anchorPoint or "BOTTOMRIGHT"
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, tooltipAnchor, oppositePoints[point])
        return
    end

    local anchorType = cursorAnchors[mode]
    if not anchorType then return end

    parent = parent or AF.UIParent
    tooltip:ClearAllPoints()
    if mode == "cursor" then
        -- ANCHOR_CURSOR intentionally ignores offsets.
        tooltip:SetOwner(parent, anchorType)
    else
        tooltip:SetOwner(parent, anchorType, config.cursorAnchor.x, config.cursorAnchor.y)
    end
end

---------------------------------------------------------------------
-- unit visibility
---------------------------------------------------------------------
local unitTooltipActive

local function OnUnitTooltipPreCall(tooltip)
    local config = T.config
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or not config or not config.enabled then return end

    unitTooltipActive = true

    -- This callback never inspects tooltip data. Blizzard remains the sole
    -- renderer of unit identity, health, and other potentially secret values.
    if config.hideUnitTooltipsInCombat and InCombatLockdown() then
        tooltip:Hide()
        return true
    end
end

local function ClearUnitTooltipState()
    unitTooltipActive = nil
end

local function OnTooltipShow(tooltip)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end

    local owner = tooltip:GetOwner()
    local ownerConfig = GetOwnerConfig(owner)
    if ownerConfig
        and (ownerConfig.enabled == false or (ownerConfig.hideInCombat and InCombatLockdown()))
    then
        tooltip:Hide()
    end
end

local function PLAYER_REGEN_DISABLED()
    if GameTooltip:IsForbidden() then return end

    local owner = GameTooltip:GetOwner()
    local ownerConfig = GetOwnerConfig(owner)
    local hideOwnerTooltip = ownerConfig and ownerConfig.hideInCombat
    local config = T.config
    local hideUnitTooltip = unitTooltipActive
        and config and config.enabled and config.hideUnitTooltipsInCombat

    if hideOwnerTooltip or hideUnitTooltip then
        GameTooltip:Hide()
    end
end

---------------------------------------------------------------------
-- setup
---------------------------------------------------------------------
local initialized
local function Initialize()
    if initialized then return end
    initialized = true

    tooltipAnchor = CreateFrame("Frame", "BFI_TooltipAnchor", AF.UIParent)
    AF.SetSize(tooltipAnchor, 150, 30)
    AF.CreateMover(tooltipAnchor, "BFI: " .. _G.OTHER, L["Tooltip"])

    hooksecurefunc("GameTooltip_SetDefaultAnchor", UpdateAnchor)
    GameTooltip:HookScript("OnShow", OnTooltipShow)
    GameTooltip:HookScript("OnHide", ClearUnitTooltipState)
    GameTooltip:HookScript("OnTooltipCleared", ClearUnitTooltipState)
    TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Unit, OnUnitTooltipPreCall)
    T:RegisterEvent("PLAYER_REGEN_DISABLED", PLAYER_REGEN_DISABLED)
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateTooltip(_, module)
    if module and module ~= "tooltip" then return end

    Initialize()

    local config = T.config
    AF.UpdateMoverSave(tooltipAnchor, config.position)
    AF.LoadPosition(tooltipAnchor, config.position)
    tooltipAnchor.enabled = config.enabled and config.anchorMode == "fixed"
    if not tooltipAnchor.enabled then
        tooltipAnchor.mover:Hide()
    end

    if config.enabled then
        GameTooltipStatusBar:SetAlpha(config.healthBar.enabled and 1 or 0)
        AF.SetHeight(GameTooltipStatusBar, config.healthBar.height)
    else
        GameTooltipStatusBar:SetAlpha(1)
        AF.SetHeight(GameTooltipStatusBar, NATIVE_STATUS_BAR_HEIGHT)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateTooltip)
