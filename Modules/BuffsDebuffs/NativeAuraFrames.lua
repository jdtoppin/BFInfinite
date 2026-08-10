---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local hasRestrictedAuraButtons = _G.C_AuraContainerUtil ~= nil
local EXPECTED_DEBUFF_PRIVATE_ANCHOR_COUNT = 6

local suppressedStates = {}
local suppressedRoots = {}
local hookedRoots = {}

local function IsAuraContainer(frame)
    return frame
        and type(frame.SetShown) == "function"
        and type(frame.GetParent) == "function"
end

local function IsVisualControl(frame)
    return frame
        and type(frame.SetAlpha) == "function"
        and type(frame.EnableMouse) == "function"
        and type(frame.GetParent) == "function"
end

local function ResolveRootPrivateAuraAnchors(frame)
    local anchors = frame.PrivateAuraAnchors
    if type(anchors) ~= "table" then return end

    local anchorCount = 0
    for key in pairs(anchors) do
        if type(key) ~= "number"
            or key % 1 ~= 0
            or key < 1
            or key > EXPECTED_DEBUFF_PRIVATE_ANCHOR_COUNT
        then
            return
        end
        anchorCount = anchorCount + 1
    end
    if anchorCount ~= EXPECTED_DEBUFF_PRIVATE_ANCHOR_COUNT then return end

    local resolved = {}
    for index = 1, EXPECTED_DEBUFF_PRIVATE_ANCHOR_COUNT do
        local anchor = anchors[index]
        if not anchor
            or frame["privateAuraAnchor" .. index] ~= anchor
            or type(anchor.GetParent) ~= "function"
            or type(anchor.SetShown) ~= "function"
            or anchor:GetParent() ~= frame
        then
            return
        end
        resolved[#resolved + 1] = anchor
    end
    return resolved
end

local function ResolveNativePublicAuraFrame(which)
    if type(hooksecurefunc) ~= "function" then return end

    if which == "buffs" then
        local frame = _G.BuffFrame
        local container = frame and frame.AuraContainer
        local collapseButton = frame and frame.CollapseAndExpandButton
        local consolidatedBuffs = frame and frame.ConsolidatedBuffs
        local consolidatedTooltip = consolidatedBuffs and consolidatedBuffs.Tooltip
        local consolidatedAuras = consolidatedTooltip and consolidatedTooltip.Auras

        if not frame
            or type(frame.UpdateAuraButtons) ~= "function"
            or type(frame.auraFrames) ~= "table"
            or not IsAuraContainer(container)
            or container:GetParent() ~= frame
            or not IsVisualControl(collapseButton)
            or collapseButton:GetParent() ~= frame
            or not IsVisualControl(consolidatedBuffs)
            or consolidatedBuffs:GetParent() ~= frame
            or not consolidatedTooltip
            or type(consolidatedTooltip.Hide) ~= "function"
            or type(consolidatedTooltip.GetParent) ~= "function"
            or consolidatedTooltip:GetParent() ~= consolidatedBuffs
            or not consolidatedAuras
            or type(consolidatedAuras.auraFrames) ~= "table"
            or type(consolidatedAuras.GetParent) ~= "function"
            or not IsAuraContainer(consolidatedAuras.AuraContainer)
            or consolidatedAuras:GetParent() ~= consolidatedTooltip
            or consolidatedAuras.AuraContainer:GetParent() ~= consolidatedAuras
        then
            return
        end

        return {
            frame = frame,
            container = container,
            controls = {collapseButton, consolidatedBuffs},
            consolidatedTooltip = consolidatedTooltip,
            consolidatedAuras = consolidatedAuras,
        }
    elseif which == "debuffs" then
        local frame = _G.DebuffFrame
        local container = frame and frame.AuraContainer
        local privateAuraAnchors = frame
            and ResolveRootPrivateAuraAnchors(frame)
        if not frame
            or type(frame.UpdateAuraButtons) ~= "function"
            or type(frame.auraFrames) ~= "table"
            or not IsAuraContainer(container)
            or container:GetParent() ~= frame
            or not privateAuraAnchors
        then
            return
        end

        return {
            frame = frame,
            container = container,
            controls = {},
            privateAuraAnchors = privateAuraAnchors,
        }
    end
end

local function HidePublicAuraOverlays(frame, publicParent)
    -- Retail 12.1's intrinsic AuraButton type denies tainted access whenever
    -- aura data is secret. This shared suppression path does not assume which
    -- child type a native container owns, so it never enumerates 12.1
    -- children. BlizzardDebuffs.lua separately validates and styles only the
    -- pinned Blizzard_BuffFrame ordinary Button pool, outside combat.
    if hasRestrictedAuraButtons then return end

    local auraFrames = frame.auraFrames
    if type(auraFrames) ~= "table" then return end

    local gameTooltip = _G.GameTooltip
    local helpTip = _G.HelpTip
    for _, button in ipairs(auraFrames) do
        if button
            and type(button.GetParent) == "function"
            and button:GetParent() == publicParent
        then
            if gameTooltip and gameTooltip:IsOwned(button) then
                gameTooltip:Hide()
            end
            if helpTip and type(helpTip.HideAll) == "function" then
                helpTip:HideAll(button)
            end
        end
    end
end

local function HideTargetOverlays(target)
    HidePublicAuraOverlays(target.frame, target.container)
    if target.consolidatedAuras then
        HidePublicAuraOverlays(target.consolidatedAuras, target.consolidatedAuras.AuraContainer)
        target.consolidatedTooltip:Hide()
    end
end

local function ApplySuppressedConstants(target)
    HideTargetOverlays(target)
    target.container:SetShown(false)
    for _, anchor in ipairs(target.privateAuraAnchors or {}) do
        anchor:SetShown(false)
    end
    for _, control in ipairs(target.controls) do
        control:SetAlpha(0)
        control:EnableMouse(false)
    end
end

local function InstallOverlayCleanupHook(target)
    if hasRestrictedAuraButtons then return end

    local frame = target.frame
    if hookedRoots[frame] then return end

    hooksecurefunc(frame, "UpdateAuraButtons", function(updatedFrame)
        local state = suppressedRoots[updatedFrame]
        if state then
            HideTargetOverlays(state.target)
        end
    end)
    hookedRoots[frame] = true
end

function BD.CanSuppressNativePublicAuras(which)
    return ResolveNativePublicAuraFrame(which) ~= nil
end

function BD.AreNativePublicAurasSuppressed(which)
    return suppressedStates[which] ~= nil
end

function BD.ReassertNativePublicAuraSuppression(which)
    if InCombatLockdown() then return false end
    local state = suppressedStates[which]
    if not state then return false end

    -- AuraFrameEditModeMixin explicitly shows all six private anchors when
    -- Edit Mode ends. Reapply the same write-only constants on the queued
    -- lifecycle tick; never inspect whether Blizzard changed visibility.
    ApplySuppressedConstants(state.target)
    return true
end

function BD.SuspendNativePublicAuraSuppressionForEditMode(which)
    if InCombatLockdown() then return false end
    local state = suppressedStates[which]
    if not state then return false end

    HideTargetOverlays(state.target)
    state.target.container:SetShown(true)
    -- Blizzard's Edit Mode preview hides private anchors while showing its
    -- ordinary example buttons. Preserve that write-only lifecycle constant
    -- regardless of callback ordering.
    for _, anchor in ipairs(state.target.privateAuraAnchors or {}) do
        anchor:SetShown(false)
    end
    for _, control in ipairs(state.target.controls) do
        control:SetAlpha(1)
        control:EnableMouse(true)
    end

    suppressedStates[which] = nil
    suppressedRoots[state.target.frame] = nil
    return true
end

function BD.SetNativePublicAurasSuppressed(which, suppressed)
    if which ~= "buffs" and which ~= "debuffs" then return false end
    suppressed = suppressed == true
    local state = suppressedStates[which]
    if (state ~= nil) == suppressed then return true end
    if InCombatLockdown() then return false end

    if state then
        HideTargetOverlays(state.target)
        state.target.container:SetShown(true)
        for _, anchor in ipairs(state.target.privateAuraAnchors or {}) do
            anchor:SetShown(true)
        end
        for _, control in ipairs(state.target.controls) do
            control:SetAlpha(1)
            control:EnableMouse(true)
        end

        suppressedStates[which] = nil
        suppressedRoots[state.target.frame] = nil
        return true
    end

    local target = ResolveNativePublicAuraFrame(which)
    if not target then return false end

    -- Retail 12.1.0.69189 (UI source a520b6c27bb8) creates the supported public
    -- AuraContainerTemplate and the six DebuffFrame private-aura anchors shown,
    -- with the ordinary Buff controls at alpha 1 and mouse enabled. Keep only a
    -- BFI-owned suppression ledger and restore those known constants; observing
    -- visibility, alpha, or mouse state can return secret values.
    -- DeadlyDebuffFrame is separate and remains untouched.
    state = {target = target}

    InstallOverlayCleanupHook(target)
    ApplySuppressedConstants(target)

    suppressedStates[which] = state
    suppressedRoots[target.frame] = state
    return true
end
