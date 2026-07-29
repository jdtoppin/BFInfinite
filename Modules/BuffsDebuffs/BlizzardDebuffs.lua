---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local InCombatLockdown = InCombatLockdown
local max = math.max
local min = math.min
local tonumber = tonumber
local type = type
local unpack = unpack

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) keeps the upper-right
-- DebuffFrame on the legacy Blizzard_BuffFrame implementation. Its fixed
-- ordinary Button pool is parented to DebuffFrame.AuraContainer, while private
-- aura anchors are direct DebuffFrame children and DeadlyDebuffFrame is
-- separate. Style only static regions on that ordinary pool. Never inspect
-- aura data, visibility, buttonInfo, or aura-driven state.
local MAX_NATIVE_ICON_SIZE = 30
local ICON_CROP_MIN = 0.08
local ICON_CROP_MAX = 0.92

local snapshots = setmetatable({}, {__mode = "k"})
local cachedTarget
local styleState = {
    active = false,
    styledButtonCount = 0,
    snapshotsCreated = 0,
}

local REQUIRED_ICON_METHODS = {
    "GetHeight",
    "GetTexCoord",
    "GetWidth",
    "SetSize",
    "SetTexCoord",
}

local REQUIRED_BORDER_METHODS = {
    "GetHeight",
    "GetWidth",
    "SetSize",
}

local REQUIRED_COUNT_METHODS = {
    "ClearAllPoints",
    "GetAlpha",
    "GetFont",
    "GetJustifyH",
    "GetJustifyV",
    "GetNumPoints",
    "GetPoint",
    "GetShadowColor",
    "GetShadowOffset",
    "GetTextColor",
    "SetAlpha",
    "SetFont",
    "SetJustifyH",
    "SetJustifyV",
    "SetPoint",
    "SetShadowColor",
    "SetShadowOffset",
    "SetTextColor",
}

local REQUIRED_DURATION_METHODS = {
    "GetAlpha",
    "SetAlpha",
}

local function HasMethods(object, methods)
    if not object then return false end
    for _, method in ipairs(methods) do
        if type(object[method]) ~= "function" then
            return false
        end
    end
    return true
end

local function IsStaticDebuffButton(button, container)
    return button
        and type(button.GetParent) == "function"
        and button:GetParent() == container
        and HasMethods(button.Icon, REQUIRED_ICON_METHODS)
        and HasMethods(button.DebuffBorder, REQUIRED_BORDER_METHODS)
        and HasMethods(button.Count, REQUIRED_COUNT_METHODS)
        and HasMethods(button.Duration, REQUIRED_DURATION_METHODS)
end

local function ResolveTarget()
    if cachedTarget then return cachedTarget end
    if InCombatLockdown() then return end

    local frame = _G.DebuffFrame
    local container = frame and frame.AuraContainer
    local privateAnchors = frame and frame.PrivateAuraAnchors
    local deadlyFrame = _G.DeadlyDebuffFrame
    if not frame
        or not container
        or type(container.GetParent) ~= "function"
        or container:GetParent() ~= frame
        or type(frame.auraFrames) ~= "table"
        or type(frame.UpdateAuraButtons) ~= "function"
        or type(container.UpdateGridLayout) ~= "function"
        or type(privateAnchors) ~= "table"
        or #privateAnchors == 0
        or not deadlyFrame
        or deadlyFrame == frame
        or deadlyFrame == container
    then
        return
    end

    for _, anchor in ipairs(privateAnchors) do
        if not anchor
            or type(anchor.GetParent) ~= "function"
            or anchor:GetParent() ~= frame
        then
            return
        end
    end

    local expectedButtonCount = tonumber(frame.maxAuras)
    if not expectedButtonCount
        or expectedButtonCount < 1
    then
        return
    end

    local buttons = {}
    for index = 1, expectedButtonCount do
        local button = frame.auraFrames[index]
        if not IsStaticDebuffButton(button, container) then
            return
        end
        buttons[index] = button
    end

    cachedTarget = {
        frame = frame,
        container = container,
        buttons = buttons,
    }
    return cachedTarget
end

local function CopyPoints(region)
    local points = {}
    for index = 1, region:GetNumPoints() do
        points[index] = {region:GetPoint(index)}
    end
    return points
end

local function SnapshotButton(button)
    local snapshot = snapshots[button]
    if snapshot then return snapshot end

    snapshot = {
        iconWidth = button.Icon:GetWidth(),
        iconHeight = button.Icon:GetHeight(),
        iconTexCoord = {button.Icon:GetTexCoord()},
        borderWidth = button.DebuffBorder:GetWidth(),
        borderHeight = button.DebuffBorder:GetHeight(),
        countFont = {button.Count:GetFont()},
        countPoints = CopyPoints(button.Count),
        countTextColor = {button.Count:GetTextColor()},
        countShadowColor = {button.Count:GetShadowColor()},
        countShadowOffset = {button.Count:GetShadowOffset()},
        countJustifyH = button.Count:GetJustifyH(),
        countJustifyV = button.Count:GetJustifyV(),
        countAlpha = button.Count:GetAlpha(),
        durationAlpha = button.Duration:GetAlpha(),
    }
    snapshots[button] = snapshot
    styleState.snapshotsCreated = styleState.snapshotsCreated + 1
    return snapshot
end

local function SetTextJustification(region, point)
    if point:find("LEFT$") then
        region:SetJustifyH("LEFT")
    elseif point:find("RIGHT$") then
        region:SetJustifyH("RIGHT")
    else
        region:SetJustifyH("CENTER")
    end

    if point:find("^TOP") then
        region:SetJustifyV("TOP")
    elseif point:find("^BOTTOM") then
        region:SetJustifyV("BOTTOM")
    else
        region:SetJustifyV("MIDDLE")
    end
end

local function ApplyTextPosition(region, position, relativeTo)
    region:ClearAllPoints()
    region:SetPoint(
        position[1],
        relativeTo,
        position[2],
        position[3],
        position[4]
    )
    SetTextJustification(region, position[1])
end

local function ClampIconSize(value)
    value = tonumber(value) or MAX_NATIVE_ICON_SIZE
    return max(10, min(MAX_NATIVE_ICON_SIZE, value))
end

local function ApplyButtonStyle(button, config)
    SnapshotButton(button)

    local width = ClampIconSize(config.width)
    local height = ClampIconSize(config.height)
    button.Icon:SetSize(width, height)
    button.Icon:SetTexCoord(
        ICON_CROP_MIN,
        ICON_CROP_MAX,
        ICON_CROP_MIN,
        ICON_CROP_MAX
    )
    button.DebuffBorder:SetSize(width + 10, height + 10)

    local stack = config.stack
    AF.SetFont(button.Count, unpack(stack.font))
    ApplyTextPosition(button.Count, stack.position, button)
    button.Count:SetTextColor(unpack(stack.color))
    button.Count:SetAlpha(stack.enabled and 1 or 0)

    -- Blizzard owns the duration value, abbreviation, font, colour, and
    -- anchoring. Alpha is static presentation and is not rewritten by its
    -- aura update path, so visibility is the only supported duration control.
    button.Duration:SetAlpha(config.duration.enabled and 1 or 0)
end

local function RestoreButton(button)
    local snapshot = snapshots[button]
    if not snapshot then return end

    button.Icon:SetSize(snapshot.iconWidth, snapshot.iconHeight)
    button.Icon:SetTexCoord(unpack(snapshot.iconTexCoord))
    button.DebuffBorder:SetSize(
        snapshot.borderWidth,
        snapshot.borderHeight
    )

    button.Count:SetFont(unpack(snapshot.countFont))
    button.Count:ClearAllPoints()
    for _, point in ipairs(snapshot.countPoints) do
        button.Count:SetPoint(unpack(point))
    end
    button.Count:SetTextColor(unpack(snapshot.countTextColor))
    button.Count:SetShadowColor(unpack(snapshot.countShadowColor))
    button.Count:SetShadowOffset(unpack(snapshot.countShadowOffset))
    button.Count:SetJustifyH(snapshot.countJustifyH)
    button.Count:SetJustifyV(snapshot.countJustifyV)
    button.Count:SetAlpha(snapshot.countAlpha)
    button.Duration:SetAlpha(snapshot.durationAlpha)
end

local function RestoreTarget(target)
    if not target then return true end
    for _, button in ipairs(target.buttons) do
        RestoreButton(button)
    end
    styleState.active = false
    styleState.styledButtonCount = 0
    return true
end

function BD.HasBlizzardDebuffStyleCapability()
    return ResolveTarget() ~= nil
        and type(AF.SetFont) == "function"
end

function BD.UpdateBlizzardDebuffStyle(config)
    if InCombatLockdown() then return false end
    local target = ResolveTarget()
    if not target or type(config) ~= "table" then return false end

    if config.enabled ~= true then
        return RestoreTarget(target)
    end

    for _, button in ipairs(target.buttons) do
        ApplyButtonStyle(button, config)
    end
    styleState.active = true
    styleState.styledButtonCount = #target.buttons
    return true
end

function BD.DisableBlizzardDebuffStyle()
    if InCombatLockdown() then return false end
    return RestoreTarget(cachedTarget)
end

function BD.GetBlizzardDebuffStyleState()
    return {
        active = styleState.active,
        styledButtonCount = styleState.styledButtonCount,
        snapshotsCreated = styleState.snapshotsCreated,
    }
end
