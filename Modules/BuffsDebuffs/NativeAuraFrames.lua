---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown

local suppressedStates = {}
local suppressedRoots = {}
local hookedRoots = {}

local function IsAuraContainer(frame)
    return frame
        and type(frame.IsShown) == "function"
        and type(frame.Hide) == "function"
        and type(frame.SetShown) == "function"
        and type(frame.GetParent) == "function"
end

local function IsVisualControl(frame)
    return frame
        and type(frame.GetAlpha) == "function"
        and type(frame.SetAlpha) == "function"
        and type(frame.IsMouseEnabled) == "function"
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
        state.target.container:SetShown(state.containerShown)
        for i, control in ipairs(state.target.controls) do
            control:SetAlpha(state.controls[i].alpha)
            control:EnableMouse(state.controls[i].mouseEnabled)
        end

        suppressedStates[which] = nil
        suppressedRoots[state.target.frame] = nil
        return true
    end

    local target = ResolveNativePublicAuraFrame(which)
    if not target then return false end

    -- Retail 12.0.7 and 12.1 keep public aura buttons under these two visual
    -- containers. Private anchors are direct root children and DeadlyDebuffFrame
    -- is separate; neither is touched here.
    state = {
        target = target,
        containerShown = target.container:IsShown(),
        controls = {},
    }
    for i, control in ipairs(target.controls) do
        state.controls[i] = {
            alpha = control:GetAlpha(),
            mouseEnabled = control:IsMouseEnabled(),
        }
    end

    InstallOverlayCleanupHook(target)
    HideTargetOverlays(target)
    target.container:Hide()
    for _, control in ipairs(target.controls) do
        control:SetAlpha(0)
        control:EnableMouse(false)
    end

    suppressedStates[which] = state
    suppressedRoots[target.frame] = state
    return true
end
