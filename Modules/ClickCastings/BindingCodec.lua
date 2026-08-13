---@type BFI
local BFI = select(2, ...)
---@class ClickCastings
local CC = BFI.modules.ClickCastings

local mouseButtons = {
    LeftButton = 1,
    RightButton = 2,
    MiddleButton = 3,
    BUTTON1 = 1,
    BUTTON2 = 2,
    BUTTON3 = 3,
}

for index = 4, 31 do
    mouseButtons["Button" .. index] = index
    mouseButtons["BUTTON" .. index] = index
end

local modifierOrder = {"ALT", "CTRL", "SHIFT"}

local function NormalizeModifierTable(modifiers)
    local normalized = {}
    if type(modifiers) == "string" then
        for modifier in modifiers:gmatch("([^-]+)") do
            normalized[modifier:upper()] = true
        end
    elseif type(modifiers) == "table" then
        for modifier, enabled in pairs(modifiers) do
            if type(modifier) == "number" then
                normalized[tostring(enabled):upper()] = true
            elseif enabled then
                normalized[tostring(modifier):upper()] = true
            end
        end
    end
    return normalized
end

function CC.NormalizeModifiers(modifiers)
    modifiers = NormalizeModifierTable(modifiers)
    local parts = {}
    for _, modifier in ipairs(modifierOrder) do
        if modifiers[modifier] then
            parts[#parts + 1] = modifier:lower()
        end
    end
    return #parts > 0 and table.concat(parts, "-") .. "-" or ""
end

local function NormalizeKey(key)
    if type(key) ~= "string" or key == "" then return end
    if key == "MouseWheelUp" then return "MOUSEWHEELUP" end
    if key == "MouseWheelDown" then return "MOUSEWHEELDOWN" end
    return key:upper()
end

function CC.EncodeChord(modifiers, key)
    local prefix = CC.NormalizeModifiers(modifiers)
    local button = mouseButtons[key]
    if button then
        return prefix .. "type" .. button
    end

    key = NormalizeKey(key)
    if not key then return end
    local virtualButton = prefix:gsub("%-", "") .. key
    return "type-" .. virtualButton
end

function CC.EncodeBinding(binding)
    if type(binding) ~= "table" then return end
    return CC.EncodeChord(binding, binding.key)
end

function CC.DecodeAttribute(attribute)
    if type(attribute) ~= "string" then return end

    local prefix, button = attribute:match("^(.-)type(%d+)$")
    if button then
        local number = tonumber(button)
        local key
        if number == 1 then
            key = "LeftButton"
        elseif number == 2 then
            key = "RightButton"
        elseif number == 3 then
            key = "MiddleButton"
        elseif number and number <= 31 then
            key = "Button" .. number
        end
        if not key then return end
        return prefix, key, false
    end

    local virtualButton = attribute:match("^type%-(.+)$")
    if not virtualButton then return end
    local modifiers = ""
    local remaining = virtualButton
    for _, modifier in ipairs(modifierOrder) do
        local lower = modifier:lower()
        if remaining:sub(1, #lower) == lower then
            modifiers = modifiers .. lower .. "-"
            remaining = remaining:sub(#lower + 1)
        end
    end
    if remaining == "SCROLLUP" then
        remaining = "MouseWheelUp"
    elseif remaining == "SCROLLDOWN" then
        remaining = "MouseWheelDown"
    end
    if remaining == "" then return end
    return modifiers, remaining, true
end

function CC.DecodeBinding(attribute)
    local modifiers, key = CC.DecodeAttribute(attribute)
    if not modifiers then return end

    local binding = {key = key}
    if key == "LeftButton" then
        binding.key = "BUTTON1"
    elseif key == "RightButton" then
        binding.key = "BUTTON2"
    elseif key == "MiddleButton" then
        binding.key = "BUTTON3"
    elseif key:match("^Button%d+$") then
        binding.key = key:upper()
    end
    binding.alt = modifiers:find("alt%-", 1, false) ~= nil
    binding.ctrl = modifiers:find("ctrl%-", 1, false) ~= nil
    binding.shift = modifiers:find("shift%-", 1, false) ~= nil
    return binding
end

function CC.GetAttributeForPayload(typeAttribute, actionType)
    local attributeType = actionType == "custom" and "macrotext"
        or actionType
    return typeAttribute:gsub("type", attributeType, 1)
end

function CC.GetClickButtonAttribute(typeAttribute)
    return typeAttribute:gsub("type", "clickbutton", 1)
end

function CC.IsProxyAction(typeAttribute, actionType)
    return actionType == "target" or actionType == "togglemenu"
end

local function QuoteSecure(value)
    return string.format("%q", value)
end

local payloadActions = {
    spell = true,
    macro = true,
    custom = true,
    item = true,
}

function CC.Compile(config)
    local compiled = {
        actions = {},
        hover = {},
    }
    if type(config) ~= "table" or not config.enabled then
        compiled.actions = {
            {
                sourceAttribute = "type1",
                typeAttribute = "type1",
                actionType = "target",
                useProxy = false,
            },
            {
                sourceAttribute = "type2",
                typeAttribute = "type2",
                actionType = "togglemenu",
                useProxy = false,
            },
        }
        compiled.snippet = ""
        return compiled
    end

    local seen = {}
    for _, binding in ipairs(config.bindings or {}) do
        local typeAttribute = binding[1]
        local hasPayload = not payloadActions[binding[2]]
            or binding[3] ~= nil and binding[3] ~= ""
        if hasPayload and not seen[typeAttribute] then
            local modifiers, key, isHover = CC.DecodeAttribute(typeAttribute)
            if modifiers then
                seen[typeAttribute] = true
                local runtimeAttribute = typeAttribute
                local virtualButton
                if isHover then
                    virtualButton = "BFI_CC_" .. (#compiled.actions + 1)
                    runtimeAttribute = "*type-" .. virtualButton
                end
                compiled.actions[#compiled.actions + 1] = {
                    sourceAttribute = typeAttribute,
                    typeAttribute = runtimeAttribute,
                    actionType = binding[2],
                    payload = binding[3],
                    useProxy = CC.IsProxyAction(typeAttribute, binding[2]),
                }
                if isHover then
                    local bindingKey = modifiers:upper()
                        .. (key == "MouseWheelUp" and "MOUSEWHEELUP"
                            or key == "MouseWheelDown" and "MOUSEWHEELDOWN"
                            or key:upper())
                    compiled.hover[#compiled.hover + 1] = {
                        key = bindingKey,
                        button = virtualButton,
                    }
                end
            end
        end
    end

    local snippet = {}
    for _, hover in ipairs(compiled.hover) do
        snippet[#snippet + 1] = "self:SetBindingClick(true, "
            .. QuoteSecure(hover.key) .. ", self, "
            .. QuoteSecure(hover.button) .. ")"
    end
    compiled.snippet = table.concat(snippet, "\n")
    return compiled
end
