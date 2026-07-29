---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local active

function DM.IsActive()
    return active == true and DM.config and DM.config.enabled == true
end

function DM.Enable()
    if active then
        DM.Renderer.SetEnabled(true)
        if DM.Automation then
            DM.Automation.SetEnabled(true)
        end
        return
    end

    active = true
    DM.Renderer.SetEnabled(true)
    if DM.Automation then
        DM.Automation.SetEnabled(true)
    end
end

function DM.Disable()
    active = nil
    if DM.Automation then
        DM.Automation.SetEnabled(false)
    end
    DM.Renderer.SetEnabled(false)
end

function DM.Refresh()
    if DM.IsActive() then
        DM.Renderer.Refresh()
    end
end

local function UpdateDamageMeter(_, module)
    if module and module ~= "damageMeter" then return end
    if not DM.config then return end

    if DM.config.enabled then
        DM.Enable()
    else
        DM.Disable()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateDamageMeter)

AF.RegisterCallback("BFI_UpdateFont", function()
    if DM.IsActive() then
        DM.Renderer.ApplySettings()
    end
end)
