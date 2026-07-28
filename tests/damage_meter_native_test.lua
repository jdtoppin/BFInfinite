local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
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
        availableSettings = {
            [enums.EditModeDamageMeterSetting.Style] = true,
            [enums.EditModeDamageMeterSetting.Numbers] = true,
            [enums.EditModeDamageMeterSetting.FrameWidth] = true,
            [enums.EditModeDamageMeterSetting.ShowSpecIcon] = true,
            [enums.EditModeDamageMeterSetting.ShowClassColor] = true,
        },
        cvars = {
            damageMeterEnabled = true,
            damageMeterResetOnNewInstance = false,
        },
        cvarWriteFailures = {},
        damageMeterInitialized = true,
        getCVarCalls = {},
        getSettingCalls = {},
        inCombat = false,
        managerShown = false,
        maxWindows = 3,
        pendingChanges = false,
        setCVarCalls = {},
        settingValues = {
            [enums.EditModeDamageMeterSetting.Style] =
                enums.DamageMeterStyle.Thin,
            [enums.EditModeDamageMeterSetting.ShowSpecIcon] = 1,
        },
        windowCount = 1,
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
        return state.maxWindows
    end
    function damageMeter:GetCurrentSessionWindowCount()
        return state.windowCount
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

assertEqual(Native.SetSetting, nil, "Edit Mode writes not exposed")
assertEqual(Native.ConfigureWindows, nil, "window writes not exposed")
assertEqual(Native.ConfigureWindowCount, nil, "window count writes not exposed")
assertEqual(Native.GetWindowTypes, nil, "window type state not exposed")
assertEqual(Native.ApplyTripleWindowPreset, nil, "type preset not exposed")

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
    "failed enabled CVar preserves value")
state.cvarWriteFailures.damageMeterResetOnNewInstance = true
ok, reason = Native.SetResetOnNewInstance(false)
assertEqual(ok, false, "failed reset CVar write")
assertEqual(reason, "cvar_write_failed", "failed reset CVar reason")
assertEqual(state.cvars.damageMeterResetOnNewInstance, true,
    "failed reset CVar preserves value")
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
local getSettingCallCount = #state.getSettingCalls
value, reason = Native.GetSetting("style")
assertEqual(value, nil, "uninitialized setting read")
assertEqual(reason, "unavailable", "uninitialized setting reason")
assertEqual(#state.getSettingCalls, getSettingCallCount,
    "uninitialized setting value not read")
state.damageMeterInitialized = true

getSettingCallCount = #state.getSettingCalls
value, reason = Native.GetSetting("frameHeight")
assertEqual(value, nil, "missing setting read")
assertEqual(reason, "unavailable", "missing setting reason")
assertEqual(#state.getSettingCalls, getSettingCallCount,
    "missing setting value not read")

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

manager.layoutType = enums.EditModeLayoutType.Preset
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "preset layout persistence")
assertEqual(reason, "preset", "preset layout persistence reason")
manager.layoutType = enums.EditModeLayoutType.Override
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "override layout persistence")
assertEqual(reason, "preset", "override layout persistence reason")
manager.layoutType = enums.EditModeLayoutType.Account

assertEqual(Native.GetMaxWindowCount(), 3, "maximum window count")
assertEqual(Native.GetWindowCount(), 1, "initial window count")
state.windowCount = 3
assertEqual(Native.GetWindowCount(), 3, "updated window count read")

environment.DamageMeter = nil
value, reason = Native.GetSetting("style")
assertEqual(value, nil, "unavailable setting read")
assertEqual(reason, "unavailable", "unavailable setting reason")
value, reason = Native.GetWindowCount()
assertEqual(value, nil, "unavailable window count")
assertEqual(reason, "unavailable", "unavailable window count reason")
environment.EditModeManagerFrame = nil
ok, reason = Native.CanPersistLayout()
assertEqual(ok, false, "unavailable layout persistence")
assertEqual(reason, "unavailable", "unavailable layout reason")

print("damage_meter_native_test.lua: ok")
