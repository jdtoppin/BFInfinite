---@type BFI
local BFI = select(2, ...)
---@class Tooltip
local T = BFI.modules.Tooltip
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = true,
    position = {"BOTTOMRIGHT", -10, 10},
    anchorMode = "fixed",
    anchorPoint = "BOTTOMRIGHT",
    cursorAnchor = {
        x = 10,
        y = -5,
    },
    hideUnitTooltipsInCombat = false,
    healthBar = {
        enabled = true,
        height = 4,
    },
}

AF.RegisterCallback("BFI_UpdateProfile", function(_, t)
    if not t["tooltip"] then
        t["tooltip"] = AF.Copy(defaults)
    end
    T.config = t["tooltip"]
end)

function T.GetDefaults()
    return AF.Copy(defaults)
end

function T.ResetToDefaults()
    wipe(T.config)
    AF.Merge(T.config, defaults)
end
