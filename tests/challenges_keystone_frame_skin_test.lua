local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function assertRGB(actual, message)
    assertEqual(type(actual), "table", message .. " color")
    assertEqual(actual[1], 0.11, message .. " red")
    assertEqual(actual[2], 0.22, message .. " green")
    assertEqual(actual[3], 0.33, message .. " blue")
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then
            return nil
        elseif name == targetName then
            return value
        end
        index = index + 1
    end
end

local function setUpvalue(func, targetName, replacement)
    local index = 1
    while true do
        local name = debug.getupvalue(func, index)
        if not name then
            error("missing upvalue: " .. targetName, 2)
        elseif name == targetName then
            debug.setupvalue(func, index, replacement)
            return
        end
        index = index + 1
    end
end

local function makeTexture(name, atlas)
    local texture = {
        alpha = 1,
        atlas = atlas,
        name = name,
        shown = true,
    }

    function texture:GetAlpha()
        return self.alpha
    end

    function texture:GetAtlas()
        return self.atlas
    end

    function texture:Hide()
        self.hideCalls = (self.hideCalls or 0) + 1
        self.shown = false
    end

    function texture:IsObjectType(objectType)
        return objectType == "Texture"
    end

    function texture:IsShown()
        return self.shown
    end

    function texture:SetAlpha(alpha)
        self.alpha = alpha
    end

    function texture:SetAtlas(newAtlas)
        self.atlas = newAtlas
    end

    function texture:SetColorTexture(...)
        self.colorTexture = {...}
        self.atlas = nil
        self.texture = nil
    end

    function texture:SetShown(shown)
        self.shown = shown
    end

    function texture:SetTexture(newTexture)
        self.texture = newTexture
        self.atlas = nil
    end

    function texture:SetVertexColor(...)
        self.vertexColor = {...}
    end

    return texture
end

local function makeFontString(name, initiallyShown)
    local fontString = {
        alpha = 1,
        name = name,
        shown = initiallyShown ~= false,
    }

    function fontString:GetAlpha()
        return self.alpha
    end

    function fontString:Hide()
        self.shown = false
    end

    function fontString:IsShown()
        return self.shown
    end

    function fontString:IsObjectType()
        return false
    end

    function fontString:SetAlpha(alpha)
        self.alpha = alpha
    end

    function fontString:SetShown(shown)
        self.shown = shown
    end

    function fontString:SetTextColor(...)
        self.textColor = {...}
    end

    function fontString:Show()
        self.shown = true
    end

    return fontString
end

local function makeButton(name, scripts)
    local button = {
        enabled = true,
        name = name,
        scripts = scripts or {},
    }

    function button:Disable()
        self.enabled = false
        self.disableCalls = (self.disableCalls or 0) + 1
    end

    function button:Enable()
        self.enabled = true
        self.enableCalls = (self.enableCalls or 0) + 1
    end

    function button:GetScript(script)
        return self.scripts[script]
    end

    return button
end

local function makeAnimation(name)
    local animation = {name = name}

    function animation:Stop()
        self.stopCalls = (self.stopCalls or 0) + 1
    end

    return animation
end

local function makeAffix(name)
    local affix = {
        Border = makeTexture(name .. "Border", "ChallengeMode-AffixRing-Lg"),
        CircleMask = makeTexture(name .. "Mask"),
        name = name,
        Portrait = makeTexture(name .. "Portrait"),
        shown = true,
    }

    function affix:Hide()
        self.shown = false
    end

    return affix
end

local originalStartOnShow = function() end
local originalStartOnClick = function() end
local originalSlotOnEvent = function() end
local originalSlotOnReceiveDrag = function() end
local originalSlotOnDragStart = function() end
local originalSlotOnClick = function() end

local startButton = makeButton("StartButton", {
    OnClick = originalStartOnClick,
    OnShow = originalStartOnShow,
})
local closeButton = makeButton("CloseButton", {
    OnClick = function() end,
})
local keystoneSlot = makeButton("KeystoneSlot", {
    OnClick = originalSlotOnClick,
    OnDragStart = originalSlotOnDragStart,
    OnEvent = originalSlotOnEvent,
    OnReceiveDrag = originalSlotOnReceiveDrag,
})
keystoneSlot.CircleMask = makeTexture("KeystoneSlotMask")
keystoneSlot.Texture = makeTexture("KeystoneSlotTexture")
keystoneSlot.registeredEvents = {"CHALLENGE_MODE_KEYSTONE_SLOTTED"}
keystoneSlot.registeredDragButtons = {"LeftButton"}
function keystoneSlot:Reset()
    self.resetCalls = (self.resetCalls or 0) + 1
end

local outerBackground = makeTexture(
    "OuterBackground",
    "ChallengeMode-KeystoneFrame"
)
local runeBackground = makeTexture("RuneBackground", "ChallengeMode-RuneBG")
local slotGlow = makeTexture(
    "KeystoneSlotGlow",
    "ChallengeMode-KeystoneSlotFrameGlow"
)
local dungeonName = makeFontString("DungeonName", false)
local powerLevel = makeFontString("PowerLevel", false)
local timeLimit = makeFontString("TimeLimit", false)
local instructions = makeFontString("Instructions", true)
local initialAffix = makeAffix("InitialAffix")
local uiParent = {}
local originalPoints = {"CENTER", 0, 40}
local originalBaseStates = {
    [outerBackground] = {alpha = 1, shown = true},
    [runeBackground] = {alpha = 1, shown = true},
    [slotGlow] = {alpha = 0, shown = true},
    [dungeonName] = {alpha = 1, shown = false},
    [powerLevel] = {alpha = 1, shown = false},
    [timeLimit] = {alpha = 1, shown = false},
    [instructions] = {alpha = 1, shown = true},
}

local frame = {
    Affixes = {initialAffix},
    baseStates = originalBaseStates,
    CloseButton = closeButton,
    DungeonName = dungeonName,
    Divider = makeTexture("Divider", "ChallengeMode-ThinDivider"),
    InsertedAnim = makeAnimation("InsertedAnim"),
    InstructionBackground = makeTexture("InstructionBackground"),
    Instructions = instructions,
    KeystoneSlot = keystoneSlot,
    parent = uiParent,
    points = originalPoints,
    PowerLevel = powerLevel,
    PulseAnim = makeAnimation("PulseAnim"),
    RunesLargeAnim = makeAnimation("RunesLargeAnim"),
    RunesLargeRotateAnim = makeAnimation("RunesLargeRotateAnim"),
    RunesSmallAnim = makeAnimation("RunesSmallAnim"),
    RunesSmallRotateAnim = makeAnimation("RunesSmallRotateAnim"),
    shown = false,
    size = {398, 548},
    StartButton = startButton,
    strata = "HIGH",
    TimeLimit = timeLimit,
}

function frame:GetRegions()
    return outerBackground, runeBackground, slotGlow,
        dungeonName, powerLevel, timeLimit, instructions
end

function frame:Reset()
    self.nativeResetCalls = (self.nativeResetCalls or 0) + 1
    self.KeystoneSlot:Reset()
    self.PulseAnim:Stop()
    self.InsertedAnim:Stop()
    self.RunesLargeAnim:Stop()
    self.RunesLargeRotateAnim:Stop()
    self.RunesSmallAnim:Stop()
    self.RunesSmallRotateAnim:Stop()
    self.StartButton:Disable()
    self.TimeLimit:Hide()
    self.DungeonName:Hide()

    for _, affix in ipairs(self.Affixes) do
        affix:Hide()
    end

    for region, state in pairs(self.baseStates) do
        region:SetShown(state.shown)
        region:SetAlpha(state.alpha)
    end
end

function frame:CreateAndPositionAffixes(numAffixes)
    self.nativeCreateAffixCalls = (self.nativeCreateAffixCalls or 0) + 1
    self.lastRequestedAffixCount = numAffixes
    if self.pendingAffix then
        self.Affixes[#self.Affixes + 1] = self.pendingAffix
        self.pendingAffix = nil
    end
    return "native-result", numAffixes
end

local function forbiddenMutation(name)
    return function()
        error(name .. " must remain Blizzard-owned", 2)
    end
end

frame.ClearAllPoints = forbiddenMutation(
    "ChallengesKeystoneFrame:ClearAllPoints"
)
frame.EnableMouse = forbiddenMutation("ChallengesKeystoneFrame:EnableMouse")
frame.Hide = forbiddenMutation("ChallengesKeystoneFrame:Hide")
frame.RegisterEvent = forbiddenMutation("ChallengesKeystoneFrame:RegisterEvent")
frame.SetFrameStrata = forbiddenMutation(
    "ChallengesKeystoneFrame:SetFrameStrata"
)
frame.SetParent = forbiddenMutation("ChallengesKeystoneFrame:SetParent")
frame.SetPoint = forbiddenMutation("ChallengesKeystoneFrame:SetPoint")
frame.SetScript = forbiddenMutation("ChallengesKeystoneFrame:SetScript")
frame.SetSize = forbiddenMutation("ChallengesKeystoneFrame:SetSize")
frame.Show = forbiddenMutation("ChallengesKeystoneFrame:Show")
frame.UnregisterEvent = forbiddenMutation(
    "ChallengesKeystoneFrame:UnregisterEvent"
)

local addonLoadedCallback
local addonLoadedName
local blizzardStyleCallback
local blizzardStyleEvent
local backdropCalls = {}
local buttonCalls = {}
local closeButtonCalls = {}
local colorRequests = {}
local iconCalls = {}
local removeTextureCalls = {}
local secureHooks = {}

local AF = {}

function AF.GetColorRGB(color, alpha)
    colorRequests[#colorRequests + 1] = {
        alpha = alpha,
        color = color,
    }
    return 0.11, 0.22, 0.33, alpha or 1
end

function AF.RegisterAddonLoaded(addonName, callback)
    addonLoadedName = addonName
    addonLoadedCallback = callback
end

function AF.RegisterCallback(event, callback)
    blizzardStyleEvent = event
    blizzardStyleCallback = callback
end

function AF.SetFontShadow(fontString)
    fontString.shadowApplied = true
end

local S = {}

function S.CreateBackdrop(region, noBackground, offset, relativeFrameLevel)
    backdropCalls[#backdropCalls + 1] = {
        noBackground = noBackground,
        offset = offset,
        region = region,
        relativeFrameLevel = relativeFrameLevel,
    }
    region.BFIBackdrop = region.BFIBackdrop or {
        owner = region,
        shown = true,
    }
end

function S.RemoveTextures(region, hide)
    if region == frame then
        error("the root texture sweep would erase native rune animations", 2)
    end

    removeTextureCalls[#removeTextureCalls + 1] = {
        hide = hide,
        region = region,
    }
    if region.IsObjectType and region:IsObjectType("Texture") then
        region:SetTexture("AF_EMPTY_TEXTURE")
        region:SetAtlas("")
        if hide then
            region:Hide()
        end
    end
end

local function recordIconStyle(kind, icon, mask, createBackdrop)
    iconCalls[#iconCalls + 1] = {
        createBackdrop = createBackdrop,
        icon = icon,
        kind = kind,
        mask = mask,
    }
    icon._BFIIconStyled = true
    if mask then
        mask:Hide()
    end
end

function S.StyleIcon(icon, createBackdrop)
    recordIconStyle("icon", icon, nil, createBackdrop)
end

function S.StyleSquareIcon(icon, mask, createBackdrop)
    recordIconStyle("square", icon, mask, createBackdrop)
end

function S.StyleButton(button, color, hoverColor, preservePressScripts)
    buttonCalls[#buttonCalls + 1] = {
        button = button,
        color = color,
        hoverColor = hoverColor,
        preservePressScripts = preservePressScripts,
    }
    button._BFIStyled = true
end

function S.StyleCloseButton(button)
    closeButtonCalls[#closeButtonCalls + 1] = button
    button._BFIStyled = true
end

local function installSecureHook(target, method, hook)
    assertEqual(type(target), "table", method .. " hook target")
    local original = target[method]
    assertEqual(type(original), "function", method .. " hook method")
    secureHooks[#secureHooks + 1] = {
        method = method,
        target = target,
    }
    target[method] = function(...)
        local results = {original(...)}
        hook(...)
        return unpack(results)
    end
end

local challengeMode = setmetatable({}, {
    __index = function(_, key)
        error("C_ChallengeMode." .. tostring(key)
            .. " must not be queried while styling", 2)
    end,
})

local BFI = {
    funcs = {
        isValueNonSecret = function()
            return true
        end,
    },
    modules = {
        Style = S,
    },
}
local addonIsLoaded = false
local environment = {
    AbstractFramework = AF,
    C_AddOns = {
        IsAddOnLoaded = function(addonName)
            assertEqual(addonName, "Blizzard_ChallengesUI",
                "load-state query addon")
            return addonIsLoaded
        end,
    },
    C_ChallengeMode = challengeMode,
    ChallengesKeystoneFrame = frame,
    PVEFrame = {},
    debug = debug,
    hooksecurefunc = installSecureHook,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    tostring = tostring,
    type = type,
    unpack = unpack,
}
environment._G = environment

local chunk, loadError =
    loadfile("Modules/Blizzard/Style/ChallengesUI.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(addonLoadedName, "Blizzard_ChallengesUI",
    "load-on-demand owner")
assertEqual(type(addonLoadedCallback), "function",
    "addon-loaded callback")
assertEqual(blizzardStyleEvent, "BFI_StyleBlizzard",
    "BFI style-ready event")
assertEqual(type(blizzardStyleCallback), "function",
    "BFI style-ready callback")
assertEqual(#backdropCalls, 0, "styling remains deferred")

local tryInitializeChallengesUI = findUpvalue(
    blizzardStyleCallback,
    "TryInitializeChallengesUI"
)
assertEqual(type(tryInitializeChallengesUI), "function",
    "two-gate initializer")
local initializeChallengesUI = findUpvalue(
    tryInitializeChallengesUI,
    "InitializeChallengesUI"
)
assertEqual(type(initializeChallengesUI), "function",
    "Challenges UI initializer")
local styleChallengesKeystoneFrame = findUpvalue(
    initializeChallengesUI,
    "StyleChallengesKeystoneFrame"
)
assertEqual(type(styleChallengesKeystoneFrame), "function",
    "keystone-frame style upvalue")

local challengesFrameStyleCalls = 0
local seasonNoticeStyleCalls = 0
setUpvalue(initializeChallengesUI, "StyleChallengesFrame", function()
    challengesFrameStyleCalls = challengesFrameStyleCalls + 1
end)
setUpvalue(initializeChallengesUI, "StyleSeasonChangeNoticeFrame", function()
    seasonNoticeStyleCalls = seasonNoticeStyleCalls + 1
end)

blizzardStyleCallback()
assertEqual(#backdropCalls, 0,
    "style-ready gate waits for Blizzard addon")
assertEqual(challengesFrameStyleCalls, 0,
    "Challenges panel waits for Blizzard addon")
assertEqual(seasonNoticeStyleCalls, 0,
    "season notice waits for Blizzard addon")

addonLoadedCallback()
assertEqual(challengesFrameStyleCalls, 1,
    "deferred Challenges panel initialization")
assertEqual(seasonNoticeStyleCalls, 1,
    "deferred season-notice initialization")

assertEqual(#backdropCalls, 1, "one popup backdrop")
assertEqual(backdropCalls[1].region, frame, "popup backdrop target")
assertEqual(backdropCalls[1].noBackground, true,
    "popup backdrop keeps native content visible")
assertEqual(backdropCalls[1].relativeFrameLevel, 1,
    "popup border renders above the native shell")
assertEqual(#closeButtonCalls, 1, "close button style count")
assertEqual(closeButtonCalls[1], closeButton, "close button target")
assertEqual(#buttonCalls, 1, "start button style count")
assertEqual(buttonCalls[1].button, startButton, "start button target")
assertEqual(buttonCalls[1].color, "BFI", "start button accent")
assertEqual(buttonCalls[1].preservePressScripts, true,
    "native start-button press path")

assertRGB(outerBackground.colorTexture, "outer background")
assertRGB(frame.InstructionBackground.colorTexture,
    "instruction background")
assertRGB(frame.Divider.vertexColor, "accent divider")
assertEqual(runeBackground.atlas, "ChallengeMode-RuneBG",
    "rune background atlas preserved")
assertEqual(runeBackground.colorTexture, nil,
    "rune background color preserved")
assertEqual(slotGlow.atlas, "ChallengeMode-KeystoneSlotFrameGlow",
    "slot-glow atlas preserved")
assertEqual(slotGlow.colorTexture, nil, "slot-glow color preserved")

assertRGB(dungeonName.textColor, "dungeon name")
assertRGB(powerLevel.textColor, "power level")
assertRGB(timeLimit.textColor, "time limit")
assertRGB(instructions.textColor, "instructions")
assertTrue(dungeonName.shadowApplied, "dungeon-name shadow")
assertTrue(powerLevel.shadowApplied, "power-level shadow")
assertTrue(timeLimit.shadowApplied, "time-limit shadow")
assertTrue(instructions.shadowApplied, "instructions shadow")
assertTrue(#colorRequests >= 5, "AF palette drives popup colors")

local function countIconStyles(icon)
    local count = 0
    local lastCall
    for _, call in ipairs(iconCalls) do
        if call.icon == icon then
            count = count + 1
            lastCall = call
        end
    end
    return count, lastCall
end

local slotIconCount, slotIconCall = countIconStyles(keystoneSlot.Texture)
assertEqual(slotIconCount, 1, "keystone-slot icon style count")
assertEqual(slotIconCall.createBackdrop, true,
    "keystone-slot icon backdrop")
assertEqual(keystoneSlot.CircleMask.shown, false,
    "keystone-slot circle mask removed")

local initialIconCount, initialIconCall =
    countIconStyles(initialAffix.Portrait)
assertEqual(initialIconCount, 1, "initial affix icon style count")
assertEqual(initialIconCall.createBackdrop, true,
    "initial affix icon backdrop")
assertEqual(initialAffix.Border.shown, false,
    "initial affix border removed")

assertEqual(#secureHooks, 1, "one lifecycle post-hook")
assertEqual(secureHooks[1].target, frame, "affix hook target")
assertEqual(secureHooks[1].method, "CreateAndPositionAffixes",
    "dynamic-affix post-hook")

local backdropCount = #backdropCalls
local buttonStyleCount = #buttonCalls
local closeStyleCount = #closeButtonCalls
local iconStyleCount = #iconCalls
local hookCount = #secureHooks
styleChallengesKeystoneFrame()
assertEqual(#backdropCalls, backdropCount, "repeat backdrop count")
assertEqual(#buttonCalls, buttonStyleCount, "repeat button style count")
assertEqual(#closeButtonCalls, closeStyleCount,
    "repeat close-button style count")
assertEqual(#iconCalls, iconStyleCount, "repeat icon style count")
assertEqual(#secureHooks, hookCount, "repeat hook count")

outerBackground:SetAlpha(0.25)
outerBackground:SetShown(false)
dungeonName:Show()
timeLimit:Show()
startButton:Enable()
frame:Reset()
assertEqual(frame.nativeResetCalls, 1, "native Reset call count")
assertEqual(startButton.enabled, false, "native Reset disables Start")
assertEqual(dungeonName.shown, false,
    "native Reset restores dungeon-name visibility")
assertEqual(timeLimit.shown, false,
    "native Reset restores time-limit visibility")
assertEqual(outerBackground.shown, true,
    "native Reset restores background visibility")
assertEqual(outerBackground.alpha, 1,
    "native Reset restores background alpha")
assertRGB(outerBackground.colorTexture,
    "outer background remains skinned after Reset")
assertRGB(dungeonName.textColor,
    "dungeon name remains skinned after Reset")
assertRGB(powerLevel.textColor,
    "power level remains skinned after Reset")
assertEqual(frame.BFIBackdrop.shown, true,
    "popup backdrop remains after Reset")
assertEqual(frame.baseStates, originalBaseStates,
    "native base-state table ownership")
assertEqual(#secureHooks, 1, "Reset requires no post-hook")

local dynamicAffix = makeAffix("DynamicAffix")
frame.pendingAffix = dynamicAffix
local nativeResult, nativeCount = frame:CreateAndPositionAffixes(2)
assertEqual(nativeResult, "native-result", "native affix return value")
assertEqual(nativeCount, 2, "native affix return count")
assertEqual(frame.nativeCreateAffixCalls, 1,
    "native dynamic-affix creation")
assertEqual(frame.lastRequestedAffixCount, 2,
    "native requested affix count")
local dynamicIconCount, dynamicIconCall =
    countIconStyles(dynamicAffix.Portrait)
assertEqual(dynamicIconCount, 1, "dynamic affix icon style count")
assertEqual(dynamicIconCall.createBackdrop, true,
    "dynamic affix icon backdrop")
assertEqual(dynamicAffix.Border.shown, false,
    "dynamic affix border removed")

frame:CreateAndPositionAffixes(2)
assertEqual(frame.nativeCreateAffixCalls, 2,
    "repeat native dynamic-affix layout")
dynamicIconCount = countIconStyles(dynamicAffix.Portrait)
assertEqual(dynamicIconCount, 1,
    "repeat layout does not restyle dynamic affix")
initialIconCount = countIconStyles(initialAffix.Portrait)
assertEqual(initialIconCount, 1,
    "repeat layout does not restyle initial affix")

assertEqual(startButton:GetScript("OnShow"), originalStartOnShow,
    "native StartButton OnShow")
assertEqual(startButton:GetScript("OnClick"), originalStartOnClick,
    "native StartButton OnClick")
assertEqual(keystoneSlot:GetScript("OnEvent"), originalSlotOnEvent,
    "native KeystoneSlot OnEvent")
assertEqual(keystoneSlot:GetScript("OnReceiveDrag"),
    originalSlotOnReceiveDrag, "native KeystoneSlot OnReceiveDrag")
assertEqual(keystoneSlot:GetScript("OnDragStart"), originalSlotOnDragStart,
    "native KeystoneSlot OnDragStart")
assertEqual(keystoneSlot:GetScript("OnClick"), originalSlotOnClick,
    "native KeystoneSlot OnClick")
assertEqual(keystoneSlot.registeredEvents[1],
    "CHALLENGE_MODE_KEYSTONE_SLOTTED", "native slot event")
assertEqual(keystoneSlot.registeredDragButtons[1], "LeftButton",
    "native slot drag registration")
assertEqual(frame.parent, uiParent, "native parent")
assertEqual(frame.points, originalPoints, "native anchors")
assertEqual(frame.size[1], 398, "native width")
assertEqual(frame.size[2], 548, "native height")
assertEqual(frame.strata, "HIGH", "native frame strata")
assertEqual(frame.shown, false, "styling does not show popup")
assertEqual(frame.InsertedAnim.name, "InsertedAnim",
    "native insertion animation")
assertEqual(frame.PulseAnim.name, "PulseAnim", "native pulse animation")

for _, call in ipairs(removeTextureCalls) do
    assertTrue(call.region ~= frame,
        "native rune textures are never swept from the root")
end

-- If Blizzard_ChallengesUI loaded before BFI's visual-style pass, the
-- style-ready callback must perform the catch-up initialization without
-- registering a redundant addon-loaded callback.
addonIsLoaded = true
addonLoadedCallback = nil
addonLoadedName = nil
blizzardStyleCallback = nil
blizzardStyleEvent = nil
frame._BFIKeystoneStyled = nil
local catchUpBackdropCount = #backdropCalls

local catchUpChunk, catchUpLoadError =
    loadfile("Modules/Blizzard/Style/ChallengesUI.lua")
assertEqual(type(catchUpChunk), "function",
    catchUpLoadError or "catch-up module load")
setfenv(catchUpChunk, environment)
catchUpChunk("BFInfinite", BFI)

assertEqual(addonLoadedCallback, nil,
    "already-loaded UI needs no addon callback")
assertEqual(addonLoadedName, nil,
    "already-loaded UI needs no addon registration")
assertEqual(blizzardStyleEvent, "BFI_StyleBlizzard",
    "catch-up style-ready event")
assertEqual(type(blizzardStyleCallback), "function",
    "catch-up style-ready callback")
assertEqual(#backdropCalls, catchUpBackdropCount + 1,
    "already-loaded popup is skinned immediately")

local catchUpTryInitialize = findUpvalue(
    blizzardStyleCallback,
    "TryInitializeChallengesUI"
)
assertEqual(type(catchUpTryInitialize), "function",
    "catch-up two-gate initializer")
local catchUpInitialize = findUpvalue(
    catchUpTryInitialize,
    "InitializeChallengesUI"
)
assertEqual(type(catchUpInitialize), "function",
    "catch-up Challenges UI initializer")

local catchUpChallengesCalls = 0
local catchUpSeasonCalls = 0
setUpvalue(catchUpInitialize, "StyleChallengesFrame", function()
    catchUpChallengesCalls = catchUpChallengesCalls + 1
end)
setUpvalue(catchUpInitialize, "StyleSeasonChangeNoticeFrame", function()
    catchUpSeasonCalls = catchUpSeasonCalls + 1
end)

assertEqual(catchUpChallengesCalls, 0,
    "already-loaded UI still waits for style readiness")
assertEqual(catchUpSeasonCalls, 0,
    "already-loaded season notice waits for style readiness")
blizzardStyleCallback()
assertEqual(catchUpChallengesCalls, 1,
    "already-loaded Challenges panel catch-up")
assertEqual(catchUpSeasonCalls, 1,
    "already-loaded season-notice catch-up")
assertEqual(#backdropCalls, catchUpBackdropCount + 1,
    "style-ready pass does not restyle the popup")

blizzardStyleCallback()
assertEqual(catchUpChallengesCalls, 1,
    "catch-up initializer runs once")
assertEqual(catchUpSeasonCalls, 1,
    "catch-up season initializer runs once")
assertEqual(#backdropCalls, catchUpBackdropCount + 1,
    "catch-up popup initializer runs once")

print("challenges_keystone_frame_skin_test.lua: ok")
