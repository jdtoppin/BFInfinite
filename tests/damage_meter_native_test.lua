local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertArray(actual, expected, message)
    assertEqual(#actual, #expected, message .. " count")
    for i, value in ipairs(expected) do
        assertEqual(actual[i], value, message .. " item " .. i)
    end
end

local function newWindow(index, damageMeterType, shown)
    local window = {
        damageMeterType = damageMeterType,
        index = index,
        shown = shown,
    }
    function window:IsShown()
        return self.shown
    end
    return window
end

local function loadNative()
    local enums = {
        DamageMeterNumbers = {
            Minimal = 0,
            Compact = 1,
            Complete = 2,
        },
        DamageMeterStyle = {
            Default = 0,
            Thin = 1,
            Bordered = 2,
            FullBackground = 3,
        },
        DamageMeterType = {
            DamageDone = 0,
            Dps = 1,
            HealingDone = 2,
            Hps = 3,
            Absorbs = 4,
            Interrupts = 5,
            Dispels = 6,
            DamageTaken = 7,
            AvoidableDamageTaken = 8,
            Deaths = 9,
            EnemyDamageTaken = 10,
        },
        DamageMeterVisibility = {
            Always = 0,
            InCombat = 1,
            Hidden = 2,
            InGroup = 3,
        },
        EditModeDamageMeterSetting = {
            Visibility = 0,
            Style = 1,
            Numbers = 2,
            FrameWidth = 3,
            FrameHeight = 4,
            Padding = 5,
            Transparency = 6,
            ShowSpecIcon = 8,
            ShowClassColor = 9,
            BarHeight = 10,
            TextSize = 11,
            BackgroundTransparency = 12,
        },
        EditModeLayoutType = {
            Preset = 0,
            Account = 1,
            Character = 2,
            Override = 3,
        },
    }
    local state = {
        cvars = {
            damageMeterEnabled = true,
            damageMeterResetOnNewInstance = false,
        },
        availableSettings = {
            [enums.EditModeDamageMeterSetting.Style] = true,
            [enums.EditModeDamageMeterSetting.Numbers] = true,
            [enums.EditModeDamageMeterSetting.FrameWidth] = true,
            [enums.EditModeDamageMeterSetting.ShowSpecIcon] = true,
            [enums.EditModeDamageMeterSetting.ShowClassColor] = true,
        },
        cvarWriteFailures = {},
        damageMeterInitialized = true,
        getCVarCalls = {},
        getSettingCalls = {},
        hideCalls = {},
        inCombat = false,
        managerShown = false,
        pendingChanges = false,
        saveCalls = 0,
        setCVarCalls = {},
        settingCalls = {},
        settingValues = {
            [enums.EditModeDamageMeterSetting.Style] =
                enums.DamageMeterStyle.Thin,
            [enums.EditModeDamageMeterSetting.ShowSpecIcon] = 1,
        },
        showCalls = 0,
        typeCalls = {},
        windows = {
            [1] = newWindow(1, enums.DamageMeterType.DamageDone, true),
        },
    }

    local damageMeter = {}
    function damageMeter:IsInitialized()
        return state.damageMeterInitialized
    end
    function damageMeter:HasSetting(setting)
        return state.availableSettings[setting] == true
    end
    function damageMeter:GetSettingValue(setting)
        state.getSettingCalls[#state.getSettingCalls + 1] = setting
        if not state.damageMeterInitialized then
            return 0
        end
        return state.settingValues[setting] or 0
    end
    function damageMeter:GetMaxSessionWindowCount()
        return 3
    end
    function damageMeter:GetCurrentSessionWindowCount()
        local count = 0
        for i = 1, 3 do
            if state.windows[i] and state.windows[i]:IsShown() then
                count = count + 1
            end
        end
        return count
    end
    function damageMeter:GetSessionWindow(index)
        return state.windows[index]
    end
    function damageMeter:GetSessionWindowDamageMeterType(window)
        return window.damageMeterType
    end
    function damageMeter:ShowNewSecondarySessionWindow()
        state.showCalls = state.showCalls + 1
        for i = 2, 3 do
            local window = state.windows[i]
            if not window then
                state.windows[i] = newWindow(
                    i,
                    enums.DamageMeterType.DamageDone,
                    true
                )
                return
            elseif not window:IsShown() then
                window.shown = true
                return
            end
        end
    end
    function damageMeter:HideSessionWindow(window)
        state.hideCalls[#state.hideCalls + 1] = window.index
        window.shown = false
    end
    function damageMeter:SetSessionWindowDamageMeterType(window, value)
        state.typeCalls[#state.typeCalls + 1] = {
            index = window.index,
            value = value,
        }
        window.damageMeterType = value
    end

    local manager = {
        layoutType = enums.EditModeLayoutType.Account,
    }
    function manager:GetActiveLayoutInfo()
        return {
            layoutType = self.layoutType,
        }
    end
    function manager:HasActiveChanges()
        return state.pendingChanges
    end
    function manager:IsShown()
        return state.managerShown
    end
    function manager:OnSystemSettingChange(owner, setting, value)
        state.settingCalls[#state.settingCalls + 1] = {
            owner = owner,
            setting = setting,
            value = value,
        }
        state.settingValues[setting] = value
    end
    function manager:SaveLayouts()
        state.saveCalls = state.saveCalls + 1
    end

    local damageMeterModule = {}
    local BFI = {
        modules = {
            DamageMeter = damageMeterModule,
        },
    }
    local environment = {
        C_CVar = {
            GetCVarBool = function(name)
                state.getCVarCalls[#state.getCVarCalls + 1] = name
                return state.cvars[name]
            end,
            SetCVar = function(name, value)
                state.setCVarCalls[#state.setCVarCalls + 1] = {
                    name = name,
                    value = value,
                }
                if state.cvarWriteFailures[name] then
                    return false
                end
                state.cvars[name] = value == "1"
                return true
            end,
        },
        DamageMeter = damageMeter,
        EditModeManagerFrame = manager,
        Enum = enums,
        InCombatLockdown = function()
            return state.inCombat
        end,
        ipairs = ipairs,
        math = math,
        next = next,
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Native.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeterModule.Native, state, enums, environment, manager
end

local Native, state, enums, environment, manager = loadNative()

local width = Native.GetSettingDefinition("frameWidth")
assertEqual(width.setting, enums.EditModeDamageMeterSetting.FrameWidth,
    "width setting")
assertEqual(width.min, 200, "width minimum")
assertEqual(width.max, 600, "width maximum")
assertEqual(width.step, 1, "width step")
width.min = 0
assertEqual(Native.GetSettingDefinition("frameWidth").min, 200,
    "definition copy")

local height = Native.GetSettingDefinition("frameHeight")
assertEqual(height.min, 120, "height minimum")
assertEqual(height.max, 400, "height maximum")
local barHeight = Native.GetSettingDefinition("barHeight")
assertEqual(barHeight.min, 15, "bar height minimum")
assertEqual(barHeight.max, 40, "bar height maximum")
local padding = Native.GetSettingDefinition("padding")
assertEqual(padding.min, 2, "padding minimum")
assertEqual(padding.max, 10, "padding maximum")
local transparency = Native.GetSettingDefinition("transparency")
assertEqual(transparency.min, 50, "transparency minimum")
assertEqual(transparency.max, 100, "transparency maximum")
local background = Native.GetSettingDefinition("backgroundTransparency")
assertEqual(background.min, 0, "background minimum")
assertEqual(background.max, 100, "background maximum")
local textSize = Native.GetSettingDefinition("textSize")
assertEqual(textSize.min, 50, "text size minimum")
assertEqual(textSize.max, 150, "text size maximum")
assertEqual(textSize.step, 10, "text size step")
assertEqual(Native.GetSettingDefinition("showSpecIcon").boolean, true,
    "spec icon boolean")
assertEqual(Native.GetSettingDefinition("showClassColor").boolean, true,
    "class color boolean")
assertEqual(
    Native.GetSettingDefinition("style").values[
        enums.DamageMeterStyle.FullBackground
    ],
    nil,
    "obsolete style excluded"
)
assertEqual(Native.GetSettingDefinition("missing"), nil,
    "unknown definition")

local availableTypes = Native.GetDamageMeterTypes()
assertEqual(#availableTypes, 11, "available type count")
assertEqual(availableTypes[1].key, "damageDone", "first type key")
assertEqual(availableTypes[1].value,
    enums.DamageMeterType.DamageDone, "first type value")
assertEqual(availableTypes[1].labelGlobal,
    "DAMAGE_METER_TYPE_DAMAGE_DONE", "first type label")
assertEqual(availableTypes[11].key, "enemyDamageTaken",
    "last type key")
assertEqual(availableTypes[11].value,
    enums.DamageMeterType.EnemyDamageTaken, "last type value")
assertEqual(availableTypes[11].labelGlobal,
    "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN", "last type label")
availableTypes[1].value = -1
assertEqual(Native.GetDamageMeterTypes()[1].value,
    enums.DamageMeterType.DamageDone, "available types copy")
assertArray(Native.GetTripleWindowPreset(), {
    enums.DamageMeterType.DamageDone,
    enums.DamageMeterType.HealingDone,
    enums.DamageMeterType.DamageTaken,
}, "triple preset")

assertEqual(Native.GetEnabled(), true, "enabled CVar read")
assertEqual(state.getCVarCalls[1], "damageMeterEnabled",
    "enabled CVar name")
local ok, reason = Native.SetEnabled(false)
assertEqual(ok, true, "enabled CVar write")
assertEqual(reason, nil, "enabled CVar write reason")
assertEqual(state.setCVarCalls[1].name, "damageMeterEnabled",
    "enabled CVar set name")
assertEqual(state.setCVarCalls[1].value, "0", "enabled CVar false value")
assertEqual(Native.GetResetOnNewInstance(), false,
    "reset CVar read")
assertEqual(state.getCVarCalls[2], "damageMeterResetOnNewInstance",
    "reset CVar name")
ok, reason = Native.SetResetOnNewInstance(true)
assertEqual(ok, true, "reset CVar write")
assertEqual(reason, nil, "reset CVar write reason")
assertEqual(state.setCVarCalls[2].name,
    "damageMeterResetOnNewInstance", "reset CVar set name")
assertEqual(state.setCVarCalls[2].value, "1", "reset CVar true value")
state.cvarWriteFailures.damageMeterEnabled = true
ok, reason = Native.SetEnabled(true)
assertEqual(ok, false, "failed enabled CVar write")
assertEqual(reason, "cvar_write_failed", "failed enabled CVar reason")
assertEqual(state.cvars.damageMeterEnabled, false,
    "failed enabled CVar write preserves value")
state.cvarWriteFailures.damageMeterResetOnNewInstance = true
ok, reason = Native.SetResetOnNewInstance(false)
assertEqual(ok, false, "failed reset CVar write")
assertEqual(reason, "cvar_write_failed", "failed reset CVar reason")
assertEqual(state.cvars.damageMeterResetOnNewInstance, true,
    "failed reset CVar write preserves value")
ok, reason = Native.SetEnabled(1)
assertEqual(ok, false, "invalid enabled CVar value")
assertEqual(reason, "invalid_value", "invalid enabled CVar reason")
ok, reason = Native.SetResetOnNewInstance("yes")
assertEqual(ok, false, "invalid reset CVar value")
assertEqual(reason, "invalid_value", "invalid reset CVar reason")
assertEqual(#state.setCVarCalls, 4, "invalid CVar writes suppressed")

local value
value, reason = Native.GetSetting("style")
assertEqual(value, enums.DamageMeterStyle.Thin, "style read")
assertEqual(reason, nil, "style read reason")
assertEqual(state.getSettingCalls[1],
    enums.EditModeDamageMeterSetting.Style, "style read setting")
value, reason = Native.GetSetting("showSpecIcon")
assertEqual(value, true, "boolean setting read")
assertEqual(reason, nil, "boolean setting read reason")
value, reason = Native.GetSetting("missing")
assertEqual(value, nil, "unknown setting read")
assertEqual(reason, "unknown_setting", "unknown setting reason")

state.damageMeterInitialized = false
assertEqual(
    environment.DamageMeter:GetSettingValue(
        enums.EditModeDamageMeterSetting.Style
    ),
    0,
    "native uninitialized setting value contract"
)
local getSettingCallCount = #state.getSettingCalls
value, reason = Native.GetSetting("style")
assertEqual(value, nil, "uninitialized system setting read")
assertEqual(reason, "unavailable", "uninitialized system setting reason")
assertEqual(#state.getSettingCalls, getSettingCallCount,
    "uninitialized setting value not read")
ok, reason = Native.SetSetting("frameWidth", 350)
assertEqual(ok, false, "uninitialized system setting write")
assertEqual(reason, "unavailable", "uninitialized system write reason")
assertEqual(#state.settingCalls, 0,
    "uninitialized setting mutation suppressed")
assertEqual(state.saveCalls, 0, "uninitialized setting save suppressed")
state.damageMeterInitialized = true

assertEqual(
    environment.DamageMeter:GetSettingValue(
        enums.EditModeDamageMeterSetting.FrameHeight
    ),
    0,
    "native missing setting value contract"
)
getSettingCallCount = #state.getSettingCalls
value, reason = Native.GetSetting("frameHeight")
assertEqual(value, nil, "missing system setting read")
assertEqual(reason, "unavailable", "missing system setting reason")
assertEqual(#state.getSettingCalls, getSettingCallCount,
    "missing setting value not read")
ok, reason = Native.SetSetting("frameHeight", 240)
assertEqual(ok, false, "missing system setting write")
assertEqual(reason, "unavailable", "missing system setting write reason")
assertEqual(#state.settingCalls, 0, "missing setting mutation suppressed")
assertEqual(state.saveCalls, 0, "missing setting save suppressed")

ok, reason = Native.CanPersistLayout()
assertEqual(ok, true, "account layout persistence")
assertEqual(reason, nil, "account layout persistence reason")
manager.layoutType = enums.EditModeLayoutType.Character
ok, reason = Native.CanPersistLayout()
assertEqual(ok, true, "character layout persistence")
assertEqual(reason, nil, "character layout persistence reason")
manager.layoutType = enums.EditModeLayoutType.Account

state.inCombat = true
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "combat layout persistence")
assertEqual(reason, "combat", "combat layout persistence reason")
ok, reason = Native.SetSetting("frameWidth", 350)
assertEqual(ok, false, "combat setting write")
assertEqual(reason, "combat", "combat setting reason")
ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.DamageDone,
})
assertEqual(ok, false, "combat window configuration")
assertEqual(reason, "combat", "combat window reason")
state.inCombat = false

state.managerShown = true
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "active Edit Mode persistence")
assertEqual(reason, "edit_mode_active", "active Edit Mode reason")
state.managerShown = false

state.pendingChanges = true
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "pending layout persistence")
assertEqual(reason, "pending_changes", "pending layout reason")
state.pendingChanges = false

ok, reason = Native.SetSetting("frameWidth", 350)
assertEqual(ok, true, "width write")
assertEqual(reason, nil, "width write reason")
assertEqual(state.settingCalls[1].owner, environment.DamageMeter,
    "width owner")
assertEqual(state.settingCalls[1].setting,
    enums.EditModeDamageMeterSetting.FrameWidth, "width enum")
assertEqual(state.settingCalls[1].value, 350, "width display value")
assertEqual(state.saveCalls, 1, "width save")

ok, reason = Native.SetSetting("showClassColor", true)
assertEqual(ok, true, "boolean write")
assertEqual(reason, nil, "boolean write reason")
assertEqual(state.settingCalls[2].setting,
    enums.EditModeDamageMeterSetting.ShowClassColor, "boolean enum")
assertEqual(state.settingCalls[2].value, 1, "boolean display value")
assertEqual(state.saveCalls, 2, "boolean save")

ok, reason = Native.SetSetting("frameWidth", 199)
assertEqual(ok, false, "width below minimum")
assertEqual(reason, "invalid_value", "width minimum reason")
ok, reason = Native.SetSetting("textSize", 55)
assertEqual(ok, false, "text size step")
assertEqual(reason, "invalid_value", "text size step reason")
ok, reason = Native.SetSetting("style",
    enums.DamageMeterStyle.FullBackground)
assertEqual(ok, false, "obsolete style write")
assertEqual(reason, "invalid_value", "obsolete style reason")
ok, reason = Native.SetSetting("missing", 1)
assertEqual(ok, false, "unknown setting write")
assertEqual(reason, "unknown_setting", "unknown setting write reason")
assertEqual(#state.settingCalls, 2, "invalid setting writes suppressed")
assertEqual(state.saveCalls, 2, "invalid setting saves suppressed")

manager.layoutType = enums.EditModeLayoutType.Preset
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "preset layout persistence")
assertEqual(reason, "preset", "preset layout persistence reason")
ok, reason = Native.SetSetting("numbers",
    enums.DamageMeterNumbers.Complete)
assertEqual(ok, false, "preset setting write")
assertEqual(reason, "preset", "preset setting reason")
assertEqual(#state.settingCalls, 2, "preset mutation suppressed")
assertEqual(state.saveCalls, 2, "preset save suppressed")
manager.layoutType = enums.EditModeLayoutType.Override
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "override layout persistence")
assertEqual(reason, "preset", "override layout persistence reason")
manager.layoutType = enums.EditModeLayoutType.Account

assertEqual(Native.GetMaxWindowCount(), 3, "maximum window count")
assertEqual(Native.GetWindowCount(), 1, "initial window count")
assertArray(Native.GetWindowTypes(), {
    enums.DamageMeterType.DamageDone,
}, "initial window types")

ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.Dps,
    enums.DamageMeterType.Hps,
    enums.DamageMeterType.Deaths,
})
assertEqual(ok, true, "three-window configuration")
assertEqual(reason, nil, "three-window configuration reason")
assertEqual(state.showCalls, 2, "secondary windows shown")
assertEqual(Native.GetWindowCount(), 3, "three-window count")
assertArray(Native.GetWindowTypes(), {
    enums.DamageMeterType.Dps,
    enums.DamageMeterType.Hps,
    enums.DamageMeterType.Deaths,
}, "three-window types")

ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.DamageDone,
    enums.DamageMeterType.DamageTaken,
})
assertEqual(ok, true, "two-window configuration")
assertEqual(reason, nil, "two-window configuration reason")
assertEqual(Native.GetWindowCount(), 2, "two-window count")
assertEqual(state.hideCalls[#state.hideCalls], 3, "third window hidden")
assertArray(Native.GetWindowTypes(), {
    enums.DamageMeterType.DamageDone,
    enums.DamageMeterType.DamageTaken,
}, "two-window types")

ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.HealingDone,
})
assertEqual(ok, true, "one-window configuration")
assertEqual(reason, nil, "one-window configuration reason")
assertEqual(Native.GetWindowCount(), 1, "one-window count")
assertEqual(state.hideCalls[#state.hideCalls], 2, "second window hidden")
assertArray(Native.GetWindowTypes(), {
    enums.DamageMeterType.HealingDone,
}, "one-window types")

ok, reason = Native.ApplyTripleWindowPreset()
assertEqual(ok, true, "triple preset apply")
assertEqual(reason, nil, "triple preset apply reason")
assertArray(Native.GetWindowTypes(), {
    enums.DamageMeterType.DamageDone,
    enums.DamageMeterType.HealingDone,
    enums.DamageMeterType.DamageTaken,
}, "applied triple preset")

ok, reason = Native.ConfigureWindows({})
assertEqual(ok, false, "zero windows rejected")
assertEqual(reason, "window_count", "zero windows reason")
ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.DamageDone,
    enums.DamageMeterType.HealingDone,
    enums.DamageMeterType.DamageTaken,
    enums.DamageMeterType.Deaths,
})
assertEqual(ok, false, "four windows rejected")
assertEqual(reason, "window_count", "four windows reason")
ok, reason = Native.ConfigureWindows({99})
assertEqual(ok, false, "unknown type rejected")
assertEqual(reason, "invalid_value", "unknown type reason")
ok, reason = Native.ConfigureWindows({
    [1] = enums.DamageMeterType.DamageDone,
    [3] = enums.DamageMeterType.HealingDone,
})
assertEqual(ok, false, "sparse type list rejected")
assertEqual(reason, "invalid_value", "sparse type list reason")

environment.DamageMeter = nil
value, reason = Native.GetSetting("style")
assertEqual(value, nil, "unavailable setting read")
assertEqual(reason, "unavailable", "unavailable setting reason")
value, reason = Native.GetWindowCount()
assertEqual(value, nil, "unavailable window count")
assertEqual(reason, "unavailable", "unavailable window count reason")
ok, reason = Native.ConfigureWindows({
    enums.DamageMeterType.DamageDone,
})
assertEqual(ok, false, "unavailable window configuration")
assertEqual(reason, "unavailable", "unavailable window reason")
environment.EditModeManagerFrame = nil
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "unavailable layout persistence")
assertEqual(reason, "unavailable", "unavailable layout persistence reason")

print("damage_meter_native_test.lua: ok")
