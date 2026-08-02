---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local hasRestrictedAuraButtons = _G.C_AuraContainerUtil ~= nil

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

local function HasRootPrivateAuraAnchors(frame)
    local anchors = frame.PrivateAuraAnchors
    if type(anchors) ~= "table" or #anchors == 0 then return false end

    for _, anchor in ipairs(anchors) do
        if not anchor
            or type(anchor.GetParent) ~= "function"
            or anchor:GetParent() ~= frame
        then
            return false
        end
    end
    return true
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
        if not frame
            or type(frame.UpdateAuraButtons) ~= "function"
            or type(frame.auraFrames) ~= "table"
            or not IsAuraContainer(container)
            or container:GetParent() ~= frame
            or not HasRootPrivateAuraAnchors(frame)
        then
            return
        end

        return {
            frame = frame,
            container = container,
            controls = {},
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

function BD.SetNativePublicAurasSuppressed(which, suppressed)
    if which ~= "buffs" and which ~= "debuffs" then return false end
    suppressed = suppressed == true
    local state = suppressedStates[which]
    if (state ~= nil) == suppressed then return true end
    if InCombatLockdown() then return false end

    if state then
        HideTargetOverlays(state.target)
        state.target.container:SetShown(true)
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

    -- Retail 12.1.0.68914 (UI source d3915c78aba7) creates the supported public
    -- AuraContainerTemplate shown, with these ordinary controls at alpha 1 and
    -- mouse enabled. Keep only a BFI-owned suppression ledger and restore those
    -- known constants; observing visibility, alpha, or mouse state can return
    -- secret values. Private anchors are direct root children and
    -- DeadlyDebuffFrame is separate; neither is touched here.
    state = {target = target}

    InstallOverlayCleanupHook(target)
    HideTargetOverlays(target)
    target.container:SetShown(false)
    for _, control in ipairs(target.controls) do
        control:SetAlpha(0)
        control:EnableMouse(false)
    end

    suppressedStates[which] = state
    suppressedRoots[target.frame] = state
    return true
end
