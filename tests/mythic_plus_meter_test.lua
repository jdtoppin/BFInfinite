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

local secretValue = {}
local state = {
    apiCalls = 0,
    inCombat = false,
    rejectedValues = 0,
    sourceCalls = 0,
}

local DAMAGE_TYPE = {
    DamageDone = 0,
    Dps = 1,
    Interrupts = 5,
    DamageTaken = 7,
    AvoidableDamageTaken = 8,
    Deaths = 9,
}
local ENUM = {
    DamageMeterSessionType = {
        Overall = 0,
        Current = 1,
    },
    DamageMeterSourceDisplayType = {
        Ally = 1,
        Enemy = 2,
    },
    DamageMeterType = DAMAGE_TYPE,
}

local function makeSource(guid, totalAmount, amountPerSecond)
    return {
        sourceGUID = guid,
        sourceCreatureID = nil,
        name = guid,
        classFilename = "WARRIOR",
        specIconID = 132355,
        totalAmount = totalAmount,
        amountPerSecond = amountPerSecond,
        isLocalPlayer = guid == "Player-1",
        deathRecapID = 0,
        deathTimeSeconds = 0,
        sourceDisplayType = ENUM.DamageMeterSourceDisplayType.Ally,
    }
end

local sessions = {
    [DAMAGE_TYPE.DamageTaken] = {
        combatSources = {
            makeSource("Player-1", 0, 0),
            makeSource("Player-2", 120, 12),
            makeSource("Outsider-1", 999, 99),
        },
        maxAmount = 999,
        totalAmount = 1119,
        durationSeconds = 100,
    },
    [DAMAGE_TYPE.AvoidableDamageTaken] = {
        combatSources = {
            makeSource("Player-1", 90, 0.9),
        },
        maxAmount = 90,
        totalAmount = 90,
        durationSeconds = 100,
    },
    [DAMAGE_TYPE.Interrupts] = {
        combatSources = {
            makeSource("Player-1", 0, 0),
            makeSource("Player-2", 3, 0.03),
        },
        maxAmount = 3,
        totalAmount = 3,
        durationSeconds = 100,
    },
    [DAMAGE_TYPE.Deaths] = {
        combatSources = {
            makeSource("Player-1", 1, 0.01),
            makeSource("Player-1", 1, 0.01),
            makeSource("Player-2", 0, 0),
        },
        maxAmount = 1,
        totalAmount = 2,
        durationSeconds = 100,
    },
    [DAMAGE_TYPE.DamageDone] = {
        combatSources = {
            makeSource("Player-1", 1000, 100),
            makeSource("Player-2", secretValue, 80),
        },
        maxAmount = 1000,
        totalAmount = 1800,
        durationSeconds = 100,
    },
    [DAMAGE_TYPE.Dps] = {
        combatSources = {
            makeSource("Player-1", 1000, 100),
            makeSource("Player-2", 800, 80),
        },
        maxAmount = 100,
        totalAmount = 180,
        durationSeconds = 100,
    },
}

local avoidableSpells = {
    {
        spellID = 101,
        totalAmount = 10,
        amountPerSecond = 0.1,
        creatureName = "One",
        isAvoidable = true,
        isDeadly = false,
    },
    {
        spellID = 102,
        totalAmount = 50,
        amountPerSecond = 0.5,
        creatureName = "Two",
        isAvoidable = true,
        isDeadly = true,
    },
    {
        spellID = 103,
        totalAmount = 30,
        amountPerSecond = 0.3,
        creatureName = "Three",
        isAvoidable = true,
        isDeadly = false,
    },
    {
        spellID = 104,
        totalAmount = 20,
        amountPerSecond = 0.2,
        creatureName = "Four",
        isAvoidable = true,
        isDeadly = false,
    },
    {
        spellID = 105,
        totalAmount = 40,
        amountPerSecond = 0.4,
        creatureName = "Five",
        isAvoidable = true,
        isDeadly = false,
    },
    {
        spellID = 106,
        totalAmount = 60,
        amountPerSecond = 0.6,
        creatureName = "Six",
        isAvoidable = true,
        isDeadly = true,
    },
}

local damageMeter = {}
function damageMeter.IsDamageMeterAvailable()
    return true, ""
end
function damageMeter.GetCombatSessionFromType(sessionType, category)
    state.apiCalls = state.apiCalls + 1
    if sessionType == ENUM.DamageMeterSessionType.Current then
        return {
            combatSources = {},
            maxAmount = 0,
            totalAmount = 0,
            durationSeconds = nil,
        }
    end
    return sessions[category]
end
function damageMeter.GetCombatSessionSourceFromType(
    _,
    category,
    guid,
    _
)
    state.sourceCalls = state.sourceCalls + 1
    if category == DAMAGE_TYPE.AvoidableDamageTaken
        and guid == "Player-1"
    then
        return {
            combatSpells = avoidableSpells,
            maxAmount = 60,
            totalAmount = 90,
        }
    end
    return {
        combatSpells = {},
        maxAmount = 0,
        totalAmount = 0,
    }
end

local unitData = {
    player = {
        guid = "Player-1",
        name = "Tank",
        className = "Warrior",
        classFilename = "WARRIOR",
        role = "TANK",
    },
    party1 = {
        guid = "Player-2",
        name = secretValue,
        className = "Mage",
        classFilename = "MAGE",
        role = "DAMAGER",
    },
    party2 = {
        guid = secretValue,
        name = "Hidden",
        className = "Priest",
        classFilename = "PRIEST",
        role = "HEALER",
    },
}

local UIWidgets = {}
local BFI = {
    funcs = {
        isValueNonSecret = function(value)
            if value == secretValue then
                state.rejectedValues = state.rejectedValues + 1
                return false
            end
            return true
        end,
    },
    modules = {
        UIWidgets = UIWidgets,
    },
}
local environment = {
    _G = false,
    C_DamageMeter = damageMeter,
    Enum = ENUM,
    InCombatLockdown = function()
        return state.inCombat
    end,
    UnitGUID = function(unit)
        return unitData[unit] and unitData[unit].guid
    end,
    UnitName = function(unit)
        return unitData[unit] and unitData[unit].name, nil
    end,
    UnitClass = function(unit)
        if not unitData[unit] then return end
        return unitData[unit].className, unitData[unit].classFilename
    end,
    UnitGroupRolesAssigned = function(unit)
        return unitData[unit] and unitData[unit].role
    end,
    ipairs = ipairs,
    math = math,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    table = table,
    type = type,
}
environment._G = environment

local chunk, loadError =
    loadfile("Modules/UIWidgets/MythicPlusMeter.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local Meter = UIWidgets.MythicPlusMeter
assertTrue(Meter, "public meter adapter")
assertEqual(
    Meter.GetDefaultSessionType(),
    ENUM.DamageMeterSessionType.Overall,
    "default session type"
)

local adapter = Meter.CreateAdapter({
    damageMeter = damageMeter,
    enum = ENUM,
    inCombatLockdown = environment.InCombatLockdown,
    isValueNonSecret = BFI.funcs.isValueNonSecret,
    unitGUID = environment.UnitGUID,
    unitName = environment.UnitName,
    unitClass = environment.UnitClass,
    unitRole = environment.UnitGroupRolesAssigned,
})

local roster = adapter:CaptureRoster()
assertEqual(#roster, 2, "secret and missing GUIDs are excluded")
assertEqual(roster[1].guid, "Player-1", "player roster order")
assertEqual(roster[2].guid, "Player-2", "party roster order")
assertEqual(roster[2].name, nil, "secret roster name is rejected")
assertEqual(roster[2].classFilename, "MAGE", "safe class retained")

state.inCombat = true
local apiCallsBeforeCombat = state.apiCalls
local combatSnapshot, combatReason =
    adapter:CollectRunSnapshot(roster)
assertEqual(combatSnapshot, nil, "combat snapshot refused")
assertEqual(combatReason, "combat_lockdown", "combat refusal reason")
assertEqual(
    state.apiCalls,
    apiCallsBeforeCombat,
    "combat refusal happens before session API reads"
)

state.inCombat = false
local snapshot, snapshotReason = adapter:CollectRunSnapshot(
    roster,
    ENUM.DamageMeterSessionType.Overall
)
assertTrue(snapshot, snapshotReason or "snapshot")
assertEqual(snapshot.sessionType, 0, "explicit session type")
assertEqual(snapshot.coreComplete, true, "optional metrics do not fail core")
assertEqual(#snapshot.players, 2, "only roster players retained")
assertEqual(snapshot.players[1].guid, "Player-1", "snapshot order player")
assertEqual(snapshot.players[2].guid, "Player-2", "snapshot order party")
assertEqual(
    snapshot.players[2].specIconID,
    132355,
    "safe meter spec metadata is propagated"
)

local playerOne = snapshot.players[1]
local playerTwo = snapshot.players[2]
assertEqual(
    playerOne.metrics.damageTaken.available,
    true,
    "explicit zero is available"
)
assertEqual(
    playerOne.metrics.damageTaken.value,
    0,
    "explicit zero is retained"
)
assertEqual(
    playerTwo.metrics.avoidableDamageTaken.available,
    true,
    "missing player row is zero when avoidable tracking is active"
)
assertEqual(
    playerTwo.metrics.avoidableDamageTaken.value,
    0,
    "active avoidable category gives missing players zero"
)
assertEqual(
    playerTwo.metrics.damageDone.available,
    false,
    "secret amount rejects its source row"
)
assertEqual(
    snapshot.categories.damageDone.complete,
    false,
    "secret source marks category incomplete"
)
assertEqual(
    snapshot.group.damageTaken.value,
    120,
    "group total includes roster sources only"
)
assertEqual(
    snapshot.group.dps.value,
    180,
    "Dps uses per-second values"
)
assertEqual(
    snapshot.players[1].metrics.deaths.value,
    2,
    "duplicate death entries aggregate by roster GUID"
)
assertEqual(
    snapshot.group.deaths.value,
    2,
    "group deaths include repeated deaths"
)
assertEqual(
    #playerOne.topAvoidableSpells,
    6,
    "raw snapshots retain all spells until run subtraction"
)
assertEqual(
    playerOne.topAvoidableSpells[1].spellID,
    106,
    "spell details are sorted by amount"
)
assertEqual(
    playerOne.avoidableDrilldownAvailable,
    true,
    "spell drilldown availability"
)
assertEqual(state.sourceCalls, 1, "only matched avoidable source drilled down")
assertTrue(state.rejectedValues >= 3, "conditional secret values rejected")

local currentSnapshot, currentReason = adapter:CollectRunSnapshot(
    roster,
    ENUM.DamageMeterSessionType.Current
)
assertEqual(currentSnapshot, nil, "missing Current session is not guessed")
assertEqual(
    currentReason,
    "session_empty",
    "authoritatively empty Current session reason"
)

local populatedSessions = sessions
sessions = {}
for _, damageType in pairs(DAMAGE_TYPE) do
    sessions[damageType] = {
        combatSources = {},
        maxAmount = 0,
        totalAmount = 0,
        durationSeconds = 10,
    }
end
sessions[DAMAGE_TYPE.DamageTaken] = {
    combatSources = {
        makeSource("Outsider-1", 100, 10),
    },
    maxAmount = 100,
    totalAmount = 100,
    durationSeconds = 10,
}
local unmatchedSnapshot, unmatchedReason =
    adapter:CollectRunSnapshot(roster)
assertEqual(unmatchedSnapshot, nil,
    "non-empty unmatched Overall data is not treated as zero")
assertEqual(unmatchedReason, "roster_sources_unavailable",
    "non-empty unmatched session fails closed")
sessions = populatedSessions

local previousAvoidable = sessions[DAMAGE_TYPE.AvoidableDamageTaken]
sessions[DAMAGE_TYPE.AvoidableDamageTaken] = {
    combatSources = {},
    maxAmount = 0,
    totalAmount = 0,
    durationSeconds = 100,
}
local inactiveSnapshot = assert(adapter:CollectRunSnapshot(roster))
assertEqual(
    inactiveSnapshot.categories.avoidableDamageTaken.available,
    false,
    "empty avoidable category is not active"
)
assertEqual(
    inactiveSnapshot.players[1].metrics.avoidableDamageTaken.available,
    false,
    "inactive category is not represented as zero"
)
sessions[DAMAGE_TYPE.AvoidableDamageTaken] = previousAvoidable

local previousInterrupts = sessions[DAMAGE_TYPE.Interrupts]
sessions[DAMAGE_TYPE.Interrupts] = {
    combatSources = {
        makeSource("Player-2", 3, 0.03),
    },
    maxAmount = 3,
    totalAmount = 3,
    durationSeconds = 100,
}
local zeroInterruptSnapshot = assert(adapter:CollectRunSnapshot(roster))
assertEqual(
    zeroInterruptSnapshot.players[1].metrics.interrupts.value,
    0,
    "players absent from Interrupts rows receive zero interrupts"
)
sessions[DAMAGE_TYPE.Interrupts] = previousInterrupts

local previousDeaths = sessions[DAMAGE_TYPE.Deaths]
sessions[DAMAGE_TYPE.Deaths] = {
    combatSources = {},
    maxAmount = 0,
    totalAmount = 0,
    durationSeconds = 100,
}
local deathlessSnapshot = assert(adapter:CollectRunSnapshot(roster))
assertEqual(
    deathlessSnapshot.group.deaths.available,
    true,
    "an available empty Deaths category has an authoritative zero"
)
assertEqual(
    deathlessSnapshot.players[2].metrics.deaths.value,
    0,
    "players absent from Deaths rows receive zero deaths"
)
assertEqual(
    deathlessSnapshot.coreComplete,
    true,
    "deathless runs retain structurally complete core meter data"
)
local deathlessDelta = assert(adapter:SubtractSnapshots({
    schemaVersion = 1,
    sessionType = 0,
    authoritativeZero = true,
    complete = true,
    coreComplete = true,
    durationSeconds = 0,
    categories = {},
    group = {},
    players = {},
}, deathlessSnapshot))
assertEqual(
    deathlessDelta.coreComplete,
    true,
    "missing death source does not invalidate a run delta"
)
sessions[DAMAGE_TYPE.Deaths] = previousDeaths

local function copyTable(source, seen)
    if type(source) ~= "table" then return source end
    seen = seen or {}
    if seen[source] then return seen[source] end

    local copy = {}
    seen[source] = copy
    for key, value in pairs(source) do
        copy[copyTable(key, seen)] = copyTable(value, seen)
    end
    return copy
end

local startSnapshot = copyTable(snapshot)
startSnapshot.durationSeconds = 90
startSnapshot.categories.damageTaken.totalAmount = 1099
startSnapshot.categories.avoidableDamageTaken.totalAmount = 80
startSnapshot.categories.interrupts.totalAmount = 1
startSnapshot.categories.deaths.totalAmount = 1
startSnapshot.categories.damageDone.totalAmount = 1700
startSnapshot.group.damageTaken.value = 100
startSnapshot.group.avoidableDamageTaken.value = 80
startSnapshot.group.interrupts.value = 1
startSnapshot.group.deaths.value = 1
startSnapshot.group.damageDone.value = 900
startSnapshot.players[1].metrics.avoidableDamageTaken.value = 80
startSnapshot.players[1].metrics.avoidableDamageTaken.totalAmount = 80
startSnapshot.players[1].metrics.deaths.value = 1
startSnapshot.players[1].metrics.deaths.totalAmount = 1
startSnapshot.players[1].metrics.damageDone.value = 900
startSnapshot.players[1].metrics.damageDone.totalAmount = 900
startSnapshot.players[2].metrics.damageTaken.value = 100
startSnapshot.players[2].metrics.damageTaken.totalAmount = 100
startSnapshot.players[2].metrics.interrupts.value = 1
startSnapshot.players[2].metrics.interrupts.totalAmount = 1
for _, spell in ipairs(startSnapshot.players[1].topAvoidableSpells) do
    spell.totalAmount = spell.totalAmount - 5
end

local deltaSnapshot, deltaReason =
    adapter:SubtractSnapshots(startSnapshot, snapshot)
assertTrue(deltaSnapshot, deltaReason or "delta snapshot")
assertEqual(deltaSnapshot.durationSeconds, 10, "duration delta")
assertEqual(deltaSnapshot.valid, true, "monotonic delta is valid")
assertEqual(deltaSnapshot.coreComplete, true, "delta core completeness")
assertEqual(
    deltaSnapshot.group.damageTaken.value,
    20,
    "group category delta"
)
assertEqual(
    deltaSnapshot.players[2].metrics.damageTaken.value,
    20,
    "player delta is matched by GUID"
)
assertEqual(
    deltaSnapshot.players[2].metrics.interrupts.value,
    2,
    "count delta"
)
assertEqual(
    deltaSnapshot.players[2].metrics.avoidableDamageTaken.available,
    true,
    "zero avoidable delta remains available"
)
assertEqual(
    deltaSnapshot.players[2].metrics.avoidableDamageTaken.value,
    0,
    "missing avoidable source subtracts as zero"
)
assertEqual(
    deltaSnapshot.players[1].metrics.dps.value,
    10,
    "run Dps is derived from damage and duration deltas"
)
assertEqual(
    deltaSnapshot.players[1].topAvoidableSpells[1].totalAmount,
    5,
    "avoidable spell totals are differenced"
)
assertEqual(
    #deltaSnapshot.players[1].topAvoidableSpells,
    5,
    "final run details retain only the top five differenced spells"
)

local zeroDurationDelta = assert(
    adapter:SubtractSnapshots(startSnapshot, startSnapshot)
)
assertEqual(
    zeroDurationDelta.durationSeconds,
    0,
    "stale snapshot duration is observable"
)
assertEqual(
    zeroDurationDelta.coreComplete,
    false,
    "zero-duration delta cannot be baseline-complete"
)

local unavailableAvoidableStart = copyTable(startSnapshot)
unavailableAvoidableStart.categories.avoidableDamageTaken = {
    available = false,
    complete = false,
    reason = "session_unavailable",
}
unavailableAvoidableStart.group.avoidableDamageTaken = {
    available = false,
    reason = "session_unavailable",
}
for _, player in ipairs(unavailableAvoidableStart.players) do
    player.metrics.avoidableDamageTaken = {
        available = false,
        reason = "session_unavailable",
    }
    player.topAvoidableSpells = nil
    player.avoidableDrilldownAvailable = false
end
local unavailableAvoidableDelta = assert(
    adapter:SubtractSnapshots(unavailableAvoidableStart, snapshot)
)
assertEqual(
    unavailableAvoidableDelta.coreComplete,
    true,
    "optional avoidable start failure does not discard core metrics"
)
assertEqual(
    unavailableAvoidableDelta.group.avoidableDamageTaken.available,
    false,
    "transient start failure is not converted to avoidable zero"
)
assertEqual(
    unavailableAvoidableDelta.players[1].topAvoidableSpells,
    nil,
    "spell drilldown is omitted when its start endpoint is unknown"
)

local inactiveAvoidableStart = copyTable(unavailableAvoidableStart)
inactiveAvoidableStart.categories.avoidableDamageTaken.reason = "not_active"
inactiveAvoidableStart.group.avoidableDamageTaken.reason = "not_active"
for _, player in ipairs(inactiveAvoidableStart.players) do
    player.metrics.avoidableDamageTaken.reason = "not_active"
end
local inactiveAvoidableDelta = assert(
    adapter:SubtractSnapshots(inactiveAvoidableStart, snapshot)
)
assertEqual(
    inactiveAvoidableDelta.group.avoidableDamageTaken.available,
    true,
    "explicitly inactive start category is an authoritative zero"
)

local resetStart = copyTable(startSnapshot)
resetStart.players[1].metrics.interrupts.value = 2
resetStart.players[1].metrics.interrupts.totalAmount = 2
local resetSnapshot = assert(
    adapter:SubtractSnapshots(resetStart, snapshot)
)
assertEqual(resetSnapshot.valid, false, "meter reset invalidates delta")
assertEqual(resetSnapshot.corrupt, true, "meter reset marks corruption")
assertEqual(
    resetSnapshot.players[1].metrics.interrupts.available,
    false,
    "decreasing counter is not clamped to zero"
)
assertEqual(
    resetSnapshot.players[1].metrics.interrupts.reason,
    "meter_reset",
    "decreasing counter reset reason"
)

local secretCategory, secretCategoryReason =
    adapter:FetchCategory(0, secretValue)
assertEqual(secretCategory, nil, "secret category refused")
assertEqual(
    secretCategoryReason,
    "secret_category",
    "secret category reason"
)

local sourceFile = assert(io.open(
    "Modules/UIWidgets/MythicPlusMeter.lua",
    "r"
))
local sourceText = sourceFile:read("*a")
sourceFile:close()
assertTrue(
    not sourceText:find("p" .. "call", 1, true),
    "module must not probe meter values through protected calls"
)

print("mythic_plus_meter_test.lua: ok")
