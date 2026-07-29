---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local raid
local indicators = {
    "healthBar",
    "powerBar",
    "nameText",
    "healthText",
    -- "powerText",
    "leaderIcon",
    -- "targetCounter",
    "statusTimer",
    "statusIcon",
    "raidIcon",
    "readyCheckIcon",
    "roleIcon",
    "targetHighlight",
    "mouseoverHighlight",
    "threatGlow",
    {"groupNativeAuras", "buffs", "HELPFUL", "buffs"},
    {"groupNativeAuras", "debuffs", "HARMFUL", "debuffs"},
}

-- bottom_to_top_then_left
-- bottom_to_top_then_right
-- top_to_bottom_then_left
-- top_to_bottom_then_right
-- left_to_right_then_down
-- left_to_right_then_up
-- right_to_left_then_down
-- right_to_left_then_up

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateRaid()
    local name = "BFI_Raid"
    raid = CreateFrame("Frame", name, UF.Parent, "SecureFrameTemplate")
    UF.AddToConfigMode("raid.container", raid)

    local header = CreateFrame("Frame", name .. "Header", raid, "SecureGroupHeaderTemplate")
    raid.header = header
    UF.AddToConfigMode("raid.header", header)
    header:SetAttribute("template", "BFIUnitButtonTemplate")
    local hasNativeGroupAuras = UF.PrepareNativeGroupAuraHeader(header)

    -- Keep the filter set empty so SecureGroupHeaders.lua sees zero
    -- filtered units and makes needButtons exactly 40 in every context.
    header:SetAttribute("startingIndex", -39)
    header:Show()
    header:SetAttribute("startingIndex", 1)
    header:SetAttribute("showSolo", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showPlayer", true)

    header:HookScript("OnAttributeChanged", function(self, attr)
        if not self.inConfigMode then return end
        if self:GetAttribute("startingIndex") ~= -39 then
            self:SetAttribute("startingIndex", -39)
        end
    end)

    raid.driverKey = "state-visibility"
    raid.driverValue = "[@raid1,exists] show; hide"

    for i = 1, 40 do
        local button = header[i]
        if hasNativeGroupAuras then
            assert(button.AuraContainer,
                "secure Raid child is missing its native aura container")
            button._nativeAuraContainers = {
                -- Blizzard supplies one header-born shell. Raid's displays
                -- have independent anchors/flows, so eagerly allocate the
                -- second bounded shell before indicator construction. The
                -- shipped four-group contract intentionally prebuilds 1,600
                -- restricted buttons across this fixed 40-child header.
                buffs = UF.CreateNativeGroupAuraContainerSeed(button),
                debuffs = button.AuraContainer,
            }
        end

        button._updateOnGroupUpdate = true
        button._deferUpdateOnUnitChange = true
        button._enableUnitButtonMapping = true
        UF.AddToConfigMode("raid", button)
        UF.CreateIndicators(button, indicators)
        UF.CreatePreviewRect(button)
    end

    -- mover
    AF.CreateMover(raid, "BFI: " .. L["Unit Frames"], _G.RAID)

    -- pixel perfect
    AF.AddToPixelUpdater_Auto(raid, nil, true)
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateRaid(_, module, which, skipIndicatorUpdates)
    if C_AddOns.IsAddOnLoaded("Cell") then
        return
    end

    if module and module ~= "unitFrames" then return end
    if which and which ~= "raid" then return end

    local config = UF.config.raid
    local wasEnabled = raid and raid.enabled == true

    if not (UF.config.general.enabled and config.general.enabled) then
        if raid then
            UnregisterAttributeDriver(raid)
            for i = 1, 40 do
                UF.DisableIndicators(raid.header[i])
            end
            raid.enabled = false -- for mover
            raid:Hide()
        end
        return
    end

    if not raid then
        CreateRaid()
    end

    raid.enabled = true -- for mover
    local skipCurrentIndicatorUpdates =
        skipIndicatorUpdates == true and wasEnabled

    -- setup
    local header = raid.header
    if raid.inConfigMode then
        -- A disabled config-mode group remains registered. Restore its
        -- visible parent before indicator setup so previews can re-enable.
        raid:Show()
    end

    -- mover
    AF.UpdateMoverSave(raid, config.general.position)

    -- position
    BFI.funcs.LoadPosition(raid, config.general.position)

    -- container size
    if strfind(config.general.orientation, "^[top|bottom]") then
        AF.SetGridSize(raid, config.general.width, config.general.height,
            config.general.spacingX, config.general.spacingY,
            config.general.maxColumns, config.general.unitsPerColumn
        )
    else
        AF.SetGridSize(raid, config.general.width, config.general.height,
            config.general.spacingX, config.general.spacingY,
            config.general.unitsPerColumn, config.general.maxColumns
        )
    end

    -- buttons
    for i = 1, 40 do
        local button = header[i]
        button:ClearAllPoints()

        -- size
        AF.SetSize(button, config.general.width, config.general.height)
        -- out of range alpha
        button.oorAlpha = config.general.oorAlpha
        -- tooltip
        button.tooltip = config.general.tooltip
        -- color
        AF.ApplyDefaultBackdropWithColors(button, config.general.bgColor, config.general.borderColor)
        -- indicators
        if not skipCurrentIndicatorUpdates then
            UF.SetupIndicators(button, indicators, config)
            if raid.inConfigMode then
                for _, indicator in next, button.indicators do
                    if indicator.EnableConfigMode then
                        indicator:EnableConfigMode()
                    end
                end
            end
        end
    end

    -- header
    header:SetAttribute("_ignore", true) -- skip SecureGroupHeader_OnAttributeChanged -> SecureGroupHeader_Update

    local _, _, x, y, cs, hp, cp = AF.GetAnchorPoints_GroupHeader(config.general.orientation, config.general.spacingX, config.general.spacingY)
    header:SetSize(config.general.width, config.general.height)
    header:ClearAllPoints()
    header:SetPoint(config.general.anchor)
    header:SetAttribute("minWidth", AF.ConvertPixelsForRegion(config.general.width, raid))
    header:SetAttribute("minHeight", AF.ConvertPixelsForRegion(config.general.height, raid))
    header:SetAttribute("point", hp)
    header:SetAttribute("xOffset", x)
    header:SetAttribute("yOffset", y)
    header:SetAttribute("sortMethod", config.general.sortMethod)
    header:SetAttribute("sortDir", config.general.sortDir)
    header:SetAttribute("groupingOrder", config.general.groupingOrder)
    header:SetAttribute("groupBy", config.general.groupBy)
    header:SetAttribute("columnAnchorPoint", cp)
    header:SetAttribute("columnSpacing", cs)
    header:SetAttribute("maxColumns", config.general.maxColumns)
    header:SetAttribute("groupFilter", config.general.groupFilter)

    header:SetAttribute("_ignore", nil) -- ready for updates
    header:SetAttribute("unitsPerColumn", config.general.unitsPerColumn)
    header:Show()

    if not raid.inConfigMode then
        -- visibility NOTE: show must invoke after settings applied
        RegisterAttributeDriver(raid, raid.driverKey, raid.driverValue)
    else
        raid:Show()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateRaid)
