---@type BFI
local BFI = select(2, ...)
local W = BFI.modules.UIWidgets
local F = BFI.funcs

local M = {}
W.MythicPlusMeter = M

local MAX_AVOIDABLE_SPELLS = 5
local ROSTER_UNITS = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4",
}
local CATEGORY_DEFINITIONS = {
    {
        key = "damageTaken",
        enumName = "DamageTaken",
        core = true,
    },
    {
        key = "avoidableDamageTaken",
        enumName = "AvoidableDamageTaken",
        includeSpells = true,
        zeroWhenSourceMissing = true,
    },
    {
        key = "interrupts",
        enumName = "Interrupts",
        core = true,
        zeroWhenSourceMissing = true,
    },
    {
        key = "deaths",
        enumName = "Deaths",
        core = true,
        zeroWhenSourceMissing = true,
    },
    {
        key = "damageDone",
        enumName = "DamageDone",
    },
    {
        key = "dps",
        enumName = "Dps",
        valuePerSecond = true,
    },
}

local Adapter = {}
Adapter.__index = Adapter

local function GetDamageMeterTypes(adapter)
    local enum = adapter.dependencies.enum
    if type(enum) ~= "table" then return end

    local types = enum.DamageMeterType
    if type(types) ~= "table" then return end

    return types
end

local function GetSessionTypes(adapter)
    local enum = adapter.dependencies.enum
    if type(enum) ~= "table" then return end

    local types = enum.DamageMeterSessionType
    if type(types) ~= "table" then return end

    return types
end

local function GetSourceDisplayTypes(adapter)
    local enum = adapter.dependencies.enum
    if type(enum) ~= "table" then return end

    local types = enum.DamageMeterSourceDisplayType
    if type(types) ~= "table" then return end

    return types
end

local function GetNonSecret(adapter, value)
    local predicate = adapter.dependencies.isValueNonSecret
    if type(predicate) ~= "function" then
        return nil, false
    end

    if not predicate(value) then
        return nil, false
    end

    return value, true
end

local function GetNonSecretNumber(adapter, value)
    local accepted, isNonSecret = GetNonSecret(adapter, value)
    if not isNonSecret or type(accepted) ~= "number" then
        return nil, false
    end

    return accepted, true
end

local function GetOptionalNonSecretNumber(adapter, value)
    local accepted, isNonSecret = GetNonSecret(adapter, value)
    if not isNonSecret then
        return nil, false
    end
    if accepted == nil then
        return nil, true
    end
    if type(accepted) ~= "number" then
        return nil, false
    end

    return accepted, true
end

local function GetOptionalNonSecretString(adapter, value)
    local accepted, isNonSecret = GetNonSecret(adapter, value)
    if not isNonSecret then
        return nil, false
    end
    if accepted == nil then
        return nil, true
    end
    if type(accepted) ~= "string" then
        return nil, false
    end

    return accepted, true
end

local function GetOptionalNonSecretBoolean(adapter, value)
    local accepted, isNonSecret = GetNonSecret(adapter, value)
    if not isNonSecret then
        return nil, false
    end
    if accepted == nil then
        return nil, true
    end
    if type(accepted) ~= "boolean" then
        return nil, false
    end

    return accepted, true
end

local function CopyValue(adapter, rawValue, expectedType)
    local value, isNonSecret = GetNonSecret(adapter, rawValue)
    if not isNonSecret then return end
    if value == nil or type(value) == expectedType then
        return value
    end
end

local function ResolveDefinitionByName(name)
    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        if name == definition.enumName or name == definition.key then
            return definition
        end
    end
end

local function ResolveDefinitionByValue(adapter, value)
    local types = GetDamageMeterTypes(adapter)
    if not types then return end

    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        if value == types[definition.enumName] then
            return definition
        end
    end
end

function Adapter:ResolveCategory(category)
    local accepted, isNonSecret = GetNonSecret(self, category)
    if not isNonSecret then
        return nil, nil, "secret_category"
    end

    local definition
    if type(accepted) == "string" then
        definition = ResolveDefinitionByName(accepted)
    elseif type(accepted) == "number" then
        definition = ResolveDefinitionByValue(self, accepted)
    end
    if not definition then
        return nil, nil, "unsupported_category"
    end

    local types = GetDamageMeterTypes(self)
    if not types then
        return nil, nil, "enum_unavailable"
    end

    local enumValue = types[definition.enumName]
    if type(enumValue) ~= "number" then
        return nil, nil, "enum_unavailable"
    end

    return enumValue, definition
end

function Adapter:GetDefaultSessionType()
    local sessionTypes = GetSessionTypes(self)
    if not sessionTypes or type(sessionTypes.Overall) ~= "number" then
        return nil
    end

    return sessionTypes.Overall
end

function Adapter:IsSafeToRead()
    local inCombatLockdown = self.dependencies.inCombatLockdown
    if type(inCombatLockdown) ~= "function" then
        return false, "lockdown_api_unavailable"
    end

    local inCombat, isNonSecret = GetNonSecret(self, inCombatLockdown())
    if not isNonSecret or type(inCombat) ~= "boolean" then
        return false, "lockdown_state_unavailable"
    end
    if inCombat then
        return false, "combat_lockdown"
    end

    return true
end

function Adapter:CaptureRoster()
    local roster = {}
    local unitGUID = self.dependencies.unitGUID
    local unitName = self.dependencies.unitName
    local unitClass = self.dependencies.unitClass
    local unitRole = self.dependencies.unitRole

    if type(unitGUID) ~= "function" then
        return roster
    end

    for _, unit in ipairs(ROSTER_UNITS) do
        local guid, guidIsNonSecret = GetNonSecret(self, unitGUID(unit))
        if guidIsNonSecret and type(guid) == "string" and guid ~= "" then
            local row = {
                order = #roster + 1,
                unit = unit,
                guid = guid,
            }

            if type(unitName) == "function" then
                local name, realmName = unitName(unit)
                row.name = CopyValue(self, name, "string")
                row.realmName = CopyValue(self, realmName, "string")
            end

            if type(unitClass) == "function" then
                local className, classFilename = unitClass(unit)
                row.className = CopyValue(self, className, "string")
                row.classFilename =
                    CopyValue(self, classFilename, "string")
            end

            if type(unitRole) == "function" then
                local role = unitRole(unit)
                row.role = CopyValue(self, role, "string")
            end

            roster[#roster + 1] = row
        end
    end

    return roster
end

local function IsRosterSource(adapter, sourceGUID, sourceDisplayType,
                              isLocalPlayer, rosterByGUID)
    if rosterByGUID then
        return sourceGUID ~= nil and rosterByGUID[sourceGUID] ~= nil
    end

    if isLocalPlayer then return true end

    local sourceDisplayTypes = GetSourceDisplayTypes(adapter)
    if not sourceDisplayTypes then return false end

    return sourceDisplayType == sourceDisplayTypes.Ally
end

local function ReadAvoidableSpells(adapter, api, sessionType, categoryType,
                                   sourceGUID, sourceCreatureID)
    local getSource = api.GetCombatSessionSourceFromType
    if type(getSource) ~= "function" then
        return nil, false
    end

    local sessionSource = getSource(
        sessionType,
        categoryType,
        sourceGUID,
        sourceCreatureID
    )
    local acceptedSource, sourceIsNonSecret =
        GetNonSecret(adapter, sessionSource)
    if not sourceIsNonSecret or type(acceptedSource) ~= "table" then
        return nil, false
    end

    local rawSpells = acceptedSource.combatSpells
    local spells, spellsAreNonSecret = GetNonSecret(adapter, rawSpells)
    if not spellsAreNonSecret or type(spells) ~= "table" then
        return nil, false
    end

    local sanitized = {}
    for _, rawSpell in ipairs(spells) do
        local spell, spellIsNonSecret = GetNonSecret(adapter, rawSpell)
        if spellIsNonSecret and type(spell) == "table" then
            local spellID, spellIDIsValid =
                GetNonSecretNumber(adapter, spell.spellID)
            local totalAmount, totalIsValid =
                GetNonSecretNumber(adapter, spell.totalAmount)
            local amountPerSecond =
                GetOptionalNonSecretNumber(adapter, spell.amountPerSecond)
            local creatureName =
                GetOptionalNonSecretString(adapter, spell.creatureName)
            local isAvoidable =
                GetOptionalNonSecretBoolean(adapter, spell.isAvoidable)
            local isDeadly =
                GetOptionalNonSecretBoolean(adapter, spell.isDeadly)

            if spellIDIsValid and totalIsValid then
                sanitized[#sanitized + 1] = {
                    spellID = spellID,
                    totalAmount = totalAmount,
                    amountPerSecond = amountPerSecond,
                    creatureName = creatureName,
                    isAvoidable = isAvoidable,
                    isDeadly = isDeadly,
                }
            end
        end
    end

    table.sort(sanitized, function(left, right)
        if left.totalAmount == right.totalAmount then
            return left.spellID < right.spellID
        end
        return left.totalAmount > right.totalAmount
    end)

    -- Retain the complete sanitized list in start/end snapshots. Truncating
    -- before subtraction can lose a spell that becomes a top contributor
    -- during the run after pre-run Overall data is removed.
    return sanitized, true
end

local function SanitizeSource(adapter, api, sessionType, categoryType,
                              definition, rawSource, rosterByGUID)
    local source, sourceIsNonSecret = GetNonSecret(adapter, rawSource)
    if not sourceIsNonSecret or type(source) ~= "table" then
        return nil, "secret_source"
    end

    local sourceGUID, guidIsNonSecret =
        GetOptionalNonSecretString(adapter, source.sourceGUID)
    if not guidIsNonSecret then
        return nil, "secret_source_guid"
    end

    local sourceCreatureID, creatureIDIsNonSecret =
        GetOptionalNonSecretNumber(adapter, source.sourceCreatureID)
    if not creatureIDIsNonSecret then
        return nil, "secret_source_creature"
    end

    local sourceDisplayType, displayTypeIsNonSecret =
        GetOptionalNonSecretNumber(adapter, source.sourceDisplayType)
    if not displayTypeIsNonSecret then
        return nil, "secret_source_display"
    end

    local isLocalPlayer, localPlayerIsNonSecret =
        GetOptionalNonSecretBoolean(adapter, source.isLocalPlayer)
    if not localPlayerIsNonSecret then
        return nil, "secret_source_local"
    end

    if not IsRosterSource(
        adapter,
        sourceGUID,
        sourceDisplayType,
        isLocalPlayer,
        rosterByGUID
    ) then
        return nil
    end

    local totalAmount, totalIsValid =
        GetNonSecretNumber(adapter, source.totalAmount)
    if not totalIsValid then
        return nil, "secret_source_total"
    end

    local amountPerSecond, perSecondIsValid =
        GetOptionalNonSecretNumber(adapter, source.amountPerSecond)
    if not perSecondIsValid then
        return nil, "secret_source_rate"
    end

    local name = GetOptionalNonSecretString(adapter, source.name)
    local classFilename =
        GetOptionalNonSecretString(adapter, source.classFilename)
    local specIconID =
        GetOptionalNonSecretNumber(adapter, source.specIconID)
    local deathRecapID =
        GetOptionalNonSecretNumber(adapter, source.deathRecapID)
    local deathTimeSeconds =
        GetOptionalNonSecretNumber(adapter, source.deathTimeSeconds)

    local sanitized = {
        sourceGUID = sourceGUID,
        sourceCreatureID = sourceCreatureID,
        name = name,
        classFilename = classFilename,
        specIconID = specIconID,
        totalAmount = totalAmount,
        amountPerSecond = amountPerSecond,
        isLocalPlayer = isLocalPlayer,
        deathRecapID = deathRecapID,
        deathTimeSeconds = deathTimeSeconds,
        sourceDisplayType = sourceDisplayType,
    }

    if definition.includeSpells then
        sanitized.topSpells, sanitized.spellDetailsAvailable =
            ReadAvoidableSpells(
                adapter,
                api,
                sessionType,
                categoryType,
                sourceGUID,
                sourceCreatureID
            )
    end

    return sanitized
end

-- Verified against generated DamageMeterDocumentation.lua from Retail
-- 12.0.7.68887 (Gethe commit 4383ced30106d51b27e3e86d1987f1552f0d259d)
-- and 12.1.0.68914 (commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9).
-- Session and source reads are SecretWhenInCombat. Spell drilldown is supplied
-- by GetCombatSessionSourceFromType(...).combatSpells in both artifacts.
function Adapter:FetchCategory(sessionType, category, rosterByGUID)
    local safe, unsafeReason = self:IsSafeToRead()
    if not safe then
        return nil, unsafeReason
    end

    local acceptedSessionType, sessionTypeIsNonSecret =
        GetNonSecret(self, sessionType)
    if not sessionTypeIsNonSecret then
        return nil, "secret_session_type"
    end
    if acceptedSessionType == nil then
        acceptedSessionType = self:GetDefaultSessionType()
    end
    if type(acceptedSessionType) ~= "number" then
        return nil, "session_type_unavailable"
    end

    local categoryType, definition, categoryError =
        self:ResolveCategory(category)
    if not categoryType then
        return nil, categoryError
    end

    local api = self.dependencies.damageMeter
    if type(api) ~= "table"
        or type(api.GetCombatSessionFromType) ~= "function"
    then
        return nil, "damage_meter_api_unavailable"
    end

    local rawSession =
        api.GetCombatSessionFromType(acceptedSessionType, categoryType)
    local session, sessionIsNonSecret = GetNonSecret(self, rawSession)
    if not sessionIsNonSecret or type(session) ~= "table" then
        return nil, "session_unavailable"
    end

    local rawSources = session.combatSources
    local combatSources, sourcesAreNonSecret =
        GetNonSecret(self, rawSources)
    if not sourcesAreNonSecret or type(combatSources) ~= "table" then
        return nil, "session_sources_unavailable"
    end

    local totalAmount, totalIsValid =
        GetNonSecretNumber(self, session.totalAmount)
    if not totalIsValid then
        return nil, "session_total_unavailable"
    end

    local maxAmount, maxIsValid =
        GetNonSecretNumber(self, session.maxAmount)
    if not maxIsValid then
        return nil, "session_max_unavailable"
    end

    local durationSeconds, durationIsValid =
        GetOptionalNonSecretNumber(self, session.durationSeconds)

    local result = {
        available = true,
        complete = durationIsValid,
        key = definition.key,
        enumName = definition.enumName,
        type = categoryType,
        totalAmount = totalAmount,
        maxAmount = maxAmount,
        durationSeconds = durationSeconds,
        sources = {},
        rejectedSources = 0,
    }

    for _, rawSource in ipairs(combatSources) do
        local source, rejectionReason = SanitizeSource(
            self,
            api,
            acceptedSessionType,
            categoryType,
            definition,
            rawSource,
            rosterByGUID
        )
        if source then
            result.sources[#result.sources + 1] = source
        elseif rejectionReason then
            result.complete = false
            result.rejectedSources = result.rejectedSources + 1
        end
    end

    if definition.enumName == "AvoidableDamageTaken"
        and #combatSources == 0
    then
        result.available = false
        result.complete = false
        result.reason = "not_active"
    end

    return result
end

local function SanitizeRoster(adapter, roster)
    local acceptedRoster, rosterIsNonSecret = GetNonSecret(adapter, roster)
    if not rosterIsNonSecret or type(acceptedRoster) ~= "table" then
        return nil
    end

    local sanitized = {}
    local byGUID = {}
    for _, rawRow in ipairs(acceptedRoster) do
        local row, rowIsNonSecret = GetNonSecret(adapter, rawRow)
        if rowIsNonSecret and type(row) == "table" then
            local guid, guidIsNonSecret =
                GetOptionalNonSecretString(adapter, row.guid)
            if guidIsNonSecret and guid and guid ~= "" then
                local copy = {
                    order = #sanitized + 1,
                    unit = CopyValue(
                        adapter,
                        row.unit,
                        "string"
                    ),
                    guid = guid,
                    name = CopyValue(
                        adapter,
                        row.name,
                        "string"
                    ),
                    realmName = CopyValue(
                        adapter,
                        row.realmName,
                        "string"
                    ),
                    className = CopyValue(
                        adapter,
                        row.className,
                        "string"
                    ),
                    classFilename = CopyValue(
                        adapter,
                        row.classFilename,
                        "string"
                    ),
                    role = CopyValue(
                        adapter,
                        row.role,
                        "string"
                    ),
                    metrics = {},
                }
                sanitized[#sanitized + 1] = copy
                byGUID[guid] = copy
            end
        end
    end

    return sanitized, byGUID
end

local function MakeUnavailableMetric(reason)
    return {
        available = false,
        reason = reason,
    }
end

local function MakeSourceMetric(definition, source)
    local value = source.totalAmount
    if definition.valuePerSecond then
        value = source.amountPerSecond
    end
    if value == nil then
        return MakeUnavailableMetric("value_unavailable")
    end

    return {
        available = true,
        value = value,
        totalAmount = source.totalAmount,
        amountPerSecond = source.amountPerSecond,
    }
end

local function MergeTopSpells(target, source)
    local bySpellID = {}
    for _, spell in ipairs(target) do
        bySpellID[spell.spellID] = spell
    end

    for _, spell in ipairs(source) do
        local existing = bySpellID[spell.spellID]
        if existing then
            existing.totalAmount =
                existing.totalAmount + spell.totalAmount
        else
            local copy = {
                spellID = spell.spellID,
                totalAmount = spell.totalAmount,
                amountPerSecond = spell.amountPerSecond,
                creatureName = spell.creatureName,
                isAvoidable = spell.isAvoidable,
                isDeadly = spell.isDeadly,
            }
            target[#target + 1] = copy
            bySpellID[copy.spellID] = copy
        end
    end

    table.sort(target, function(left, right)
        if left.totalAmount == right.totalAmount then
            return left.spellID < right.spellID
        end
        return left.totalAmount > right.totalAmount
    end)
end

local function MergeSourcesByGUID(sources)
    local byGUID = {}
    for _, source in ipairs(sources) do
        local guid = source.sourceGUID
        if guid then
            local existing = byGUID[guid]
            if existing then
                existing.totalAmount =
                    existing.totalAmount + source.totalAmount
                if source.amountPerSecond then
                    existing.amountPerSecond =
                        (existing.amountPerSecond or 0)
                        + source.amountPerSecond
                end
                if not existing.name then
                    existing.name = source.name
                end
                if not existing.classFilename then
                    existing.classFilename = source.classFilename
                end
                if not existing.specIconID then
                    existing.specIconID = source.specIconID
                end
                if source.topSpells then
                    existing.topSpells = existing.topSpells or {}
                    MergeTopSpells(existing.topSpells, source.topSpells)
                end
                existing.spellDetailsAvailable =
                    existing.spellDetailsAvailable == true
                    and source.spellDetailsAvailable == true
            else
                local copy = {
                    sourceGUID = source.sourceGUID,
                    sourceCreatureID = source.sourceCreatureID,
                    name = source.name,
                    classFilename = source.classFilename,
                    specIconID = source.specIconID,
                    totalAmount = source.totalAmount,
                    amountPerSecond = source.amountPerSecond,
                    isLocalPlayer = source.isLocalPlayer,
                    deathRecapID = source.deathRecapID,
                    deathTimeSeconds = source.deathTimeSeconds,
                    sourceDisplayType = source.sourceDisplayType,
                    spellDetailsAvailable =
                        source.spellDetailsAvailable,
                }
                if source.topSpells then
                    copy.topSpells = {}
                    MergeTopSpells(copy.topSpells, source.topSpells)
                end
                byGUID[guid] = copy
            end
        end
    end
    return byGUID
end

local function ApplyCategoryToPlayers(definition, category, players)
    local sourcesByGUID = MergeSourcesByGUID(category.sources)

    for _, player in ipairs(players) do
        local source = sourcesByGUID[player.guid]
        if not category.available then
            player.metrics[definition.key] =
                MakeUnavailableMetric(category.reason or "category_unavailable")
        elseif source then
            player.metrics[definition.key] =
                MakeSourceMetric(definition, source)
            if not player.name and source.name then
                player.name = source.name
            end
            if not player.classFilename and source.classFilename then
                player.classFilename = source.classFilename
            end
            if not player.specIconID and source.specIconID then
                player.specIconID = source.specIconID
            end
        elseif definition.zeroWhenSourceMissing then
            -- Action rows are event-like and omitted for roster members with
            -- no events. Avoidable damage is also an authoritative zero for
            -- missing players once that category has at least one source;
            -- FetchCategory keeps a wholly empty Avoidable category
            -- unavailable because Blizzard labels that state "not active".
            player.metrics[definition.key] = {
                available = true,
                value = 0,
                totalAmount = 0,
                amountPerSecond = 0,
            }
        else
            player.metrics[definition.key] =
                MakeUnavailableMetric("source_missing")
        end

        if definition.includeSpells then
            player.topAvoidableSpells =
                source and source.topSpells or nil
            player.avoidableDrilldownAvailable =
                source and source.spellDetailsAvailable == true or false
        end
    end
end

local function AggregateGroupMetric(definition, category, players)
    if not category.available then
        return MakeUnavailableMetric(category.reason or "category_unavailable")
    end

    local total = 0
    local sourceCount = 0
    for _, player in ipairs(players) do
        local metric = player.metrics[definition.key]
        if metric.available then
            total = total + metric.value
            sourceCount = sourceCount + 1
        end
    end

    if sourceCount == 0 then
        return MakeUnavailableMetric("source_missing")
    end

    return {
        available = true,
        value = total,
        sourceCount = sourceCount,
    }
end

function Adapter:IsDamageMeterAvailable()
    local api = self.dependencies.damageMeter
    if type(api) ~= "table"
        or type(api.IsDamageMeterAvailable) ~= "function"
    then
        return false, "damage_meter_api_unavailable"
    end

    local available = api.IsDamageMeterAvailable()
    local accepted, isNonSecret = GetNonSecret(self, available)
    if not isNonSecret or type(accepted) ~= "boolean" then
        return false, "damage_meter_state_unavailable"
    end
    if not accepted then
        return false, "damage_meter_unavailable"
    end

    return true
end

function Adapter:CollectRunSnapshot(roster, sessionType)
    local safe, unsafeReason = self:IsSafeToRead()
    if not safe then
        return nil, unsafeReason
    end

    local available, unavailableReason = self:IsDamageMeterAvailable()
    if not available then
        return nil, unavailableReason
    end

    local acceptedRoster, rosterIsNonSecret = GetNonSecret(self, roster)
    if not rosterIsNonSecret then
        return nil, "secret_roster"
    end
    if acceptedRoster == nil then
        acceptedRoster = self:CaptureRoster()
    end
    local players, rosterByGUID = SanitizeRoster(self, acceptedRoster)
    if not players or #players == 0 then
        return nil, "roster_unavailable"
    end

    local acceptedSessionType, sessionTypeIsNonSecret =
        GetNonSecret(self, sessionType)
    if not sessionTypeIsNonSecret then
        return nil, "secret_session_type"
    end
    if acceptedSessionType == nil then
        acceptedSessionType = self:GetDefaultSessionType()
    end
    if type(acceptedSessionType) ~= "number" then
        return nil, "session_type_unavailable"
    end

    local snapshot = {
        schemaVersion = 1,
        sessionType = acceptedSessionType,
        complete = true,
        coreComplete = true,
        durationSeconds = nil,
        categories = {},
        group = {},
        players = players,
        unavailableCategories = {},
    }
    local fetchedCategoryCount = 0
    local matchedSourceCount = 0
    local observedSessionTotal = 0

    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        local category, reason = self:FetchCategory(
            acceptedSessionType,
            definition.enumName,
            rosterByGUID
        )
        if category then
            fetchedCategoryCount = fetchedCategoryCount + 1
            matchedSourceCount =
                matchedSourceCount + #category.sources
            observedSessionTotal =
                observedSessionTotal + math.abs(category.totalAmount)
            snapshot.categories[definition.key] = category
            ApplyCategoryToPlayers(definition, category, players)
            snapshot.group[definition.key] =
                AggregateGroupMetric(definition, category, players)

            if not category.available or not category.complete then
                snapshot.complete = false
                if definition.core then
                    snapshot.coreComplete = false
                end
            end
            if category.durationSeconds
                and (
                    not snapshot.durationSeconds
                    or category.durationSeconds > snapshot.durationSeconds
                )
            then
                snapshot.durationSeconds = category.durationSeconds
            end
        else
            snapshot.complete = false
            if definition.core then
                snapshot.coreComplete = false
            end
            snapshot.categories[definition.key] = {
                available = false,
                complete = false,
                key = definition.key,
                enumName = definition.enumName,
                reason = reason,
                sources = {},
            }
            snapshot.group[definition.key] =
                MakeUnavailableMetric(reason)
            snapshot.unavailableCategories[
                #snapshot.unavailableCategories + 1
            ] = definition.key
            for _, player in ipairs(players) do
                player.metrics[definition.key] =
                    MakeUnavailableMetric(reason)
            end
        end
    end

    if fetchedCategoryCount == 0 then
        return nil, "session_unavailable"
    end
    if matchedSourceCount == 0 then
        if observedSessionTotal == 0 then
            return nil, "session_empty"
        end
        return nil, "roster_sources_unavailable"
    end
    if snapshot.durationSeconds == nil then
        snapshot.complete = false
        snapshot.coreComplete = false
    end

    return snapshot
end

local function GetNonSecretTable(adapter, value)
    local accepted, isNonSecret = GetNonSecret(adapter, value)
    if not isNonSecret or type(accepted) ~= "table" then
        return nil
    end
    return accepted
end

local function ReadMetric(adapter, rawMetric)
    local metric = GetNonSecretTable(adapter, rawMetric)
    if not metric then
        return nil, "metric_unavailable"
    end

    local available, availabilityIsNonSecret =
        GetOptionalNonSecretBoolean(adapter, metric.available)
    if not availabilityIsNonSecret or available ~= true then
        local reason =
            GetOptionalNonSecretString(adapter, metric.reason)
        return nil, reason or "metric_unavailable"
    end

    local value, valueIsValid =
        GetNonSecretNumber(adapter, metric.value)
    if not valueIsValid then
        return nil, "value_unavailable"
    end

    local totalAmount =
        GetOptionalNonSecretNumber(adapter, metric.totalAmount)
    return {
        value = value,
        totalAmount = totalAmount,
    }
end

local function IsAuthoritativeZeroReason(reason)
    return reason == "not_active" or reason == "source_missing"
end

local function MakeStartUnavailableMetric(reason)
    return MakeUnavailableMetric(
        "start_" .. (reason or "metric_unavailable")
    )
end

local function SubtractValue(startValue, endValue)
    local tolerance = math.max(0.001, math.abs(startValue) * 0.000001)
    if endValue < startValue - tolerance then
        return nil, true
    end

    local delta = endValue - startValue
    if delta < 0 then
        delta = 0
    end
    return delta, false
end

local function MarkReset(result)
    result.complete = false
    result.coreComplete = false
    result.valid = false
    result.corrupt = true
    result.resetDetected = true
    result.reason = "meter_reset"
end

local function SubtractMetric(adapter, startMetric, endMetric, result,
                              durationSeconds, startIsAuthoritativeZero)
    local ending, endReason = ReadMetric(adapter, endMetric)
    if not ending then
        return MakeUnavailableMetric(endReason)
    end

    local starting, startReason = ReadMetric(adapter, startMetric)
    if not starting
        and not startIsAuthoritativeZero
        and not IsAuthoritativeZeroReason(startReason)
    then
        return MakeStartUnavailableMetric(startReason)
    end
    local startValue = starting and starting.value or 0
    local value, reset = SubtractValue(startValue, ending.value)
    if reset then
        MarkReset(result)
        return MakeUnavailableMetric("meter_reset")
    end

    local totalAmount
    if ending.totalAmount ~= nil then
        local startTotal =
            starting and starting.totalAmount or 0
        if startTotal == nil then
            startTotal = 0
        end
        totalAmount, reset =
            SubtractValue(startTotal, ending.totalAmount)
        if reset then
            MarkReset(result)
            return MakeUnavailableMetric("meter_reset")
        end
    end

    local delta = {
        available = true,
        value = value,
        totalAmount = totalAmount,
    }
    if durationSeconds and durationSeconds > 0 then
        delta.amountPerSecond =
            (totalAmount or value) / durationSeconds
    end
    return delta
end

local function ReadCategoryTotal(adapter, rawCategory)
    local category = GetNonSecretTable(adapter, rawCategory)
    if not category then
        return nil, "category_unavailable"
    end

    local available, availabilityIsNonSecret =
        GetOptionalNonSecretBoolean(adapter, category.available)
    if not availabilityIsNonSecret or available ~= true then
        local reason =
            GetOptionalNonSecretString(adapter, category.reason)
        return nil, reason or "category_unavailable"
    end

    local totalAmount, totalIsValid =
        GetNonSecretNumber(adapter, category.totalAmount)
    if not totalIsValid then
        return nil, "category_total_unavailable"
    end

    local complete =
        GetOptionalNonSecretBoolean(adapter, category.complete)
    return {
        totalAmount = totalAmount,
        complete = complete == true,
    }
end

local function SubtractCategory(adapter, definition, startCategory,
                                endCategory, result,
                                startIsAuthoritativeZero)
    local ending, endReason =
        ReadCategoryTotal(adapter, endCategory)
    if not ending then
        return {
            available = false,
            complete = false,
            key = definition.key,
            enumName = definition.enumName,
            reason = endReason,
            sources = {},
        }
    end

    local starting, startReason =
        ReadCategoryTotal(adapter, startCategory)
    if not starting
        and not startIsAuthoritativeZero
        and not IsAuthoritativeZeroReason(startReason)
    then
        return {
            available = false,
            complete = false,
            key = definition.key,
            enumName = definition.enumName,
            reason = "start_"
                .. (startReason or "category_unavailable"),
            sources = {},
        }
    end
    local startTotal = starting and starting.totalAmount or 0
    local totalAmount, reset =
        SubtractValue(startTotal, ending.totalAmount)
    if reset then
        MarkReset(result)
        return {
            available = false,
            complete = false,
            key = definition.key,
            enumName = definition.enumName,
            reason = "meter_reset",
            sources = {},
        }
    end

    return {
        available = true,
        complete = ending.complete,
        key = definition.key,
        enumName = definition.enumName,
        totalAmount = totalAmount,
        durationSeconds = result.durationSeconds,
        sources = {},
    }
end

local function IndexPlayers(adapter, rawPlayers)
    local players = GetNonSecretTable(adapter, rawPlayers)
    if not players then return nil end

    local byGUID = {}
    for _, rawPlayer in ipairs(players) do
        local player = GetNonSecretTable(adapter, rawPlayer)
        if player then
            local guid, guidIsNonSecret =
                GetOptionalNonSecretString(adapter, player.guid)
            if guidIsNonSecret and guid and guid ~= "" then
                byGUID[guid] = player
            end
        end
    end
    return byGUID
end

local function ReadSpellMap(adapter, rawSpells)
    local spells = GetNonSecretTable(adapter, rawSpells)
    if not spells then return nil end

    local bySpellID = {}
    for _, rawSpell in ipairs(spells) do
        local spell = GetNonSecretTable(adapter, rawSpell)
        if spell then
            local spellID, spellIDIsValid =
                GetNonSecretNumber(adapter, spell.spellID)
            local totalAmount, totalIsValid =
                GetNonSecretNumber(adapter, spell.totalAmount)
            if spellIDIsValid and totalIsValid then
                bySpellID[spellID] = {
                    spell = spell,
                    totalAmount = totalAmount,
                }
            end
        end
    end
    return bySpellID
end

local function CanSubtractStartSpells(
    adapter,
    startPlayer,
    startIsAuthoritativeZero
)
    if startIsAuthoritativeZero then return true end
    if not startPlayer then return false end

    local drilldownAvailable = GetOptionalNonSecretBoolean(
        adapter,
        startPlayer.avoidableDrilldownAvailable
    )
    if drilldownAvailable == true then return true end

    local metrics = GetNonSecretTable(adapter, startPlayer.metrics) or {}
    local metric, reason =
        ReadMetric(adapter, metrics.avoidableDamageTaken)
    return (metric and metric.value == 0)
        or IsAuthoritativeZeroReason(reason)
end

local function SubtractAvoidableSpells(
    adapter,
    startPlayer,
    endPlayer,
    result,
    startIsAuthoritativeZero
)
    local endDrilldownAvailable = GetOptionalNonSecretBoolean(
        adapter,
        endPlayer.avoidableDrilldownAvailable
    )
    if endDrilldownAvailable ~= true
        or not CanSubtractStartSpells(
            adapter,
            startPlayer,
            startIsAuthoritativeZero
        )
    then
        return nil
    end

    local endSpells =
        ReadSpellMap(adapter, endPlayer.topAvoidableSpells)
    if not endSpells then return nil end

    local startSpells = {}
    if startPlayer then
        startSpells =
            ReadSpellMap(adapter, startPlayer.topAvoidableSpells) or {}
    end

    local deltas = {}
    for spellID, ending in pairs(endSpells) do
        local starting = startSpells[spellID]
        local startTotal = starting and starting.totalAmount or 0
        local totalAmount, reset =
            SubtractValue(startTotal, ending.totalAmount)
        if reset then
            MarkReset(result)
        elseif totalAmount > 0 then
            local endSpell = ending.spell
            deltas[#deltas + 1] = {
                spellID = spellID,
                totalAmount = totalAmount,
                creatureName = GetOptionalNonSecretString(
                    adapter,
                    endSpell.creatureName
                ),
                isAvoidable = GetOptionalNonSecretBoolean(
                    adapter,
                    endSpell.isAvoidable
                ),
                isDeadly = GetOptionalNonSecretBoolean(
                    adapter,
                    endSpell.isDeadly
                ),
            }
        end
    end

    table.sort(deltas, function(left, right)
        if left.totalAmount == right.totalAmount then
            return left.spellID < right.spellID
        end
        return left.totalAmount > right.totalAmount
    end)

    local topSpells = {}
    local count = math.min(#deltas, MAX_AVOIDABLE_SPELLS)
    for index = 1, count do
        topSpells[index] = deltas[index]
    end
    return topSpells
end

local function ComputeDpsMetric(adapter, endMetric, damageMetric,
                               durationSeconds)
    local ending = ReadMetric(adapter, endMetric)
    if not ending
        or not damageMetric
        or damageMetric.available ~= true
        or not durationSeconds
        or durationSeconds <= 0
    then
        return MakeUnavailableMetric("value_unavailable")
    end

    local totalAmount =
        damageMetric.totalAmount or damageMetric.value
    local dps = totalAmount / durationSeconds
    return {
        available = true,
        value = dps,
        totalAmount = totalAmount,
        amountPerSecond = dps,
    }
end

function Adapter:SubtractSnapshots(startSnapshot, endSnapshot)
    local acceptedStart =
        GetNonSecretTable(self, startSnapshot)
    if not acceptedStart then
        return nil, "start_snapshot_unavailable"
    end

    local acceptedEnd =
        GetNonSecretTable(self, endSnapshot)
    if not acceptedEnd then
        return nil, "end_snapshot_unavailable"
    end

    local startIsAuthoritativeZero =
        GetOptionalNonSecretBoolean(
            self,
            acceptedStart.authoritativeZero
        ) == true

    local startDuration =
        GetOptionalNonSecretNumber(self, acceptedStart.durationSeconds)
    local endDuration, endDurationIsValid =
        GetOptionalNonSecretNumber(self, acceptedEnd.durationSeconds)
    local durationSeconds
    local durationReset = false
    if endDurationIsValid and endDuration ~= nil then
        durationSeconds, durationReset =
            SubtractValue(startDuration or 0, endDuration)
    end

    local endComplete =
        GetOptionalNonSecretBoolean(self, acceptedEnd.complete)
    local endCoreComplete =
        GetOptionalNonSecretBoolean(self, acceptedEnd.coreComplete)
    local sessionType =
        GetOptionalNonSecretNumber(self, acceptedEnd.sessionType)
    local result = {
        schemaVersion = 1,
        sessionType = sessionType,
        isDelta = true,
        complete = endComplete == true
            and durationSeconds ~= nil
            and durationSeconds > 0,
        coreComplete =
            endCoreComplete == true
            and durationSeconds ~= nil
            and durationSeconds > 0,
        valid = true,
        corrupt = false,
        resetDetected = false,
        durationSeconds = durationSeconds,
        categories = {},
        group = {},
        players = {},
        unavailableCategories = {},
    }
    if durationReset then
        MarkReset(result)
    elseif durationSeconds == nil or durationSeconds <= 0 then
        result.complete = false
        result.coreComplete = false
    end

    local startCategories =
        GetNonSecretTable(self, acceptedStart.categories) or {}
    local endCategories =
        GetNonSecretTable(self, acceptedEnd.categories) or {}
    local startGroup =
        GetNonSecretTable(self, acceptedStart.group) or {}
    local endGroup =
        GetNonSecretTable(self, acceptedEnd.group) or {}

    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        if not definition.valuePerSecond then
            local category = SubtractCategory(
                self,
                definition,
                startCategories[definition.key],
                endCategories[definition.key],
                result,
                startIsAuthoritativeZero
            )
            result.categories[definition.key] = category
            if not category.available then
                result.complete = false
                if definition.core then
                    result.coreComplete = false
                end
                result.unavailableCategories[
                    #result.unavailableCategories + 1
                ] = definition.key
            end

            result.group[definition.key] = SubtractMetric(
                self,
                startGroup[definition.key],
                endGroup[definition.key],
                result,
                durationSeconds,
                startIsAuthoritativeZero
            )
            if not result.group[definition.key].available then
                result.complete = false
            end
        end
    end

    local startPlayers =
        IndexPlayers(self, acceptedStart.players) or {}
    local endPlayers =
        GetNonSecretTable(self, acceptedEnd.players)
    if not endPlayers then
        return nil, "end_players_unavailable"
    end

    for _, rawEndPlayer in ipairs(endPlayers) do
        local endPlayer = GetNonSecretTable(self, rawEndPlayer)
        if endPlayer then
            local guid, guidIsNonSecret =
                GetOptionalNonSecretString(self, endPlayer.guid)
            if guidIsNonSecret and guid and guid ~= "" then
                local startPlayer = startPlayers[guid]
                local startMetrics = startPlayer
                    and GetNonSecretTable(self, startPlayer.metrics)
                    or {}
                local endMetrics =
                    GetNonSecretTable(self, endPlayer.metrics) or {}
                local player = {
                    order = #result.players + 1,
                    unit = CopyValue(self, endPlayer.unit, "string"),
                    guid = guid,
                    name = CopyValue(self, endPlayer.name, "string"),
                    realmName =
                        CopyValue(self, endPlayer.realmName, "string"),
                    className =
                        CopyValue(self, endPlayer.className, "string"),
                    classFilename = CopyValue(
                        self,
                        endPlayer.classFilename,
                        "string"
                    ),
                    specIconID = CopyValue(
                        self,
                        endPlayer.specIconID,
                        "number"
                    ),
                    role = CopyValue(self, endPlayer.role, "string"),
                    metrics = {},
                }

                for _, definition in ipairs(CATEGORY_DEFINITIONS) do
                    if not definition.valuePerSecond then
                        player.metrics[definition.key] =
                            SubtractMetric(
                                self,
                                startMetrics[definition.key],
                                endMetrics[definition.key],
                                result,
                                durationSeconds,
                                startIsAuthoritativeZero
                            )
                    end
                end

                player.topAvoidableSpells =
                    SubtractAvoidableSpells(
                        self,
                        startPlayer,
                        endPlayer,
                        result,
                        startIsAuthoritativeZero
                    )
                player.avoidableDrilldownAvailable =
                    player.topAvoidableSpells ~= nil

                player.metrics.dps = ComputeDpsMetric(
                    self,
                    endMetrics.dps,
                    player.metrics.damageDone,
                    durationSeconds
                )
                result.players[#result.players + 1] = player
            end
        end
    end

    result.group.dps = ComputeDpsMetric(
        self,
        endGroup.dps,
        result.group.damageDone,
        durationSeconds
    )
    local dpsDefinition = ResolveDefinitionByName("Dps")
    local endDpsCategory =
        ReadCategoryTotal(self, endCategories.dps)
    if endDpsCategory and result.group.dps.available then
        result.categories.dps = {
            available = true,
            complete = true,
            key = dpsDefinition.key,
            enumName = dpsDefinition.enumName,
            totalAmount = result.group.dps.value,
            durationSeconds = durationSeconds,
            sources = {},
        }
    else
        result.complete = false
        result.categories.dps = {
            available = false,
            complete = false,
            key = dpsDefinition.key,
            enumName = dpsDefinition.enumName,
            reason = "category_unavailable",
            sources = {},
        }
        result.unavailableCategories[
            #result.unavailableCategories + 1
        ] = dpsDefinition.key
    end

    if #result.players == 0 then
        return nil, "end_players_unavailable"
    end

    return result
end

function M.CreateAdapter(dependencies)
    return setmetatable({
        dependencies = dependencies or {},
    }, Adapter)
end

local defaultAdapter = M.CreateAdapter({
    damageMeter = _G.C_DamageMeter,
    enum = _G.Enum,
    inCombatLockdown = _G.InCombatLockdown,
    isValueNonSecret = F.isValueNonSecret,
    unitGUID = _G.UnitGUID,
    unitName = _G.UnitName,
    unitClass = _G.UnitClass,
    unitRole = _G.UnitGroupRolesAssigned,
})

function M.ResolveCategory(category)
    return defaultAdapter:ResolveCategory(category)
end

function M.GetDefaultSessionType()
    return defaultAdapter:GetDefaultSessionType()
end

function M.IsSafeToRead()
    return defaultAdapter:IsSafeToRead()
end

function M.CaptureRoster()
    return defaultAdapter:CaptureRoster()
end

function M.FetchCategory(sessionType, category)
    return defaultAdapter:FetchCategory(sessionType, category)
end

function M.CollectRunSnapshot(roster, sessionType)
    return defaultAdapter:CollectRunSnapshot(roster, sessionType)
end

function M.SubtractSnapshots(startSnapshot, endSnapshot)
    return defaultAdapter:SubtractSnapshots(startSnapshot, endSnapshot)
end
