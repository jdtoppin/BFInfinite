---@type BFI
local BFI = select(2, ...)
local W = BFI.modules.UIWidgets
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local IsRaidMarkerActive = IsRaidMarkerActive

local WORLD_MARKER_INDEX_MAP = {5, 6, 3, 2, 7, 1, 4, 8}

local markersFrame

local targetMarkers = {}
local worldMarkers = {}

---------------------------------------------------------------------
-- shared
---------------------------------------------------------------------
local function Gradient_ShowUp(self, show)
    if show then
        AF.FrameResizeHeight(self, 0.15, nil, AF.ConvertPixels(W.config.markers.height - 2))
    else
        AF.FrameResizeHeight(self, 0.15, nil, 0)
    end
end

local function CreateGradientForMarker(marker, color)
    marker.gradient = AF.CreateGradientTexture(marker, "VERTICAL", color, AF.GetColorTable(color, 0))
    marker.gradient:SetHeight(0.001)
    AF.SetPoint(marker.gradient, "BOTTOMLEFT", 1, 1)
    AF.SetPoint(marker.gradient, "BOTTOMRIGHT", -1, 1)
    marker.gradient:SetDrawLayer("ARTWORK", -1)
    marker.gradient.ShowUp = Gradient_ShowUp
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateMarkersFrame()
    markersFrame = CreateFrame("Frame", "BFI_MarkersFrame", AF.UIParent)
    AF.AddEventHandler(markersFrame)

    -- mover
    AF.CreateMover(markersFrame, "BFI: " .. L["UI Widgets"], L["Markers"])

    -- marker parents, used for hiding/showing all markers at once
    markersFrame.targetMarkerParent = CreateFrame("Frame", nil, markersFrame)
    markersFrame.targetMarkerParent:SetAllPoints()
    markersFrame.worldMarkerParent = CreateFrame("Frame", nil, markersFrame)
    markersFrame.worldMarkerParent:SetAllPoints()

    local bgColor = AF.GetColorTable("background", 0.7)

    -- target markers
    for i = 1, 9 do
        local marker = AF.CreateButton(markersFrame.targetMarkerParent, nil,
            {"none", AF.GetColorTable(i == 9 and "firebrick" or "marker" .. i, 0.4)},
            nil, nil, "SecureActionButtonTemplate"
        )
        tinsert(targetMarkers, marker)

        marker.bg:SetColorTexture(AF.UnpackColor(bgColor))

        marker.texture = AF.CreateTexture(marker, i == 9 and "Interface\\Buttons\\UI-GroupLoot-Pass-Up" or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        AF.SetInside(marker.texture, marker, 2)
        marker.texture:SetDrawLayer("ARTWORK", 1)
        marker:EnablePushEffect(false)

        if i == 9 then
            marker:SetAttribute("type", "raidtarget")
            marker:SetAttribute("action", "clear-all")
        else
            -- Retail 12.0.7.68887 and 12.1.0.68914:
            -- Blizzard_APIDocumentationGenerated/RaidMarkersDocumentation.lua
            -- marks GetRaidTargetIndex as secret-returning, while
            -- Blizzard_FrameXML/SecureTemplates.lua provides this handler.
            marker:SetAttribute("type", "raidtarget")
            marker:SetAttribute("unit", "target")
            marker:SetAttribute("marker", i)
            marker:SetAttribute("action1", "toggle")
            marker:SetAttribute("action2", "clear")
        end
    end

    -- world markers
    for i = 1, 9 do
        local marker = AF.CreateButton(markersFrame.worldMarkerParent, nil,
            {i == 9 and "none" or AF.GetColorTable("marker" .. i, 0.4), AF.GetColorTable(i == 9 and "firebrick" or "marker" .. i, i == 9 and 0.4 or 0.6)},
            nil, nil, "SecureActionButtonTemplate"
        )
        tinsert(worldMarkers, marker)

        marker.bg:SetColorTexture(AF.UnpackColor(bgColor))

        if i == 9 then
            marker.texture = AF.CreateTexture(marker, "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            AF.SetInside(marker.texture, marker, 2)
            marker:EnablePushEffect(false)

            marker:SetAttribute("type", "worldmarker")
            marker:SetAttribute("action", "clear")
        else
            CreateGradientForMarker(marker, "marker" .. i)

            marker:SetAttribute("type", "worldmarker")
            marker:SetAttribute("marker", WORLD_MARKER_INDEX_MAP[i])
            marker:SetAttribute("action1", "set")
            marker:SetAttribute("action2", "clear")
        end
    end
end

---------------------------------------------------------------------
-- setup
---------------------------------------------------------------------
local function SetupMarkersFrame(config)
    local spacingX, spacingY
    if config.arrangement:find("^[tb]") then -- vertical
        spacingX, spacingY = config.groupSpacing, config.markerSpacing
        AF.SetGridSize(markersFrame, config.width, config.height, spacingX, spacingY, 2, 9)
    else -- horizontal
        spacingX, spacingY = config.markerSpacing, config.groupSpacing
        AF.SetGridSize(markersFrame, config.width, config.height, spacingX, spacingY, 9, 2)
    end

    local coords = AF.CalcTexCoordPreCrop(nil, config.width / config.height)
    local point, relativePoint, newLineRelativePoint, x, y, newLineX, newLineY = AF.GetAnchorPoints_Complex(config.arrangement, spacingX, spacingY)

    -- target markers
    for i, marker in next, targetMarkers do
        marker.texture:SetTexCoord(unpack(coords))
        AF.SetSize(marker, config.width, config.height)

        AF.ClearPoints(marker)
        if i == 1 then
            AF.SetPoint(marker, point)
        else
            AF.SetPoint(marker, point, targetMarkers[i - 1], relativePoint, x, y)
        end
    end

    -- world markers
    for i, marker in next, worldMarkers do
        if marker.texture then
            marker.texture:SetTexCoord(unpack(coords))
        end
        AF.SetSize(marker, config.width, config.height)

        AF.ClearPoints(marker)
        if i == 1 then
            AF.SetPoint(marker, point, targetMarkers[1], newLineRelativePoint, newLineX, newLineY)
        else
            AF.SetPoint(marker, point, worldMarkers[i - 1], relativePoint, x, y)
        end
    end
end

---------------------------------------------------------------------
-- update world marker state
---------------------------------------------------------------------
local function UpdateWorldMarkers()
    for i = 1, 8 do
        worldMarkers[i].gradient:ShowUp(IsRaidMarkerActive(WORLD_MARKER_INDEX_MAP[i]))
        -- if IsRaidMarkerActive(WORLD_MARKER_INDEX_MAP[i]) then
        --     worldMarkers[i]:SetBorderColor("marker" .. i)
        -- else
        --     worldMarkers[i]:SetBorderColor("border")
        -- end
    end
end

---------------------------------------------------------------------
-- check permission
---------------------------------------------------------------------
local function CheckPermission()
    if not markersFrame or not markersFrame.enabled then return end

    local groupType = AF.GetGroupType()

    if groupType == "solo" and W.config.markers.showIfSolo then
        AF.SetProtectedFrameShown(markersFrame.targetMarkerParent, W.config.markers.targetMarkers)
        AF.HideProtectedFrame(markersFrame.worldMarkerParent)
    elseif groupType ~= "solo" and AF.HasMarkerPermission() then
        AF.SetProtectedFrameShown(markersFrame.targetMarkerParent, W.config.markers.targetMarkers)
        AF.SetProtectedFrameShown(markersFrame.worldMarkerParent, W.config.markers.worldMarkers)
    else
        AF.HideProtectedFrame(markersFrame.targetMarkerParent)
        AF.HideProtectedFrame(markersFrame.worldMarkerParent)
    end
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateMarkers(_, module, which)
    if module and module ~= "uiWidgets" then return end
    if which and which ~= "markers" then return end

    local config = W.config.markers

    if not config.enabled then
        if markersFrame then
            markersFrame.enabled = false
            markersFrame:Hide()
            markersFrame:UnregisterAllEvents()
            AF.UnregisterCallback("AF_MARKER_PERMISSION_CHANGED", CheckPermission)
        end
        return
    end

    if not markersFrame then
        CreateMarkersFrame()
    end
    markersFrame:Show()
    markersFrame.enabled = true

    SetupMarkersFrame(config)
    AF.UpdateMoverSave(markersFrame, config.position)
    AF.LoadPosition(markersFrame, config.position)

    UpdateWorldMarkers()
    markersFrame:RegisterEvent("RAID_TARGET_UPDATE", UpdateWorldMarkers)

    CheckPermission()
    AF.RegisterCallback("AF_MARKER_PERMISSION_CHANGED", CheckPermission)
end
AF.RegisterCallback("BFI_UpdateModule", UpdateMarkers)
