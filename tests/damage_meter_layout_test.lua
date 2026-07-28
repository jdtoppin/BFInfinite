local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertPoint(frame, expected, message)
    local point = frame.points[#frame.points]
    assertEqual(type(point), "table", message .. " exists")
    for i, value in ipairs(expected) do
        assertEqual(point[i], value, message .. " value " .. i)
    end
end

local function newWindow(name, shown)
    local window = {
        clearCalls = 0,
        name = name,
        points = {},
        shown = shown,
        sizeCalls = {},
        userPlaced = nil,
    }

    function window:ClearAllPoints()
        self.clearCalls = self.clearCalls + 1
        self.points = {}
    end

    function window:IsShown()
        return self.shown
    end

    function window:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function window:SetSize(width, height)
        self.sizeCalls[#self.sizeCalls + 1] = {
            width = width,
            height = height,
        }
    end

    function window:SetUserPlaced(userPlaced)
        self.userPlaced = userPlaced
    end

    return window
end

local function loadLayout(options)
    options = options or {}

    local state = {
        canPersistCalls = 0,
        canPersist = options.canPersist ~= false,
        editModeShown = options.editModeShown == true,
        inCombat = options.inCombat == true,
        pendingChanges = options.pendingChanges == true,
        persistReason = options.persistReason,
        positionChangeCalls = 0,
        saveCalls = 0,
        uiParent = {},
        windows = {},
    }

    local damageMeter = newWindow("DamageMeter", true)
    damageMeter.defaultPosition = options.defaultPosition ~= false
    damageMeter.height = options.height or 210
    damageMeter.width = options.width or 360

    function damageMeter:GetMaxSessionWindowCount()
        return options.maxWindows or 3
    end

    function damageMeter:GetSessionWindow(index)
        return state.windows[index]
    end

    function damageMeter:GetSize()
        return self.width, self.height
    end

    function damageMeter:IsInDefaultPosition()
        return self.defaultPosition
    end

    function damageMeter:OnSystemPositionChange()
        state.positionChangeCalls = state.positionChangeCalls + 1
    end

    local windowCount = options.windowCount or 1
    state.windows[1] = damageMeter
    for i = 2, windowCount do
        state.windows[i] = newWindow("DamageMeterSessionWindow" .. i, true)
    end

    local manager = {}
    function manager:HasActiveChanges()
        return state.pendingChanges
    end
    function manager:IsShown()
        return state.editModeShown
    end
    function manager:SaveLayouts()
        state.saveCalls = state.saveCalls + 1
    end

    local damageMeterModule = {
        Native = {
            CanPersistLayout = function()
                state.canPersistCalls = state.canPersistCalls + 1
                if state.canPersist then
                    return true
                end
                return false, state.persistReason or "preset"
            end,
        },
    }
    local BFI = {
        modules = {
            DamageMeter = damageMeterModule,
        },
    }
    local environment = {
        DamageMeter = damageMeter,
        EditModeManagerFrame = manager,
        InCombatLockdown = function()
            return state.inCombat
        end,
        UIParent = state.uiParent,
        ipairs = ipairs,
        math = math,
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Layout.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeterModule, state, damageMeter, manager
end

local savedDM, saved, savedMeter = loadLayout({
    height = 218,
    width = 372,
    windowCount = 3,
})
local ok, reason = savedDM.ApplyBottomRightLayout()
assertEqual(ok, true, "custom layout apply")
assertEqual(reason, nil, "custom layout apply reason")
assertEqual(savedMeter.clearCalls, 1, "custom layout primary points cleared")
assertPoint(savedMeter, {
    "BOTTOMRIGHT",
    saved.uiParent,
    "BOTTOMRIGHT",
    -20,
    20,
}, "custom layout primary point")
assertEqual(saved.positionChangeCalls, 1, "custom layout position persisted")
assertEqual(saved.saveCalls, 1, "custom layout saved")

local second = saved.windows[2]
assertEqual(second.clearCalls, 1, "second window points cleared")
assertPoint(second, {
    "BOTTOMRIGHT",
    savedMeter,
    "BOTTOMLEFT",
    -8,
    0,
}, "second window point")
assertEqual(second.sizeCalls[1].width, 372, "second window width")
assertEqual(second.sizeCalls[1].height, 218, "second window height")
assertEqual(second.userPlaced, true, "second window user placed")

local third = saved.windows[3]
assertEqual(third.clearCalls, 1, "third window points cleared")
assertPoint(third, {
    "BOTTOMRIGHT",
    second,
    "BOTTOMLEFT",
    -8,
    0,
}, "third window point")
assertEqual(third.sizeCalls[1].width, 372, "third window width")
assertEqual(third.sizeCalls[1].height, 218, "third window height")
assertEqual(third.userPlaced, true, "third window user placed")

local presetDM, preset, presetMeter = loadLayout({
    canPersist = false,
    persistReason = "preset",
    windowCount = 3,
})
ok, reason = presetDM.ApplyBottomRightLayout()
assertEqual(ok, false, "explicit preset apply refused")
assertEqual(reason, "preset", "explicit preset refusal reason")
assertEqual(presetMeter.clearCalls, 0, "explicit preset primary preserved")
assertEqual(preset.positionChangeCalls, 0, "explicit preset position not persisted")
assertEqual(preset.saveCalls, 0, "explicit preset not saved")
assertEqual(preset.windows[2].clearCalls, 0, "explicit preset secondary preserved")

local runtimeDM, runtime, runtimeMeter = loadLayout({
    canPersist = false,
    height = 190,
    persistReason = "preset",
    width = 330,
    windowCount = 2,
})
ok, reason = runtimeDM.ApplyDefaultPositionIfNeeded()
assertEqual(ok, true, "preset default runtime apply")
assertEqual(reason, "runtime", "preset default runtime reason")
assertPoint(runtimeMeter, {
    "BOTTOMRIGHT",
    runtime.uiParent,
    "BOTTOMRIGHT",
    -20,
    20,
}, "preset runtime primary point")
assertEqual(runtime.positionChangeCalls, 0, "preset runtime not persisted")
assertEqual(runtime.saveCalls, 0, "preset runtime not saved")
assertEqual(runtime.windows[2].clearCalls, 0,
    "preset runtime secondary preserved")
assertEqual(#runtime.windows[2].sizeCalls, 0,
    "preset runtime secondary size preserved")
assertEqual(runtime.windows[2].userPlaced, nil,
    "preset runtime secondary placement preserved")

local automaticDM, automatic, automaticMeter = loadLayout({
    height = 205,
    width = 355,
    windowCount = 2,
})
ok, reason = automaticDM.ApplyDefaultPositionIfNeeded()
assertEqual(ok, true, "custom default primary apply")
assertEqual(reason, nil, "custom default primary reason")
assertPoint(automaticMeter, {
    "BOTTOMRIGHT",
    automatic.uiParent,
    "BOTTOMRIGHT",
    -20,
    20,
}, "custom default primary point")
assertEqual(automatic.positionChangeCalls, 1,
    "custom default primary persisted")
assertEqual(automatic.saveCalls, 1, "custom default layout saved")
assertEqual(automatic.windows[2].clearCalls, 0,
    "custom default secondary preserved")
assertEqual(#automatic.windows[2].sizeCalls, 0,
    "custom default secondary size preserved")

local customDM, custom, customMeter = loadLayout({
    defaultPosition = false,
    windowCount = 2,
})
ok, reason = customDM.ApplyDefaultPositionIfNeeded()
assertEqual(ok, false, "custom user position preserved")
assertEqual(reason, "custom_position", "custom user position reason")
assertEqual(customMeter.clearCalls, 0, "custom user primary untouched")
assertEqual(custom.canPersistCalls, 0, "custom user persistence not queried")
assertEqual(custom.saveCalls, 0, "custom user layout not saved")
assertEqual(custom.windows[2].clearCalls, 0, "custom user secondary untouched")

ok, reason = customDM.ArrangeSecondaryWindows()
assertEqual(ok, true, "custom secondary layout apply")
assertEqual(reason, nil, "custom secondary layout reason")
assertEqual(customMeter.clearCalls, 0, "custom secondary primary untouched")
assertEqual(custom.saveCalls, 0, "custom secondary layout not saved")
assertPoint(custom.windows[2], {
    "BOTTOMRIGHT",
    customMeter,
    "BOTTOMLEFT",
    -8,
    0,
}, "custom secondary point")

local partialDM, partial = loadLayout({
    windowCount = 3,
})
ok, reason = partialDM.ArrangeSecondaryWindows(3)
assertEqual(ok, true, "new secondary layout apply")
assertEqual(reason, nil, "new secondary layout reason")
assertEqual(partial.windows[2].clearCalls, 0,
    "existing secondary position preserved")
assertEqual(#partial.windows[2].sizeCalls, 0,
    "existing secondary size preserved")
assertPoint(partial.windows[3], {
    "BOTTOMRIGHT",
    partial.windows[2],
    "BOTTOMLEFT",
    -8,
    0,
}, "new secondary point")

local combatDM, combat, combatMeter = loadLayout({
    inCombat = true,
    windowCount = 2,
})
ok, reason = combatDM.ApplyBottomRightLayout()
assertEqual(ok, false, "combat layout refused")
assertEqual(reason, "combat", "combat layout refusal reason")
assertEqual(combatMeter.clearCalls, 0, "combat primary untouched")
assertEqual(combat.canPersistCalls, 0, "combat persistence not queried")
assertEqual(combat.saveCalls, 0, "combat layout not saved")
assertEqual(combat.windows[2].clearCalls, 0, "combat secondary untouched")

local pendingDM, pending, pendingMeter = loadLayout({
    pendingChanges = true,
    windowCount = 2,
})
ok, reason = pendingDM.ApplyBottomRightLayout()
assertEqual(ok, false, "pending Edit Mode changes refused")
assertEqual(reason, "pending_changes", "pending changes refusal reason")
assertEqual(pendingMeter.clearCalls, 0, "pending changes primary untouched")
assertEqual(pending.canPersistCalls, 0, "pending changes persistence not queried")
assertEqual(pending.saveCalls, 0, "pending changes layout not saved")
assertEqual(pending.windows[2].clearCalls, 0,
    "pending changes secondary untouched")

print("damage_meter_layout_test.lua: ok")
