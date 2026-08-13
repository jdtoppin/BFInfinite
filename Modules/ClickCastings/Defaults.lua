---@type BFI
local BFI = select(2, ...)
---@class ClickCastings
local CC = BFI.modules.ClickCastings
---@type AbstractFramework
local AF = _G.AbstractFramework

local classDefaults = {
    enabled = true,
    smartResurrection = "disabled",
    preferMassResurrection = true,
    bindings = {
        {"type1", "target"},
        {"type2", "togglemenu"},
    },
}

local defaults = {
    schemaVersion = 2,
    classes = {},
}

local validActionTypes = {
    target = true,
    togglemenu = true,
    focus = true,
    assist = true,
    spell = true,
    macro = true,
    custom = true,
    item = true,
}

local payloadTypes = {
    spell = {number = true, string = true},
    macro = {number = true, string = true},
    custom = {string = true},
    item = {number = true, string = true},
}

local function NormalizeBinding(binding)
    if type(binding) ~= "table"
        or type(binding[1]) ~= "string"
        or not validActionTypes[binding[2]]
    then
        return
    end

    local payloadKinds = payloadTypes[binding[2]]
    if payloadKinds and not payloadKinds[type(binding[3])] then
        return
    end

    if not payloadKinds and binding[3] ~= nil then
        return
    end

    local decoded = CC.DecodeBinding(binding[1])
    decoded = decoded and AF.NormalizeBinding(decoded)
    local attribute = decoded and CC.EncodeBinding(decoded)
    if not attribute or attribute ~= binding[1] then return end

    return {attribute, binding[2], binding[3]}
end

local function NormalizeClassConfig(config)
    if type(config) ~= "table" then
        return AF.Copy(classDefaults)
    end

    if type(config.enabled) ~= "boolean" then
        config.enabled = classDefaults.enabled
    end
    if config.smartResurrection ~= "disabled"
        and config.smartResurrection ~= "normal"
        and config.smartResurrection ~= "normal+combat"
    then
        config.smartResurrection = classDefaults.smartResurrection
    end
    if type(config.preferMassResurrection) ~= "boolean" then
        config.preferMassResurrection = classDefaults.preferMassResurrection
    end

    if config.bindings == nil then
        config.bindings = AF.Copy(classDefaults.bindings)
    elseif type(config.bindings) ~= "table" then
        config.bindings = {}
    else
        local normalized = {}
        local seen = {}
        for _, binding in ipairs(config.bindings) do
            local valid = NormalizeBinding(binding)
            if valid and not seen[valid[1]] then
                normalized[#normalized + 1] = valid
                seen[valid[1]] = true
            end
        end
        config.bindings = normalized
    end

    return config
end

function CC.NormalizeConfig(config)
    if type(config) ~= "table" then config = AF.Copy(defaults) end
    config.schemaVersion = defaults.schemaVersion
    if type(config.classes) ~= "table" then config.classes = {} end

    for class, classConfig in pairs(config.classes) do
        if type(class) == "string" then
            config.classes[class] = NormalizeClassConfig(classConfig)
        else
            config.classes[class] = nil
        end
    end

    local playerClass = AF.player.class
    config.classes[playerClass] = NormalizeClassConfig(
        config.classes[playerClass]
    )
    return config
end

function CC.GetActiveConfig()
    return CC.config and CC.config.classes[AF.player.class]
end

function CC.SyncActiveConfig()
    if not CC.config then return end

    local classConfig = type(CC.config.classes) == "table"
        and CC.config.classes[AF.player.class]
    if classConfig ~= CC.activeConfig then
        CC.config = CC.NormalizeConfig(CC.config)
        CC.activeConfig = CC.GetActiveConfig()
    end
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    profile.clickCastings = CC.NormalizeConfig(profile.clickCastings)
    CC.config = profile.clickCastings
    CC.activeConfig = CC.GetActiveConfig()
end)

-- Module copying replaces the class map while retaining the profile module's
-- outer table. Refresh the nested active pointer before the runtime callback.
AF.RegisterCallback("BFI_UpdateModule", function(_, module)
    if module and module ~= "clickCastings" then return end
    CC.SyncActiveConfig()
end, "high")

function CC.GetDefaults()
    return AF.Copy(defaults)
end

function CC.ResetToDefaults()
    CC.config.classes[AF.player.class] = AF.Copy(classDefaults)
    CC.activeConfig = CC.config.classes[AF.player.class]
end
