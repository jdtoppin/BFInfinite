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

local function makeTexture(name)
    local texture = {
        name = name,
    }

    function texture:Hide()
        self.hidden = true
    end

    function texture:SetAlpha(alpha)
        self.alpha = alpha
    end

    function texture:SetAtlas(atlas)
        self.atlas = atlas
    end

    function texture:SetTexture(value)
        self.texture = value
    end

    return texture
end

local function makeRegion(name, ...)
    return {
        name = name,
        textures = {...},
    }
end

local function makeFontString(name)
    local fontString = {
        name = name,
    }

    function fontString:SetShadowColor(...)
        self.shadowColor = {...}
    end

    function fontString:SetTextColor(...)
        self.textColor = {...}
    end

    return fontString
end

local textBackground = makeTexture("TextBackground")
local portrait = makeTexture("Portrait")
local portraitBackground = makeTexture("PortraitBg")
local sheen = makeTexture("Sheen")
local textSheen = makeTexture("TextSheen")
local glowTop = makeTexture("Glow_TopBar")
local glowLeft = makeTexture("Glow_LeftBar")
local glowRight = makeTexture("Glow_RightBar")
local name = makeFontString("Name")
local text = makeFontString("Text")

local model = makeRegion("Model", portraitBackground)
model.shown = true

local overlay = makeRegion("Overlay", glowTop, glowLeft, glowRight)
overlay.Glow_TopBar = glowTop
overlay.Glow_LeftBar = glowLeft
overlay.Glow_RightBar = glowRight

local closeButton = {
    name = "CloseButton",
}
local mainFrame = makeRegion("MainFrame", sheen, textSheen)
mainFrame.CloseButton = closeButton
mainFrame.Model = model
mainFrame.Overlay = overlay
mainFrame.Sheen = sheen
mainFrame.TextSheen = textSheen

local originalClick = function()
end
local originalEvents = {
    "TALKINGHEAD_REQUESTED",
    "TALKINGHEAD_CLOSE",
}
local originalPoints = {
    "BOTTOM",
    0,
    96,
}
local frame = {
    BackgroundFrame = makeRegion("BackgroundFrame", textBackground),
    isInEditMode = true,
    isManagedFrame = true,
    MainFrame = mainFrame,
    NameFrame = {
        Name = name,
    },
    OnClick = originalClick,
    points = originalPoints,
    registeredEvents = originalEvents,
    PortraitFrame = makeRegion("PortraitFrame", portrait),
    TextFrame = {
        Text = text,
    },
}
frame.BackgroundFrame.TextBackground = textBackground
frame.PortraitFrame.Portrait = portrait

function frame:PlayCurrent()
    textBackground:SetAtlas("TalkingHeads-Horde-TextBackground")
    portrait:SetAtlas("TalkingHeads-Horde-PortraitFrame")
    portraitBackground:SetAtlas("TalkingHeads-Horde-PortraitBg")
    textBackground:SetAlpha(1)
    portrait:SetAlpha(1)
    portraitBackground:SetAlpha(1)
    name:SetTextColor(0.28, 0.02, 0.02)
    text:SetTextColor(0, 0, 0)
    name:SetShadowColor(0, 0, 0, 0)
    text:SetShadowColor(0, 0, 0, 0)
end

function frame:FadeinFrames()
    self.nativeFadeInCalls = (self.nativeFadeInCalls or 0) + 1
end

function frame:FadeoutFrames()
    self.nativeFadeOutCalls = (self.nativeFadeOutCalls or 0) + 1
end

function frame:UpdateShownState()
    self.nativeShownStateCalls = (self.nativeShownStateCalls or 0) + 1
end

local callbacks = {}
local hookCount = 0
local removeCalls = {}
local backdropCalls = {}
local closeButtonCalls = 0
local fadeAnimationCalls = {}
local colors = {
    BFI = {1, 0.4, 0, 1},
    white = {1, 1, 1, 1},
}

local AF = {
    UIParent = {},
}

function AF.CreateFadeInOutAnimation(region, duration, noHide)
    fadeAnimationCalls[#fadeAnimationCalls + 1] = {
        duration = duration,
        noHide = noHide,
        region = region,
    }

    function region:FadeIn()
        self.fadeInCalls = (self.fadeInCalls or 0) + 1
        self.fadeInStartAlpha = self.alpha
        self.alpha = 1
    end

    function region:FadeOut()
        self.fadeOutCalls = (self.fadeOutCalls or 0) + 1
        self.fadeOutStartAlpha = self.alpha
        self.alpha = 0
    end

    function region:SetAlpha(alpha)
        self.alpha = alpha
    end

    function region:SetFadeDuration(fadeDuration)
        self.fadeDuration = fadeDuration
    end

    function region:ShowNow()
        self.showNowCalls = (self.showNowCalls or 0) + 1
        self.alpha = 1
        self.shown = true
    end
end

function AF.GetColorRGB(color)
    return unpack(colors[color])
end

function AF.RegisterAddonLoaded()
    error("Talking Head must not wait for ADDON_LOADED", 2)
end

function AF.CreateMover()
end

function AF.ClearPoints(region)
    region:ClearAllPoints()
end

function AF.SetPoint(region, point, relativeTo, relativePoint, x, y)
    region:SetPoint(point, relativeTo, relativePoint, x, y)
end

function AF.RegisterCallback(event, registeredCallback)
    callbacks[event] = registeredCallback
end

function AF.SetFontShadow(fontString)
    fontString:SetShadowColor(0, 0, 0, 1)
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
    region.BFIBackdrop = {
        alpha = 1,
        shown = true,
    }
end

function S.RemoveTextures(region, hide)
    removeCalls[#removeCalls + 1] = region
    for _, texture in ipairs(region.textures) do
        texture:SetTexture(nil)
        texture:SetAtlas("")
        if hide then
            texture:Hide()
        end
    end
end

function S.StyleCloseButton(button)
    closeButtonCalls = closeButtonCalls + 1
    button._BFIStyled = true
end

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

local environment = {
    AbstractFramework = AF,
    CreateFrame = function()
        local proxy = {}

        function proxy:ClearAllPoints()
        end

        function proxy:Hide()
        end

        function proxy:RegisterEvent()
        end

        function proxy:SetScript()
        end

        function proxy:SetPoint()
        end

        function proxy:SetSize()
        end

        return proxy
    end,
    hooksecurefunc = function(target, method, hook)
        local original = target[method]
        hookCount = hookCount + 1
        target[method] = function(...)
            original(...)
            hook(...)
        end
    end,
    ipairs = ipairs,
    math = math,
    select = select,
    tostring = tostring,
    type = type,
    unpack = unpack,
}
environment._G = environment
environment.OTHER = "Other"
environment.HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL = "Talking Head"
environment.TalkingHeadFrame = frame

local chunk, loadError =
    loadfile("Modules/Blizzard/Style/TalkingHeadFrame.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callbacks.BFI_StyleBlizzard), "function", "startup style callback")
assertEqual(type(callbacks.BFI_PrepareEditModePositions), "function", "mover prepare callback")
assertEqual(#removeCalls, 0, "styling is deferred")

callbacks.BFI_StyleBlizzard()

assertEqual(#removeCalls, 5, "native art containers")
assertTrue(textBackground.hidden, "text background hidden")
assertTrue(portrait.hidden, "portrait frame hidden")
assertTrue(portraitBackground.hidden, "portrait background hidden")
assertTrue(sheen.hidden, "sheen hidden")
assertTrue(textSheen.hidden, "text sheen hidden")
assertTrue(glowTop.hidden, "top glow hidden")
assertTrue(glowLeft.hidden, "left glow hidden")
assertTrue(glowRight.hidden, "right glow hidden")
assertTrue(model.shown, "talking-head model preserved")

assertEqual(#backdropCalls, 2, "replacement backdrops")
assertEqual(backdropCalls[1].region, frame, "root backdrop target")
assertEqual(backdropCalls[1].relativeFrameLevel, -1,
    "root backdrop layer")
assertEqual(backdropCalls[2].region, model, "portrait border target")
assertEqual(backdropCalls[2].noBackground, true,
    "portrait border has no background")
assertEqual(backdropCalls[2].relativeFrameLevel, 1,
    "portrait border layer")
assertEqual(closeButtonCalls, 1, "close button styled")
assertEqual(#fadeAnimationCalls, 1, "backdrop fade setup")
assertEqual(fadeAnimationCalls[1].region, frame.BFIBackdrop,
    "backdrop fade target")
assertEqual(fadeAnimationCalls[1].duration, 1,
    "default backdrop fade duration")
assertEqual(fadeAnimationCalls[1].noHide, true,
    "faded backdrop remains available")
assertEqual(hookCount, 4, "Talking Head lifecycle hooks")

assertEqual(name.textColor[1], colors.BFI[1], "name color")
assertEqual(text.textColor[1], colors.white[1], "body color")
assertTrue(name.shadowApplied, "name shadow")
assertTrue(text.shadowApplied, "body shadow")

frame:FadeoutFrames()
assertEqual(frame.nativeFadeOutCalls, 1, "native fade-out preserved")
assertEqual(frame.BFIBackdrop.fadeOutCalls, 1, "backdrop fade-out")
assertEqual(frame.BFIBackdrop.fadeOutStartAlpha, 1,
    "backdrop fade-out start alpha")
assertEqual(frame.BFIBackdrop.fadeDuration, 1,
    "backdrop fade-out duration")
assertEqual(frame.BFIBackdrop.alpha, 0,
    "backdrop reaches zero alpha before the root hides")

frame:FadeinFrames()
assertEqual(frame.nativeFadeInCalls, 1, "native fade-in preserved")
assertEqual(frame.BFIBackdrop.fadeInCalls, 1, "backdrop fade-in")
assertEqual(frame.BFIBackdrop.fadeInStartAlpha, 0,
    "backdrop fade-in start alpha")
assertEqual(frame.BFIBackdrop.fadeDuration, 0.75,
    "backdrop fade-in duration")
assertEqual(frame.BFIBackdrop.alpha, 1,
    "backdrop reaches full alpha")

frame.BFIBackdrop.alpha = 0
frame.isInEditMode = true
frame.isPlaying = false
frame:UpdateShownState()
assertEqual(frame.nativeShownStateCalls, 1,
    "native shown-state update preserved")
assertEqual(frame.BFIBackdrop.alpha, 1,
    "Edit Mode restores the backdrop")

frame.BFIBackdrop.alpha = 0
frame.isInEditMode = false
frame:UpdateShownState()
assertEqual(frame.BFIBackdrop.alpha, 0,
    "ordinary hidden state does not restore the backdrop")
frame.isInEditMode = true

frame:PlayCurrent()
assertTrue(textBackground.hidden,
    "texture-kit update does not reshow the background")
assertTrue(portrait.hidden,
    "texture-kit update does not reshow the portrait frame")
assertTrue(portraitBackground.hidden,
    "texture-kit update does not reshow the portrait background")
assertEqual(name.textColor[1], colors.BFI[1],
    "name color restored after PlayCurrent")
assertEqual(text.textColor[1], colors.white[1],
    "body color restored after PlayCurrent")
assertEqual(name.shadowColor[4], 1,
    "name shadow restored after PlayCurrent")
assertEqual(text.shadowColor[4], 1,
    "body shadow restored after PlayCurrent")

callbacks.BFI_StyleBlizzard()
assertEqual(#removeCalls, 5, "repeat initialization is ignored")
assertEqual(#backdropCalls, 2, "no duplicate backdrops")
assertEqual(closeButtonCalls, 1, "no duplicate close-button skin")
assertEqual(#fadeAnimationCalls, 1, "no duplicate fade setup")
assertEqual(hookCount, 4, "no duplicate hooks")

assertEqual(frame.OnClick, originalClick, "native click handler preserved")
assertEqual(frame.registeredEvents, originalEvents, "native events preserved")
assertEqual(frame.points, originalPoints, "managed anchor preserved")
assertEqual(frame.isManagedFrame, true, "managed-frame state preserved")
assertEqual(frame.isInEditMode, true, "Edit Mode state preserved")

local loadFile = assert(io.open("Modules/Blizzard/Load.xml", "r"))
local loadContents = loadFile:read("*a")
loadFile:close()
assertTrue(loadContents:find(
    '<Script file="Style\\TalkingHeadFrame.lua"/>',
    1,
    true
), "Talking Head skin is loaded")

print("talking_head_frame_skin_test.lua: ok")
