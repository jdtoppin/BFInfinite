---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local party
local indicators = {
    "healthBar",
    "powerBar",
    "portrait",
    "castBar",
    "nameText",
    "healthText",
    "powerText",
    "levelText",
    "leaderText",
    "combatIcon",
    "leaderIcon",
    "targetCounter",
    "statusTimer",
    "statusIcon",
    "raidIcon",
    "readyCheckIcon",
    "roleIcon",
    "factionIcon",
    "targetHighlight",
    "mouseoverHighlight",
    "threatGlow",
    {"groupNativeAuras", "buffs", "HELPFUL", "buffs"},
    {"groupNativeAuras", "debuffs", "HARMFUL", "debuffs"},
    {"groupNativeDispels", "dispels", "dispels"},
}

---------------------------------------------------------------------
-- create -- TODO: pet & target
---------------------------------------------------------------------
local function CreateParty()
    local name = "BFI_Party"
    party = CreateFrame("Frame", name, UF.Parent, "SecureFrameTemplate")
    UF.AddToConfigMode("party.container", party)

    local header = CreateFrame("Frame", name .. "Header", party, "SecureGroupHeaderTemplate")
    party.header = header
    UF.AddToConfigMode("party.header", header)
    header:SetAttribute("template", "BFIUnitButtonTemplate")
    local hasNativeGroupAuras = UF.PrepareNativeGroupAuraHeader(header)
    header:SetAttribute("showSolo", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", true)

    --! to make needButtons == 5 in SecureGroupHeaders.lua
    header:SetAttribute("startingIndex", -4)
    header:Show()
    header:SetAttribute("startingIndex", 1)

    header:HookScript("OnAttributeChanged", function(self, attr)
        if not self.inConfigMode then return end
        if self:GetAttribute("startingIndex") ~= -4 then
            self:SetAttribute("startingIndex", -4)
        end
    end)

    party.driverKey = "state-visibility"
    party.driverValue = "[@raid1,exists] hide;[@party1,exists] show;[group:party] show;hide"

    for i = 1, 5 do
        local button = header[i]
        if hasNativeGroupAuras then
            assert(button.AuraContainer,
                "secure Party child is missing its native aura container")
            button._nativeAuraContainers = {
                -- Blizzard supplies one header-born shell. Party's displays
                -- have independent anchors/flows, so eagerly allocate the
                -- second bounded shell before indicator construction.
                buffs = UF.CreateNativeGroupAuraContainerSeed(button),
                debuffs = button.AuraContainer,
                -- The full-frame dispel tint has an independent lifecycle
                -- and topology from the visible harmful-icon row.
                dispels = UF.CreateNativeGroupAuraContainerSeed(button),
            }
        end

        button._updateOnGroupUpdate = true
        button._deferUpdateOnUnitChange = true
        button._enableUnitButtonMapping = true
        UF.AddToConfigMode("party", button)
        UF.CreateIndicators(button, indicators)
        UF.CreatePreviewRect(button)
    end

    -- mover
    AF.CreateMover(party, "BFI: " .. L["Unit Frames"], _G.PARTY)

    -- pixel perfect
    AF.AddToPixelUpdater_Auto(party, nil, true)
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateParty(_, module, which, skipIndicatorUpdates)
    if module and module ~= "unitFrames" then return end
    if which and which ~= "party" then return end

    local config = UF.config.party
    local wasEnabled = party and party.enabled == true

    if not (UF.config.general.enabled and config.general.enabled) then
        if party then
            UnregisterAttributeDriver(party)
            for i = 1, 5 do
                UF.DisableIndicators(party.header[i])
            end
            party.enabled = false -- for mover
            party:Hide()
        end
        return
    end

    if not party then
        CreateParty()
    end

    party.enabled = true -- for mover
    local skipCurrentIndicatorUpdates =
        skipIndicatorUpdates == true and wasEnabled

    -- setup
    local header = party.header
    local unitCount = 5 -- config.general.showPlayer and 5 or 4
    if party.inConfigMode then
        -- A disabled config-mode group remains registered. Restore its
        -- visible parent before indicator setup so previews can re-enable.
        party:Show()
    end

    -- strata & level
    -- party:SetFrameStrata(config.general.frameStrata)
    -- party:SetFrameLevel(config.general.frameLevel)

    -- mover
    AF.UpdateMoverSave(party, config.general.position)

    -- position
    BFI.funcs.LoadPosition(party, config.general.position)

    -- container size
    if config.general.orientation == "top_to_bottom" or config.general.orientation == "bottom_to_top" then
        AF.SetWidth(party, config.general.width)
        AF.SetListHeight(party, unitCount, config.general.height, config.general.spacing)
    else
        AF.SetHeight(party, config.general.height)
        AF.SetListWidth(party, unitCount, config.general.width, config.general.spacing)
    end

    -- buttons
    for i = 1, 5 do
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
            if party.inConfigMode then
                for _, indicator in next, button.indicators do
                    if indicator.EnableConfigMode then
                        indicator:EnableConfigMode()
                    end
                end
            end
        end
    end

    -- header
    local p, _, x, y = AF.GetAnchorPoints_Simple(config.general.orientation, config.general.spacing)
    header:ClearAllPoints()
    header:SetPoint(config.general.anchor, party)
    header:SetAttribute("point", p)
    header:SetAttribute("xOffset", x)
    header:SetAttribute("yOffset", y)
    header:SetAttribute("buttonWidth", AF.ConvertPixelsForRegion(config.general.width, party))
    header:SetAttribute("buttonHeight", AF.ConvertPixelsForRegion(config.general.height, party))
    header:SetAttribute("showPlayer", config.general.showPlayer)
    header:SetAttribute("sortMethod", config.general.sortMethod)
    header:SetAttribute("sortDir", config.general.sortDir)
    header:SetAttribute("groupingOrder", config.general.groupingOrder)
    header:SetAttribute("groupBy", config.general.groupBy)
    header:SetSize(config.general.width, config.general.height)
    header:SetAttribute("unitsPerColumn", 5)
    header:Show()

    if not party.inConfigMode then
        -- visibility NOTE: show must invoke after settings applied
        RegisterAttributeDriver(party, party.driverKey, party.driverValue)
    else
        party:Show()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateParty)
