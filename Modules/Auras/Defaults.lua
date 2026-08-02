---@type BFI
local BFI = select(2, ...)
---@class Auras
local A = BFI.modules.Auras
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- shared colors
---------------------------------------------------------------------
local defaults = {
    blacklist = {
    },
    priorities = {
        [980] = 1,
        [32390] = 2,
        [316099] = 3,
        [48181] = 4,
    },
    colors = {
    },
}

AF.RegisterCallback("BFI_UpdateConfig", function(_, module)
    if module then return end -- init

    if not BFIConfig.auras then
        BFIConfig.auras = AF.Copy(defaults)
    else
        for key, value in next, defaults do
            if type(BFIConfig.auras[key]) ~= "table" then
                BFIConfig.auras[key] = AF.Copy(value)
            end
        end
    end
    A.config = BFIConfig.auras
end, "high")

function A.GetDefaults(which)
    if which then
        return AF.Copy(defaults[which])
    end
    return AF.Copy(defaults)
end

function A.ResetToDefaults(which)
    -- Only Global Colors is a supported Auras surface. Preserve retired
    -- blacklist/priority tables through resets and profile round-trips.
    which = which or "colors"
    wipe(BFIConfig["auras"][which])
    AF.Merge(BFIConfig["auras"][which], defaults[which])
end
