---@type BFI
local BFI = select(2, ...)
local NP = BFI.modules.Nameplates
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local HOSTILE_PLATE_TYPES = {
    hostile_npc = true,
    hostile_player = true,
}

local function ConfigsEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[left] then
        return seen[left] == right
    end
    seen[left] = right

    for key, value in pairs(left) do
        if not ConfigsEqual(value, right[key], seen) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function GetEffectivePosition(config, plateConfig)
    local position = config.position
    local nameText = plateConfig and plateConfig.nameText
    local namePosition = nameText and nameText.position
    if not nameText
        or nameText.placement ~= "inside"
        or config.anchorTo ~= "healthBar"
        or nameText.anchorTo ~= "healthBar"
        or type(position) ~= "table"
        or type(position[1]) ~= "string"
        or type(position[2]) ~= "string"
        or type(namePosition) ~= "table"
        or type(namePosition[1]) ~= "string"
        or type(namePosition[2]) ~= "string"
        or not position[1]:find("^BOTTOM")
        or not position[2]:find("^TOP")
        or not namePosition[1]:find("^BOTTOM")
        or not namePosition[2]:find("^TOP")
    then
        return position
    end

    local font = nameText.font or {}
    local reservedHeight = math.max(
        0,
        (tonumber(namePosition[4]) or 0)
            + (tonumber(font[2]) or 12)
    )

    return {
        position[1],
        position[2],
        position[3],
        (tonumber(position[4]) or 0) - reservedHeight,
    }
end

local function NormalizeDebuffConfig(config, plateConfig, enabled)
    -- This leaf restores the supported enemy row only. Friendly dispellable
    -- debuffs require a different native policy and remain fail-closed until
    -- that reaction direction is migrated independently.
    local nativeConfig = {
        enabled = config.enabled == true and enabled == true,
        position = AF.Copy(GetEffectivePosition(config, plateConfig)),
        anchorTo = config.anchorTo,
        orientation = config.orientation,
        cooldownStyle = config.cooldownStyle,
        width = config.width,
        height = config.height,
        spacingX = config.spacingX,
        spacingY = config.spacingY,
        numPerLine = config.numPerLine,
        numTotal = config.numTotal,
        frameLevel = config.frameLevel,
        durationText = AF.Copy(config.durationText),
        stackText = AF.Copy(config.stackText),
        auraTypeColor = AF.Copy(config.auraTypeColor),
        mode = "blacklist",
        blacklist = {},
        filters = {
            all = false,
            player = true,
            notPlayer = false,
            raidInCombat = false,
            raidPlayerDispellable = false,
            bigDefensive = false,
            externalDefensive = false,
            important = false,
            anyDispellable = false,
        },
        tooltip = {enabled = false},
    }
    -- The saved crowd-control blocker was never consumed by the legacy live
    -- Debuffs constructor. Preserve that row here; a dedicated CC type remains
    -- a separate migration instead of silently changing the existing set.
    return nativeConfig
end

local function ApplyNameplatePlacement(holder, placement, root)
    AF.SetFrameLevel(holder, placement.frameLevel, root)
    NP.LoadIndicatorPosition(
        holder,
        placement.position,
        placement.anchorTo
    )
end

local function GetAppliedHostileConfig(config, plateConfig)
    if type(NP.GetAppliedHostileNameplateConfig) == "function" then
        local applied = NP.GetAppliedHostileNameplateConfig()
        if applied and applied.debuffs then
            return applied.debuffs, applied
        end
    end
    return config, plateConfig
end

local function WrapNameplateConfig(frame)
    local LoadNativeConfig = frame.LoadConfig
    local NativeRequiresReload = frame.RequiresReloadForConfig

    local function ApplyHostileConfig(self, config, plateConfig)
        local nativeConfig =
            NormalizeDebuffConfig(config, plateConfig, true)
        self._nameplatePlateConfig = plateConfig
        if ConfigsEqual(self._nameplateAppliedConfig, nativeConfig) then
            return false
        end
        self._nameplateAppliedConfig = AF.Copy(nativeConfig)
        LoadNativeConfig(self, nativeConfig)
        return true
    end

    frame.ApplyNameplateHostileConfig = ApplyHostileConfig
    frame.RequiresNameplateHostileReload = function(
        self,
        config,
        plateConfig
    )
        return NativeRequiresReload(
            self,
            NormalizeDebuffConfig(config, plateConfig, true)
        )
    end

    frame.LoadConfig = function(self, config, plateConfig)
        if HOSTILE_PLATE_TYPES[self.root.configKey] ~= true then
            -- A pooled native row can pass through an unsupported friendly
            -- assignment and return to an enemy during the same combat. Do
            -- not dirty or replace its last complete enemy snapshot here;
            -- Common will disable and curtain the indicator after this call.
            self.enabled = false
            return
        end

        config, plateConfig =
            GetAppliedHostileConfig(config, plateConfig)
        ApplyHostileConfig(self, config, plateConfig)
    end

    frame.RequiresReloadForConfig = function(
        self,
        config,
        plateConfig
    )
        if HOSTILE_PLATE_TYPES[self.root.configKey] ~= true then
            return false
        end
        config, plateConfig =
            GetAppliedHostileConfig(config, plateConfig)
        plateConfig = plateConfig or self._nameplatePlateConfig
        return self:RequiresNameplateHostileReload(
            config,
            plateConfig
        )
    end
end

function NP.CreateDebuffs(parent, name)
    local frame, errorCode = UF.CreateNativeAuraIndicator(
        parent,
        name,
        "HARMFUL",
        false,
        {
            includeSpellColors = false,
            allowCombatInitialBuild = true,
            keepNativeEnabledWhenHidden = true,
            immediateConfigCommit = true,
            applyPlacement = ApplyNameplatePlacement,
            controller = {
                liveUnitChanges = true,
                allowCombatInitialBuild = true,
                alphaOnlyVisibility = true,
            },
        }
    )
    assert(frame, errorCode or "native nameplate aura backend unavailable")

    frame._nameplateAuraType = "enemyDebuffs"
    WrapNameplateConfig(frame)
    return frame
end

function NP.PrepareNameplateAuraConfigUpdate()
    local plateConfig = NP.config and NP.config.hostile_npc
    local config = plateConfig and plateConfig.debuffs
    if not config then return false end

    local prepared = {}
    local reloadRequired = false
    for _, frame in next, NP.created do
        local debuffs = frame.indicators
            and frame.indicators.debuffs
        local state = debuffs
            and debuffs.GetNativeAuraState
            and debuffs:GetNativeAuraState()
        if debuffs
            and debuffs._nameplateAppliedConfig
            and state
            and state.built == true
        then
            prepared[#prepared + 1] = debuffs
            reloadRequired =
                debuffs:RequiresNameplateHostileReload(
                    config,
                    plateConfig
                ) == true
                or reloadRequired
        end
    end

    for _, debuffs in ipairs(prepared) do
        debuffs:ApplyNameplateHostileConfig(config, plateConfig)
    end
    return reloadRequired
end
