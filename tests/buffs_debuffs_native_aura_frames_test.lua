local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function newContainer(parent)
    local container = {
        parent = parent,
        shown = true,
    }

    function container:GetParent()
        return self.parent
    end

    function container:IsShown()
        return self.shown
    end

    function container:Hide()
        self.shown = false
    end

    function container:SetShown(shown)
        self.shown = shown
    end

    return container
end

local function loadAdapter(hasRestrictedAuraButtons)
    local hooks = {}
    _G.C_AuraContainerUtil = hasRestrictedAuraButtons and {} or nil
    _G.InCombatLockdown = function()
        return false
    end
    _G.hooksecurefunc = function(frame, method, callback)
        hooks[frame] = hooks[frame] or {}
        hooks[frame][method] = callback
    end

    local BFI = {
        modules = {
            BuffsDebuffs = {},
        },
    }
    local chunk = assert(loadfile("Modules/BuffsDebuffs/NativeAuraFrames.lua"))
    chunk("BFInfinite", BFI)
    return BFI.modules.BuffsDebuffs, hooks
end

local function newDebuffFrame(button)
    local frame = {
        auraFrames = {button},
    }
    local container = newContainer(frame)
    frame.AuraContainer = container
    frame.PrivateAuraAnchors = {
        {
            GetParent = function()
                return frame
            end,
        },
    }

    function frame:UpdateAuraButtons()
    end

    function frame:IsMouseOver()
        return false
    end

    return frame, container
end

local forbiddenButtonCalls = 0
local forbiddenButton = {
    GetParent = function()
        forbiddenButtonCalls = forbiddenButtonCalls + 1
        error("restricted AuraButton was inspected", 2)
    end,
}

local restrictedAdapter, restrictedHooks = loadAdapter(true)
local restrictedFrame, restrictedContainer = newDebuffFrame(forbiddenButton)
_G.DebuffFrame = restrictedFrame
_G.GameTooltip = {
    IsOwned = function()
        error("restricted AuraButton tooltip owner was inspected", 2)
    end,
    Hide = function()
        error("restricted AuraButton tooltip was hidden by addon code", 2)
    end,
}
_G.HelpTip = {
    HideAll = function()
        error("restricted AuraButton help tip was inspected", 2)
    end,
}

assertEqual(
    restrictedAdapter.CanSuppressNativePublicAuras("debuffs"),
    true,
    "restricted capability"
)
assertEqual(
    restrictedAdapter.SetNativePublicAurasSuppressed("debuffs", true),
    true,
    "restricted suppression"
)
assertEqual(restrictedContainer.shown, false, "restricted container hidden")
assertEqual(forbiddenButtonCalls, 0, "restricted suppression button calls")
assertEqual(
    restrictedHooks[restrictedFrame],
    nil,
    "restricted update hook omitted"
)
assertEqual(
    restrictedAdapter.SetNativePublicAurasSuppressed("debuffs", false),
    true,
    "restricted restoration"
)
assertEqual(restrictedContainer.shown, true, "restricted container restored")
assertEqual(forbiddenButtonCalls, 0, "restricted restoration button calls")

local legacyButtonCalls = 0
local legacyFrame
local legacyContainer
local legacyButton = {
    GetParent = function()
        legacyButtonCalls = legacyButtonCalls + 1
        return legacyContainer
    end,
}
local legacyAdapter, legacyHooks = loadAdapter(false)
legacyFrame, legacyContainer = newDebuffFrame(legacyButton)
_G.DebuffFrame = legacyFrame
local legacyTooltipHides = 0
_G.GameTooltip = {
    IsOwned = function(_, button)
        return button == legacyButton
    end,
    Hide = function()
        legacyTooltipHides = legacyTooltipHides + 1
    end,
}
_G.HelpTip = {
    HideAll = function()
    end,
}

assertEqual(
    legacyAdapter.SetNativePublicAurasSuppressed("debuffs", true),
    true,
    "legacy suppression"
)
assertEqual(legacyButtonCalls, 1, "legacy suppression button calls")
assertEqual(legacyTooltipHides, 1, "legacy tooltip cleanup")
assertEqual(
    type(legacyHooks[legacyFrame].UpdateAuraButtons),
    "function",
    "legacy update hook installed"
)
legacyHooks[legacyFrame].UpdateAuraButtons(legacyFrame)
assertEqual(legacyButtonCalls, 2, "legacy hook button calls")
assertEqual(legacyTooltipHides, 2, "legacy hook tooltip cleanup")

print("buffs/debuffs native aura frame tests passed")
