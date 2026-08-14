local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message, 2)
    end
end

local function newWidget(state, kind, parent)
    local widget = {
        enabled = true,
        kind = kind,
        parent = parent,
        points = {},
        shown = true,
    }

    function widget:SetAllPoints()
        self.allPoints = true
    end

    function widget:SetHeight(height)
        self.height = height
    end

    function widget:SetWidth(width)
        self.width = width
    end

    function widget:SetScrollStep(step)
        self.scrollStep = step
    end

    function widget:SetShown(shown)
        self.shown = shown and true or false
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:Show()
        self.shown = true
    end

    function widget:Hide()
        self.shown = false
    end

    function widget:SetEnabled(enabled)
        self.enabled = enabled and true or false
    end

    function widget:SetText(text)
        self.text = text
    end

    function widget:SetColor(color)
        self.color = color
    end

    function widget:SetJustifyH(justify)
        self.justifyH = justify
    end

    function widget:SetTips(...)
        self.tips = self.tips or newWidget(state, "tips", self)
        self.tips.arguments = {...}
    end

    function widget:SetTipsPosition(position, x, y)
        self.tipPosition = {position, x, y}
    end

    function widget:SetOnCheck(callback)
        self.onCheck = callback
    end

    function widget:SetChecked(checked)
        self.checked = checked and true or false
    end

    function widget:SetLabel(label)
        self.label = label
        state.controls[label] = self
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = nil
        self.selectedText = nil
        for _, item in ipairs(self.items or {}) do
            if item.value == value then
                self.selectedValue = value
                self.selectedText = item.text
                break
            end
        end
    end

    function widget:SetAfterValueChanged(callback)
        self.afterValueChanged = callback
    end

    function widget:SetValue(value)
        self.value = value
    end

    function widget:SetMinMaxValues(low, high)
        self.low = low
        self.high = high
    end

    function widget:SetOnClick(callback)
        self.onClick = callback
    end

    return widget
end

local function createHarness()
    local state = {
        callbacks = {},
        combatProtectionCalls = 0,
        combatQueries = 0,
        controls = {},
        dataAvailable = false,
        deferredCallbacks = {},
        fires = {},
        fontStrings = {},
        namedFrames = {},
        nativeReset = true,
        panes = {},
        repointed = {},
        resetPositionCalls = 0,
        scrollFrames = {},
    }
    local root = newWidget(state, "root")
    local AF = {}

    function AF.CreateFrame(parent, name)
        local frame = newWidget(state, "frame", parent)
        if name then
            state.namedFrames[name] = frame
        end
        return frame
    end

    function AF.CreateScrollFrame(parent)
        local frame = newWidget(state, "scroll", parent)
        frame.scrollContent = newWidget(state, "scrollContent", frame)
        state.scrollFrames[#state.scrollFrames + 1] = frame
        return frame
    end

    function AF.CreateTitledPane(parent, title, width, height)
        local pane = newWidget(state, "titledPane", parent)
        pane.titleText = title
        pane.width = width
        pane.height = height
        state.panes[title] = pane
        return pane
    end

    function AF.CreateFontString(parent, text, color)
        local fontString = newWidget(state, "fontString", parent)
        fontString.text = text
        fontString.color = color
        state.fontStrings[#state.fontStrings + 1] = fontString
        return fontString
    end

    function AF.CreateCheckButton(parent, label)
        local control = newWidget(state, "checkButton", parent)
        control.label = label
        state.controls[label] = control
        return control
    end

    function AF.CreateDropdown(parent, width)
        local control = newWidget(state, "dropdown", parent)
        control.width = width
        return control
    end

    function AF.CreateSlider(parent, label, width, low, high, step, percentage)
        local control = newWidget(state, "slider", parent)
        control.label = label
        control.width = width
        control.low = low
        control.high = high
        control.step = step
        control.percentage = percentage and true or false
        state.controls[label] = control
        return control
    end

    function AF.CreateButton(parent, label)
        local control = newWidget(state, "button", parent)
        control.label = label
        state.controls[label] = control
        return control
    end

    function AF.SetPoint(widget, ...)
        widget.points[#widget.points + 1] = {...}
    end

    function AF.RePoint(widget)
        state.repointed[#state.repointed + 1] = widget
    end

    function AF.LSM_GetBarTextureDropdownItems()
        return {
            {text = "AF", value = "AF"},
            {text = "Test Texture", value = "TestTexture"},
        }
    end

    function AF.RegisterCallback(name, callback)
        state.callbacks[name] = callback
    end

    function AF.Fire(...)
        state.fires[#state.fires + 1] = {...}
    end

    function AF.ApplyCombatProtectionToWidget()
        state.combatProtectionCalls = state.combatProtectionCalls + 1
    end

    local config = {
        alwaysShowPlayer = false,
        backgroundAlpha = 0.73,
        barAlpha = 0.66,
        barHeight = 19,
        classColor = true,
        enabled = false,
        headerHeight = 25,
        headerTextSize = 12,
        locked = true,
        numberMode = "perSecond",
        padding = 6,
        rowTextSize = 12,
        resetOnMythicPlusStart = true,
        showSpecIcon = false,
        spacing = 4,
        texture = "TestTexture",
        width = 333,
        windowCount = 3,
        windowTypes = {
            "DamageDone",
            "HealingDone",
            "DamageTaken",
        },
        windowSyncSessions = {
            true,
            false,
            true,
        },
        windowAutoCurrentOnCombat = {
            false,
            true,
            false,
        },
        windowAutoCurrentOnMythicPlusStart = {
            true,
            false,
            true,
        },
        windowAutoOverallOnMythicPlusComplete = {
            false,
            true,
            false,
        },
        mythicPlusWindowTypes = {
            false,
            "Deaths",
            "Absorbs",
        },
        windowHeights = {
            277,
            288,
            299,
        },
    }
    local damageMeter = {
        config = config,
        Data = {
            IsAvailable = function()
                return state.dataAvailable
            end,
            Reset = function() end,
        },
        Native = {
            GetResetOnNewInstance = function()
                return state.nativeReset
            end,
            SetResetOnNewInstance = function(value)
                state.nativeReset = value and true or false
                return true
            end,
        },
        Renderer = {
            ResetPosition = function()
                state.resetPositionCalls = state.resetPositionCalls + 1
            end,
        },
    }
    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = L,
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local environment = {
        AbstractFramework = AF,
        BFIOptionsFrame_ContentPane = root,
        C_Timer = {
            After = function(delay, callback)
                state.deferredCallbacks[#state.deferredCallbacks + 1] = {
                    callback = callback,
                    delay = delay,
                }
            end,
        },
        InCombatLockdown = function()
            state.combatQueries = state.combatQueries + 1
            return true
        end,
    }
    setmetatable(environment, {__index = _G})
    environment._G = environment

    local chunk, loadError = loadfile("Options/DamageMeter.lua")
    assertEqual(type(chunk), "function", loadError or "options module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return state, damageMeter
end

local state, DM = createHarness()
local showPanel = state.callbacks.BFI_ShowOptionsPanel
local refreshPanel = state.callbacks.BFI_RefreshOptions
assertEqual(type(showPanel), "function", "show callback registration")
assertEqual(type(refreshPanel), "function", "refresh callback registration")

showPanel(nil, "damageMeter")

local panel = state.namedFrames.BFIOptionsFrame_DamageMeterPanel
local general = state.panes["BFI Damage Meter"]
local meters = state.panes.Meters
local status = state.fontStrings[1]
assertTrue(panel and panel:IsShown(), "Damage Meter panel must build and show")
assertEqual(
    #state.deferredCallbacks,
    1,
    "first open schedules a next-frame scroll layout refresh"
)
assertEqual(state.deferredCallbacks[1].delay, 0, "layout refresh delay")
assertEqual(#state.repointed, 0, "layout refresh remains deferred")
state.deferredCallbacks[1].callback()
assertEqual(#state.repointed, 1, "first open refreshes scroll layout")
assertEqual(
    state.repointed[1],
    state.scrollFrames[1],
    "first open refreshes the Damage Meter scroll frame"
)

showPanel(nil, "general")
showPanel(nil, "damageMeter")
assertEqual(
    #state.deferredCallbacks,
    2,
    "reopening schedules another scroll layout refresh"
)
state.deferredCallbacks[2].callback()
assertEqual(#state.repointed, 2, "reopening refreshes scroll layout")

showPanel(nil, "damageMeter")
showPanel(nil, "general")
state.deferredCallbacks[3].callback()
assertEqual(
    #state.repointed,
    2,
    "a stale refresh does not reanchor a hidden panel"
)
showPanel(nil, "damageMeter")
state.deferredCallbacks[4].callback()
assertEqual(#state.repointed, 3, "a later visible reopen still refreshes")
assertTrue(
    general and meters and state.panes["Sessions and Automation"]
        and state.panes.Appearance
        and state.panes["Damage Meter Actions"],
    "all Damage Meter panes must build"
)
assertEqual(general.height, 60, "empty General pane height")
assertEqual(status.text, "", "empty status text")
assertEqual(status:IsShown(), false, "empty status hidden")
assertEqual(meters.points[1][2], general, "Meters pane anchor parent")
assertEqual(meters.points[1][3], "BOTTOMLEFT", "Meters pane anchor edge")
assertEqual(meters.points[1][5], -12, "compact section gap")

local placeMeters =
    state.controls["Place Meters Below Objective Tracker"]
assertTrue(placeMeters ~= nil, "tracker-safe placement action")
placeMeters.onClick()
assertEqual(
    state.resetPositionCalls,
    1,
    "tracker-safe placement action resets the meter stack"
)
assertEqual(
    state.controls["Place Meters Bottom Right"],
    nil,
    "obsolete overlapping placement action removed"
)

local expectedTips = {
    ["BFI Damage Meter"] = "BFI Damage Meter Tip",
    Meters = "BFI Damage Meter Windows Tip",
    ["Sessions and Automation"] = "BFI Damage Meter Automation Tip",
    Appearance = "BFI Damage Meter Appearance Tip",
}
for title, body in pairs(expectedTips) do
    local tips = state.panes[title].tips
    assertTrue(tips ~= nil, title .. " info button")
    assertEqual(#tips.arguments, 2, title .. " tooltip argument count")
    assertEqual(tips.arguments[1], title, title .. " tooltip title")
    assertEqual(tips.arguments[2], body, title .. " tooltip body")
    assertTrue(
        tips.arguments[1] ~= tips.arguments[2],
        title .. " tooltip title and body must remain distinct"
    )
    assertEqual(
        tips.tipPosition[1],
        "BOTTOMRIGHT",
        title .. " tooltip grows inward"
    )
end

local width = state.controls["Frame Width"]
local headerHeight = state.controls["Header Height"]
local barHeight = state.controls["Bar Height"]
local padding = state.controls.Padding
local barTextSize = state.controls["Bar Text Size"]
local headerTextSize = state.controls["Header Text Size"]
local windowCount = state.controls["Window Count"]
local firstMeterType = state.controls["Meter 1 Type"]
local secondMeterType = state.controls["Meter 2 Type"]
local firstMeterHeight = state.controls["Meter 1 Height"]
local secondMeterHeight = state.controls["Meter 2 Height"]
local thirdMeterHeight = state.controls["Meter 3 Height"]
local lockMeters = state.controls["Lock Meters"]
local alwaysShowPlayer = state.controls["Always Show Player"]
local resetOnMythicPlusStart =
    state.controls["Reset Data on Mythic+ Start"]
local firstMythicPlusType =
    state.controls["Meter 1 Type on Mythic+ Start"]
local secondMythicPlusType =
    state.controls["Meter 2 Type on Mythic+ Start"]
local firstSyncSessions =
    state.controls["Meter 1 Sync Session Selection"]
local secondSyncSessions =
    state.controls["Meter 2 Sync Session Selection"]
local firstAutoCurrentOnCombat =
    state.controls["Meter 1 Auto Current on Combat"]
local secondAutoCurrentOnCombat =
    state.controls["Meter 2 Auto Current on Combat"]
local firstAutoCurrentOnMythicPlusStart =
    state.controls["Meter 1 Current on Mythic+ Start"]
local secondAutoCurrentOnMythicPlusStart =
    state.controls["Meter 2 Current on Mythic+ Start"]
local firstAutoOverallOnMythicPlusComplete =
    state.controls["Meter 1 Overall on Mythic+ Complete"]
local secondAutoOverallOnMythicPlusComplete =
    state.controls["Meter 2 Overall on Mythic+ Complete"]
local texture = state.controls["Bar Texture"]
local enabled = state.controls["Enable BFI Damage Meter"]
assertTrue(width and width:IsShown(), "Frame Width control visible")
assertEqual(state.controls["Meter Text Size"], nil,
    "single combined meter text size control removed")
assertEqual(width.value, 333, "Frame Width loaded value")
assertEqual(windowCount.selectedValue, 3, "Window Count loaded value")
assertEqual(windowCount.selectedText, "3", "Window Count visible text")
assertEqual(
    firstMeterType.selectedValue,
    "DamageDone",
    "first meter type loaded value"
)
assertEqual(#firstMeterType.items, 11, "all Blizzard meter types exposed")
local expectedMeterTypes = {
    DamageDone = true,
    Dps = true,
    HealingDone = true,
    Hps = true,
    Absorbs = true,
    Interrupts = true,
    Dispels = true,
    DamageTaken = true,
    AvoidableDamageTaken = true,
    Deaths = true,
    EnemyDamageTaken = true,
}
for _, item in ipairs(firstMeterType.items) do
    expectedMeterTypes[item.value] = nil
end
assertEqual(
    next(expectedMeterTypes),
    nil,
    "every Blizzard meter type has a dropdown item"
)
assertEqual(firstMeterHeight.value, 277, "first meter height loaded")
assertEqual(secondMeterHeight.value, 288, "second meter height loaded")
assertEqual(thirdMeterHeight.value, 299, "third meter height loaded")
assertEqual(firstMeterHeight.low, 84, "meter height minimum is compact")
assertEqual(firstMeterHeight.high, 520, "meter height maximum remains available")
assertEqual(barTextSize.low, 8, "bar text size minimum")
assertEqual(barTextSize.high, 14, "bar text size maximum")
assertEqual(headerTextSize.low, 8, "header text size minimum")
assertEqual(headerTextSize.high, 14, "header text size maximum")
assertEqual(lockMeters.checked, true, "lock state loaded")
assertEqual(alwaysShowPlayer.checked, false, "player pin state loaded")
assertEqual(
    resetOnMythicPlusStart.checked,
    true,
    "key-start reset state loaded"
)
assertEqual(
    firstMythicPlusType.selectedText,
    "Keep Current Type",
    "first key-start type default visible"
)
assertEqual(
    secondMythicPlusType.selectedValue,
    "Deaths",
    "second key-start type loaded"
)
assertEqual(
    #firstMythicPlusType.items,
    12,
    "key-start type exposes keep-current and every meter type"
)
assertEqual(firstSyncSessions.checked, true, "first session sync loaded")
assertEqual(secondSyncSessions.checked, false, "second session sync loaded")
assertEqual(
    firstAutoCurrentOnCombat.checked,
    false,
    "first combat automation loaded"
)
assertEqual(
    secondAutoCurrentOnCombat.checked,
    true,
    "second combat automation loaded"
)
assertEqual(
    firstAutoCurrentOnMythicPlusStart.checked,
    true,
    "first key-start session loaded"
)
assertEqual(
    secondAutoCurrentOnMythicPlusStart.checked,
    false,
    "second key-start session loaded"
)
assertEqual(
    firstAutoOverallOnMythicPlusComplete.checked,
    false,
    "first key-complete session loaded"
)
assertEqual(
    secondAutoOverallOnMythicPlusComplete.checked,
    true,
    "second key-complete session loaded"
)
assertEqual(
    state.controls["Frame Height"],
    nil,
    "shared frame height control removed"
)
assertEqual(
    state.controls["Accent Header"],
    nil,
    "obsolete Accent Header control removed"
)
assertEqual(texture.selectedValue, "TestTexture", "texture loaded value")
assertEqual(texture.selectedText, "Test Texture", "texture visible text")
assertEqual(barTextSize.value, 12, "bar text size loaded")
assertEqual(headerTextSize.value, 12, "header text size loaded")
assertEqual(enabled.checked, false, "enabled state loaded")
assertTrue(enabled.enabled, "enabled control remains writable")

firstMeterType.onSelect("Deaths")
assertEqual(DM.config.windowTypes[1], "Deaths", "meter type writes live")
secondMeterHeight.afterValueChanged(345)
assertEqual(
    DM.config.windowHeights[2],
    345,
    "per-window height writes live"
)
DM.config.windowHeights[3] = 84
barTextSize.afterValueChanged(14)
assertEqual(DM.config.rowTextSize, 14, "bar text size writes live")
barHeight.afterValueChanged(14)
assertEqual(
    barTextSize.high,
    10,
    "compact bar height lowers the bar text size maximum"
)
assertEqual(
    DM.config.rowTextSize,
    10,
    "compact bar height clamps the configured bar text size"
)
headerTextSize.afterValueChanged(14)
assertEqual(DM.config.headerTextSize, 14, "header text size writes live")
headerHeight.afterValueChanged(18)
assertEqual(headerTextSize.high, 12,
    "compact header height lowers the header text size maximum")
assertEqual(DM.config.headerTextSize, 12,
    "compact header height clamps the configured header text size")
headerHeight.afterValueChanged(36)
barHeight.afterValueChanged(36)
padding.afterValueChanged(12)
assertEqual(firstMeterHeight.low, 96,
    "dense appearance raises the meter height minimum")
assertEqual(thirdMeterHeight.low, 96,
    "every meter uses the dense appearance minimum")
assertEqual(DM.config.windowHeights[3], 96,
    "dense appearance preserves one complete meter row")
assertEqual(barTextSize.high, 14,
    "larger bars restore the bar text size maximum")
assertEqual(headerTextSize.high, 14,
    "larger headers restore the header text size maximum")
barTextSize.afterValueChanged(12)
assertEqual(DM.config.rowTextSize, 12,
    "restored bar text size writes live")
DM.config.windowHeights[1] = 301
DM.config.windowHeights[2] = 302
DM.config.windowHeights[3] = 303
refreshPanel(nil, "damageMeter")
assertEqual(firstMeterHeight.value, 301, "external first height refreshes")
assertEqual(secondMeterHeight.value, 302, "external second height refreshes")
assertEqual(thirdMeterHeight.value, 303, "external third height refreshes")
lockMeters.onCheck(false)
assertEqual(DM.config.locked, false, "lock setting writes live")
alwaysShowPlayer.onCheck(true)
assertEqual(DM.config.alwaysShowPlayer, true, "player pin writes live")
resetOnMythicPlusStart.onCheck(false)
assertEqual(
    DM.config.resetOnMythicPlusStart,
    false,
    "key-start reset writes live"
)
firstMythicPlusType.onSelect("HealingDone")
assertEqual(
    DM.config.mythicPlusWindowTypes[1],
    "HealingDone",
    "key-start type writes live"
)
firstMythicPlusType.onSelect(firstMythicPlusType.items[1].value)
assertEqual(
    DM.config.mythicPlusWindowTypes[1],
    false,
    "keep-current clears key-start type"
)
firstSyncSessions.onCheck(false)
assertEqual(
    DM.config.windowSyncSessions[1],
    false,
    "session sync writes live"
)
firstAutoCurrentOnCombat.onCheck(true)
assertEqual(
    DM.config.windowAutoCurrentOnCombat[1],
    true,
    "combat automation writes live"
)
firstAutoCurrentOnMythicPlusStart.onCheck(false)
assertEqual(
    DM.config.windowAutoCurrentOnMythicPlusStart[1],
    false,
    "key-start session writes live"
)
firstAutoOverallOnMythicPlusComplete.onCheck(true)
assertEqual(
    DM.config.windowAutoOverallOnMythicPlusComplete[1],
    true,
    "key-complete session writes live"
)
windowCount.onSelect(1)
assertEqual(secondMeterType.enabled, false, "hidden meter type disabled")
assertEqual(secondMeterHeight.enabled, false, "hidden meter height disabled")
assertEqual(
    secondMythicPlusType.enabled,
    false,
    "hidden meter key-start type disabled"
)
assertEqual(
    secondSyncSessions.enabled,
    false,
    "hidden meter session sync disabled"
)
assertEqual(
    secondAutoCurrentOnCombat.enabled,
    false,
    "hidden meter combat automation disabled"
)
assertEqual(
    secondAutoCurrentOnMythicPlusStart.enabled,
    false,
    "hidden meter key-start session disabled"
)
assertEqual(
    secondAutoOverallOnMythicPlusComplete.enabled,
    false,
    "hidden meter key-complete session disabled"
)
windowCount.onSelect(3)
assertEqual(secondMeterType.enabled, true, "shown meter type enabled")
assertEqual(secondMeterHeight.enabled, true, "shown meter height enabled")
assertEqual(
    secondMythicPlusType.enabled,
    true,
    "shown meter key-start type enabled"
)
assertEqual(
    secondSyncSessions.enabled,
    true,
    "shown meter session sync enabled"
)

enabled:SetChecked(true)
enabled.onCheck(true)
assertEqual(DM.config.enabled, true, "enabled callback writes during combat")
assertEqual(general.height, 80, "unavailable status expands General pane")
assertEqual(status:IsShown(), true, "unavailable status shown")
assertEqual(
    status.text,
    "Damage Meter Data Unavailable",
    "unavailable status message"
)

state.dataAvailable = true
refreshPanel(nil, "damageMeter")
assertEqual(general.height, 60, "available status restores compact pane")
assertEqual(status:IsShown(), false, "available status hidden")
assertEqual(state.combatQueries, 0, "settings must not query combat lockdown")
assertEqual(
    state.combatProtectionCalls,
    0,
    "settings must not apply combat protection"
)

local lastFire = state.fires[#state.fires]
assertEqual(lastFire[1], "BFI_UpdateModule", "live settings refresh event")
assertEqual(lastFire[2], "damageMeter", "live settings refresh module")

print("damage_meter_options_test.lua: ok")
