---@type BFI
local BFI = select(2, ...)
---@class DisableBlizzard
local DB = BFI.modules.DisableBlizzard
---@type AbstractFramework
local AF = _G.AbstractFramework

-- Keep Blizzard's controllers and event frames active. BFI still relies on
-- their override-state, Extra Action, and Quick Keybind services.
local visualActionBars = {
    "MainActionBar",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "OverrideActionBar",
    "PetActionBar",
    "PossessActionBar",
    "StanceBar",
}

local init
local function DisableBlizzardActionBars()
    -- Requires ReloadUI to restore Blizzard's visual bars.
    if init then return end
    init = true

    if not DB.config.actionBars then return end

    for _, name in ipairs(visualActionBars) do
        local frame = _G[name]
        if frame then
            frame:SetParent(AF.hiddenParent)
        else
            AF.Debug("DisableBlizzard ActionBars: Frame not found - " .. name)
        end
    end
end
AF.RegisterCallback("BFI_DisableBlizzard", DisableBlizzardActionBars)
