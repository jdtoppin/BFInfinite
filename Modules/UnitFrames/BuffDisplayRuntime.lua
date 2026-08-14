---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local CreateFrame = CreateFrame
local ipairs, next, pairs, sort, type =
    ipairs, next, pairs, table.sort, type

local STATE_DESTROYED = "DESTROYED"
local STATE_ERROR = "ERROR"
local STATE_LIMIT_EXCEEDED = "LIMIT_EXCEEDED"
local STATE_RELOAD_REQUIRED = "RELOAD_REQUIRED"
local STATE_UNALLOCATED = "UNALLOCATED"

-- Retail 12.1.0.69299 (wow-ui-source 31c7f7b9) keeps AuraContainer
-- construction add-only. A composite Buffs indicator therefore delegates to
-- one ordinary native runtime per eagerly allocated container seed and never
-- creates a display in response to a live profile edit.

local function IsDisplayPresent(display)
    return type(display) == "table" and display.deleted ~= true
end

local function IsDisplayEnabled(display)
    return IsDisplayPresent(display) and display.enabled == true
end

local function GetDisplays(config)
    return type(config) == "table"
        and type(config.displays) == "table"
        and config.displays
        or nil
end

local function GetReservationPlan(config)
    if type(UF.GetActiveBuffDisplayReservationPlan) == "function" then
        local reserved, overflow, metrics =
            UF.GetActiveBuffDisplayReservationPlan(config)
        return reserved or {}, overflow or {}, metrics or {}
    end

    -- Standalone compatibility for older integrations and focused harnesses.
    -- The production load order always provides the bounded model first.
    local reserved = {}
    for id, display in pairs(GetDisplays(config) or {}) do
        if IsDisplayEnabled(display) then
            reserved[#reserved + 1] = {
                id = display.id or id,
            }
        end
    end
    return reserved, {}, {
        buttonCapacityCosts = {},
        reservationCosts = {},
        displayMetrics = {},
    }
end

local function IndexDisplays(displays)
    local indexed = {}
    for _, display in ipairs(displays or {}) do
        if type(display) == "table"
            and type(display.id) == "string"
            and display.id ~= ""
        then
            indexed[display.id] = true
        end
    end
    return indexed
end

local function AppendSortedMissingIDs(result, seen, source)
    local missing = {}
    for id in pairs(source or {}) do
        if type(id) == "string" and id ~= "" and not seen[id] then
            missing[#missing + 1] = id
        end
    end
    sort(missing)
    for _, id in ipairs(missing) do
        seen[id] = true
        result[#result + 1] = id
    end
end

local function GetOrderedDisplayIDs(config, runtimes)
    local result, seen = {}, {}
    local displays = GetDisplays(config)
    local order = type(config) == "table"
        and type(config.order) == "table"
        and config.order
        or nil

    for _, id in ipairs(order or {}) do
        if type(id) == "string"
            and id ~= ""
            and not seen[id]
            and (
                (displays and displays[id] ~= nil)
                or (runtimes and runtimes[id] ~= nil)
            )
        then
            seen[id] = true
            result[#result + 1] = id
        end
    end

    AppendSortedMissingIDs(result, seen, displays)
    AppendSortedMissingIDs(result, seen, runtimes)
    return result
end

function UF.HasEnabledGroupBuffDisplay(config)
    if type(config) ~= "table" then return false end
    if config.enabled == true then return true end

    for _, display in pairs(GetDisplays(config) or {}) do
        if IsDisplayEnabled(display) then
            return true
        end
    end
    return false
end

local function RequiresStructuralReload(
    manager,
    config,
    reserved,
    metrics
)
    local displays = GetDisplays(config)
    local runtimes = manager._buffDisplayRuntimes

    -- A seed claimed at construction represents one persistent display ID.
    -- Removing that ID cannot safely reclaim or repurpose its add-only native
    -- container during the current session.
    for id in pairs(runtimes) do
        if not IsDisplayPresent(displays and displays[id]) then
            return true
        end
    end

    if not manager._buffDisplayUsesReservationPlan then
        -- Disabled displays may remain configuration-only. Enabling one
        -- without a matching seed is structural and must wait for a reload.
        for id, display in pairs(displays or {}) do
            if IsDisplayEnabled(display) and runtimes[id] == nil then
                return true
            end
        end
        return false
    end

    -- Only displays admitted by the bounded plan need a live shell. Overflow
    -- remains inert until the user frees capacity. A reload is useful only
    -- when an admitted display has no shell or asks for more native
    -- construction capacity than that shell was initially allocated for.
    local costs = type(metrics) == "table"
        and (
            type(metrics.buttonCapacityCosts) == "table"
                and metrics.buttonCapacityCosts
            or type(metrics.reservationCosts) == "table"
                and metrics.reservationCosts
        )
        or {}
    local allocatedCosts = manager._buffDisplayAllocationCosts or {}
    for _, display in ipairs(reserved or {}) do
        local id = display.id
        if runtimes[id] == nil then
            return true
        end
        local allocated = allocatedCosts[id]
        local requested = costs[id]
        if type(allocated) == "number"
            and type(requested) == "number"
            and requested > allocated
        then
            return true
        end
    end
    return false
end

local function SetChildEnabled(runtime, enabled)
    runtime.enabled = enabled == true
    if not runtime.enabled then
        runtime:Disable()
    end
end

local function QuiesceAll(manager)
    local base = manager._buffDisplayBase
    SetChildEnabled(base, false)
    for _, runtime in pairs(manager._buffDisplayRuntimes) do
        SetChildEnabled(runtime, false)
    end
end

local function ForEachRuntime(manager, callback)
    callback(manager._buffDisplayBase, nil)
    for id, runtime in pairs(manager._buffDisplayRuntimes) do
        callback(runtime, id)
    end
end

local function BuffDisplays_LoadConfig(self, config)
    if self._buffDisplaysDestroyed then return end
    assert(type(config) == "table", "buff display config must be a table")

    self._buffDisplaySourceConfig = AF.Copy(config)
    local reserved, overflow, metrics = GetReservationPlan(config)
    local reservedIDs = IndexDisplays(reserved)
    self._buffDisplayReservedIDs = reservedIDs
    self._buffDisplayOverflowIDs = IndexDisplays(overflow)
    self._buffDisplayReservationMetrics = AF.Copy(metrics)
    local wasStructuralReload = self._buffDisplayStructuralReload == true
    self._buffDisplayStructuralReload =
        RequiresStructuralReload(
            self,
            config,
            reserved,
            metrics
        ) or nil
    self._buffDisplayActive = nil

    if self._buffDisplayStructuralReload then
        self.enabled = false
        QuiesceAll(self)
        if not wasStructuralReload then
            -- Options preflight handles direct edits. This event also covers
            -- profile and preset changes, which otherwise quiesce add-only
            -- native shells with no explanation until the next manual reload.
            AF.Fire("BFI_NativeAuraReloadRequired")
        end
        return
    end

    local rootEnabled = self.root.enabled ~= false
    local base = self._buffDisplayBase
    base.enabled = rootEnabled and config.enabled == true
    base:LoadConfig(config)

    local displays = GetDisplays(config)
    for id, runtime in pairs(self._buffDisplayRuntimes) do
        local display = displays and displays[id]
        local admitted = not self._buffDisplayUsesReservationPlan
            or reservedIDs[id] == true
        runtime.enabled = rootEnabled
            and admitted
            and IsDisplayEnabled(display)
        if admitted and display then
            runtime:LoadConfig(display)
        else
            runtime:Disable()
        end
    end

    self.enabled = rootEnabled
        and (
            config.enabled == true
            or next(reservedIDs) ~= nil
        )
        or false
end

local function BuffDisplays_Enable(self)
    if self._buffDisplaysDestroyed
        or self._buffDisplayStructuralReload
    then
        return
    end

    self._buffDisplayActive = true
    ForEachRuntime(self, function(runtime)
        if runtime.enabled then
            runtime:Enable()
        else
            runtime:Disable()
        end
    end)
end

local function BuffDisplays_Disable(self)
    if self._buffDisplaysDestroyed then return end
    self._buffDisplayActive = nil
    ForEachRuntime(self, function(runtime)
        runtime:Disable()
    end)
end

local function BuffDisplays_Update(self, force)
    if self._buffDisplaysDestroyed
        or self._buffDisplayStructuralReload
        or not self._buffDisplayActive
    then
        return
    end

    ForEachRuntime(self, function(runtime)
        if runtime.enabled then
            runtime:Update(force)
        end
    end)
end

local function BuffDisplays_SetUnit(self, unit)
    if self._buffDisplaysDestroyed
        or self._buffDisplayStructuralReload
        or not self._buffDisplayActive
    then
        return
    end

    ForEachRuntime(self, function(runtime)
        if runtime.enabled then
            runtime:SetUnit(unit)
        end
    end)
end

local function BuffDisplays_RefreshVisibility(self)
    if self._buffDisplaysDestroyed
        or self._buffDisplayStructuralReload
    then
        return
    end

    ForEachRuntime(self, function(runtime)
        if runtime.enabled then
            runtime:RefreshVisibility()
        end
    end)
end

local function BuffDisplays_EnableConfigMode(self)
    if self._buffDisplaysDestroyed
        or self._buffDisplayStructuralReload
    then
        return
    end

    self._buffDisplaysConfigMode = true
    ForEachRuntime(self, function(runtime)
        if runtime._config then
            runtime:EnableConfigMode()
        end
    end)
end

local function BuffDisplays_DisableConfigMode(self)
    if self._buffDisplaysDestroyed then return end
    self._buffDisplaysConfigMode = nil
    ForEachRuntime(self, function(runtime)
        runtime:DisableConfigMode()
    end)
end

local function BuffDisplays_RequiresReloadForConfig(self, config)
    if self._buffDisplaysDestroyed or type(config) ~= "table" then
        return false
    end
    local reserved, _, metrics = GetReservationPlan(config)
    if RequiresStructuralReload(self, config, reserved, metrics) then
        return true
    end

    if self._buffDisplayBase:RequiresReloadForConfig(config) then
        return true
    end

    local displays = GetDisplays(config)
    local reservedIDs = IndexDisplays(reserved)
    for id, runtime in pairs(self._buffDisplayRuntimes) do
        local display = displays and displays[id]
        if reservedIDs[id]
            and display
            and runtime:RequiresReloadForConfig(display)
        then
            return true
        end
    end
    return false
end

local function NewUnallocatedState(display, admitted, preallocated)
    local enabled = IsDisplayEnabled(display)
    return {
        state = enabled
            and (admitted and STATE_RELOAD_REQUIRED or STATE_LIMIT_EXCEEDED)
            or STATE_UNALLOCATED,
        active = false,
        built = false,
        pending = false,
        configMode = false,
        reloadRequired = enabled and admitted or false,
        preallocated = preallocated == true,
        limitExceeded = enabled and not admitted or false,
    }
end

local function BuffDisplays_GetState(self)
    if self._buffDisplaysDestroyed then
        return {
            state = STATE_DESTROYED,
            active = false,
            built = false,
            pending = false,
            configMode = false,
            reloadRequired = false,
            base = {state = STATE_DESTROYED},
            displays = {},
            order = {},
            reservationMetrics = {},
        }
    end

    local baseState = self._buffDisplayBase:GetNativeAuraState()
    local result = AF.Copy(baseState)
    local config = self._buffDisplaySourceConfig or {}
    local displays = GetDisplays(config)
    local states = {}
    local order = GetOrderedDisplayIDs(
        config,
        self._buffDisplayRuntimes
    )
    local active = baseState.active == true
    local built = baseState.built == true
    local pending = baseState.pending == true
    local reloadRequired = baseState.reloadRequired == true
    local hasError = baseState.state == STATE_ERROR
    local hasLimitExceeded = false
    local reservedIDs = self._buffDisplayReservedIDs or {}
    local overflowIDs = self._buffDisplayOverflowIDs or {}
    local reservationMetrics =
        self._buffDisplayReservationMetrics or {}
    local displayReservationMetrics =
        type(reservationMetrics.displayMetrics) == "table"
        and reservationMetrics.displayMetrics
        or {}

    for _, id in ipairs(order) do
        local runtime = self._buffDisplayRuntimes[id]
        local state
        if runtime and not overflowIDs[id] then
            state = runtime:GetNativeAuraState()
            state.preallocated = true
        else
            state = NewUnallocatedState(
                displays and displays[id],
                reservedIDs[id] == true,
                runtime ~= nil
            )
        end
        local reservation = displayReservationMetrics[id]
        if type(reservation) == "table" then
            state.reservation = AF.Copy(reservation)
            state.buttonCapacityCost =
                reservation.buttonCapacityCost
            state.buttonCapacityLimit =
                reservation.buttonCapacityLimit
            state.reservationCost = reservation.reservationCost
            state.capacityExceeded =
                reservation.capacityExceeded == true
            state.buttonCapacityExceeded =
                reservation.buttonCapacityExceeded == true
            state.sortMode = reservation.sortMode
            state.effectiveSortMode =
                reservation.effectiveSortMode
            state.priorityPreferenceLatent =
                reservation.priorityPreferenceLatent == true
            state.prioritySpellCount =
                reservation.prioritySpellCount
            state.maxDisplayed = reservation.maxDisplayed
            state.reservationErrorCode = reservation.errorCode
        end
        states[id] = state
        active = state.active == true or active
        built = state.built == true or built
        pending = state.pending == true or pending
        reloadRequired = state.reloadRequired == true or reloadRequired
        hasError = state.state == STATE_ERROR or hasError
        hasLimitExceeded = state.limitExceeded == true
            or hasLimitExceeded
    end

    if self._buffDisplayStructuralReload then
        result.state = STATE_RELOAD_REQUIRED
        reloadRequired = true
        active = false
    elseif hasError then
        result.state = STATE_ERROR
    elseif reloadRequired then
        result.state = STATE_RELOAD_REQUIRED
    elseif hasLimitExceeded then
        result.state = STATE_LIMIT_EXCEEDED
    end

    result.active = active
    result.built = built
    result.pending = pending
    result.configMode = self._buffDisplaysConfigMode == true
    result.reloadRequired = reloadRequired
    result.limitExceeded = hasLimitExceeded
    result.nativeBackendAvailable = true
    result.base = baseState
    result.displays = states
    result.order = order
    result.reservationMetrics = AF.Copy(reservationMetrics)
    return result
end

local function BuffDisplays_Destroy(self)
    if self._buffDisplaysDestroyed then return end

    self._buffDisplaysDestroyed = true
    self._buffDisplayActive = nil
    self._buffDisplaysConfigMode = nil
    self.enabled = false
    ForEachRuntime(self, function(runtime)
        runtime:Destroy()
    end)
    self:Hide()
end

local function CreateDisplayRuntime(
    parent,
    name,
    auraFilter,
    seedContainer,
    options
)
    local runtime, errorCode = UF.CreateNativeGroupAuraIndicator(
        parent,
        name,
        auraFilter,
        seedContainer,
        options
    )
    assert(runtime, errorCode or "native buff display runtime is unavailable")
    return runtime
end

function UF.CreateGroupBuffDisplays(
    parent,
    name,
    auraFilter,
    containerKey
)
    auraFilter = auraFilter or "HELPFUL"
    containerKey = containerKey or "buffs"

    if not UF.HasNativeAuraContainerBackend() then
        return UF.CreateGroupNativeAuras(
            parent,
            name,
            auraFilter,
            containerKey
        )
    end

    local containers = parent._nativeAuraContainers
    local baseSeed = containers and containers[containerKey]
    assert(baseSeed, "native group Buffs container seed is missing")

    local base = CreateDisplayRuntime(
        parent,
        name .. "_Base",
        auraFilter,
        baseSeed
    )
    local manager = CreateFrame("Frame", name, parent)
    manager:SetAllPoints(base)
    manager.root = parent
    manager.auraFilter = auraFilter
    manager._buffDisplayBase = base
    manager._buffDisplayRuntimes = {}
    manager._buffDisplayUsesReservationPlan =
        type(UF.GetActiveBuffDisplayReservationPlan) == "function"
    manager._buffDisplayAllocationCosts = AF.Copy(
        parent._nativeAuraBuffDisplayReservationCosts or {}
    )

    local displaySeeds = containers.buffDisplays or {}
    local ids = {}
    for id in pairs(displaySeeds) do
        assert(type(id) == "string" and id ~= "",
            "native Buff display IDs must be non-empty strings")
        ids[#ids + 1] = id
    end
    sort(ids)

    for index, id in ipairs(ids) do
        manager._buffDisplayRuntimes[id] = CreateDisplayRuntime(
            parent,
            name .. "_Display" .. index,
            auraFilter,
            displaySeeds[id],
            {
                -- Buff Displays own their explicit filter/spell-list policy.
                -- Suppress suite-global spell-color bucket expansion so one
                -- display cannot multiply the bounded native group budget.
                includeSpellColors = false,
                -- Separate Own builds relation variants beyond the policy
                -- group count used by the reservation plan. Buff Displays
                -- deliberately compile one unpartitioned presentation.
                includePartition = false,
            }
        )
    end

    manager.LoadConfig = BuffDisplays_LoadConfig
    manager.Enable = BuffDisplays_Enable
    manager.Disable = BuffDisplays_Disable
    manager.Update = BuffDisplays_Update
    manager.SetUnit = BuffDisplays_SetUnit
    manager.RefreshVisibility = BuffDisplays_RefreshVisibility
    manager.EnableConfigMode = BuffDisplays_EnableConfigMode
    manager.DisableConfigMode = BuffDisplays_DisableConfigMode
    manager.RequiresReloadForConfig =
        BuffDisplays_RequiresReloadForConfig
    manager.GetNativeAuraState = BuffDisplays_GetState
    manager.Destroy = BuffDisplays_Destroy
    return manager
end
