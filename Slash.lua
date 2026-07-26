---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

SLASH_BFI1 = "/bfi"
function SlashCmdList.BFI(msg, editbox)
    local command = msg:match("^(%S*)")
    command = strlower(command or "")

    if command == "mover" then
        local moverParent = _G.AFMoverParent
        if not (moverParent and moverParent:IsShown()) then
            F.PrepareEditModePositions()
        end
        AF.ToggleMovers()
    elseif command == "reset" then
        AF.ShowGlobalDialog(L["Are you sure you want to reset all BFI settings?"] .. "\n" ..  AF.WrapTextInColor(L["This action cannot be undone"], "firebrick"), function()
            -- reset BFI
            BFIConfig = nil
            BFIProfile = nil
            BFIPlayer = nil

            -- reset some AF settings
            AFConfig.accentColor = nil
            AFConfig.fontSizeDelta = nil
            AFConfig.scale = nil

            ReloadUI()
        end, nil, true)
    else
        F.ToggleOptionsFrame()
    end
end
