---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local AB = BFI.modules.ActionBars
---@type AbstractFramework
local AF = _G.AbstractFramework

local vehicleExitHolder
local vehicleExitButton
local original

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function AttachButton()
    vehicleExitButton:SetScript("OnShow", nil)
    vehicleExitButton:SetScript("OnHide", nil)
    vehicleExitButton:SetParent(vehicleExitHolder)
    AF.SetOnePixelInside(vehicleExitButton, vehicleExitHolder)
    vehicleExitButton:GetNormalTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
    vehicleExitButton:GetPushedTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
end

local function RestoreButton()
    vehicleExitButton:SetScript("OnShow", original.onShow)
    vehicleExitButton:SetScript("OnHide", original.onHide)
    vehicleExitButton:SetParent(original.parent)
    vehicleExitButton:ClearAllPoints()
    for _, point in ipairs(original.points) do
        vehicleExitButton:SetPoint(unpack(point))
    end
    AF.SetSize(vehicleExitButton, original.width, original.height)
    vehicleExitButton:SetFrameStrata(original.frameStrata)
    vehicleExitButton:SetFrameLevel(original.frameLevel)
    vehicleExitButton:GetNormalTexture():SetTexCoord(unpack(original.normalTexCoords))
    vehicleExitButton:GetPushedTexture():SetTexCoord(unpack(original.pushedTexCoords))
    vehicleExitButton:Update()
end

local function CreateButton()
    vehicleExitHolder = AF.CreateBorderedFrame(AF.UIParent, "BFI_VehicleExitHolder", 20, 20)
    vehicleExitHolder:Hide()
    vehicleExitHolder.enabled = false
    AF.AddToPixelUpdater_Auto(vehicleExitHolder, function()
        AF.DefaultUpdatePixels(vehicleExitHolder)
        if vehicleExitHolder.enabled then
            AF.SetOnePixelInside(vehicleExitButton, vehicleExitHolder)
        end
    end, true)

    vehicleExitButton = _G.MainMenuBarVehicleLeaveButton
    vehicleExitHolder.button = vehicleExitButton

    original = {
        parent = vehicleExitButton:GetParent(),
        points = {},
        width = vehicleExitButton:GetWidth(),
        height = vehicleExitButton:GetHeight(),
        frameStrata = vehicleExitButton:GetFrameStrata(),
        frameLevel = vehicleExitButton:GetFrameLevel(),
        normalTexCoords = {vehicleExitButton:GetNormalTexture():GetTexCoord()},
        pushedTexCoords = {vehicleExitButton:GetPushedTexture():GetTexCoord()},
        onShow = vehicleExitButton:GetScript("OnShow"),
        onHide = vehicleExitButton:GetScript("OnHide"),
    }
    for i = 1, vehicleExitButton:GetNumPoints() do
        original.points[i] = {vehicleExitButton:GetPoint(i)}
    end

    hooksecurefunc(vehicleExitButton, "Update", function()
        if vehicleExitHolder.enabled then
            vehicleExitHolder:SetShown(vehicleExitButton:CanExitVehicle())
        end
    end)

    hooksecurefunc(vehicleExitButton, "SetPoint", function(_, _, anchorTo)
        if vehicleExitHolder.enabled and anchorTo ~= vehicleExitHolder then
            AttachButton()
        end
    end)

    AF.CreateMover(vehicleExitHolder, "BFI: " .. L["Action Bars"], _G.HUD_EDIT_MODE_VEHICLE_LEAVE_BUTTON_LABEL)
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateButton(_, module, which)
    if module and module ~= "actionBars" then return end
    if which and which ~= "vehicle" then return end

    local enabled = AB.config.general.enabled
    local config = AB.config.vehicleExitButton

    if not vehicleExitHolder then
        CreateButton()
    end

    if not (enabled and config.enabled) then
        vehicleExitHolder:Hide()
        if vehicleExitHolder.enabled then
            vehicleExitHolder.enabled = false
            RestoreButton()
        end
        return
    end

    vehicleExitHolder.enabled = true
    AttachButton()

    -- mover
    AF.UpdateMoverSave(vehicleExitHolder, config.position)

    -- load config
    AF.LoadPosition(vehicleExitHolder, config.position)
    AF.SetSize(vehicleExitHolder, config.size, config.size)
    vehicleExitHolder:SetFrameStrata(AB.config.general.frameStrata)
    vehicleExitHolder:SetFrameLevel(AB.config.general.frameLevel)
    vehicleExitButton:SetFrameStrata(AB.config.general.frameStrata)
    vehicleExitButton:SetFrameLevel(AB.config.general.frameLevel + 1)
    vehicleExitButton:Update()
end
AF.RegisterCallback("BFI_UpdateModule", UpdateButton)
