local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertSame(actual, expected, message)
    if actual ~= expected then
        error(message or "expected identical values", 2)
    end
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

local startupCallback
local addonLoadedCallback
local backdropCalls = 0
local backdropOptions
local ordinaryStyleCalls = 0
local onePixelInsideCalls = 0
local hookCalls = {}

local function makeTooltip()
    local tooltip = {
        Delimiter1 = {},
        Delimiter2 = {},
        NineSlice = {},
    }

    function tooltip:IsForbidden()
        return false
    end

    function tooltip.Delimiter1:SetTexture()
    end

    function tooltip.Delimiter2:SetTexture()
    end

    return tooltip
end

local uiParent = {}
local AF = {}
local S = {}

function AF.RegisterCallback(event, callback)
    assertEqual(event, "BFI_StyleBlizzard", "startup callback event")
    startupCallback = callback
end

function AF.RegisterAddonLoaded(addon, callback)
    assertEqual(addon, "Blizzard_AuraContainer", "addon-loaded registration")
    addonLoadedCallback = callback
end

function AF.GetOnePixelForRegion(region)
    assertSame(region, uiParent, "pixel reference frame")
    return 1.25
end

function AF.GetPlainTexture()
    return "Interface\\AddOns\\AbstractFramework\\Media\\Textures\\White"
end

function AF.GetColorRGB(color)
    if color == "background" then
        return 0.1, 0.2, 0.3, 0.85
    elseif color == "border" then
        return 0.4, 0.5, 0.6, 1
    end
    error("unexpected color " .. tostring(color), 2)
end

function AF.ApplyDefaultBackdropWithColors()
    ordinaryStyleCalls = ordinaryStyleCalls + 1
end

function AF.SetOnePixelInside()
    onePixelInsideCalls = onePixelInsideCalls + 1
end

function AF.SetPoint()
end

function AF.AddToPixelUpdater_Auto()
end

function S.StyleIcon()
end

function S.StyleIconBorder()
end

function S.CreateBackdrop()
end

local function createColor(r, g, b, a)
    return {r = r, g = g, b = b, a = a}
end

local function hookSecureFunction(name)
    hookCalls[#hookCalls + 1] = name
end

local embeddedItemTooltip = makeTooltip()
embeddedItemTooltip.ItemTooltip = {
    Icon = {},
    IconBorder = {},
}

local gameTooltip = makeTooltip()
local gameTooltipStatusBar = {}
function gameTooltipStatusBar:SetStatusBarTexture()
end
function gameTooltipStatusBar:ClearAllPoints()
end

local campaignTooltip = makeTooltip()

local environment = {
    _G = false,
    AbstractFramework = AF,
    CreateColor = createColor,
    EmbeddedItemTooltip = embeddedItemTooltip,
    FriendsTooltip = makeTooltip(),
    GameTooltip = gameTooltip,
    GameTooltipStatusBar = gameTooltipStatusBar,
    ItemRefShoppingTooltip1 = makeTooltip(),
    ItemRefShoppingTooltip2 = makeTooltip(),
    ItemRefTooltip = makeTooltip(),
    LibDBIconTooltip = makeTooltip(),
    QuickKeybindTooltip = makeTooltip(),
    ReputationParagonTooltip = makeTooltip(),
    SettingsTooltip = makeTooltip(),
    ShoppingTooltip1 = makeTooltip(),
    ShoppingTooltip2 = makeTooltip(),
    UIParent = uiParent,
    WorldMapTooltip = makeTooltip(),
    debug = debug,
    hooksecurefunc = hookSecureFunction,
    next = next,
    QuestMapLog_GetCampaignTooltip = function()
        return campaignTooltip
    end,
    select = select,
    tostring = tostring,
    type = type,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        if key == "AuraButtonTooltip" then
            error("forbidden AuraButtonTooltip lookup", 2)
        end
    end,
})

local BFI = {
    media = {
        bar = "BFI bar texture",
    },
    modules = {
        Style = S,
    },
}

local chunk, loadError = loadfile("Modules/Blizzard/Style/Tooltip.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(startupCallback), "function", "startup callback")
assertEqual(type(addonLoadedCallback), "function", "addon-loaded callback")

local styleAuraButtonTooltip = findUpvalue(
    startupCallback,
    "StyleAuraButtonTooltip"
)
assertEqual(type(styleAuraButtonTooltip), "function", "native tooltip style upvalue")
assertSame(addonLoadedCallback, styleAuraButtonTooltip, "shared retry callback")

-- Loading order is not assumed: the startup path must fail closed when the
-- Blizzard inbound API is absent, then the ADDON_LOADED path may retry.
startupCallback()
assertEqual(backdropCalls, 0, "missing capability call count")
assertEqual(ordinaryStyleCalls, 14, "ordinary tooltip style call count")
assertEqual(onePixelInsideCalls, 14, "ordinary tooltip inset call count")
assertEqual(#hookCalls, 3, "ordinary tooltip hook count")
assertEqual(hookCalls[1], "SharedTooltip_SetBackdropStyle", "backdrop hook")
assertEqual(hookCalls[2], "GameTooltip_ShowStatusBar", "status-bar hook")
assertEqual(hookCalls[3], "GameTooltip_ShowProgressBar", "progress-bar hook")

environment.AuraContainerInbound = {}
addonLoadedCallback()
assertEqual(backdropCalls, 0, "missing setter call count")

environment.AuraContainerInbound = {
    SetTooltipBackdrop = {},
}
addonLoadedCallback()
assertEqual(backdropCalls, 0, "non-function setter call count")

environment.AuraContainerInbound = {
    SetTooltipBackdrop = function(options)
        backdropCalls = backdropCalls + 1
        backdropOptions = options
    end,
}

addonLoadedCallback()
assertEqual(backdropCalls, 1, "native backdrop call count")

local backdropInfo = backdropOptions.backdropInfo
assertEqual(backdropInfo.bgFile, AF.GetPlainTexture(), "background texture")
assertEqual(backdropInfo.edgeFile, AF.GetPlainTexture(), "border texture")
assertEqual(backdropInfo.edgeSize, 1.25, "border size")
assertEqual(backdropInfo.insets.left, 1.25, "left inset")
assertEqual(backdropInfo.insets.right, 1.25, "right inset")
assertEqual(backdropInfo.insets.top, 1.25, "top inset")
assertEqual(backdropInfo.insets.bottom, 1.25, "bottom inset")

assertEqual(backdropOptions.borderColor.r, 0.4, "border red")
assertEqual(backdropOptions.borderColor.g, 0.5, "border green")
assertEqual(backdropOptions.borderColor.b, 0.6, "border blue")
assertEqual(backdropOptions.borderColor.a, 1, "border alpha")
assertEqual(backdropOptions.centerColor.r, 0.1, "background red")
assertEqual(backdropOptions.centerColor.g, 0.2, "background green")
assertEqual(backdropOptions.centerColor.b, 0.3, "background blue")
assertEqual(backdropOptions.centerColor.a, 0.85, "background alpha")

assertEqual(backdropOptions.anchorOffsets.left, 1.25, "left anchor inset")
assertEqual(backdropOptions.anchorOffsets.right, -1.25, "right anchor inset")
assertEqual(backdropOptions.anchorOffsets.top, -1.25, "top anchor inset")
assertEqual(backdropOptions.anchorOffsets.bottom, 1.25, "bottom anchor inset")

styleAuraButtonTooltip()
assertEqual(backdropCalls, 1, "idempotent native backdrop call count")

print("native_aura_tooltip_skin_test.lua: ok")
