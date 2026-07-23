---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local AB = BFI.modules.ActionBars
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- create bar
---------------------------------------------------------------------
local stanceBar
local function CreateStanceBar()
    stanceBar = CreateFrame("Frame", "BFI_StanceBar", AF.UIParent, "SecureHandlerStateTemplate")

    stanceBar.name = "stancebar"
    stanceBar.buttons = {}

    AB.bars[stanceBar.name] = stanceBar

    AF.CreateMover(stanceBar, "BFI: " .. L["Action Bars"], L["Stance Bar"])
    AB.CreatePreviewRect(stanceBar)

    stanceBar:SetScript("OnEnter", AB.ActionBar_OnEnter)
    stanceBar:SetScript("OnLeave", AB.ActionBar_OnLeave)

    AF.AddToPixelUpdater_Auto(stanceBar, nil, true)
end

---------------------------------------------------------------------
-- bindings
---------------------------------------------------------------------
local function AssignBindings()
    if InCombatLockdown() then return end

    ClearOverrideBindings(stanceBar)

    for i, b in ipairs(stanceBar.buttons) do
        b.HotKey:SetText("")
        local command = ("SHAPESHIFTBUTTON%d"):format(i)
        local key1, key2 = GetBindingKey(command)
        b.HotKey:SetText(AB.GetHotkey(key1))
        for _, key in next, {key1, key2} do
            if key and key ~= "" then
                SetOverrideBindingClick(stanceBar, false, key, b:GetName())
            end
        end
    end
end

local function RemoveBindings()
    if InCombatLockdown() then return end
    ClearOverrideBindings(stanceBar)
end

---------------------------------------------------------------------
-- update cooldown
---------------------------------------------------------------------
local function UPDATE_SHAPESHIFT_COOLDOWN()
    local numForms = min(GetNumShapeshiftForms(), stanceBar.maxButtons)
    for i = 1, numForms do
        local button = stanceBar.buttons[i]
        local texture = GetShapeshiftFormInfo(i)
        button.cooldown:SetShown(texture ~= nil)

        local start, duration, enable = GetShapeshiftFormCooldown(i)
        CooldownFrame_Set(button.cooldown, start, duration, enable)
    end
end

---------------------------------------------------------------------
-- update buttons
---------------------------------------------------------------------
local function UpdateStanceButtonStatus()
    local num = min(GetNumShapeshiftForms(), stanceBar.maxButtons)
    for i, b in next, stanceBar.buttons do
        if i <= num then
            local icon, isActive, isCastable, spellID = GetShapeshiftFormInfo(i)
            b.spellID = spellID
            b.icon:SetTexture(icon)
            b.icon:SetVertexColor(AF.GetColorRGB(isCastable and "white" or "disabled"))
            b:SetChecked(isActive)
        else
            b:SetChecked(false)
        end
    end
end

local function UpdateStanceButtons()
    if InCombatLockdown() then
        AB:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateStanceButtons)
        return
    end
    AB:UnregisterEvent("PLAYER_REGEN_ENABLED", UpdateStanceButtons)

    local num = min(GetNumShapeshiftForms(), stanceBar.maxButtons)

    for i, b in next, stanceBar.buttons do
        if i <= num then
            b:SetAttribute("statehidden", nil)
            b:Show()
        else
            b:SetAttribute("statehidden", true)
            b:Hide()
        end
    end

    if num ~= 0 and stanceBar.enabled then
        stanceBar:Show()
        RegisterStateDriver(stanceBar, "visibility", stanceBar.visibility)
    else
        stanceBar:Hide()
        UnregisterStateDriver(stanceBar, "visibility")
    end

    UpdateStanceButtonStatus()
end

---------------------------------------------------------------------
-- update bar
---------------------------------------------------------------------
local function UpdateStanceBar(_, module, which)
    if module and module ~= "actionBars" then return end
    if which and which ~= "stancebar" then return end

    local enabled = AB.config.general.enabled
    local config = AB.config.barConfig.stancebar

    if not stanceBar then
        CreateStanceBar()
    end

    if not (enabled and config.enabled) then
        AB:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS")
        AB:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
        AB:UnregisterEvent("UPDATE_SHAPESHIFT_USABLE")
        AB:UnregisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
        AB:UnregisterEvent("UPDATE_BINDINGS", AssignBindings)

        if AF.isRetail then
            AB:UnregisterEvent("PET_BATTLE_CLOSE", AssignBindings)
            AB:UnregisterEvent("PET_BATTLE_OPENING_DONE", RemoveBindings)
        end

        stanceBar.enabled = false
        ClearOverrideBindings(stanceBar)
        UnregisterStateDriver(stanceBar, "visibility")
        stanceBar:Hide()
        return
    end

    stanceBar.enabled = true
    config.num = AF.Clamp(config.num, 1, 10)
    config.buttonsPerLine = AF.Clamp(config.buttonsPerLine, 1, config.num)
    stanceBar.maxButtons = config.num

    -- mover
    AF.UpdateMoverSave(stanceBar, config.position)

    -- events
    AB:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", UpdateStanceButtons)
    AB:RegisterEvent("UPDATE_SHAPESHIFT_FORM", UpdateStanceButtonStatus)
    AB:RegisterEvent("UPDATE_SHAPESHIFT_USABLE", UpdateStanceButtonStatus)
    AB:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", UPDATE_SHAPESHIFT_COOLDOWN)
    AB:RegisterEvent("UPDATE_BINDINGS", AssignBindings)

    if AF.isRetail then
        AB:RegisterEvent("PET_BATTLE_CLOSE", AssignBindings)
        AB:RegisterEvent("PET_BATTLE_OPENING_DONE", RemoveBindings)
    end

    for i = 1, 10 do
        local b
        if not stanceBar.buttons[i] then
            b = AB.CreateStanceButton(stanceBar, i)
            stanceBar.buttons[i] = b
        else
            b = stanceBar.buttons[i]
        end

        if config.buttonConfig.hideElements.hotkey then
            b.HotKey:Hide()
        else
            AB.ApplyTextConfig(b.HotKey, config.buttonConfig.text.hotkey)
            b.HotKey:Show()
        end

        -- tooltip
        b.tooltip = AB.config.general.tooltip
    end

    -- load config
    AB.ReArrange(stanceBar, config.width, config.height, config.spacingX, config.spacingY, config.buttonsPerLine, config.num, config.orientation)
    AF.LoadPosition(stanceBar, config.position)

    stanceBar:SetFrameStrata(AB.config.general.frameStrata)
    stanceBar:SetFrameLevel(AB.config.general.frameLevel)

    stanceBar.alpha = config.alpha
    stanceBar:SetAlpha(config.alpha)

    stanceBar.visibility = config.visibility

    UpdateStanceButtons()
    AssignBindings()
end
AF.RegisterCallback("BFI_UpdateModule", UpdateStanceBar)
