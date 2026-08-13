local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertWrites(actual, expected, message)
    assertEqual(#actual, #expected, message .. " count")
    for index, value in ipairs(expected) do
        assertEqual(actual[index], value, message .. " #" .. index)
    end
end

local function ForbiddenObserver(label)
    return function()
        error(label .. " observer must not be called", 2)
    end
end

local secretParents = {}
local secretEqualityCalls = 0

local function IsValueNonSecret(value)
    for _, secret in ipairs(secretParents) do
        if rawequal(value, secret) then
            return false
        end
    end
    return true
end

local function SetSecretParent(object, expected)
    local equalityTrap = {
        __eq = function()
            secretEqualityCalls = secretEqualityCalls + 1
            error("secret parent must be gated before equality", 2)
        end,
    }
    setmetatable(expected, equalityTrap)
    local secret = setmetatable({}, equalityTrap)
    secretParents[#secretParents + 1] = secret
    function object:GetParent()
        return secret
    end
end

local function NewContainer(parent, label)
    local container = {
        shown = true,
        shownWrites = {},
        GetAlpha = ForbiddenObserver(label .. ":GetAlpha"),
        Hide = ForbiddenObserver(label .. ":Hide"),
        IsMouseEnabled = ForbiddenObserver(label .. ":IsMouseEnabled"),
        IsMouseOver = ForbiddenObserver(label .. ":IsMouseOver"),
        IsShown = ForbiddenObserver(label .. ":IsShown"),
    }

    function container:GetParent()
        return parent
    end

    function container:SetShown(shown)
        self.shown = shown
        self.shownWrites[#self.shownWrites + 1] = shown
    end

    return container
end

local function NewControl(parent, label)
    local control = {
        alpha = 1,
        alphaWrites = {},
        mouseEnabled = true,
        mouseWrites = {},
        GetAlpha = ForbiddenObserver(label .. ":GetAlpha"),
        IsMouseEnabled = ForbiddenObserver(label .. ":IsMouseEnabled"),
        IsMouseOver = ForbiddenObserver(label .. ":IsMouseOver"),
        IsShown = ForbiddenObserver(label .. ":IsShown"),
    }

    function control:GetParent()
        return parent
    end

    function control:SetAlpha(alpha)
        self.alpha = alpha
        self.alphaWrites[#self.alphaWrites + 1] = alpha
    end

    function control:EnableMouse(enabled)
        self.mouseEnabled = enabled
        self.mouseWrites[#self.mouseWrites + 1] = enabled
    end

    return control
end

local function NewAuraButton(parent, label)
    local button = {
        IsMouseOver = ForbiddenObserver(label .. ":IsMouseOver"),
        IsShown = ForbiddenObserver(label .. ":IsShown"),
    }

    function button:GetParent()
        return parent
    end

    return button
end

local function NewUntouchableFrame(parent, label)
    local frame = {
        mutationCount = 0,
    }

    function frame:GetParent()
        return parent
    end

    local function rejectMutation()
        frame.mutationCount = frame.mutationCount + 1
        error(label .. " must not be mutated", 2)
    end

    frame.EnableMouse = rejectMutation
    frame.Hide = rejectMutation
    frame.SetAlpha = rejectMutation
    frame.SetShown = rejectMutation
    frame.Show = rejectMutation
    return frame
end

local function NewBuffFrame()
    local frame = {
        auraFrames = {},
    }
    function frame:UpdateAuraButtons()
    end

    frame.AuraContainer = NewContainer(frame, "BuffFrame.AuraContainer")
    frame.CollapseAndExpandButton = NewControl(frame, "BuffFrame.CollapseAndExpandButton")
    frame.ConsolidatedBuffs = NewControl(frame, "BuffFrame.ConsolidatedBuffs")

    local tooltip = {
        hideCount = 0,
    }
    function tooltip:GetParent()
        return frame.ConsolidatedBuffs
    end
    function tooltip:Hide()
        self.hideCount = self.hideCount + 1
    end
    frame.ConsolidatedBuffs.Tooltip = tooltip

    local consolidatedAuras = {
        auraFrames = {},
    }
    function consolidatedAuras:GetParent()
        return tooltip
    end
    tooltip.Auras = consolidatedAuras
    consolidatedAuras.AuraContainer = NewContainer(
        consolidatedAuras,
        "BuffFrame.ConsolidatedBuffs.Tooltip.Auras.AuraContainer"
    )

    frame.publicButton = NewAuraButton(frame.AuraContainer, "BuffFrame public aura")
    frame.auraFrames[1] = frame.publicButton
    consolidatedAuras.publicButton = NewAuraButton(
        consolidatedAuras.AuraContainer,
        "BuffFrame consolidated aura"
    )
    consolidatedAuras.auraFrames[1] = consolidatedAuras.publicButton

    return frame
end

local function NewDebuffFrame()
    local frame = {
        auraFrames = {},
    }
    function frame:UpdateAuraButtons()
    end

    frame.AuraContainer = NewContainer(frame, "DebuffFrame.AuraContainer")
    frame.publicButton = NewAuraButton(frame.AuraContainer, "DebuffFrame public aura")
    frame.auraFrames[1] = frame.publicButton
    frame.privateAnchor = NewUntouchableFrame(frame, "DebuffFrame private aura anchor")
    frame.PrivateAuraAnchors = {frame.privateAnchor}
    return frame
end

local inCombat = false
local hooks = {}
local hookCounts = {}

_G.InCombatLockdown = function()
    return inCombat
end
_G.hooksecurefunc = function(frame, methodName, callback)
    hooks[frame] = hooks[frame] or {}
    hooks[frame][methodName] = callback
    hookCounts[frame] = (hookCounts[frame] or 0) + 1
end

local buffFrame = NewBuffFrame()
local debuffFrame = NewDebuffFrame()
local deadlyDebuffFrame = NewUntouchableFrame(nil, "DeadlyDebuffFrame")
_G.BuffFrame = buffFrame
_G.DebuffFrame = debuffFrame
_G.DeadlyDebuffFrame = deadlyDebuffFrame

_G.GameTooltip = {
    hidden = {},
}
function _G.GameTooltip:IsOwned()
    return true
end
function _G.GameTooltip:Hide()
    self.hidden[#self.hidden + 1] = true
end

_G.HelpTip = {
    hidden = {},
}
function _G.HelpTip:HideAll(button)
    self.hidden[#self.hidden + 1] = button
end

local function LoadAdapter(hasRestrictedAuraButtons)
    _G.C_AuraContainerUtil = hasRestrictedAuraButtons and {} or nil
    local adapter = {}
    local BFI = {
        funcs = {
            isValueNonSecret = IsValueNonSecret,
        },
        modules = {
            BuffsDebuffs = adapter,
        },
    }
    local chunk = assert(loadfile("Modules/BuffsDebuffs/NativeAuraFrames.lua"))
    chunk("BFInfinite", BFI)
    return adapter
end

local BD = LoadAdapter(false)

assertEqual(BD.CanSuppressNativePublicAuras("buffs"), true, "buff capability")
assertEqual(BD.CanSuppressNativePublicAuras("debuffs"), true, "debuff capability")
assertEqual(BD.CanSuppressNativePublicAuras("invalid"), false, "invalid capability")
assertEqual(BD.AreNativePublicAurasSuppressed("buffs"), false, "initial buff state")
assertEqual(BD.AreNativePublicAurasSuppressed("debuffs"), false, "initial debuff state")
assertEqual(BD.SetNativePublicAurasSuppressed("invalid", true), false, "invalid pane")

assertEqual(BD.SetNativePublicAurasSuppressed("buffs", true), true, "suppress buffs")
assertEqual(BD.AreNativePublicAurasSuppressed("buffs"), true, "suppressed buff state")
assertWrites(buffFrame.AuraContainer.shownWrites, {false}, "buff container suppression")
assertWrites(
    buffFrame.CollapseAndExpandButton.alphaWrites,
    {0},
    "collapse alpha suppression"
)
assertWrites(
    buffFrame.CollapseAndExpandButton.mouseWrites,
    {false},
    "collapse mouse suppression"
)
assertWrites(buffFrame.ConsolidatedBuffs.alphaWrites, {0}, "consolidated alpha suppression")
assertWrites(
    buffFrame.ConsolidatedBuffs.mouseWrites,
    {false},
    "consolidated mouse suppression"
)
assertWrites(
    buffFrame.ConsolidatedBuffs.Tooltip.Auras.AuraContainer.shownWrites,
    {},
    "consolidated aura container ownership boundary"
)
assertEqual(#_G.GameTooltip.hidden, 2, "initial buff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 2, "initial buff help-tip cleanup")
assertEqual(buffFrame.ConsolidatedBuffs.Tooltip.hideCount, 1, "initial consolidated tooltip cleanup")
assertEqual(hookCounts[buffFrame], 1, "single buff cleanup hook")

assertEqual(BD.SetNativePublicAurasSuppressed("buffs", true), true, "idempotent buff suppression")
assertWrites(buffFrame.AuraContainer.shownWrites, {false}, "idempotent buff container")
assertEqual(#_G.GameTooltip.hidden, 2, "idempotent buff tooltip cleanup")
assertEqual(hookCounts[buffFrame], 1, "idempotent buff cleanup hook")

assertEqual(type(hooks[buffFrame].UpdateAuraButtons), "function", "buff cleanup hook")
hooks[buffFrame].UpdateAuraButtons(buffFrame)
assertEqual(#_G.GameTooltip.hidden, 4, "hooked buff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 4, "hooked buff help-tip cleanup")
assertEqual(buffFrame.ConsolidatedBuffs.Tooltip.hideCount, 2, "hooked consolidated cleanup")
assertWrites(buffFrame.AuraContainer.shownWrites, {false}, "hook does not rewrite container")

inCombat = true
assertEqual(BD.SetNativePublicAurasSuppressed("buffs", false), false, "combat restore deferral")
assertEqual(BD.AreNativePublicAurasSuppressed("buffs"), true, "combat preserves buff ledger")
assertWrites(buffFrame.AuraContainer.shownWrites, {false}, "combat preserves container")
assertWrites(buffFrame.CollapseAndExpandButton.alphaWrites, {0}, "combat preserves alpha")

inCombat = false
assertEqual(BD.SetNativePublicAurasSuppressed("buffs", false), true, "restore buffs")
assertEqual(BD.AreNativePublicAurasSuppressed("buffs"), false, "restored buff state")
assertWrites(buffFrame.AuraContainer.shownWrites, {false, true}, "buff container constants")
assertWrites(
    buffFrame.CollapseAndExpandButton.alphaWrites,
    {0, 1},
    "collapse alpha constants"
)
assertWrites(
    buffFrame.CollapseAndExpandButton.mouseWrites,
    {false, true},
    "collapse mouse constants"
)
assertWrites(buffFrame.ConsolidatedBuffs.alphaWrites, {0, 1}, "consolidated alpha constants")
assertWrites(
    buffFrame.ConsolidatedBuffs.mouseWrites,
    {false, true},
    "consolidated mouse constants"
)
assertEqual(#_G.GameTooltip.hidden, 6, "restore buff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 6, "restore buff help-tip cleanup")
assertEqual(buffFrame.ConsolidatedBuffs.Tooltip.hideCount, 3, "restore consolidated cleanup")

assertEqual(BD.SetNativePublicAurasSuppressed("buffs", false), true, "idempotent buff restore")
assertWrites(buffFrame.AuraContainer.shownWrites, {false, true}, "idempotent buff restore writes")
assertEqual(#_G.GameTooltip.hidden, 6, "idempotent buff restore cleanup")

assertEqual(BD.SetNativePublicAurasSuppressed("debuffs", true), true, "suppress debuffs")
assertEqual(BD.AreNativePublicAurasSuppressed("debuffs"), true, "suppressed debuff state")
assertWrites(debuffFrame.AuraContainer.shownWrites, {false}, "debuff container suppression")
assertEqual(debuffFrame.privateAnchor.mutationCount, 0, "private anchor suppression boundary")
assertEqual(deadlyDebuffFrame.mutationCount, 0, "deadly debuff suppression boundary")
assertEqual(hookCounts[debuffFrame], 1, "single debuff cleanup hook")
assertEqual(#_G.GameTooltip.hidden, 7, "initial debuff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 7, "initial debuff help-tip cleanup")

assertEqual(type(hooks[debuffFrame].UpdateAuraButtons), "function", "debuff cleanup hook")
hooks[debuffFrame].UpdateAuraButtons(debuffFrame)
assertEqual(#_G.GameTooltip.hidden, 8, "hooked debuff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 8, "hooked debuff help-tip cleanup")

assertEqual(BD.SetNativePublicAurasSuppressed("debuffs", false), true, "restore debuffs")
assertEqual(BD.AreNativePublicAurasSuppressed("debuffs"), false, "restored debuff state")
assertWrites(debuffFrame.AuraContainer.shownWrites, {false, true}, "debuff container constants")
assertEqual(debuffFrame.privateAnchor.mutationCount, 0, "private anchor restore boundary")
assertEqual(deadlyDebuffFrame.mutationCount, 0, "deadly debuff restore boundary")
assertEqual(#_G.GameTooltip.hidden, 9, "restore debuff tooltip cleanup")
assertEqual(#_G.HelpTip.hidden, 9, "restore debuff help-tip cleanup")

local restrictedButtonCalls = 0
local restrictedButton = {
    GetParent = function()
        restrictedButtonCalls = restrictedButtonCalls + 1
        error("restricted AuraButton was inspected", 2)
    end,
}
local restrictedFrame = NewDebuffFrame()
restrictedFrame.publicButton = restrictedButton
restrictedFrame.auraFrames = {restrictedButton}
_G.DebuffFrame = restrictedFrame
_G.GameTooltip = {
    IsOwned = function()
        error("restricted AuraButton tooltip owner was inspected", 2)
    end,
    Hide = function()
        error("restricted AuraButton tooltip was hidden", 2)
    end,
}
_G.HelpTip = {
    HideAll = function()
        error("restricted AuraButton help tip was inspected", 2)
    end,
}

local restrictedBD = LoadAdapter(true)
assertEqual(
    restrictedBD.CanSuppressNativePublicAuras("debuffs"),
    true,
    "restricted debuff capability"
)
assertEqual(
    restrictedBD.SetNativePublicAurasSuppressed("debuffs", true),
    true,
    "restricted debuff suppression"
)
assertWrites(
    restrictedFrame.AuraContainer.shownWrites,
    {false},
    "restricted debuff container suppression"
)
assertEqual(restrictedButtonCalls, 0, "restricted suppression button calls")
assertEqual(hooks[restrictedFrame], nil, "restricted update hook omitted")
assertEqual(restrictedFrame.privateAnchor.mutationCount, 0,
    "restricted private anchor boundary")
assertEqual(deadlyDebuffFrame.mutationCount, 0,
    "restricted deadly debuff boundary")
assertEqual(
    restrictedBD.SetNativePublicAurasSuppressed("debuffs", false),
    true,
    "restricted debuff restoration"
)
assertWrites(
    restrictedFrame.AuraContainer.shownWrites,
    {false, true},
    "restricted debuff container restoration"
)
assertEqual(restrictedButtonCalls, 0, "restricted restoration button calls")

local secretBD = LoadAdapter(false)

local secretContainerFrame = NewBuffFrame()
SetSecretParent(secretContainerFrame.AuraContainer, secretContainerFrame)
_G.BuffFrame = secretContainerFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("buffs"),
    false,
    "secret container parent"
)

local secretControlFrame = NewBuffFrame()
SetSecretParent(secretControlFrame.CollapseAndExpandButton, secretControlFrame)
_G.BuffFrame = secretControlFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("buffs"),
    false,
    "secret control parent"
)

local secretTooltipFrame = NewBuffFrame()
local secretTooltip = secretTooltipFrame.ConsolidatedBuffs.Tooltip
SetSecretParent(secretTooltip, secretTooltipFrame.ConsolidatedBuffs)
_G.BuffFrame = secretTooltipFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("buffs"),
    false,
    "secret consolidated tooltip parent"
)

local secretAurasFrame = NewBuffFrame()
local secretAurasTooltip = secretAurasFrame.ConsolidatedBuffs.Tooltip
SetSecretParent(secretAurasTooltip.Auras, secretAurasTooltip)
_G.BuffFrame = secretAurasFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("buffs"),
    false,
    "secret consolidated auras parent"
)

local secretNestedContainerFrame = NewBuffFrame()
local secretNestedAuras =
    secretNestedContainerFrame.ConsolidatedBuffs.Tooltip.Auras
SetSecretParent(secretNestedAuras.AuraContainer, secretNestedAuras)
_G.BuffFrame = secretNestedContainerFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("buffs"),
    false,
    "secret consolidated container parent"
)

local secretPrivateFrame = NewDebuffFrame()
SetSecretParent(secretPrivateFrame.privateAnchor, secretPrivateFrame)
_G.DebuffFrame = secretPrivateFrame
assertEqual(
    secretBD.CanSuppressNativePublicAuras("debuffs"),
    false,
    "secret private-anchor parent"
)

local secretButtonFrame = NewDebuffFrame()
SetSecretParent(secretButtonFrame.publicButton, secretButtonFrame.AuraContainer)
_G.DebuffFrame = secretButtonFrame
assertEqual(
    secretBD.SetNativePublicAurasSuppressed("debuffs", true),
    true,
    "secret legacy button parent suppression"
)
assertEqual(secretEqualityCalls, 0, "secret parents never compared")

local sourceFile = assert(io.open("Modules/BuffsDebuffs/NativeAuraFrames.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
for _, observerName in ipairs({"GetAlpha", "IsMouseEnabled", "IsMouseOver", "IsShown"}) do
    assertEqual(
        source:find("." .. observerName, 1, true),
        nil,
        observerName .. " source guard"
    )
end
assertEqual(source:find("containerShown", 1, true), nil, "snapshot source guard")
assertEqual(
    source:find("IsNativePublicAuraFrameHovered", 1, true),
    nil,
    "hover helper source guard"
)
local getParentPosition = assert(source:find(
    "local parent = object:GetParent()", 1, true
))
local gatePosition = assert(source:find(
    "IsValueNonSecret(parent)", getParentPosition, true
))
local comparisonPosition = assert(source:find(
    "parent == expected", gatePosition, true
))
assertEqual(getParentPosition < gatePosition, true, "GetParent before secret gate")
assertEqual(gatePosition < comparisonPosition, true, "secret gate before equality")
local _, getParentCalls = source:gsub(":GetParent%(%)", "")
assertEqual(getParentCalls, 1, "GetParent calls centralized behind gate")

print("buffs_debuffs_native_aura_frames_test: ok")
