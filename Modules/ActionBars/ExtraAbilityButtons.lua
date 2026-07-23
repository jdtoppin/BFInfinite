---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local AB = BFI.modules.ActionBars
---@type AbstractFramework
local AF = _G.AbstractFramework

local GetBindingKey = GetBindingKey

local ExtraAbilityContainer = _G.ExtraAbilityContainer

local function CaptureLayout(frame)
    local layout = {
        parent = frame:GetParent(),
        points = {},
        frameStrata = frame:GetFrameStrata(),
        frameLevel = frame:GetFrameLevel(),
        ignoreInLayout = frame.ignoreInLayout,
    }
    for i = 1, frame:GetNumPoints() do
        layout.points[i] = {frame:GetPoint(i)}
    end
    return layout
end

local function IsManagedByContainer(frame)
    for _, framePair in ipairs(ExtraAbilityContainer.frames) do
        if framePair.frame == frame then
            return true
        end
    end
end

local function RestoreLayout(frame, layout)
    frame.ignoreInLayout = layout.ignoreInLayout
    frame:SetFrameStrata(layout.frameStrata)
    frame:SetFrameLevel(layout.frameLevel)
    frame:ClearAllPoints()

    if IsManagedByContainer(frame) then
        frame:SetParent(ExtraAbilityContainer)
        ExtraAbilityContainer:MarkDirty()
    else
        frame:SetParent(layout.parent)
        for _, point in ipairs(layout.points) do
            frame:SetPoint(unpack(point))
        end
    end
end

---------------------------------------------------------------------
-- zone ability
---------------------------------------------------------------------
local ZoneAbilityFrame = _G.ZoneAbilityFrame
local zoneAbilityHolder
local zoneAbilityLayout
local zoneAbilityStyleAlpha
local ZoneAbility_UpdateParent, ZoneAbility_UpdateScale, ZoneAbility_UpdateAbility

local function AttachZoneAbility()
    ZoneAbilityFrame:SetParent(zoneAbilityHolder)
    ZoneAbilityFrame:ClearAllPoints()
    ZoneAbilityFrame:SetAllPoints(zoneAbilityHolder)
    ZoneAbilityFrame.ignoreInLayout = true
end

local function CreateZoneAbilityHolder()
    zoneAbilityHolder = CreateFrame("Frame", "BFI_ZoneAbilityHolder", AF.UIParent)
    zoneAbilityHolder:Hide()
    zoneAbilityHolder.enabled = false
    AF.CreateMover(zoneAbilityHolder, "BFI: " .. L["Action Bars"], L["Zone Ability"])

    zoneAbilityLayout = CaptureLayout(ZoneAbilityFrame)
    zoneAbilityStyleAlpha = ZoneAbilityFrame.Style:GetAlpha()
    ZoneAbilityFrame.SpellButtonContainer.holder = zoneAbilityHolder

    hooksecurefunc(ZoneAbilityFrame.SpellButtonContainer, "SetSize", ZoneAbility_UpdateScale)
    hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", ZoneAbility_UpdateAbility)

    hooksecurefunc(ZoneAbilityFrame, "SetParent", function(_, parent)
        if zoneAbilityHolder.enabled and parent ~= zoneAbilityHolder then
            if InCombatLockdown() then
                AB:RegisterEvent("PLAYER_REGEN_ENABLED", ZoneAbility_UpdateParent)
            else
                ZoneAbility_UpdateParent()
            end
        end
    end)

    hooksecurefunc(ZoneAbilityFrame, "SetPoint", function(_, _, relativeTo)
        if zoneAbilityHolder.enabled and relativeTo ~= zoneAbilityHolder then
            if InCombatLockdown() then
                AB:RegisterEvent("PLAYER_REGEN_ENABLED", ZoneAbility_UpdateParent)
            else
                AttachZoneAbility()
            end
        end
    end)
end

function ZoneAbility_UpdateParent()
    AB:UnregisterEvent("PLAYER_REGEN_ENABLED", ZoneAbility_UpdateParent)
    if zoneAbilityHolder.enabled then
        AttachZoneAbility()
    end
end

function ZoneAbility_UpdateScale(_, width, height)
    if zoneAbilityHolder.enabled then
        zoneAbilityHolder:SetSize(width, height)
    end
end

function ZoneAbility_UpdateAbility()
    if not zoneAbilityHolder.enabled then return end

    ZoneAbilityFrame.Style:SetAlpha(zoneAbilityHolder.hideTexture and 0 or 1)

    for spellButton in ZoneAbilityFrame.SpellButtonContainer:EnumerateActive() do
        if spellButton and not spellButton.skinnedByBFI then
            spellButton.skinnedByBFI = true
            spellButton.holder = zoneAbilityHolder

            AB.StylizeButton(spellButton)
            AF.AddToPixelUpdater_Auto(spellButton, nil, true)
        end
    end
end

---------------------------------------------------------------------
-- extra action
---------------------------------------------------------------------
local ExtraActionBarFrame = _G.ExtraActionBarFrame
local extraActionHolder
local extraActionLayout
local ExtraAction_UpdateParent, UpdateExtraActionButton
local extraButtons = {}
local extraButtonStyleAlpha = {}

local function AttachExtraAction()
    ExtraActionBarFrame:SetParent(extraActionHolder)
    ExtraActionBarFrame:ClearAllPoints()
    ExtraActionBarFrame:SetAllPoints(extraActionHolder)
    ExtraActionBarFrame.ignoreInLayout = true
end

local function CreateExtraActionHolder()
    extraActionHolder = CreateFrame("Frame", "BFI_ExtraActionHolder", AF.UIParent)
    extraActionHolder:Hide()
    extraActionHolder.enabled = false
    AF.CreateMover(extraActionHolder, "BFI: " .. L["Action Bars"], L["Extra Action"])

    extraActionLayout = CaptureLayout(ExtraActionBarFrame)

    hooksecurefunc(ExtraActionBarFrame, "SetParent", function(_, parent)
        if extraActionHolder.enabled and parent ~= extraActionHolder then
            if InCombatLockdown() then
                AB:RegisterEvent("PLAYER_REGEN_ENABLED", ExtraAction_UpdateParent)
            else
                ExtraAction_UpdateParent()
            end
        end
    end)

    hooksecurefunc(ExtraActionBarFrame, "SetPoint", function(_, _, relativeTo)
        if extraActionHolder.enabled and relativeTo ~= extraActionHolder then
            if InCombatLockdown() then
                AB:RegisterEvent("PLAYER_REGEN_ENABLED", ExtraAction_UpdateParent)
            else
                AttachExtraAction()
            end
        end
    end)
end

function ExtraAction_UpdateParent()
    AB:UnregisterEvent("PLAYER_REGEN_ENABLED", ExtraAction_UpdateParent)
    if extraActionHolder.enabled then
        AttachExtraAction()
    end
end

function UpdateExtraActionButton()
    local button = ExtraActionBarFrame.button
    if not button.skinnedByBFI then
        button.skinnedByBFI = true
        extraButtons[button] = true
        extraButtonStyleAlpha[button] = button.style:GetAlpha()

        AB.StylizeButton(button)
        button.style:SetDrawLayer("BACKGROUND", -7)

        AF.AddToPixelUpdater_Auto(button, nil, true)

        -- tooltip
        button.tooltip = AB.config.general.tooltip
    end

    button.style:SetAlpha(extraActionHolder.hideTexture and 0 or 1)
    AB.ApplyTextConfig(button.HotKey, extraActionHolder.hotkey)
    button.HotKey:SetText(AB.GetHotkey(GetBindingKey(button.commandName)))
end

local function UpdateExtraActionBinding()
    local button = ExtraActionBarFrame.button
    button.HotKey:SetText(AB.GetHotkey(GetBindingKey(button.commandName)))
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateButton(_, module, which)
    if module and module ~= "actionBars" then return end
    if which and which ~= "extra" then return end

    local enabled = AB.config.general.enabled
    local extraAbilityEnabled = AB.config.extraAbilityButtons.enabled
    local zoneAbilityConfig = AB.config.extraAbilityButtons.zoneAbility
    local extraActionConfig = AB.config.extraAbilityButtons.extraAction

    if not (enabled and extraAbilityEnabled) then
        if zoneAbilityHolder then
            zoneAbilityHolder.enabled = false
            zoneAbilityHolder:Hide()
            AB:UnregisterEvent("PLAYER_REGEN_ENABLED", ZoneAbility_UpdateParent)
            ZoneAbilityFrame.Style:SetAlpha(zoneAbilityStyleAlpha)
            RestoreLayout(ZoneAbilityFrame, zoneAbilityLayout)
        end

        if extraActionHolder then
            extraActionHolder.enabled = false
            extraActionHolder:Hide()
            AB:UnregisterEvent("PLAYER_REGEN_ENABLED", ExtraAction_UpdateParent)
            for button in pairs(extraButtons) do
                button.style:SetAlpha(extraButtonStyleAlpha[button])
            end
            AB:UnregisterEvent("UPDATE_BINDINGS", UpdateExtraActionBinding)
            RestoreLayout(ExtraActionBarFrame, extraActionLayout)
        end
        return
    end

    -- zone ability -----------------------------------------------------
    if not zoneAbilityHolder then
        CreateZoneAbilityHolder()
    end
    zoneAbilityHolder.enabled = true
    zoneAbilityHolder:Show()
    zoneAbilityHolder.hideTexture = zoneAbilityConfig.hideTexture

    AttachZoneAbility()
    AF.UpdateMoverSave(zoneAbilityHolder, zoneAbilityConfig.position)
    AF.LoadPosition(zoneAbilityHolder, zoneAbilityConfig.position)
    zoneAbilityHolder:SetFrameStrata(AB.config.general.frameStrata)
    zoneAbilityHolder:SetFrameLevel(AB.config.general.frameLevel)
    zoneAbilityHolder:SetScale(zoneAbilityConfig.scale)
    zoneAbilityHolder:SetSize(ZoneAbilityFrame.SpellButtonContainer:GetSize())
    ZoneAbilityFrame:SetFrameStrata(AB.config.general.frameStrata)
    ZoneAbilityFrame:SetFrameLevel(AB.config.general.frameLevel + 1)
    ZoneAbility_UpdateAbility()

    -- extra action -----------------------------------------------------
    if not extraActionHolder then
        CreateExtraActionHolder()
    end
    extraActionHolder.enabled = true
    extraActionHolder:Show()
    extraActionHolder.hotkey = extraActionConfig.hotkey
    extraActionHolder.hideTexture = extraActionConfig.hideTexture

    AttachExtraAction()
    AF.UpdateMoverSave(extraActionHolder, extraActionConfig.position)
    AF.LoadPosition(extraActionHolder, extraActionConfig.position)
    extraActionHolder:SetFrameStrata(AB.config.general.frameStrata)
    extraActionHolder:SetFrameLevel(AB.config.general.frameLevel)
    extraActionHolder:SetScale(extraActionConfig.scale)
    extraActionHolder:SetSize(52, 52)
    ExtraActionBarFrame:SetFrameStrata(AB.config.general.frameStrata)
    ExtraActionBarFrame:SetFrameLevel(AB.config.general.frameLevel + 1)
    UpdateExtraActionButton()
    AB:RegisterEvent("UPDATE_BINDINGS", UpdateExtraActionBinding)
end
AF.RegisterCallback("BFI_UpdateModule", UpdateButton)
