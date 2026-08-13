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

local function assertDeepEqual(actual, expected, message, seen)
    message = message or "tables differ"
    if type(actual) ~= type(expected) then
        error(message .. ": type mismatch", 2)
    end
    if type(actual) ~= "table" then
        assertEqual(actual, expected, message)
        return
    end

    seen = seen or {}
    if seen[actual] == expected then return end
    seen[actual] = expected
    for key, value in pairs(expected) do
        assertDeepEqual(
            actual[key],
            value,
            message .. "." .. tostring(key),
            seen
        )
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(message .. ": unexpected key " .. tostring(key), 2)
        end
    end
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local UF = {}
local BFI = {
    modules = {
        UnitFrames = UF,
    },
}
local environment = {
    _G = false,
    assert = assert,
    error = error,
    ipairs = ipairs,
    math = math,
    pairs = pairs,
    select = select,
    string = string,
    table = table,
    tonumber = tonumber,
    type = type,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error("unexpected buff-display global: " .. tostring(key), 2)
    end,
})

local chunk, loadError =
    loadfile("Modules/UnitFrames/BuffDisplays.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local function newLegacyConfig()
    return {
        enabled = true,
        position = {"TOPRIGHT", "TOPRIGHT", 0, 0},
        anchorTo = "root",
        cooldownStyle = "vertical",
        width = 12,
        height = 12,
        tooltip = {
            enabled = true,
            anchorTo = "self",
        },
        filters = {
            castByMe = true,
            castByOthers = false,
        },
        mode = "blacklist",
        blacklist = {8326},
        whitelist = {17, 139},
    }
end

local function testLegacyMigrationIsAdditive()
    local buffs = newLegacyConfig()
    local before = copy(buffs)
    local filters = buffs.filters
    local tooltip = buffs.tooltip
    local healingWhitelist = {774, 194384, 53563}

    local normalized, errorCode = UF.NormalizeBuffDisplayCollection(
        buffs,
        {healingWhitelist = healingWhitelist}
    )
    assertEqual(normalized, buffs, "normalization is in place")
    assertEqual(errorCode, nil, "legacy normalization error")
    assertEqual(buffs.schemaVersion, 1, "schema version")
    assertEqual(buffs.nextCustomID, 1, "first custom ID")
    assertEqual(buffs.filters, filters, "flat filter identity")
    assertEqual(buffs.tooltip, tooltip, "flat tooltip identity")

    for key, value in pairs(before) do
        assertDeepEqual(
            buffs[key],
            value,
            "legacy flat key preserved: " .. key
        )
    end

    assertEqual(#buffs.order, 3, "three built-in children")
    assertEqual(buffs.order[1], "healing_auras", "healing order")
    assertEqual(buffs.order[2], "defensives", "defensive order")
    assertEqual(buffs.order[3], "externals", "external order")

    local healing = buffs.displays.healing_auras
    assertEqual(healing.name, "Healing Auras", "healing label")
    assertEqual(healing.builtIn, true, "healing permanence")
    assertEqual(healing.enabled, false,
        "migrated healing display is disabled")
    assertEqual(healing.presentation, "icons",
        "healing presentation is explicit")
    assertEqual(healing.config, nil,
        "display aura settings are not wrapped")
    assertDeepEqual(healing.whitelist, healingWhitelist,
        "caller-owned healing whitelist is copied")
    assertTrue(healing.whitelist ~= healingWhitelist,
        "healing list does not alias its preset source")

    local defensives = buffs.displays.defensives
    assertEqual(defensives.name, "Defensives", "defensive label")
    assertEqual(defensives.enabled, false,
        "migrated defensives are disabled")
    assertEqual(defensives.presentation, "icons",
        "defensive presentation is explicit")
    assertEqual(defensives.filters.bigDefensive, true,
        "defensive native category")
    assertEqual(defensives.filters.externalDefensive, false,
        "defensive category is separate")

    local externals = buffs.displays.externals
    assertEqual(externals.name, "Externals", "external label")
    assertEqual(externals.enabled, false,
        "migrated externals are disabled")
    assertEqual(externals.filters.bigDefensive, false,
        "external category is separate")
    assertEqual(externals.filters.externalDefensive, true,
        "external native category")

    healing.enabled = true
    UF.NormalizeBuffDisplayCollection(buffs, {
        healingWhitelist = {999},
    })
    assertEqual(healing.enabled, true,
        "idempotent normalization preserves user state")
    assertEqual(healing.whitelist[1], 774,
        "idempotent normalization does not replace saved config")
end

local function testFutureSchemaFailsWithoutMutation()
    local buffs = newLegacyConfig()
    buffs.schemaVersion = 2
    local before = copy(buffs)
    local normalized, errorCode =
        UF.NormalizeBuffDisplayCollection(buffs)
    assertEqual(normalized, nil, "future schema is rejected")
    assertEqual(errorCode, "UNSUPPORTED_SCHEMA_VERSION",
        "future schema error")
    assertDeepEqual(buffs, before, "future schema remains untouched")
end

local function testMutationHelpers()
    local buffs = newLegacyConfig()
    UF.NormalizeBuffDisplayCollection(buffs, {
        healingWhitelist = {17, 139},
    })

    local first = assert(UF.CreateBuffDisplay(
        buffs,
        "  Tank Cooldowns  ",
        buffs.displays.defensives
    ))
    assertEqual(first.id, "custom_1", "first stable custom ID")
    assertEqual(first.name, "Tank Cooldowns", "custom name trimmed")
    assertEqual(first.enabled, false,
        "new display does not reserve implicitly")
    assertEqual(first.presentation, "icons",
        "new display carries presentation directly")
    assertEqual(first.config, nil,
        "custom display aura settings are not wrapped")

    local duplicate = assert(UF.DuplicateBuffDisplay(
        buffs,
        first.id
    ))
    assertEqual(duplicate.id, "custom_2", "monotonic custom ID")
    assertEqual(duplicate.name, "Tank Cooldowns Copy",
        "duplicate default name")
    assertEqual(duplicate.enabled, false,
        "duplicate starts disabled")
    assertTrue(duplicate ~= first,
        "duplicate record is a deep copy")
    assertTrue(duplicate.filters ~= first.filters,
        "duplicate filters do not alias")
    duplicate.filters.bigDefensive = false
    assertEqual(first.filters.bigDefensive, true,
        "duplicate edits are isolated")

    local renamed = assert(UF.RenameBuffDisplay(
        buffs,
        duplicate.id,
        "Raid Utility"
    ))
    assertEqual(renamed.name, "Raid Utility", "custom rename")
    local rejected, renameError = UF.RenameBuffDisplay(
        buffs,
        "externals",
        "Other Name"
    )
    assertEqual(rejected, nil, "built-in rename rejected")
    assertEqual(renameError, "BUILT_IN_DISPLAY",
        "built-in rename error")

    assert(UF.MoveBuffDisplay(buffs, duplicate.id, 1))
    assertEqual(buffs.order[1], duplicate.id, "display moved")
    local deleted = assert(UF.DeleteBuffDisplay(buffs, first.id))
    assertEqual(deleted, first, "deleted record returned")
    assertEqual(buffs.displays[first.id], nil, "custom removed")

    assert(UF.SetBuffDisplayEnabled(buffs, "externals", true))
    local disabledBuiltIn, deleteCode =
        UF.DeleteBuffDisplay(buffs, "externals")
    assertEqual(disabledBuiltIn.id, "externals",
        "built-in delete returns record")
    assertEqual(deleteCode, "BUILT_IN_DISABLED",
        "built-in delete is disable-only")
    assertEqual(buffs.displays.externals.enabled, false,
        "built-in remains but is disabled")

    local third = assert(UF.CreateBuffDisplay(
        buffs,
        "Third",
        first
    ))
    assertEqual(third.id, "custom_3",
        "deleted IDs are not recycled")
end

local function testReservationBudget()
    local buffs = newLegacyConfig()
    UF.NormalizeBuffDisplayCollection(buffs)

    local records = {}
    for index = 1, 5 do
        records[index] = assert(UF.CreateBuffDisplay(
            buffs,
            "Display " .. index
        ))
    end

    for index = 1, UF.MAX_ACTIVE_CHILD_BUFF_DISPLAYS do
        assert(UF.SetBuffDisplayEnabled(
            buffs,
            records[index].id,
            true
        ))
    end
    local rejected, limitError = UF.SetBuffDisplayEnabled(
        buffs,
        records[5].id,
        true
    )
    assertEqual(rejected, nil, "fifth child activation rejected")
    assertEqual(limitError, "ACTIVE_DISPLAY_LIMIT",
        "active child budget error")

    -- Imported/hand-edited SavedVariables can bypass the setter. The runtime
    -- reservation plan remains hard-bounded and reports the overflow.
    records[5].enabled = true
    local reserved, overflow, metrics =
        UF.GetActiveBuffDisplayReservationPlan(buffs)
    assertEqual(#reserved, 4, "reservation plan is bounded")
    assertEqual(#overflow, 1, "reservation overflow reported")
    assertEqual(overflow[1], records[5], "ordered overflow record")
    assertEqual(metrics.reservationCosts[records[1].id], 10,
        "per-display reservation cost is reported")

    assert(UF.SetBuffDisplayEnabled(
        buffs,
        records[1].id,
        false
    ))
    assert(UF.SetBuffDisplayEnabled(
        buffs,
        records[5].id,
        true
    ))
end

local function testFrameHighlightReservationRequiresOneGroup()
    local buffs = newLegacyConfig()
    UF.NormalizeBuffDisplayCollection(buffs)
    local highlight = assert(UF.CreateBuffDisplay(
        buffs,
        "Renew Highlight"
    ))
    highlight.presentation = "frame_highlight"

    UF.CompileNativeAuraPolicy = function()
        return {groups = {}}
    end
    assert(UF.SetBuffDisplayEnabled(
        buffs,
        highlight.id,
        true
    ))
    local emptyReserved, _, emptyMetrics =
        UF.GetActiveBuffDisplayReservationPlan(buffs)
    assertEqual(#emptyReserved, 1,
        "empty frame highlight keeps its configuration shell")
    assertEqual(emptyMetrics.initialReservations, 0,
        "empty frame highlight reserves no managed button")
    assert(UF.SetBuffDisplayEnabled(
        buffs,
        highlight.id,
        false
    ))

    UF.CompileNativeAuraPolicy = function()
        return {groups = {{}, {}}}
    end
    local rejected, errorCode = UF.SetBuffDisplayEnabled(
        buffs,
        highlight.id,
        true
    )
    assertEqual(rejected, nil,
        "multi-group frame highlight rejected")
    assertEqual(errorCode, "ACTIVE_DISPLAY_LIMIT",
        "multi-group frame highlight error")

    UF.CompileNativeAuraPolicy = function()
        return {groups = {{}}}
    end
    assert(UF.SetBuffDisplayEnabled(
        buffs,
        highlight.id,
        true
    ))
    local reserved, overflow, metrics =
        UF.GetActiveBuffDisplayReservationPlan(buffs)
    assertEqual(#reserved, 1, "single-group highlight reserved")
    assertEqual(#overflow, 0, "single-group highlight overflow")
    assertEqual(metrics.initialReservations, 1,
        "single-group highlight slot cost")

    UF.CompileNativeAuraPolicy = nil
end

local function testOrderChangesReservationPriority()
    local buffs = newLegacyConfig()
    UF.NormalizeBuffDisplayCollection(buffs)
    local records = {}
    for index = 1, 5 do
        records[index] = assert(UF.CreateBuffDisplay(
            buffs,
            "Priority " .. index
        ))
        records[index].enabled = true
    end

    local reserved, overflow =
        UF.GetActiveBuffDisplayReservationPlan(buffs)
    assertEqual(reserved[1], records[1],
        "initial reservation priority")
    assertEqual(overflow[1], records[5],
        "initial overflow priority")

    assert(UF.MoveBuffDisplay(buffs, records[5].id, 4))
    reserved, overflow = UF.GetActiveBuffDisplayReservationPlan(buffs)
    assertEqual(reserved[1], records[5],
        "moved display gains reservation priority")
    assertEqual(overflow[1], records[4],
        "lowest-priority display moves to overflow")
end

local function testOrderRepairAndExplicitTemplate()
    local buffs = newLegacyConfig()
    buffs.schemaVersion = 1
    buffs.nextCustomID = 2
    buffs.order = {"custom_10", "custom_10", "missing"}
    buffs.displays = {
        custom_2 = {
            name = "Two",
            enabled = false,
        },
        custom_10 = {
            name = "Ten",
            enabled = false,
        },
    }
    local healingTemplate = {
        enabled = true,
        marker = "caller template",
        filters = {player = true},
        whitelist = {999},
    }

    UF.NormalizeBuffDisplayCollection(buffs, {
        healing_auras = healingTemplate,
    })
    assertEqual(buffs.order[1], "custom_10",
        "saved valid order leads")
    assertEqual(buffs.order[2], "healing_auras",
        "missing built-ins are appended canonically")
    assertEqual(buffs.order[5], "custom_2",
        "missing custom records append deterministically")
    assertEqual(buffs.nextCustomID, 11,
        "allocator advances past imported IDs")
    assertEqual(
        buffs.displays.healing_auras.marker,
        "caller template",
        "complete healing template accepted"
    )
    assertEqual(
        buffs.displays.healing_auras.enabled,
        false,
        "caller template cannot activate during migration"
    )
    assertTrue(
        buffs.displays.healing_auras ~= healingTemplate,
        "caller template is copied"
    )
end

testLegacyMigrationIsAdditive()
testFutureSchemaFailsWithoutMutation()
testMutationHelpers()
testReservationBudget()
testFrameHighlightReservationRequiresOneGroup()
testOrderChangesReservationPriority()
testOrderRepairAndExplicitTemplate()

print("unit_frame_buff_displays_model_test.lua: ok")
