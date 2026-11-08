local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message, tostring(expected), tostring(actual)), 2)
    end
end

local function noop()
end

local function findUpvalue(func, targetName)
    for index = 1, math.huge do
        local name, value = debug.getupvalue(func, index)
        if not name then return end
        if name == targetName then return value end
    end
end

local CLIENT_FONT = "Fonts\\ARHei.ttf"
local LATIN_FONT = "Interface\\AddOns\\AbstractFramework\\Media\\Fonts\\NotoSansCJKsc_AP_Latin.ttf"
local MEDIA_ROOT = "Interface\\AddOns\\AbstractFramework_Media\\Media\\Fonts\\"
local MEDIA_FONTS = {
    Noto_AP = MEDIA_ROOT .. "NotoSansCJKsc_AP.ttf",
    Noto_Dolphin = MEDIA_ROOT .. "NotoSansCJKsc_Dolphin.ttf",
    Unifont = MEDIA_ROOT .. "Unifont.otf",
}

local function loadSession(savedConfig, mediaInstalled, englishClient)
    local registeredFonts = {
        Dolphin = "Interface\\AddOns\\AbstractFramework\\Media\\Fonts\\Dolphin.ttf",
        Noto_AP_Latin = LATIN_FONT,
    }
    if mediaInstalled then
        for name, path in pairs(MEDIA_FONTS) do
            registeredFonts[name] = path
        end
    end
    local defaultChanges = {}
    local LSM = {}
    function LSM:IsValid(kind, name)
        assertEqual(kind, "font", "media kind")
        return registeredFonts[name] ~= nil
    end
    function LSM:Fetch(kind, name)
        assert(self:IsValid(kind, name), "must not fetch an unregistered font")
        return registeredFonts[name]
    end
    function LSM:Register(kind, name, path)
        assertEqual(kind, "font", "registration kind")
        assertEqual(type(path), "string", "registered font path")
        registeredFonts[name] = path
    end
    function LSM:SetDefault(kind, name)
        assert(self:IsValid(kind, name), "must not set an unregistered default")
        defaultChanges[#defaultChanges + 1] = name
    end

    local callbacks = {}
    local eventHandler = {UnregisterEvent = noop, RegisterEvent = noop}
    local AF = {
        Libs = {LSM = LSM},
        player = {class = "PRIEST"},
        CreateSimpleEventHandler = function() return eventHandler end,
        GetAddOnVersion = function() return "r6-alpha", 6 end,
        GetColorTable = function() return {1, 1, 1, 1} end,
        SetAddonAccentColor = noop,
        RequireVersion = function(version)
            assertEqual(version, 44, "runtime AF version")
        end,
        RegisterCallback = function(event, callback)
            callbacks[event] = callback
        end,
        Fire = function(event)
            if callbacks[event] then callbacks[event]() end
        end,
        -- AF's own regression tests cover resolution. This consumer stub
        -- makes invalid raw LSM Fetch/SetDefault calls fail immediately.
        LSM_GetFont = function(name)
            if englishClient and name == "Noto_AP" and not registeredFonts[name] then
                return LATIN_FONT
            end
            return registeredFonts[name] or CLIENT_FONT
        end,
        Debug = noop,
        Clamp = function(value, minimum, maximum)
            return math.max(minimum, math.min(maximum, value))
        end,
    }
    local baseFont
    AF.UpdateBaseFont = function(path) baseFont = path end
    AF.SetFont = function(object, name, size, outline)
        object.path, object.size, object.outline = AF.LSM_GetFont(name), size, outline
    end

    local gameFont = {path = CLIENT_FONT, size = 13, outline = ""}
    function gameFont:GetFont() return self.path, self.size, self.outline end
    function gameFont:GetShadowOffset() return 0, 0 end

    local environment = {
        AbstractFramework = AF,
        BFIConfig = savedConfig,
        LOCALE_enUS = englishClient == true,
        GameFontNormal = gameFont,
        GetCVar = function() return "1" end,
        GetCVarBool = function() return false end,
        GetCVarDefault = function() return "1" end,
        SetCVar = noop,
        MILLISECONDS_ABBR = "ms",
        LAG_TOLERANCE = "Lag Tolerance",
        SHOW_PLAYER_NAMES = "Show Player Names",
        UNIT_NAME_GUILD = "Guild",
        UNIT_NAME_PLAYER_TITLE = "PvP Title",
    }
    environment._G = environment
    setmetatable(environment, {__index = _G})
    local BFI = {
        name = "BFInfinite", vars = {}, modules = {ActionBars = {}},
        funcs = {ReviseCommon = noop, ReviseProfile = noop},
        L = setmetatable({}, {__index = function(_, key) return key end}),
    }
    local function loadModule(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end
    loadModule("Core.lua")
    loadModule("Modules/General.lua")
    eventHandler:ADDON_LOADED("BFInfinite")

    return {
        config = environment.BFIConfig, fonts = registeredFonts,
        environment = environment, defaultChanges = defaultChanges,
        baseFont = baseFont, gameFont = gameFont,
        AF = AF, BFI = BFI, callbacks = callbacks, loadModule = loadModule,
    }
end

local function assertMissing(session)
    assertEqual(session.fonts.BFI, CLIENT_FONT, "BFI alias uses client fallback")
    assertEqual(session.baseFont, CLIENT_FONT, "AF settings use client fallback")
    assertEqual(session.environment.STANDARD_TEXT_FONT, CLIENT_FONT, "Blizzard text fallback")
    assertEqual(session.gameFont.path, CLIENT_FONT, "font objects use client fallback")
    assertEqual(#session.defaultChanges, 0, "missing font never changes global LSM default")
end

local fresh = loadSession(nil, false)
assertMissing(fresh)
assertEqual(fresh.config.general.font.common.font, "Noto_AP", "fresh preferred font is retained")

for _, installed in ipairs({false, true}) do
    local english = loadSession(nil, installed, true)
    assertEqual(english.config.general.font.common.font, "Noto_AP_Latin", "English default is included slim font")
    assertEqual(english.fonts.BFI, LATIN_FONT, "English BFI alias uses slim font")
    assertEqual(english.baseFont, LATIN_FONT, "English settings use slim font")
    assertEqual(english.environment.STANDARD_TEXT_FONT, LATIN_FONT, "English Blizzard text uses slim font")
    assertEqual(english.defaultChanges[1], "Noto_AP_Latin", "English LSM default is available")
end

local saved = {general = {font = {
    common = {font = "Noto_AP", overrideAF = true, overrideBlizzard = true, blizzardFontSizeDelta = 0},
    combatText = {font = "Noto_Dolphin", override = true},
    nameText = {font = "Unifont", override = true},
}}}
local absent = loadSession(saved, false)
assertMissing(absent)
assertEqual(absent.environment.DAMAGE_TEXT_FONT, CLIENT_FONT, "combat font fallback")
assertEqual(absent.environment.UNIT_NAME_FONT, CLIENT_FONT, "name font fallback")

for _, installed in ipairs({false, true, false}) do
    local englishSaved = loadSession(saved, installed, true)
    local expected = installed and MEDIA_FONTS.Noto_AP or LATIN_FONT
    assertEqual(englishSaved.config.general.font.common.font, "Noto_AP", "English existing full-font preference retained")
    assertEqual(englishSaved.fonts.BFI, expected, "English existing preference resolves across pack changes")
    assertEqual(englishSaved.baseFont, expected, "English existing settings retain base font style")
    assertEqual(englishSaved.environment.DAMAGE_TEXT_FONT, installed and MEDIA_FONTS.Noto_Dolphin or CLIENT_FONT, "other optional fonts keep their existing fallback")
end

for _, installed in ipairs({true, false, true}) do
    local session = loadSession(saved, installed)
    assertEqual(session.config.general.font.common.font, "Noto_AP", "common choice survives pack changes")
    assertEqual(session.config.general.font.combatText.font, "Noto_Dolphin", "combat choice survives pack changes")
    assertEqual(session.config.general.font.nameText.font, "Unifont", "name choice survives pack changes")
    if installed then
        assertEqual(session.fonts.BFI, MEDIA_FONTS.Noto_AP, "BFI alias restores media font")
        assertEqual(session.baseFont, MEDIA_FONTS.Noto_AP, "AF settings restore media font")
        assertEqual(session.environment.STANDARD_TEXT_FONT, MEDIA_FONTS.Noto_AP, "Blizzard text restores media font")
        assertEqual(session.environment.DAMAGE_TEXT_FONT, MEDIA_FONTS.Noto_Dolphin, "combat font restores")
        assertEqual(session.environment.UNIT_NAME_FONT, MEDIA_FONTS.Unifont, "name font restores")
        assertEqual(session.defaultChanges[1], "Noto_AP", "installed choice becomes LSM default")
    else
        assertMissing(session)
    end
end

local function loadFontOptions(session)
    local AF = session.AF
    local dropdowns = {}
    local pane
    local function widget()
        return {
            SetAllPoints = noop, SetLabel = noop, SetChecked = noop,
            SetEnabled = noop, SetValue = noop, SetOnCheck = noop,
            SetAfterValueChanged = noop, SetOnSelect = noop,
            SetTooltip = function(self, ...) self.tooltip = {...} end,
            SetTips = function(self, ...) self.tips = {...} end,
        }
    end
    AF.CreateFrame = widget
    AF.ApplyCombatProtectionToFrame = noop
    AF.CreateTitledPane = function() pane = widget(); return pane end
    AF.SetPoint = noop
    AF.WrapTextInColor = function(text) return text end
    AF.CreateCheckButton = widget
    AF.CreateSlider = widget
    AF.LSM_GetFontDropdownItems = function()
        local items = {}
        for name, path in pairs(session.fonts) do
            items[#items + 1] = {text = name, value = name, font = path}
        end
        return items
    end
    AF.CreateDropdown = function()
        local dropdown = widget()
        function dropdown:SetItems(items) self.items = items end
        function dropdown:SetSelectedValue(value)
            self.text, self.selected = "", nil
            for _, item in ipairs(self.items) do
                if item.value == value then
                    self.text, self.selected = item.text, item
                    return
                end
            end
        end
        dropdowns[#dropdowns + 1] = dropdown
        return dropdown
    end
    session.loadModule("Options/General.lua")
    local showOptions = session.callbacks.BFI_ShowOptionsPanel
    findUpvalue(showOptions, "CreateGeneralPanel")()
    findUpvalue(showOptions, "CreateFontPane")()
    pane.Load()
    return dropdowns, pane
end

local absentDropdowns, absentPane = loadFontOptions(absent)
local englishDropdowns = loadFontOptions(loadSession(nil, false, true))
assertEqual(englishDropdowns[1].text, "Noto_AP_Latin", "English base font appears as available")
assertEqual(englishDropdowns[1].selected.disabled, nil, "English base font is selectable without media pack")
for index, name in ipairs({"Noto_AP", "Noto_Dolphin", "Unifont"}) do
    assertEqual(absentDropdowns[index].text, name .. " (unavailable)", "missing selection stays visible")
    assertEqual(absentDropdowns[index].selected.value, name, "missing selection value is preserved")
    assertEqual(absentDropdowns[index].selected.disabled, true, "unavailable font cannot be newly selected")
end
assert(absentPane.tips[3]:find("AbstractFramework_Media", 1, true), "font pane identifies optional addon")
assert(absentPane.tips[4]:find("saved choice is kept", 1, true), "font pane explains retained preference")
assert(table.concat(absentDropdowns[1].tooltip, " "):find("Dolphin is the small Latin font", 1, true), "tooltip distinguishes Dolphin from Noto_Dolphin")

local installedDropdowns = loadFontOptions(loadSession(saved, true))
for index, name in ipairs({"Noto_AP", "Noto_Dolphin", "Unifont"}) do
    assertEqual(installedDropdowns[index].text, name, "installed selection is shown normally")
    assertEqual(installedDropdowns[index].selected.disabled, nil, "installed font can be selected")
end
for _, item in ipairs(installedDropdowns[1].items) do
    assert(item.value ~= "BFI", "BFI alias must not select itself")
end

print("optional_media_fonts_test.lua: ok")
