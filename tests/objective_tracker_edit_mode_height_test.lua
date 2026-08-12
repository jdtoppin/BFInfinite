local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message or "expected true", 2) end
end

local function assertContains(source, pattern, message)
    if not source:find(pattern, 1, true) then
        error(message .. ": missing " .. pattern, 2)
    end
end

local function assertNotContains(source, pattern, message)
    if source:find(pattern, 1, true) then
        error(message .. ": found " .. pattern, 2)
    end
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    assertEqual(type(file), "userdata", openError or ("open " .. path))
    local source = file:read("*a")
    file:close()
    return source
end

local function copy(value)
    if type(value) ~= "table" then return value end

    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local Enum = {
    EditModeLayoutType = {
        Preset = 0,
        Account = 1,
        Character = 2,
        Override = 3,
    },
    EditModeObjectiveTrackerSetting = {
        Height = 0,
        Opacity = 1,
    },
    EditModePresetLayoutsMeta = {
        NumValues = 2,
    },
    EditModeSystem = {
        ObjectiveTracker = 12,
    },
}

local sourceLayouts
local savedLayouts
local saveCalls
local inCombat
local editModeActive

local function resetLayouts()
    sourceLayouts = {
        -- C_EditMode.GetLayouts returns saved layouts only. activeLayout keeps
        -- the global index that includes Blizzard's two preset layouts.
        activeLayout = 3,
        layouts = {
            {
                layoutName = "My Layout",
                layoutType = Enum.EditModeLayoutType.Account,
                systems = {
                    {
                        anchorInfo = {
                            point = "TOPRIGHT",
                            relativeTo = "UIParent",
                            relativePoint = "TOPRIGHT",
                            offsetX = -110,
                            offsetY = -275,
                        },
                        isInDefaultPosition = false,
                        settings = {
                            {setting = Enum.EditModeObjectiveTrackerSetting.Height, value = 40},
                            {setting = Enum.EditModeObjectiveTrackerSetting.Opacity, value = 13},
                        },
                        system = Enum.EditModeSystem.ObjectiveTracker,
                    },
                    {
                        isInDefaultPosition = false,
                        settings = {
                            {setting = 99, value = 17},
                        },
                        system = 99,
                    },
                },
            },
        },
    }
    savedLayouts = nil
    saveCalls = 0
    inCombat = false
    editModeActive = false
end

resetLayouts()

local editMode = {
    GetLayouts = function()
        return sourceLayouts
    end,
    SaveLayouts = function(layouts)
        saveCalls = saveCalls + 1
        savedLayouts = layouts
        sourceLayouts = layouts
    end,
}
local BFI = {
    modules = {
        UIWidgets = {},
    },
}
local environment = {
    AbstractFramework = {
        Copy = copy,
    },
    C_EditMode = editMode,
    EditModeManagerFrame = {
        IsEditModeActive = function()
            return editModeActive
        end,
    },
    Enum = Enum,
    InCombatLockdown = function()
        return inCombat
    end,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local source = readFile("Modules/UIWidgets/ObjectiveTrackerEditMode.lua")
assertContains(source, "Retail 12.1.0.68914",
    "native height adapter records its API evidence")
assertContains(source, "editMode.GetLayouts()",
    "native height adapter reads the documented layout snapshot")
assertContains(source, "editMode.SaveLayouts(layouts)",
    "native height adapter persists through the documented API")
assertContains(source, "EditModePresetLayoutsMeta",
    "native height adapter maps the global active layout index")
assertContains(source, "SetObjectiveTrackerBFIRightStackPlacement",
    "native placement adapter is exported")
assertContains(source, "offsetY = -200",
    "BFI right stack moves the tracker higher than Blizzard's preset")
assertContains(source, "BFI_TRACKER_DEFAULT_HEIGHT = 640",
    "BFI native layout defines a 640 Objective Tracker height")
for _, forbidden in ipairs({
    "ObjectiveTrackerFrame",
    "OnSystemSettingChange",
    "UpdateSystemSettingValue",
    "SetHeight(",
    "SetSize(",
    "UpdateHeight(",
}) do
    assertNotContains(source, forbidden,
        "native height adapter must not take Objective Tracker ownership")
end

local optionsSource = readFile("Options/UIWidgets_Options.lua")
assertContains(optionsSource, '"objectiveTrackerNativeHeight"',
    "Objective Tracker settings include the native height proxy")
assertContains(optionsSource, 'builder["objectiveTrackerNativeHeight"]',
    "native height proxy has an options pane")
assertContains(optionsSource, "W.SetObjectiveTrackerNativeHeight(value)",
    "native height proxy delegates to the Edit Mode adapter")

local chunk, loadError =
    loadfile("Modules/UIWidgets/ObjectiveTrackerEditMode.lua")
assertEqual(type(chunk), "function", loadError or "adapter load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local W = BFI.modules.UIWidgets
assertEqual(type(W.GetObjectiveTrackerNativeHeight), "function",
    "native height getter is exported")
assertEqual(type(W.SetObjectiveTrackerNativeHeight), "function",
    "native height setter is exported")
assertEqual(type(W.GetObjectiveTrackerNativePlacement), "function",
    "native placement getter is exported")
assertEqual(type(W.SetObjectiveTrackerBFIRightStackPlacement), "function",
    "native placement setter is exported")

local height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, 800, "raw default height converts to pixels")
assertEqual(reason, nil, "custom tracker height is initially writable")
assertTrue(W.SetObjectiveTrackerNativeHeight(800),
    "unchanged height is accepted")
assertEqual(saveCalls, 0, "unchanged height does not rewrite layouts")

local originalLayouts = sourceLayouts
assertTrue(W.SetObjectiveTrackerNativeHeight(650),
    "custom tracker height saves through Edit Mode")
assertEqual(saveCalls, 1, "one layout save for one setting change")
assertTrue(savedLayouts ~= originalLayouts,
    "native height save uses a copied layout snapshot")
assertEqual(
    originalLayouts.layouts[1].systems[1].settings[1].value,
    40,
    "source layout remains untouched before the native save"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    25,
    "650 pixels converts to Blizzard raw height index"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[2].value,
    13,
    "Objective Tracker opacity remains unchanged"
)
assertEqual(
    savedLayouts.layouts[1].systems[2].settings[1].value,
    17,
    "unrelated Edit Mode systems remain unchanged"
)
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, 650, "saved native height is read back")
assertEqual(reason, nil, "saved native height remains writable")
assertTrue(W.SetObjectiveTrackerNativeHeight(650),
    "matching native height is accepted")
assertEqual(saveCalls, 1, "matching native height does not rewrite layouts")
assertTrue(W.SetObjectiveTrackerNativeHeight(557),
    "native height rounds to Blizzard's step")
assertEqual(saveCalls, 2, "rounded native height saves once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    16,
    "557 pixels rounds to 560 native height"
)

resetLayouts()
local isDefaultPosition, placementReason =
    W.GetObjectiveTrackerNativePlacement()
assertEqual(isDefaultPosition, false,
    "custom-position tracker reports its current native placement")
assertEqual(placementReason, nil,
    "custom-position tracker placement is writable")
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "BFI right stack saves through Edit Mode")
assertEqual(saveCalls, 1, "one layout save for BFI right stack placement")
assertEqual(
    savedLayouts.layouts[1].systems[1].isInDefaultPosition,
    false,
    "BFI right stack keeps the tracker out of Blizzard's managed column"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].anchorInfo.point,
    "TOPRIGHT",
    "BFI right stack uses the native top-right anchor"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].anchorInfo.relativeTo,
    "UIParent",
    "BFI right stack remains screen-relative"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].anchorInfo.relativePoint,
    "TOPRIGHT",
    "BFI right stack targets the screen top-right"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].anchorInfo.offsetX,
    -110,
    "BFI right stack retains Blizzard's right inset"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].anchorInfo.offsetY,
    -200,
    "BFI right stack is 75 pixels higher than Blizzard's preset"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    24,
    "BFI placement saves Blizzard's 640 native height value"
)
assertEqual(
    savedLayouts.layouts[1].systems[2].settings[1].value,
    17,
    "BFI placement leaves unrelated Edit Mode systems unchanged"
)
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "matching BFI right stack placement is accepted")
assertEqual(saveCalls, 1,
    "matching BFI right stack position and height do not rewrite layouts")

resetLayouts()
sourceLayouts.layouts[1].systems[1].anchorInfo.offsetY = -200
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "existing BFI placement upgrades its default native height")
assertEqual(saveCalls, 1,
    "existing BFI placement saves its missing default height once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    24,
    "existing BFI placement upgrades Blizzard's 800 height to 640"
)

resetLayouts()
sourceLayouts.layouts[1].systems[1].isInDefaultPosition = true
isDefaultPosition, placementReason = W.GetObjectiveTrackerNativePlacement()
assertEqual(isDefaultPosition, true,
    "managed tracker exposes its native default-position state")
assertEqual(placementReason, nil,
    "managed tracker can opt into BFI's custom placement")
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "BFI right stack moves a managed tracker into a custom layout")
assertEqual(
    savedLayouts.layouts[1].systems[1].isInDefaultPosition,
    false,
    "BFI right stack disables Blizzard's right-managed placement"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    24,
    "managed tracker receives BFI's 640 native height when positioned"
)

resetLayouts()
local originalHeightSettings = Enum.EditModeObjectiveTrackerSetting
Enum.EditModeObjectiveTrackerSetting = nil
isDefaultPosition, placementReason = W.GetObjectiveTrackerNativePlacement()
assertEqual(isDefaultPosition, false,
    "placement works even when this client has no native height setting")
assertEqual(placementReason, nil,
    "placement does not depend on the native height enum")
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "placement persists without the native height enum")
assertEqual(saveCalls, 1,
    "placement without the native height enum saves once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[1].value,
    40,
    "older clients retain their native setting when height is unavailable"
)
assertEqual(#savedLayouts.layouts[1].systems[1].settings, 2,
    "older clients do not add an invalid native height setting")
Enum.EditModeObjectiveTrackerSetting = originalHeightSettings

resetLayouts()
sourceLayouts.layouts[1].systems[1].settings = nil
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "BFI placement works without an optional native settings list")
assertEqual(saveCalls, 1,
    "BFI placement without an optional native settings list saves once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings,
    nil,
    "BFI placement does not invent an unsupported native settings list"
)

resetLayouts()
table.remove(sourceLayouts.layouts[1].systems[1].settings, 1)
assertTrue(W.SetObjectiveTrackerBFIRightStackPlacement(),
    "BFI placement creates a missing native height setting")
assertEqual(saveCalls, 1,
    "BFI placement with a missing height setting saves once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[2].setting,
    Enum.EditModeObjectiveTrackerSetting.Height,
    "BFI placement adds Blizzard's height setting"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[2].value,
    24,
    "BFI placement adds its 640 native height value"
)

resetLayouts()
table.remove(sourceLayouts.layouts[1].systems[1].settings, 1)
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, 800, "missing native setting uses Blizzard default")
assertEqual(reason, nil, "missing native setting can be created")
assertTrue(W.SetObjectiveTrackerNativeHeight(500),
    "missing native height setting is added")
assertEqual(saveCalls, 1, "created native height saves once")
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[2].setting,
    Enum.EditModeObjectiveTrackerSetting.Height,
    "created setting uses Blizzard's height enum"
)
assertEqual(
    savedLayouts.layouts[1].systems[1].settings[2].value,
    10,
    "500 pixels uses raw index 10"
)

resetLayouts()
sourceLayouts.layouts[1].systems[1].isInDefaultPosition = true
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, nil, "default-position tracker exposes no native height")
assertEqual(reason, "customPosition",
    "default-position tracker explains Blizzard's requirement")
assertEqual(W.SetObjectiveTrackerNativeHeight(500), false,
    "default-position tracker is not modified")
assertEqual(saveCalls, 0, "default-position tracker does not save layouts")

resetLayouts()
sourceLayouts.activeLayout = 1
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, nil, "preset layout exposes no writable native height")
assertEqual(reason, "customLayout",
    "preset layout requires a user-created layout")
assertEqual(W.SetObjectiveTrackerNativeHeight(500), false,
    "preset layout is not overwritten")
assertEqual(W.SetObjectiveTrackerBFIRightStackPlacement(), false,
    "preset layout is not overwritten by BFI placement")
assertEqual(saveCalls, 0, "preset layout does not save")

resetLayouts()
sourceLayouts.layouts[1].layoutType = Enum.EditModeLayoutType.Override
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, nil, "override layout exposes no writable native height")
assertEqual(reason, "customLayout",
    "override layout is not treated as a saved user layout")

resetLayouts()
inCombat = true
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, 800, "combat retains the current displayed height")
assertEqual(reason, "combat", "combat blocks native height writes")
assertEqual(W.SetObjectiveTrackerNativeHeight(500), false,
    "combat does not write Edit Mode layouts")
assertEqual(W.SetObjectiveTrackerBFIRightStackPlacement(), false,
    "combat does not write BFI placement to Edit Mode layouts")
assertEqual(saveCalls, 0, "combat does not save layouts")

resetLayouts()
editModeActive = true
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, 800, "active Edit Mode retains the displayed height")
assertEqual(reason, "editMode", "active Edit Mode blocks snapshot writes")
assertEqual(W.SetObjectiveTrackerNativeHeight(500), false,
    "active Edit Mode does not overwrite unsaved layout state")
assertEqual(W.SetObjectiveTrackerBFIRightStackPlacement(), false,
    "active Edit Mode does not overwrite BFI placement state")
assertEqual(saveCalls, 0, "active Edit Mode does not save layouts")

resetLayouts()
assertEqual(W.SetObjectiveTrackerNativeHeight("500"), false,
    "non-numeric native height is rejected")
assertEqual(saveCalls, 0, "invalid native height does not save")

local originalEditMode = environment.C_EditMode
environment.C_EditMode = nil
height, reason = W.GetObjectiveTrackerNativeHeight()
assertEqual(height, nil, "missing Edit Mode API exposes no height")
assertEqual(reason, "unavailable", "missing Edit Mode API is explicit")
environment.C_EditMode = originalEditMode

print("objective_tracker_edit_mode_height_test.lua: ok")
