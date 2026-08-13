---@type BFI
local BFI = select(2, ...)
---@class ClickCastings
local CC = BFI.modules.ClickCastings
---@type AbstractFramework
local AF = _G.AbstractFramework

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local ClearOverrideBindings = ClearOverrideBindings

-- Contract pin: Retail 12.1.0.68914, Blizzard UI source
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. SecureUnitButton_OnClick
-- gives native Spell/Macro/PetAction click bindings priority and suppresses
-- target/menu attributes when no native interaction exists. Enabled
-- target/menu chords therefore delegate through a secure action proxy.
-- This intentionally favors a working local menu when Blizzard's interaction
-- is unbound; unlike SecureUnitButton_OnClick, that delegated menu does not
-- consume an active spell-targeting cursor before opening.

local manager = CreateFrame(
    "Frame",
    "BFIClickCastingSecureManager",
    nil,
    "SecureHandlerStateTemplate"
)

manager:SetAttribute("_onstate-mouseoverstate", [[
    if newstate == "false" and mouseoverbutton then
        if not mouseoverbutton:IsUnderMouse() then
            mouseoverbutton:ClearBindings()
            mouseoverbutton = nil
        end
    end
]])
RegisterStateDriver(manager, "mouseoverstate", "[@mouseover,exists] true; false")

local function AddOwnedAttribute(frame, attribute)
    frame._bfiClickCastingOwned = frame._bfiClickCastingOwned or {}
    frame._bfiClickCastingOwned[attribute] = true
end

local function SetOwnedAttribute(frame, attribute, value)
    frame:SetAttribute(attribute, value)
    AddOwnedAttribute(frame, attribute)
end

local function ClearOwnedAttributes(frame)
    if frame._bfiClickCastingOwned then
        for attribute in pairs(frame._bfiClickCastingOwned) do
            frame:SetAttribute(attribute, nil)
        end
        wipe(frame._bfiClickCastingOwned)
    end

    local proxy = frame._bfiClickCastingProxy
    if proxy and proxy._bfiClickCastingOwned then
        for attribute in pairs(proxy._bfiClickCastingOwned) do
            proxy:SetAttribute(attribute, nil)
        end
        wipe(proxy._bfiClickCastingOwned)
    end
end

local function CreateProxy(frame)
    if frame._bfiClickCastingProxy then
        return frame._bfiClickCastingProxy
    end
    if InCombatLockdown() then return end

    local proxy = CreateFrame(
        "Button",
        nil,
        frame,
        "SecureActionButtonTemplate"
    )
    proxy:EnableMouse(false)
    proxy:RegisterForClicks("AnyDown", "AnyUp")
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:SetAttribute("useparent-unit", true)
    proxy:SetAttribute("useparent-unitsuffix", true)
    proxy:SetAttribute("useparent-toggleForVehicle", true)
    proxy:SetAttribute("useparent-allowVehicleTarget", true)
    frame._bfiClickCastingProxy = proxy
    return proxy
end

local function InstallSecureHover(frame)
    if frame._bfiClickCastingHoverInstalled then return true end
    if InCombatLockdown() then return false end

    frame:SetAttribute("_onenter", [[
        self:ClearBindings()
        local snippet = self:GetAttribute("bfi-click-casting-snippet")
        if snippet then self:Run(snippet) end
    ]])
    frame:SetAttribute("_onleave", [[
        self:ClearBindings()
    ]])
    frame:SetAttribute("_onmousedown", [[
        self:ClearBindings()
        local snippet = self:GetAttribute("bfi-click-casting-snippet")
        if snippet then self:Run(snippet) end
    ]])
    frame:SetAttribute("_onhide", [[
        self:ClearBindings()
    ]])
    manager:WrapScript(frame, "OnEnter", [[
        if mouseoverbutton and mouseoverbutton ~= self then
            mouseoverbutton:ClearBindings()
        end
        mouseoverbutton = self
    ]])
    frame._bfiClickCastingHoverInstalled = true
    return true
end

local function ApplyAction(frame, proxy, action)
    local actionType = action.actionType
    local typeAttribute = action.typeAttribute

    if action.useProxy then
        local clickButtonAttribute = CC.GetClickButtonAttribute(typeAttribute)
        SetOwnedAttribute(frame, typeAttribute, "click")
        SetOwnedAttribute(frame, clickButtonAttribute, proxy)
        SetOwnedAttribute(proxy, typeAttribute, actionType)
        return
    end

    if actionType == "custom" then
        SetOwnedAttribute(frame, typeAttribute, "macro")
        SetOwnedAttribute(
            frame,
            CC.GetAttributeForPayload(typeAttribute, actionType),
            action.payload
        )
    elseif actionType == "spell" or actionType == "macro"
        or actionType == "item"
    then
        SetOwnedAttribute(frame, typeAttribute, actionType)
        SetOwnedAttribute(
            frame,
            CC.GetAttributeForPayload(typeAttribute, actionType),
            action.payload
        )
    else
        SetOwnedAttribute(frame, typeAttribute, actionType)
    end
end

local function ApplyToFrame(frame, compiled)
    if InCombatLockdown() then return false end

    local proxy = CreateProxy(frame)
    if not proxy or not InstallSecureHover(frame) then return false end

    ClearOverrideBindings(frame)
    ClearOwnedAttributes(frame)
    SetOwnedAttribute(
        frame,
        "bfi-click-casting-snippet",
        compiled.snippet ~= "" and compiled.snippet or nil
    )

    for _, action in ipairs(compiled.actions) do
        ApplyAction(frame, proxy, action)
    end
    return true
end

local compiled = CC.Compile(nil)
local updatePending

local function UpdateAll()
    if InCombatLockdown() then
        updatePending = true
        CC:RegisterEvent("PLAYER_REGEN_ENABLED", CC.FlushPending)
        return false
    end

    compiled = CC.Compile(CC.activeConfig)
    local complete = true
    for _, frame in pairs(BFI.vars.unitButtons or {}) do
        if not ApplyToFrame(frame, compiled) then
            complete = false
        end
    end
    updatePending = not complete
    if complete then
        CC:UnregisterEvent("PLAYER_REGEN_ENABLED", CC.FlushPending)
    else
        CC:RegisterEvent("PLAYER_REGEN_ENABLED", CC.FlushPending)
    end
    return complete
end

function CC.FlushPending()
    if updatePending then UpdateAll() end
end

function CC.RegisterFrame(frame)
    if not frame then return false end
    if InCombatLockdown() then
        updatePending = true
        CC:RegisterEvent("PLAYER_REGEN_ENABLED", CC.FlushPending)
        return false
    end
    return ApplyToFrame(frame, compiled)
end

function CC.Refresh()
    return UpdateAll()
end

function CC.GetCompiled()
    return compiled
end

function CC.GetNativeConflicts()
    local conflicts = {}
    if not _G.C_ClickBindings
        or type(_G.C_ClickBindings.GetProfileInfo) ~= "function"
        or type(CC.activeConfig) ~= "table"
        or not CC.activeConfig.enabled
    then
        return conflicts
    end

    local native = _G.C_ClickBindings.GetProfileInfo()
    if type(native) ~= "table" then return conflicts end

    local localMouse = {}
    for _, action in ipairs(CC.Compile(CC.activeConfig).actions) do
        local modifiers, key, isHover = CC.DecodeAttribute(
            action.sourceAttribute
        )
        if modifiers and not isHover then
            localMouse[modifiers .. key] = {
                action.sourceAttribute,
                action.actionType,
                action.payload,
            }
        end
    end

    for _, binding in ipairs(native) do
        local modifier
        if type(binding.modifiers) == "number"
            and type(_G.GetStringFromModifiers) == "function"
        then
            modifier = CC.NormalizeModifiers(
                _G.GetStringFromModifiers(binding.modifiers)
            )
        end
        local key = binding.button
        if key == "Button1" then
            key = "LeftButton"
        elseif key == "Button2" then
            key = "RightButton"
        elseif key == "Button3" then
            key = "MiddleButton"
        end
        if modifier and key then
            local physicalBinding = localMouse[modifier .. key]
            local nativeType = binding.type
            local interactionType = _G.Enum
                and _G.Enum.ClickBindingType
                and _G.Enum.ClickBindingType.Interaction
            local targetAction = _G.Enum
                and _G.Enum.ClickBindingInteraction
                and _G.Enum.ClickBindingInteraction.Target
            local menuAction = _G.Enum
                and _G.Enum.ClickBindingInteraction
                and _G.Enum.ClickBindingInteraction.OpenContextMenu
            local effectiveBinding = physicalBinding
            if nativeType == interactionType then
                local effectiveKey
                if type(_G.C_ClickBindings.GetEffectiveInteractionButton)
                    == "function"
                then
                    effectiveKey = _G.C_ClickBindings
                        .GetEffectiveInteractionButton(
                            binding.button,
                            binding.modifiers
                        )
                end
                if effectiveKey == "Button1" then
                    effectiveKey = "LeftButton"
                elseif effectiveKey == "Button2" then
                    effectiveKey = "RightButton"
                elseif effectiveKey == "Button3" then
                    effectiveKey = "MiddleButton"
                end
                effectiveKey = effectiveKey
                    or binding.actionID == targetAction
                    and "LeftButton"
                    or binding.actionID == menuAction
                    and "RightButton"
                effectiveBinding = effectiveKey
                    and localMouse[modifier .. effectiveKey]
            end

            local expectedAction = binding.actionID == targetAction
                and "target"
                or binding.actionID == menuAction
                and "togglemenu"
            local cooperativeInteraction = nativeType == interactionType
                and effectiveBinding
                and effectiveBinding[2] == expectedAction
            local physicalIsRemapped = physicalBinding
                and physicalBinding ~= effectiveBinding
            if physicalIsRemapped
                or effectiveBinding and not cooperativeInteraction
                or physicalBinding and nativeType ~= interactionType
            then
                conflicts[#conflicts + 1] = {
                    localBinding = effectiveBinding or physicalBinding,
                    physicalBinding = physicalBinding,
                    nativeBinding = binding,
                }
            end
        end
    end
    return conflicts
end

AF.RegisterCallback("BFI_UpdateModule", function(_, module)
    if module and module ~= "clickCastings" then return end
    UpdateAll()
end)
