---@type BFI
local BFI = select(2, ...)
---@class UnitFrames
local UF = BFI.modules.UnitFrames

local floor = math.floor
local ipairs, pairs, sort, type =
    ipairs, pairs, table.sort, type
local insert, remove = table.insert, table.remove
local match = string.match

-- The base Buffs indicator keeps its existing flat schema. These four keys
-- describe optional child displays that may reserve additional native aura
-- containers. Keeping the collection in the existing table makes migration
-- additive and preserves the established Buffs row and runtime verbatim.
local SCHEMA_VERSION = 1
-- Retail 12.1.0.69299 (wow-ui-source commit
-- 31c7f7b9cc79e56c986b365c06a6afbcf3c9177b) allocates managed custom-aura
-- buttons in batches of ten. A single-group child display across forty Raid
-- units can therefore add 400 restricted buttons, so keep the concurrently
-- reserved child topology deliberately small and deterministic.
local MAX_ACTIVE_CHILD_DISPLAYS = 4
local MAX_CHILD_INITIAL_RESERVATIONS = 40
local NATIVE_GROUP_INITIAL_RESERVATIONS = 10

local BUILT_IN_ORDER = {
    "healing_auras",
    "defensives",
    "externals",
}

local BUILT_IN_NAMES = {
    healing_auras = "Healing Auras",
    defensives = "Defensives",
    externals = "Externals",
}

local COLLECTION_KEYS = {
    displays = true,
    nextCustomID = true,
    order = true,
    schemaVersion = true,
}

UF.BUFF_DISPLAY_SCHEMA_VERSION = SCHEMA_VERSION
UF.MAX_ACTIVE_CHILD_BUFF_DISPLAYS = MAX_ACTIVE_CHILD_DISPLAYS
UF.MAX_CHILD_BUFF_DISPLAY_INITIAL_RESERVATIONS =
    MAX_CHILD_INITIAL_RESERVATIONS
UF.BUILT_IN_BUFF_DISPLAY_IDS = {
    BUILT_IN_ORDER[1],
    BUILT_IN_ORDER[2],
    BUILT_IN_ORDER[3],
}

local function Copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local copied = {}
    seen[value] = copied
    for key, child in pairs(value) do
        copied[Copy(key, seen)] = Copy(child, seen)
    end
    return copied
end

local function CopyBaseBuffConfig(buffConfig)
    local copied = {}
    for key, value in pairs(buffConfig) do
        if not COLLECTION_KEYS[key] then
            copied[Copy(key)] = Copy(value)
        end
    end
    return copied
end

local function IsPositiveInteger(value)
    return type(value) == "number"
        and value > 0
        and value == floor(value)
end

local function NormalizeName(value)
    if type(value) ~= "string" then return nil end
    local trimmed = match(value, "^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    return trimmed
end

local function CategoryFilters(id)
    return {
        all = false,
        player = false,
        notPlayer = false,
        raidInCombat = false,
        raidPlayerDispellable = false,
        bigDefensive = id == "defensives",
        externalDefensive = id == "externals",
        important = false,
        anyDispellable = false,
    }
end

local function ResolveTemplate(templates, id)
    if type(templates) ~= "table" then return nil end

    local template = templates[id]
    if type(template) == "table" then return template end

    if id == "healing_auras"
        and type(templates.healingAuras) == "table"
    then
        return templates.healingAuras
    end
end

local function CreateBuiltInConfig(buffConfig, templates, id)
    local supplied = ResolveTemplate(templates, id)
    local config = supplied and Copy(supplied)
        or CopyBaseBuffConfig(buffConfig)

    config.enabled = false
    if supplied then return config end

    if id == "healing_auras" then
        local whitelist = type(templates) == "table"
            and templates.healingWhitelist
            or nil
        config.mode = "whitelist"
        config.blacklist = {}
        if type(whitelist) == "table" then
            config.whitelist = Copy(whitelist)
        elseif type(config.whitelist) ~= "table" then
            config.whitelist = {}
        end
    else
        config.filters = CategoryFilters(id)
        config.mode = "blacklist"
        config.blacklist = {}
        config.whitelist = {}
    end

    return config
end

local function CreateBuiltInRecord(buffConfig, templates, id)
    local record = CreateBuiltInConfig(buffConfig, templates, id)
    record.id = id
    record.builtIn = true
    record.name = BUILT_IN_NAMES[id]
    record.presentation = record.presentation or "icons"
    return record
end

local function CustomIDNumber(id)
    if type(id) ~= "string" then return nil end
    local digits = match(id, "^custom_(%d+)$")
    local value = digits and tonumber(digits)
    if not IsPositiveInteger(value) then return nil end
    return value
end

local function SortDisplayIDs(left, right)
    local leftNumber = CustomIDNumber(left)
    local rightNumber = CustomIDNumber(right)
    if leftNumber and rightNumber then
        return leftNumber < rightNumber
    elseif leftNumber then
        return false
    elseif rightNumber then
        return true
    end
    return left < right
end

local function AppendMissingOrderIDs(buffConfig)
    local displays = buffConfig.displays
    local seen = {}
    local normalized = {}

    if type(buffConfig.order) == "table" then
        for _, id in ipairs(buffConfig.order) do
            if type(id) == "string"
                and type(displays[id]) == "table"
                and not seen[id]
            then
                seen[id] = true
                normalized[#normalized + 1] = id
            end
        end
    end

    for _, id in ipairs(BUILT_IN_ORDER) do
        if not seen[id] then
            seen[id] = true
            normalized[#normalized + 1] = id
        end
    end

    local remaining = {}
    for id, record in pairs(displays) do
        if type(id) == "string"
            and type(record) == "table"
            and not seen[id]
        then
            remaining[#remaining + 1] = id
        end
    end
    sort(remaining, SortDisplayIDs)
    for _, id in ipairs(remaining) do
        normalized[#normalized + 1] = id
    end

    buffConfig.order = normalized
end

local function NormalizeRecords(buffConfig, templates)
    local displays = buffConfig.displays
    for id in pairs(displays) do
        if type(id) ~= "string" or type(displays[id]) ~= "table" then
            displays[id] = nil
        end
    end

    for _, id in ipairs(BUILT_IN_ORDER) do
        local record = displays[id]
        if type(record) ~= "table" then
            record = CreateBuiltInRecord(buffConfig, templates, id)
            displays[id] = record
        end
        record.id = id
        record.builtIn = true
        record.name = BUILT_IN_NAMES[id]
        record.presentation = record.presentation or "icons"
        if type(record.enabled) ~= "boolean" then
            record.enabled = false
        end
    end

    for id, record in pairs(displays) do
        if not BUILT_IN_NAMES[id] then
            record.id = id
            record.builtIn = false
            record.name = NormalizeName(record.name)
                or ("Buff Display " .. id)
            record.presentation = record.presentation or "icons"
            if type(record.enabled) ~= "boolean" then
                record.enabled = false
            end
        end
    end
end

local function NormalizeNextCustomID(buffConfig)
    local nextID = IsPositiveInteger(buffConfig.nextCustomID)
        and buffConfig.nextCustomID
        or 1

    for id in pairs(buffConfig.displays) do
        local value = CustomIDNumber(id)
        if value and value >= nextID then
            nextID = value + 1
        end
    end
    buffConfig.nextCustomID = nextID
end

-- templates may provide complete configs by built-in ID. As a convenience,
-- callers may instead pass `healingWhitelist`; this keeps the curated spell
-- list owned by Presets.lua while this model remains list-agnostic.
function UF.NormalizeBuffDisplayCollection(buffConfig, templates)
    if type(buffConfig) ~= "table" then
        return nil, "INVALID_BUFF_CONFIG"
    end

    local version = buffConfig.schemaVersion
    if version ~= nil and version ~= SCHEMA_VERSION then
        return nil, "UNSUPPORTED_SCHEMA_VERSION"
    end

    buffConfig.schemaVersion = SCHEMA_VERSION
    if type(buffConfig.displays) ~= "table" then
        buffConfig.displays = {}
    end

    NormalizeRecords(buffConfig, templates)
    AppendMissingOrderIDs(buffConfig)
    NormalizeNextCustomID(buffConfig)
    return buffConfig
end

local function RequireCollection(buffConfig)
    return UF.NormalizeBuffDisplayCollection(buffConfig)
end

local function FindOrderIndex(buffConfig, id)
    for index, orderedID in ipairs(buffConfig.order) do
        if orderedID == id then return index end
    end
end

function UF.GetOrderedBuffDisplays(buffConfig)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local ordered = {}
    for _, id in ipairs(buffConfig.order) do
        local record = buffConfig.displays[id]
        if record then ordered[#ordered + 1] = record end
    end
    return ordered
end

local function GetInitialReservationCost(record)
    local isFrameHighlight = record.presentation == "frame_highlight"

    -- BuffDisplayRuntime compiles children with spell-color expansion and the
    -- Separate Own subFrame partition disabled. The policy group count is
    -- therefore the complete AddAuraGroup topology for icon presentations.
    if type(UF.CompileNativeAuraPolicy) == "function" then
        local policy = UF.CompileNativeAuraPolicy(
            "HELPFUL",
            record.filters
        )
        if type(policy) ~= "table" then
            return MAX_CHILD_INITIAL_RESERVATIONS + 1
        end
        local groupCount = type(policy.groups) == "table"
            and #policy.groups
            or 0
        if isFrameHighlight then
            -- One AuraSlot drives one managed overlay. A filter that compiles
            -- to multiple native groups cannot preserve those semantics with
            -- a single frame highlight, so reject it instead of widening it.
            if groupCount == 0 then return 0 end
            return groupCount == 1
                and 1
                or MAX_CHILD_INITIAL_RESERVATIONS + 1
        end
        return groupCount * NATIVE_GROUP_INITIAL_RESERVATIONS
    end

    -- The standalone schema can load before AuraPolicy. Reserve one native
    -- batch conservatively until the policy compiler is available; a frame
    -- highlight always consumes exactly one native slot.
    return isFrameHighlight and 1 or NATIVE_GROUP_INITIAL_RESERVATIONS
end

-- Runtime construction must consume this bounded plan instead of walking the
-- raw map. Imported profiles can therefore never reserve more than the
-- reviewed child-container budget even when their SavedVariables were edited.
function UF.GetActiveBuffDisplayReservationPlan(buffConfig)
    local ordered, errorCode = UF.GetOrderedBuffDisplays(buffConfig)
    if not ordered then return nil, nil, errorCode end

    local reserved = {}
    local overflow = {}
    local reservations = 0
    local reservationCosts = {}
    for _, record in ipairs(ordered) do
        if record.enabled == true then
            local cost = GetInitialReservationCost(record)
            reservationCosts[record.id] = cost
            if #reserved < MAX_ACTIVE_CHILD_DISPLAYS
                and reservations + cost
                    <= MAX_CHILD_INITIAL_RESERVATIONS
            then
                reserved[#reserved + 1] = record
                reservations = reservations + cost
            else
                overflow[#overflow + 1] = record
            end
        end
    end
    return reserved, overflow, {
        initialReservations = reservations,
        initialReservationLimit = MAX_CHILD_INITIAL_RESERVATIONS,
        reservationCosts = reservationCosts,
    }
end

function UF.SetBuffDisplayEnabled(buffConfig, id, enabled)
    if type(enabled) ~= "boolean" then
        return nil, "INVALID_ENABLED_STATE"
    end

    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local record = buffConfig.displays[id]
    if not record then return nil, "UNKNOWN_DISPLAY" end
    if not enabled or record.enabled == true then
        record.enabled = enabled
        return record
    end

    record.enabled = true
    local reserved = UF.GetActiveBuffDisplayReservationPlan(buffConfig)
    local admitted = false
    for _, active in ipairs(reserved) do
        if active == record then
            admitted = true
            break
        end
    end
    if not admitted then
        record.enabled = false
        return nil, "ACTIVE_DISPLAY_LIMIT"
    end
    return record
end

function UF.AllocateCustomBuffDisplayID(buffConfig)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local value = buffConfig.nextCustomID
    local id = "custom_" .. value
    while buffConfig.displays[id] do
        value = value + 1
        id = "custom_" .. value
    end
    buffConfig.nextCustomID = value + 1
    return id
end

function UF.CreateBuffDisplay(buffConfig, name, templateConfig)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    name = NormalizeName(name)
    if not name then return nil, "INVALID_DISPLAY_NAME" end
    if templateConfig ~= nil and type(templateConfig) ~= "table" then
        return nil, "INVALID_DISPLAY_TEMPLATE"
    end

    local id, allocationError =
        UF.AllocateCustomBuffDisplayID(buffConfig)
    if not id then return nil, allocationError end

    local record = templateConfig and Copy(templateConfig)
        or CopyBaseBuffConfig(buffConfig)
    record.id = id
    record.builtIn = false
    record.name = name
    record.enabled = false
    record.presentation = record.presentation or "icons"
    buffConfig.displays[id] = record
    buffConfig.order[#buffConfig.order + 1] = id
    return record
end

function UF.DuplicateBuffDisplay(buffConfig, id, name)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local source = buffConfig.displays[id]
    if not source then return nil, "UNKNOWN_DISPLAY" end
    return UF.CreateBuffDisplay(
        buffConfig,
        name or (source.name .. " Copy"),
        source
    )
end

function UF.RenameBuffDisplay(buffConfig, id, name)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local record = buffConfig.displays[id]
    if not record then return nil, "UNKNOWN_DISPLAY" end
    if record.builtIn then return nil, "BUILT_IN_DISPLAY" end

    name = NormalizeName(name)
    if not name then return nil, "INVALID_DISPLAY_NAME" end
    record.name = name
    return record
end

function UF.DeleteBuffDisplay(buffConfig, id)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end

    local record = buffConfig.displays[id]
    if not record then return nil, "UNKNOWN_DISPLAY" end
    if record.builtIn then
        record.enabled = false
        return record, "BUILT_IN_DISABLED"
    end

    buffConfig.displays[id] = nil
    local index = FindOrderIndex(buffConfig, id)
    if index then remove(buffConfig.order, index) end
    return record
end

function UF.MoveBuffDisplay(buffConfig, id, newIndex)
    local normalized, errorCode = RequireCollection(buffConfig)
    if not normalized then return nil, errorCode end
    if not IsPositiveInteger(newIndex) then
        return nil, "INVALID_DISPLAY_INDEX"
    end

    local oldIndex = FindOrderIndex(buffConfig, id)
    if not oldIndex then return nil, "UNKNOWN_DISPLAY" end

    if newIndex > #buffConfig.order then
        newIndex = #buffConfig.order
    end
    remove(buffConfig.order, oldIndex)
    insert(buffConfig.order, newIndex, id)
    return buffConfig.displays[id]
end
