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

local function NewHarmfulHarness()
    local calls = {}
    local secretValues = {}
    local state = {
        combatValue = false,
    }

    local function Record(value)
        calls[#calls + 1] = value
    end

    local function IsOrdinary(value)
        for index = 1, #secretValues do
            if rawequal(value, secretValues[index]) then
                return false
            end
        end
        return true
    end

    local function CanBeAccessedInContext(object)
        object.accessCalls = (object.accessCalls or 0) + 1
        if state.onAccess then
            state.onAccess(object, object.accessCalls)
        end
        if object.accessResult ~= nil then
            return object.accessResult
        end
        return true
    end

    local function NewRegion(parent, label)
        local region = {
            parent = parent,
            width = 26,
            height = 26,
            CanBeAccessedInContext = CanBeAccessedInContext,
            IsShown = ForbiddenObserver(label .. ":IsShown"),
            GetAlpha = ForbiddenObserver(label .. ":GetAlpha"),
            GetPoint = ForbiddenObserver(label .. ":GetPoint"),
        }
        function region:GetParent()
            return self.parent
        end
        function region:GetWidth()
            return self.width
        end
        function region:GetHeight()
            if state.onRegionHeight then
                state.onRegionHeight(self)
            end
            return self.height
        end
        return region
    end

    local function SetUnit(anchor, unit, showDispelType)
        Record("anchor:" .. anchor.auraIndex .. ":" .. tostring(unit))
        anchor.lastUnit = unit
        anchor.lastShowDispelType = showDispelType
        if state.failAnchorIndex == anchor.auraIndex then
            state.failAnchorIndex = nil
            error("opaque private anchor failure " .. anchor.auraIndex, 2)
        end
    end

    local function UpdatePrivateAuraAnchors(root, unit)
        Record("restore:" .. tostring(unit))
        if state.failRestore then
            state.failRestore = false
            error("opaque private restore failure", 2)
        end
        for index = 1, 6 do
            root.PrivateAuraAnchors[index]:SetUnit(
                unit,
                root.AuraContainer.showDispelType
            )
        end
    end

    local function NewTopology()
        local frame = {
            auraFrames = {},
            maxPrivateAuras = 6,
            CanBeAccessedInContext = CanBeAccessedInContext,
        }
        function frame:UpdateAuraButtons()
        end

        local container = {
            parent = frame,
            showDispelType = true,
            CanBeAccessedInContext = CanBeAccessedInContext,
            IsShown = ForbiddenObserver("harmful AuraContainer:IsShown"),
            GetAlpha = ForbiddenObserver("harmful AuraContainer:GetAlpha"),
        }
        function container:GetParent()
            return self.parent
        end
        function container:SetShown(shown)
            Record("container:" .. tostring(shown))
            if state.failContainerValue == shown then
                state.failContainerValue = nil
                error("opaque harmful container failure", 2)
            end
            self.shown = shown
        end
        frame.AuraContainer = container

        local anchors = {}
        for index = 1, 6 do
            local anchor = {
                auraIndex = index,
                isAuraAnchor = true,
                parent = frame,
                CanBeAccessedInContext = CanBeAccessedInContext,
                SetUnit = SetUnit,
                IsShown = ForbiddenObserver(
                    "private anchor " .. index .. ":IsShown"
                ),
                GetAlpha = ForbiddenObserver(
                    "private anchor " .. index .. ":GetAlpha"
                ),
                Hide = ForbiddenObserver(
                    "private anchor " .. index .. ":Hide"
                ),
                Show = ForbiddenObserver(
                    "private anchor " .. index .. ":Show"
                ),
            }
            function anchor:GetParent()
                return self.parent
            end
            anchor.Icon = NewRegion(
                anchor,
                "private anchor " .. index .. " Icon"
            )
            anchor.Duration = NewRegion(
                anchor,
                "private anchor " .. index .. " Duration"
            )
            anchors[index] = anchor
            frame["privateAuraAnchor" .. index] = anchor
        end
        frame.PrivateAuraAnchors = anchors
        frame.UpdatePrivateAuraAnchors = UpdatePrivateAuraAnchors
        return frame, container
    end

    local frame, container = NewTopology()

    _G.DebuffFrameMixin = {
        UpdatePrivateAuraAnchors = UpdatePrivateAuraAnchors,
    }
    _G.BuffFramePrivateAuraAnchorMixin = {
        SetUnit = SetUnit,
    }
    _G.C_UnitAuras = {
        AddPrivateAuraAnchor = function()
            return 1
        end,
        RemovePrivateAuraAnchor = function()
        end,
    }
    _G.DebuffFrame = frame
    _G.C_AuraContainerUtil = {}
    _G.InCombatLockdown = function()
        if state.combatFunction then
            return state.combatFunction()
        end
        return state.combatValue
    end
    _G.DeadlyDebuffFrame = setmetatable({}, {
        __index = function(_, key)
            error("DeadlyDebuffFrame was observed: " .. tostring(key), 2)
        end,
        __newindex = function(_, key)
            error("DeadlyDebuffFrame was mutated: " .. tostring(key), 2)
        end,
    })

    local adapter = {}
    local BFI = {
        funcs = {
            isValueNonSecret = IsOrdinary,
        },
        modules = {
            BuffsDebuffs = adapter,
        },
    }
    local chunk = assert(loadfile("Modules/BuffsDebuffs/NativeAuraFrames.lua"))
    chunk("BFInfinite", BFI)

    local function GetUpvalue(target, wanted)
        local index = 1
        while true do
            local name, value = debug.getupvalue(target, index)
            if name == nil then return nil end
            if name == wanted then return value end
            index = index + 1
        end
    end

    local harness = {
        BD = adapter,
        calls = calls,
        container = container,
        frame = frame,
        state = state,
        clearCalls = function()
            for index = #calls, 1, -1 do
                calls[index] = nil
            end
        end,
        markSecret = function(value)
            secretValues[#secretValues + 1] = value
        end,
    }
    harness.getHarmfulSnapshot = function()
        return GetUpvalue(
            adapter.SetNativeHarmfulAurasSuppressed,
            "harmfulRecoveryState"
        ) or GetUpvalue(
            adapter.SetNativeHarmfulAurasSuppressed,
            "harmfulSuppressedState"
        )
    end
    harness.replaceTopology = function()
        local replacementFrame, replacementContainer = NewTopology()
        _G.DebuffFrame = replacementFrame
        harness.replacementFrame = replacementFrame
        harness.replacementContainer = replacementContainer
        return replacementFrame, replacementContainer
    end
    return harness
end

local suppressWrites = {
    "anchor:1:nil",
    "anchor:2:nil",
    "anchor:3:nil",
    "anchor:4:nil",
    "anchor:5:nil",
    "anchor:6:nil",
    "container:false",
}

local function RestoreWrites(unit)
    local writes = {"restore:" .. unit}
    for index = 1, 6 do
        writes[#writes + 1] = "anchor:" .. index .. ":" .. unit
    end
    writes[#writes + 1] = "container:true"
    return writes
end

do
    local harness = NewHarmfulHarness()
    local harmfulBD = harness.BD

    assertEqual(
        harmfulBD.CanSuppressNativeHarmfulAuras(),
        true,
        "full harmful capability"
    )
    assertEqual(
        harmfulBD.AreNativeHarmfulAurasSuppressed(),
        false,
        "initial full harmful state"
    )
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "full harmful suppression"
    )
    assertWrites(harness.calls, suppressWrites, "full harmful suppression order")
    assertEqual(
        harmfulBD.AreNativeHarmfulAurasSuppressed(),
        true,
        "completed full harmful ledger"
    )

    harness.clearCalls()
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "idempotent full harmful suppression"
    )
    assertWrites(harness.calls, {}, "idempotent full harmful writes")
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(false),
        false,
        "missing restore unit rejected"
    )
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(false, "target"),
        false,
        "foreign restore unit rejected"
    )
    assertWrites(harness.calls, {}, "invalid restore performs no writes")

    -- These are ordinary presentation settings, not topology identities. A
    -- restore must use their current values after Edit Mode/profile changes.
    harness.container.showDispelType = false
    for index = 1, 6 do
        local anchor = harness.frame.PrivateAuraAnchors[index]
        anchor.Icon.width = 30
        anchor.Icon.height = 31
        anchor.Duration.width = 32
        anchor.Duration.height = 33
    end
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(false, "player"),
        true,
        "restore accepts ordinary presentation drift"
    )
    assertWrites(harness.calls, RestoreWrites("player"),
        "restore-first harmful order")
    for index = 1, 6 do
        assertEqual(
            harness.frame.PrivateAuraAnchors[index].lastShowDispelType,
            false,
            "restore uses current dispel setting " .. index
        )
    end
    assertEqual(
        harmfulBD.AreNativeHarmfulAurasSuppressed(),
        false,
        "restored full harmful ledger"
    )

    harness.clearCalls()
    assertEqual(
        harmfulBD.SetNativeHarmfulAurasSuppressed(false, "vehicle"),
        true,
        "idempotent harmful restore"
    )
    assertWrites(harness.calls, {}, "idempotent harmful restore writes")
end

do
    local harness = NewHarmfulHarness()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "reassert failure setup suppression"
    )
    harness.clearCalls()
    harness.state.failAnchorIndex = 4
    local ok = pcall(function()
        harness.BD.ReassertNativeHarmfulAuraSuppression()
    end)
    assertEqual(ok, false, "opaque reassert error propagates")
    assertWrites(harness.calls, {
        "anchor:1:nil",
        "anchor:2:nil",
        "anchor:3:nil",
        "anchor:4:nil",
    }, "partial harmful reassert order")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        true,
        "reassert failure preserves completed suppression ledger"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "reassert recovery ledger blocks repeat suppression"
    )
    assertEqual(
        harness.BD.ReassertNativeHarmfulAuraSuppression(),
        false,
        "reassert recovery ledger blocks repeat reassert"
    )
    assertWrites(harness.calls, {},
        "reassert recovery blocks all removal writes")

    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(false, "player"),
        true,
        "reassert failure explicit restore"
    )
    assertWrites(harness.calls, RestoreWrites("player"),
        "reassert failure restore-first recovery")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        false,
        "reassert restore clears completed ledger"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "suppression succeeds after reassert recovery"
    )
    assertWrites(harness.calls, suppressWrites,
        "post-reassert-recovery suppression order")
end

do
    local harness = NewHarmfulHarness()
    harness.state.failAnchorIndex = 3
    local ok = pcall(function()
        harness.BD.SetNativeHarmfulAurasSuppressed(true)
    end)
    assertEqual(ok, false, "opaque removal error propagates")
    assertWrites(harness.calls, {
        "anchor:1:nil",
        "anchor:2:nil",
        "anchor:3:nil",
    }, "partial harmful removal order")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        false,
        "partial removal is not completed suppression"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "recovery ledger blocks another removal batch"
    )
    assertWrites(harness.calls, {}, "blocked recovery removal writes")
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(false, "vehicle"),
        true,
        "recovery ledger permits explicit restore"
    )
    assertWrites(harness.calls, RestoreWrites("vehicle"),
        "partial removal recovery order")

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "suppression available after recovery"
    )
    assertWrites(harness.calls, suppressWrites,
        "post-recovery harmful suppression")
end

do
    local harness = NewHarmfulHarness()
    harness.state.failContainerValue = false
    local ok = pcall(function()
        harness.BD.SetNativeHarmfulAurasSuppressed(true)
    end)
    assertEqual(ok, false, "opaque public hide error propagates")
    assertWrites(harness.calls, suppressWrites,
        "hide failure occurs after six removals")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        false,
        "hide failure is recovery-only"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(false, "player"),
        true,
        "hide failure recovery"
    )
    assertWrites(harness.calls, RestoreWrites("player"),
        "hide failure restore-first order")
end

for _, failureCase in ipairs({
    {name = "private restore", field = "failRestore"},
    {
        name = "public show",
        field = "failContainerValue",
        value = true,
    },
}) do
    local harness = NewHarmfulHarness()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        failureCase.name .. " setup suppression"
    )
    harness.clearCalls()
    harness.state[failureCase.field] = failureCase.value
    if failureCase.value == nil then
        harness.state[failureCase.field] = true
    end
    local ok = pcall(function()
        harness.BD.SetNativeHarmfulAurasSuppressed(false, "player")
    end)
    assertEqual(ok, false, failureCase.name .. " error propagates")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        true,
        failureCase.name .. " preserves completed ledger"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(false, "player"),
        true,
        failureCase.name .. " retry"
    )
    assertWrites(harness.calls, RestoreWrites("player"),
        failureCase.name .. " retry order")
end

do
    local harness = NewHarmfulHarness()
    harness.state.combatValue = true
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "combat blocks full harmful suppression"
    )
    assertWrites(harness.calls, {}, "combat harmful writes")

    harness.state.combatValue = "invalid"
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "non-boolean combat state fails closed"
    )
    assertWrites(harness.calls, {}, "invalid combat harmful writes")

    local combatCalls = 0
    harness.state.combatFunction = function()
        combatCalls = combatCalls + 1
        return combatCalls >= 2
    end
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "second combat gate blocks post-capture writes"
    )
    assertWrites(harness.calls, {}, "late combat harmful writes")
end

do
    local harness = NewHarmfulHarness()
    assertEqual(
        harness.BD.SetNativePublicAurasSuppressed("debuffs", true),
        true,
        "public suppression setup"
    )
    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        "public ledger excludes full harmful suppression"
    )
    assertWrites(harness.calls, {}, "public/full exclusion writes")
    assertEqual(
        harness.BD.SetNativePublicAurasSuppressed("debuffs", false),
        true,
        "public suppression restore"
    )

    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        "full harmful suppression after public restore"
    )
    harness.clearCalls()
    assertEqual(
        harness.BD.SetNativePublicAurasSuppressed("debuffs", true),
        false,
        "full harmful ledger excludes public suppression"
    )
    assertWrites(harness.calls, {}, "full/public exclusion writes")
end

local harmfulTopologyCases = {
    {
        name = "wrong private count",
        mutate = function(harness)
            harness.frame.maxPrivateAuras = 5
        end,
    },
    {
        name = "extra array entry",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[7] =
                harness.frame.PrivateAuraAnchors[6]
        end,
    },
    {
        name = "metadata array entry",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors.label = "unexpected"
        end,
    },
    {
        name = "missing array entry",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[6] = nil
        end,
    },
    {
        name = "alias mismatch",
        mutate = function(harness)
            harness.frame.privateAuraAnchor3 =
                harness.frame.PrivateAuraAnchors[2]
        end,
    },
    {
        name = "aura index mismatch",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[4].auraIndex = 3
        end,
    },
    {
        name = "anchor marker mismatch",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[2].isAuraAnchor = false
        end,
    },
    {
        name = "anchor parent mismatch",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[1].parent = {}
        end,
    },
    {
        name = "anchor access denied",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[1].accessResult = false
        end,
    },
    {
        name = "anchor method drift",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[5].SetUnit = function()
            end
        end,
    },
    {
        name = "mixin method drift",
        mutate = function()
            _G.BuffFramePrivateAuraAnchorMixin.SetUnit = function()
            end
        end,
    },
    {
        name = "root method drift",
        mutate = function(harness)
            harness.frame.UpdatePrivateAuraAnchors = function()
            end
        end,
    },
    {
        name = "container parent mismatch",
        mutate = function(harness)
            harness.container.parent = {}
        end,
    },
    {
        name = "dispel setting type drift",
        mutate = function(harness)
            harness.container.showDispelType = 1
        end,
    },
    {
        name = "icon parent mismatch",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[2].Icon.parent = {}
        end,
    },
    {
        name = "zero icon width",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[2].Icon.width = 0
        end,
    },
    {
        name = "duration parent mismatch",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[2].Duration.parent = {}
        end,
    },
    {
        name = "duration aliases icon",
        mutate = function(harness)
            local anchor = harness.frame.PrivateAuraAnchors[3]
            anchor.Duration = anchor.Icon
        end,
    },
    {
        name = "zero duration height",
        mutate = function(harness)
            harness.frame.PrivateAuraAnchors[2].Duration.height = 0
        end,
    },
    {
        name = "private add API drift",
        mutate = function()
            _G.C_UnitAuras.AddPrivateAuraAnchor = true
        end,
    },
    {
        name = "private remove API drift",
        mutate = function()
            _G.C_UnitAuras.RemovePrivateAuraAnchor = true
        end,
    },
    {
        name = "secret frame",
        mutate = function(harness)
            harness.markSecret(harness.frame)
        end,
    },
    {
        name = "secret icon",
        mutate = function(harness)
            harness.markSecret(harness.frame.PrivateAuraAnchors[1].Icon)
        end,
    },
}

for _, topologyCase in ipairs(harmfulTopologyCases) do
    local harness = NewHarmfulHarness()
    topologyCase.mutate(harness)
    assertEqual(
        harness.BD.CanSuppressNativeHarmfulAuras(),
        false,
        topologyCase.name .. " capability"
    )
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        false,
        topologyCase.name .. " suppression"
    )
    assertWrites(harness.calls, {}, topologyCase.name .. " writes")
end

do
    local harness = NewHarmfulHarness()
    local widthCalls = 0
    local icon = harness.frame.PrivateAuraAnchors[1].Icon
    function icon:GetWidth()
        widthCalls = widthCalls + 1
        return 26 + widthCalls
    end
    assertEqual(
        harness.BD.CanSuppressNativeHarmfulAuras(),
        false,
        "double capture rejects topology-time geometry drift"
    )
    assertWrites(harness.calls, {}, "double capture drift writes")
end

local storedParallelArrays = {
    "anchors",
    "anchorObjects",
    "anchorAccessMethods",
    "anchorGetParents",
    "anchorSetUnits",
    "anchorAuraIndexes",
    "anchorIsAuraAnchors",
    "anchorIcons",
    "anchorIconAccessMethods",
    "anchorIconGetParents",
    "anchorIconGetWidths",
    "anchorIconWidths",
    "anchorIconGetHeights",
    "anchorIconHeights",
    "anchorDurations",
    "anchorDurationAccessMethods",
    "anchorDurationGetParents",
    "anchorDurationGetWidths",
    "anchorDurationWidths",
    "anchorDurationGetHeights",
    "anchorDurationHeights",
}

for _, arrayName in ipairs(storedParallelArrays) do
    for _, shape in ipairs({"extra", "metadata", "missing"}) do
        local harness = NewHarmfulHarness()
        assertEqual(
            harness.BD.SetNativeHarmfulAurasSuppressed(true),
            true,
            arrayName .. " " .. shape .. " setup"
        )
        local snapshot = assert(
            harness.getHarmfulSnapshot(),
            arrayName .. " stored snapshot"
        )
        local array = assert(snapshot[arrayName], arrayName .. " array")
        if shape == "extra" then
            array[7] = array[6]
        elseif shape == "metadata" then
            array.label = array[1]
        else
            array[6] = nil
        end
        harness.clearCalls()
        local ok, result = pcall(
            harness.BD.SetNativeHarmfulAurasSuppressed,
            false,
            "player"
        )
        assertEqual(ok, true, arrayName .. " " .. shape .. " no error")
        assertEqual(result, false,
            arrayName .. " " .. shape .. " rejects restore")
        assertWrites(harness.calls, {},
            arrayName .. " " .. shape .. " zero writes")
        assertEqual(
            harness.BD.AreNativeHarmfulAurasSuppressed(),
            true,
            arrayName .. " " .. shape .. " retains ledger"
        )
    end
end

for _, tieCase in ipairs({
    {
        name = "stored raw/captured anchor tie",
        mutate = function(snapshot)
            snapshot.anchorObjects[3] = snapshot.anchorObjects[2]
        end,
    },
    {
        name = "stored anchor array identity tie",
        mutate = function(snapshot)
            local replacement = {}
            for index = 1, 6 do
                replacement[index] = snapshot.anchors[index]
            end
            snapshot.anchors = replacement
        end,
    },
    {
        name = "stored icon/duration distinction",
        mutate = function(snapshot)
            snapshot.anchorDurations[3] = snapshot.anchorIcons[3]
        end,
    },
}) do
    local harness = NewHarmfulHarness()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        tieCase.name .. " setup"
    )
    tieCase.mutate(assert(harness.getHarmfulSnapshot()))
    harness.clearCalls()
    local ok, result = pcall(
        harness.BD.SetNativeHarmfulAurasSuppressed,
        false,
        "vehicle"
    )
    assertEqual(ok, true, tieCase.name .. " no error")
    assertEqual(result, false, tieCase.name .. " rejected")
    assertWrites(harness.calls, {}, tieCase.name .. " zero writes")
end

for _, poisonCase in ipairs({
    {
        name = "old inaccessible object",
        poison = function(harness, snapshot)
            snapshot.anchorObjects[2].accessResult = false
        end,
    },
    {
        name = "old secret object",
        poison = function(harness, snapshot)
            harness.markSecret(snapshot.anchorIcons[2])
        end,
    },
    {
        name = "old secret method",
        poison = function(harness, snapshot)
            harness.markSecret(snapshot.anchorSetUnits[2])
        end,
    },
    {
        name = "old secret parallel array",
        poison = function(harness, snapshot)
            harness.markSecret(snapshot.anchorGetParents)
        end,
    },
    {
        name = "old secret parallel entry",
        poison = function(harness, snapshot)
            harness.markSecret(snapshot.anchorIconGetWidths[2])
        end,
    },
}) do
    local harness = NewHarmfulHarness()
    assertEqual(
        harness.BD.SetNativeHarmfulAurasSuppressed(true),
        true,
        poisonCase.name .. " setup"
    )
    local snapshot = assert(harness.getHarmfulSnapshot())
    harness.replaceTopology()
    poisonCase.poison(harness, snapshot)
    harness.clearCalls()
    for _, operation in ipairs({
        {
            name = "capability",
            call = harness.BD.CanSuppressNativeHarmfulAuras,
        },
        {
            name = "reassert",
            call = harness.BD.ReassertNativeHarmfulAuraSuppression,
        },
        {
            name = "restore",
            call = function()
                return harness.BD.SetNativeHarmfulAurasSuppressed(
                    false,
                    "player"
                )
            end,
        },
    }) do
        local ok, result = pcall(operation.call)
        assertEqual(ok, true,
            poisonCase.name .. " " .. operation.name .. " no error")
        assertEqual(result, false,
            poisonCase.name .. " " .. operation.name .. " rejects")
    end
    assertWrites(harness.calls, {}, poisonCase.name .. " zero writes")
    assertEqual(
        harness.BD.AreNativeHarmfulAurasSuppressed(),
        true,
        poisonCase.name .. " retains completed ledger"
    )
end

do
    local harness = NewHarmfulHarness()
    local heightCalls = 0
    harness.state.onRegionHeight = function()
        heightCalls = heightCalls + 1
        if heightCalls == 24 then
            harness.markSecret(harness.frame.PrivateAuraAnchors[1])
        end
    end
    local ok, result = pcall(
        harness.BD.SetNativeHarmfulAurasSuppressed,
        true
    )
    assertEqual(ok, true, "final-capture revocation raises no error")
    assertEqual(result, false, "final-capture revocation rejects suppression")
    assertEqual(heightCalls, 24,
        "revocation occurs at the final capture callback boundary")
    assertWrites(harness.calls, {}, "final-capture revocation zero writes")
end

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
assertEqual(source:find(".anchorID", 1, true), nil,
    "private anchor ID observation guard")
assertEqual(source:find("pcall(", 1, true), nil,
    "opaque private setter pcall guard")
assertEqual(source:find("securecallfunction", 1, true), nil,
    "private setter direct-call guard")
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
