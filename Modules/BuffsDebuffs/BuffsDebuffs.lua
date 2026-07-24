---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local GetUnitAuraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local InCombatLockdown = InCombatLockdown
local mainHandSlot = GetInventorySlotInfo("MainHandSlot")
local secondaryHandSlot = GetInventorySlotInfo("SecondaryHandSlot")

local REQUIRED_AF_VERSION = 21

-- Retail 12.0.7 loads the implementation and template together from
-- Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders. Retail 12.1 only
-- loads the replacement SecureAuraHeader files for Classic clients.
function BD.HasSecureAuraHeaderBackend()
    return AF.isRetail
        and (tonumber(AF.versionNum) or 0) >= REQUIRED_AF_VERSION
        and type(_G.SecureAuraHeader_Update) == "function"
        and type(_G.SecureAuraHeader_UpdateEventRegistrations) == "function"
        and type(GetUnitAuraInstanceIDs) == "function"
        and type(GetWeaponEnchantInfo) == "function"
        and type(BD.CanSuppressNativePublicAuras) == "function"
        and type(BD.SetNativePublicAurasSuppressed) == "function"
end

---------------------------------------------------------------------
-- header
---------------------------------------------------------------------
local function CreateHeader(name, moverName, filter)
    local header = CreateFrame("Frame", name, AF.UIParent, "SecureAuraHeaderTemplate")
    header:SetAttribute("template", "BFIAuraButtonTemplate")
    if filter == "HELPFUL" then
        header:SetAttribute("includeWeapons", 1)
        header:SetAttribute("weaponTemplate", "BFITemporaryEnchantButtonTemplate")
    end
    header:SetAttribute("filter", filter)
    header.filter = filter

    header:SetAttribute("unit", "player")
    RegisterAttributeDriver(header, "unit", "[vehicleui] vehicle;player")

    header:SetAttribute("initialConfigFunction", [[
        local header = self:GetParent()
        self:SetWidth(header:GetAttribute("buttonWidth") or 20)
        self:SetHeight(header:GetAttribute("buttonHeight") or 20)
        self:CallMethod("LoadConfig")
    ]])

    AF.CreateMover(header, "BFI: " .. L["UI Widgets"], moverName)

    return header
end

---------------------------------------------------------------------
-- create header
---------------------------------------------------------------------
local buffFrame, debuffFrame

local function CreateBuffHeader()
    buffFrame = CreateHeader("BFIBuffFrame", _G.HUD_EDIT_MODE_BUFF_FRAME_LABEL, "HELPFUL")
    return buffFrame
end

local function CreateDebuffHeader()
    debuffFrame = CreateHeader("BFIDebuffFrame", _G.HUD_EDIT_MODE_DEBUFF_FRAME_LABEL, "HARMFUL")
    return debuffFrame
end

---------------------------------------------------------------------
-- create aura button
---------------------------------------------------------------------
local function UpdateAura(button, index)
    if not index then
        button:ClearAura()
        return
    end

    local unit = button.header:GetAttribute("unit")
    -- SecureAuraHeader sorts a private list but assigns each child its original
    -- unsorted aura index. Resolve that index against the matching C-side list;
    -- applying the configured sort a second time would select a different aura.
    local auraInstanceIDs = GetUnitAuraInstanceIDs(
        unit,
        button.filter,
        index,
        Enum.UnitAuraSortRule.Unsorted,
        Enum.UnitAuraSortDirection.Normal
    )
    local auraInstanceID = auraInstanceIDs[index]
    if auraInstanceID then
        button:SetAura(unit, auraInstanceID)
    else
        button:ClearAura()
    end
end

-- local function Button_OnUpdate(button, elapsed)

-- end

local function Button_OnAttributeChanged(button, name, value)
    -- print(name, value)
    if name == "index" then
        UpdateAura(button, value)
    end
end

local function Button_LoadConfig(button)
    local config = button.header.config
    if not config then return end

    button:SetupStackText(config.stack)
    button:SetupDurationText(config.duration)
end

local function Button_UpdatePixels(button)
    AF.ReBorder(button)
    AF.RePoint(button.icon)
end

function BD.InitAuraButton(button)
    button.header = button:GetParent()
    button.filter = button.header.filter

    AF.InitAura(button, nil, true)
    AF.SetOnePixelInside(button.icon, button)
    button:SetFallbackIcon(button.filter == "HELPFUL" and 135953 or 136071)
    button:EnableDispelColor(button.filter == "HARMFUL")

    button.LoadConfig = Button_LoadConfig
    AF.AddToPixelUpdater_Auto(button, Button_UpdatePixels)
    AF.ApplyDefaultBackdropColors(button)

    button:EnableTooltip({
        enabled = true,
        anchorTo = "self_adaptive",
    })

    -- event
    button:SetScript("OnAttributeChanged", Button_OnAttributeChanged)
    -- button:SetScript("OnUpdate", Button_OnUpdate)
    button:SetScript("OnSizeChanged", AF.ReCalcTexCoordForAura)
end

local function GetTemporaryEnchantInfo(inventorySlot)
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges,
        _, hasSecondaryHandEnchant, secondaryHandExpiration, secondaryHandCharges = GetWeaponEnchantInfo()

    if inventorySlot == mainHandSlot then
        return hasMainHandEnchant, mainHandExpiration, mainHandCharges
    elseif inventorySlot == secondaryHandSlot then
        return hasSecondaryHandEnchant, secondaryHandExpiration, secondaryHandCharges
    end
end

local function RefreshTemporaryEnchant(button)
    local inventorySlot = button:GetAttribute("target-slot")
    local hasEnchant, remainingTimeMs, applications = GetTemporaryEnchantInfo(inventorySlot)
    if hasEnchant and remainingTimeMs then
        button:SetTemporaryEnchant("player", inventorySlot, remainingTimeMs, applications or 0)
        if GameTooltip:IsOwned(button) then
            button:ShowTooltip()
        end
    else
        if GameTooltip:IsOwned(button) then
            button:HideTooltip()
        end
        button:ClearAura()
    end
end

local function TemporaryEnchant_OnAttributeChanged(button, name)
    if name == "target-slot" then
        RefreshTemporaryEnchant(button)
    end
end

function BD.InitTemporaryEnchantButton(button)
    button.header = button:GetParent()

    AF.InitAura(button, nil, true)
    AF.SetOnePixelInside(button.icon, button)
    button:SetFallbackIcon(134400)

    button.LoadConfig = Button_LoadConfig
    AF.AddToPixelUpdater_Auto(button, Button_UpdatePixels)
    AF.ApplyDefaultBackdropColors(button)

    button:EnableTooltip({
        enabled = true,
        anchorTo = "self_adaptive",
    })

    button:SetScript("OnAttributeChanged", TemporaryEnchant_OnAttributeChanged)
    button:SetScript("OnEvent", RefreshTemporaryEnchant)
    button:SetScript("OnSizeChanged", AF.ReCalcTexCoordForAura)
    button:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    button:RegisterEvent("WEAPON_SLOT_CHANGED")
end

---------------------------------------------------------------------
-- setup header
---------------------------------------------------------------------
--[[
filter = [STRING] -- a pipe-separated list of aura filter options ("RAID" will be ignored)
separateOwn = [NUMBER] -- indicate whether buffs you cast yourself should be separated before (1) or after (-1) others. If 0 or nil, no separation is done.
sortMethod = ["INDEX", "NAME", "TIME"] -- defines how the group is sorted (Default: "INDEX")
sortDirection = ["+", "-"] -- defines the sort order (Default: "+")
groupBy = [nil, auraFilter] -- if present, a series of comma-separated filters, appended to the base filter to separate auras into groups within a single stream
includeWeapons = [nil, NUMBER] -- The aura sub-stream before which to include temporary weapon enchants. If nil or 0, they are ignored.
consolidateTo = [nil, NUMBER] -- The aura sub-stream before which to place a proxy for the consolidated header. If nil or 0, consolidation is ignored.
consolidateDuration = [nil, NUMBER] -- the minimum total duration an aura should have to be considered for consolidation (Default: 30)
consolidateThreshold = [nil, NUMBER] -- buffs with less remaining duration than this many seconds should not be consolidated (Default: 10)
consolidateFraction = [nil, NUMBER] -- The fraction of remaining duration a buff should still have to be eligible for consolidation (Default: .10)

template = [STRING] -- the XML template to use for the unit buttons. If the created widgets should be something other than Buttons, append the Widget name after a comma.
weaponTemplate = [STRING] -- the XML template to use for temporary enchant buttons. Can be nil if you preset the tempEnchant1 and tempEnchant2 attributes, or if you don't include temporary enchants.
consolidateProxy = [STRING|Frame] -- Either the button which represents consolidated buffs, or the name of the template used to construct one.
consolidateHeader = [STRING|Frame] -- Either the aura header which contains consolidated buffs, or the name of the template used to construct one.

point = [STRING] -- a valid XML anchoring point (Default: "TOPRIGHT")
minWidth = [nil, NUMBER] -- the minimum width of the container frame
minHeight = [nil, NUMBER] -- the minimum height of the container frame
xOffset = [NUMBER] -- the x-Offset to use when anchoring the unit buttons. This should typically be set to at least the width of your buff template.
yOffset = [NUMBER] -- the y-Offset to use when anchoring the unit buttons. This should typically be set to at least the height of your buff template.
wrapAfter = [NUMBER] -- begin a new row or column after this many auras. If 0 or nil, never wrap or limit the first row
wrapXOffset = [NUMBER] -- the x-offset from one row or column to the next
wrapYOffset = [NUMBER] -- the y-offset from one row or column to the next
maxWraps = [NUMBER] -- limit the number of rows or columns. If 0 or nil, the number of rows or columns will not be limited.
--]]

local function GetAttributes(config)
    local point, x, y, wrapX, wrapY, minWidth, minHeight, _
    point, _, _, x, y, wrapX, wrapY = AF.GetAnchorPoints_Complex(config.orientation, config.spacingX, config.spacingY)

    if config.orientation:find("^[lr]") then
        minWidth = config.width * config.wrapAfter + config.spacingX * (config.wrapAfter - 1)
        minHeight = config.height * config.maxWraps + config.spacingY * (config.maxWraps - 1)
    else
        minWidth = config.width * config.maxWraps + config.spacingX * (config.maxWraps - 1)
        minHeight = config.height * config.wrapAfter + config.spacingY * (config.wrapAfter - 1)
    end

    if config.orientation == "bottom_to_top_then_left" then
        y = y + config.height
        wrapX = wrapX - config.width
    elseif config.orientation == "bottom_to_top_then_right" then
        y = y + config.height
        wrapX = wrapX + config.width
    elseif config.orientation == "top_to_bottom_then_left" then
        y = y - config.height
        wrapX = wrapX - config.width
    elseif config.orientation == "top_to_bottom_then_right" then
        y = y - config.height
        wrapX = wrapX + config.width
    elseif config.orientation == "left_to_right_then_down" then
        x = x + config.width
        wrapY = wrapY - config.height
    elseif config.orientation == "left_to_right_then_up" then
        x = x + config.width
        wrapY = wrapY + config.height
    elseif config.orientation == "right_to_left_then_down" then
        x = x - config.width
        wrapY = wrapY - config.height
    elseif config.orientation == "right_to_left_then_up" then
        x = x - config.width
        wrapY = wrapY + config.height
    end

    return point, x, y, wrapX, wrapY, minWidth, minHeight
end

local function SetupHeader(header, config)
    -- Attribute changes update a visible secure header immediately. Configure
    -- it while hidden so children are rebuilt once, from a complete state.
    header:Hide()
    header.config = config

    header:SetAttribute("separateOwn", config.separateOwn)
    header:SetAttribute("sortMethod", config.sortMethod)
    header:SetAttribute("sortDirection", config.sortDirection)
    header:SetAttribute("maxWraps", config.maxWraps)
    header:SetAttribute("wrapAfter", config.wrapAfter)
    -- Blizzard applies maxAuraCount before its Lua TIME/NAME sort. Bound the
    -- INDEX candidate set only; capping other modes would change their result.
    header:SetAttribute(
        "maxAuraCount",
        config.sortMethod == "INDEX" and config.wrapAfter * config.maxWraps or nil
    )

    local point, x, y, wrapX, wrapY, minWidth, minHeight = GetAttributes(config)
    header:SetAttribute("point", point)
    header:SetAttribute("xOffset", x)
    header:SetAttribute("yOffset", y)
    header:SetAttribute("wrapXOffset", wrapX)
    header:SetAttribute("wrapYOffset", wrapY)
    header:SetAttribute("minWidth", minWidth)
    header:SetAttribute("minHeight", minHeight)

    -- size
    header:SetAttribute("buttonWidth", config.width)
    header:SetAttribute("buttonHeight", config.height)
    for _, b in pairs({header:GetChildren()}) do
        b:SetSize(config.width, config.height)
        b:LoadConfig()
    end

    header:Show()
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local updatePending
local pendingWhich
local UpdateBuffsDebuffs

local function RetryBuffsDebuffsUpdate()
    BD:UnregisterEvent("PLAYER_REGEN_ENABLED", RetryBuffsDebuffsUpdate)

    local which = pendingWhich
    updatePending = nil
    pendingWhich = nil
    UpdateBuffsDebuffs(nil, "buffsDebuffs", which)
end

local function DisableHeader(which, header)
    if not BD.SetNativePublicAurasSuppressed(which, false) then return end
    if header then
        header.enabled = false
        header:Hide()
    end
end

local function EnableHeader(which, header, createHeader, config)
    -- Restore native visuals before protected reconfiguration. If a later
    -- operation fails, Blizzard remains the visible fallback.
    if not BD.SetNativePublicAurasSuppressed(which, false) then return header end

    if not BD.CanSuppressNativePublicAuras(which) then
        if header then
            header.enabled = false
            header:Hide()
        end
        return header
    end

    if not header then
        header = createHeader()
    end
    header.enabled = true
    SetupHeader(header, config)
    AF.UpdateMoverSave(header, config.position)
    AF.LoadPosition(header, config.position)

    if not BD.SetNativePublicAurasSuppressed(which, true) then
        header.enabled = false
        header:Hide()
    end
    return header
end

UpdateBuffsDebuffs = function(_, module, which)
    if module and module ~= "buffsDebuffs" then return end
    if which and which ~= "buffs" and which ~= "debuffs" then return end
    if not BD.HasSecureAuraHeaderBackend() then return end

    if InCombatLockdown() then
        if not updatePending then
            pendingWhich = which
        elseif pendingWhich ~= which then
            pendingWhich = nil
        end
        updatePending = true
        BD:RegisterEvent("PLAYER_REGEN_ENABLED", RetryBuffsDebuffsUpdate)
        return
    end

    -- buffs
    local config = BD.config.buffs
    if not which or which == "buffs" then
        if config.enabled then
            buffFrame = EnableHeader("buffs", buffFrame, CreateBuffHeader, config)
        else
            DisableHeader("buffs", buffFrame)
        end
    end

    -- debuffs
    config = BD.config.debuffs
    if not which or which == "debuffs" then
        if config.enabled then
            debuffFrame = EnableHeader("debuffs", debuffFrame, CreateDebuffHeader, config)
        else
            DisableHeader("debuffs", debuffFrame)
        end
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateBuffsDebuffs)
