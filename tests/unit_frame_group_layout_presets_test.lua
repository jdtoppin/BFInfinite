local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function mergeTable(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeTable(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function copyTables(...)
    local copy = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if source then
            mergeTable(copy, source)
        end
    end
    return copy
end

local function assertTableFields(actual, expected, message)
    local count = 0
    for key, value in pairs(actual) do
        count = count + 1
        assertEqual(value, expected[key], message .. " " .. key)
    end

    local expectedCount = 0
    for _ in pairs(expected) do
        expectedCount = expectedCount + 1
    end
    assertEqual(count, expectedCount, message .. " field count")
end

local function loadPresets()
    local callbacks = {}
    local unitFrames = {}
    local translations = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = translations,
        modules = {
            UnitFrames = unitFrames,
        },
    }
    local AF = {
        Copy = copyTables,
        GetColorTable = function(name, alpha)
            return {name = name, alpha = alpha}
        end,
        Merge = mergeTable,
        RegisterCallback = function(name, callback)
            callbacks[name] = callback
        end,
    }
    local environment = setmetatable({
        AbstractFramework = AF,
    }, {__index = _G})
    environment._G = environment

    local chunk, loadError = loadfile("Modules/UnitFrames/Presets.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return unitFrames, callbacks
end

local function assertLayoutPreset(preset, expected, message)
    assertTableFields(preset.get(), expected, message .. " patch")
end

local UF, callbacks = loadPresets()
assertEqual(#UF.GetPresets(), 2, "full unit preset count")
assertEqual(UF.GetGroupLayoutPresets("boss"), nil, "unknown group preset owner")
assertEqual(UF.GetGroupLayoutPreset("party", "missing"), nil, "unknown party preset")

local party = UF.GetGroupLayoutPresets("party")
assertEqual(#party, 4, "party layout preset count")
assertEqual(party[1].id, "default", "party default id")
assertEqual(party[2].id, "across", "party across id")
assertEqual(party[3].id, "compact", "party compact id")
assertEqual(party[4].id, "compactAcross", "party compact across id")
assertLayoutPreset(party[1], {orientation = "bottom_to_top", spacing = 20}, "party default")
assertLayoutPreset(party[2], {orientation = "left_to_right", spacing = 20}, "party across")
assertLayoutPreset(party[3], {orientation = "bottom_to_top", spacing = 0}, "party compact")
assertLayoutPreset(party[4], {orientation = "left_to_right", spacing = 0}, "party compact across")
assertTableFields(party[1].preview, {columns = 1, rows = 4, gap = 8}, "party default preview")
assertTableFields(party[2].preview, {columns = 4, rows = 1, gap = 8}, "party across preview")
assertTableFields(party[3].preview, {columns = 1, rows = 4, gap = 0}, "party compact preview")
assertTableFields(party[4].preview, {columns = 4, rows = 1, gap = 0}, "party compact across preview")

local raid = UF.GetGroupLayoutPresets("raid")
assertEqual(#raid, 2, "raid layout preset count")
assertEqual(raid[1].id, "growDown", "raid grow down id")
assertEqual(raid[2].id, "growAcross", "raid grow across id")
assertLayoutPreset(raid[1], {orientation = "top_to_bottom_then_right"}, "raid grow down")
assertLayoutPreset(raid[2], {orientation = "left_to_right_then_down"}, "raid grow across")
assertTableFields(raid[1].preview, {columns = 6, rows = 5, gap = 2}, "raid grow down preview")
assertTableFields(raid[2].preview, {columns = 5, rows = 6, gap = 2}, "raid grow across preview")

local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback registration")

local profile = {}
updateProfile(nil, profile)
assertEqual(UF.config, profile.unitFrames, "profile config identity")

local partyGeneral = UF.config.party.general
partyGeneral.position = {"TOP", 123, -45}
partyGeneral.anchor = "TOP"
partyGeneral.width = 177
partyGeneral.height = 42
partyGeneral.bgColor = {guard = "party background"}
partyGeneral.borderColor = {guard = "party border"}
partyGeneral.sortMethod = "NAME"
partyGeneral.sortDir = "DESC"
partyGeneral.groupBy = "CLASS"
partyGeneral.groupingOrder = "HEALER,TANK,DAMAGER"
partyGeneral.tooltip = {guard = "party tooltip"}

local partyPosition = partyGeneral.position
local partyBackground = partyGeneral.bgColor
local partyBorder = partyGeneral.borderColor
local partyTooltip = partyGeneral.tooltip
local partyIndicators = UF.config.party.indicators

assertEqual(UF.ApplyGroupLayoutPreset("party", "across"), true, "apply party across")
assertEqual(partyGeneral.orientation, "left_to_right", "party across orientation")
assertEqual(partyGeneral.spacing, 20, "party across spacing")
assertEqual(partyGeneral.position, partyPosition, "party position identity")
assertEqual(partyGeneral.anchor, "TOP", "party anchor")
assertEqual(partyGeneral.width, 177, "party width")
assertEqual(partyGeneral.height, 42, "party height")
assertEqual(partyGeneral.bgColor, partyBackground, "party background identity")
assertEqual(partyGeneral.borderColor, partyBorder, "party border identity")
assertEqual(partyGeneral.sortMethod, "NAME", "party sort method")
assertEqual(partyGeneral.sortDir, "DESC", "party sort direction")
assertEqual(partyGeneral.groupBy, "CLASS", "party group by")
assertEqual(partyGeneral.groupingOrder, "HEALER,TANK,DAMAGER", "party grouping order")
assertEqual(partyGeneral.tooltip, partyTooltip, "party tooltip identity")
assertEqual(UF.config.party.indicators, partyIndicators, "party indicator identity")

assertEqual(UF.ApplyGroupLayoutPreset("party", party[3]), true, "apply party compact descriptor")
assertEqual(partyGeneral.orientation, "bottom_to_top", "party compact orientation")
assertEqual(partyGeneral.spacing, 0, "party compact spacing")
assertEqual(UF.ApplyGroupLayoutPreset("party", "missing"), nil, "reject missing party preset")
assertEqual(
    UF.ApplyGroupLayoutPreset("party", {orientation = "top_to_bottom", width = 1}),
    nil,
    "reject unregistered layout patch"
)
assertEqual(partyGeneral.spacing, 0, "missing party preset leaves layout unchanged")
assertEqual(partyGeneral.width, 177, "unregistered layout patch leaves party width unchanged")

local raidGeneral = UF.config.raid.general
raidGeneral.position = {"BOTTOMRIGHT", -321, 98}
raidGeneral.anchor = "BOTTOMLEFT"
raidGeneral.spacingX = 17
raidGeneral.spacingY = 19
raidGeneral.maxColumns = 4
raidGeneral.unitsPerColumn = 7
raidGeneral.groupFilter = "8,7,6"
raidGeneral.sortMethod = "NAME"
raidGeneral.sortDir = "DESC"
raidGeneral.groupBy = "CLASS"
raidGeneral.groupingOrder = "HEALER,TANK,DAMAGER"
raidGeneral.width = 101
raidGeneral.height = 36
raidGeneral.tooltip = {guard = "raid tooltip"}

local raidPosition = raidGeneral.position
local raidTooltip = raidGeneral.tooltip
local raidIndicators = UF.config.raid.indicators

assertEqual(UF.ApplyGroupLayoutPreset("raid", "growAcross"), true, "apply raid grow across")
assertEqual(raidGeneral.orientation, "left_to_right_then_down", "raid grow across orientation")
assertEqual(raidGeneral.position, raidPosition, "raid position identity")
assertEqual(raidGeneral.anchor, "BOTTOMLEFT", "raid anchor")
assertEqual(raidGeneral.spacingX, 17, "raid horizontal spacing")
assertEqual(raidGeneral.spacingY, 19, "raid vertical spacing")
assertEqual(raidGeneral.maxColumns, 4, "raid max columns")
assertEqual(raidGeneral.unitsPerColumn, 7, "raid units per column")
assertEqual(raidGeneral.groupFilter, "8,7,6", "raid group filter")
assertEqual(raidGeneral.sortMethod, "NAME", "raid sort method")
assertEqual(raidGeneral.sortDir, "DESC", "raid sort direction")
assertEqual(raidGeneral.groupBy, "CLASS", "raid group by")
assertEqual(raidGeneral.groupingOrder, "HEALER,TANK,DAMAGER", "raid grouping order")
assertEqual(raidGeneral.width, 101, "raid width")
assertEqual(raidGeneral.height, 36, "raid height")
assertEqual(raidGeneral.tooltip, raidTooltip, "raid tooltip identity")
assertEqual(UF.config.raid.indicators, raidIndicators, "raid indicator identity")

assertEqual(UF.ApplyGroupLayoutPreset("raid", UF.GetGroupLayoutPreset("raid", "growDown")), true, "apply raid grow down descriptor")
assertEqual(raidGeneral.orientation, "top_to_bottom_then_right", "raid grow down orientation")
assertEqual(UF.ApplyGroupLayoutPreset("boss", "growAcross"), nil, "reject unsupported group owner")

print("unit frame group layout preset tests passed")
