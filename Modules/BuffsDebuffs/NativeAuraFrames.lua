---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
local IsValueNonSecret = BFI.funcs.isValueNonSecret

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local hasRestrictedAuraButtons = _G.C_AuraContainerUtil ~= nil

local suppressedStates = {}
local suppressedRoots = {}
local hookedRoots = {}

local function HasExpectedParent(object, expected)
    if not object or type(object.GetParent) ~= "function" then return false end
    local parent = object:GetParent()
    return IsValueNonSecret(parent) and parent == expected
end

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
        if not HasExpectedParent(anchor, frame) then
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
            or not HasExpectedParent(container, frame)
            or not IsVisualControl(collapseButton)
            or not HasExpectedParent(collapseButton, frame)
            or not IsVisualControl(consolidatedBuffs)
            or not HasExpectedParent(consolidatedBuffs, frame)
            or not consolidatedTooltip
            or type(consolidatedTooltip.Hide) ~= "function"
            or type(consolidatedTooltip.GetParent) ~= "function"
            or not HasExpectedParent(consolidatedTooltip, consolidatedBuffs)
            or not consolidatedAuras
            or type(consolidatedAuras.auraFrames) ~= "table"
            or type(consolidatedAuras.GetParent) ~= "function"
            or not IsAuraContainer(consolidatedAuras.AuraContainer)
            or not HasExpectedParent(consolidatedAuras, consolidatedTooltip)
            or not HasExpectedParent(
                consolidatedAuras.AuraContainer,
                consolidatedAuras
            )
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
            or not HasExpectedParent(container, frame)
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
    -- Retail 12.1.0.69273 AuraButtons can deny addon access while aura data is
    -- secret. C_AuraContainerUtil identifies that native path: never enumerate
    -- intrinsic children or install the update hook that would revisit them.
    if hasRestrictedAuraButtons then return end

    local auraFrames = frame.auraFrames
    if type(auraFrames) ~= "table" then return end

    local gameTooltip = _G.GameTooltip
    local helpTip = _G.HelpTip
    for _, button in ipairs(auraFrames) do
        if HasExpectedParent(button, publicParent) then
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

    -- Retail 12.1.0.69273 (wow-ui-source
    -- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) creates the supported public
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
