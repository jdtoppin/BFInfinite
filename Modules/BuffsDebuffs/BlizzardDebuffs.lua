---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local IsValueNonSecret = BFI.funcs.isValueNonSecret
local InCombatLockdown = InCombatLockdown
local max = math.max
local min = math.min
local rawequal = rawequal
local type = type

-- Retail 12.1.0.69273 (wow-ui-source
-- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) keeps DebuffFrame on
-- Blizzard_BuffFrame. DebuffFrame.AuraContainer owns a fixed pool of 16
-- ordinary Buttons; private anchors remain direct DebuffFrame children and
-- DeadlyDebuffFrame remains separate. Aura identity, visibility, child
-- enumeration, and Blizzard update methods are deliberately outside this
-- adapter's boundary.
--
-- Script-object access and the geometry/texture/font getters used below can
-- be secret. Every operation therefore builds all 16 temporary snapshots,
-- then resolves and access-checks the complete topology a second time before
-- its first setter. WoW offers no transaction across the later protected
-- setters; this provides an atomic read/snapshot boundary without claiming a
-- setter transaction.
local EXPECTED_DEBUFF_BUTTON_COUNT = 16
local MAX_NATIVE_ICON_SIZE = 30
local MAX_SNAPSHOT_POINTS = 8
local ICON_CROP_MIN = 0.08
local ICON_CROP_MAX = 0.92

local VALID_ANCHORS = {
    BOTTOM = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    TOPLEFT = true,
    TOPRIGHT = true,
}

local VALID_FONT_OUTLINES = {
    monochrome = true,
    monochrome_outline = true,
    monochrome_thickoutline = true,
    none = true,
    outline = true,
    thickoutline = true,
}

local HORIZONTAL_JUSTIFICATION = {
    BOTTOM = "CENTER",
    BOTTOMLEFT = "LEFT",
    BOTTOMRIGHT = "RIGHT",
    CENTER = "CENTER",
    LEFT = "LEFT",
    RIGHT = "RIGHT",
    TOP = "CENTER",
    TOPLEFT = "LEFT",
    TOPRIGHT = "RIGHT",
}

local VERTICAL_JUSTIFICATION = {
    BOTTOM = "BOTTOM",
    BOTTOMLEFT = "BOTTOM",
    BOTTOMRIGHT = "BOTTOM",
    CENTER = "MIDDLE",
    LEFT = "MIDDLE",
    RIGHT = "MIDDLE",
    TOP = "TOP",
    TOPLEFT = "TOP",
    TOPRIGHT = "TOP",
}

local REQUIRED_FRAME_METHODS = {
    "UpdateAuraButtons",
}

local REQUIRED_CONTAINER_METHODS = {
    "GetParent",
    "UpdateGridLayout",
}

local REQUIRED_BUTTON_METHODS = {
    "GetParent",
}

local REQUIRED_ICON_METHODS = {
    "GetHeight",
    "GetParent",
    "GetTexCoord",
    "GetWidth",
    "SetSize",
    "SetTexCoord",
}

local REQUIRED_BORDER_METHODS = {
    "GetAlpha",
    "GetHeight",
    "GetParent",
    "GetWidth",
    "SetAlpha",
    "SetSize",
}

local REQUIRED_COUNT_METHODS = {
    "ClearAllPoints",
    "GetAlpha",
    "GetFont",
    "GetJustifyH",
    "GetJustifyV",
    "GetNumPoints",
    "GetParent",
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
    "GetParent",
    "SetAlpha",
}

local activeTarget
local styleState = {
    active = false,
    snapshotsCreated = 0,
    styledButtonCount = 0,
}

local function IsOrdinaryTable(value)
    if not IsValueNonSecret(value) then return false end
    return type(value) == "table"
end

local function IsOrdinaryBoolean(value)
    if not IsValueNonSecret(value) then return false end
    return type(value) == "boolean"
end

local function IsOrdinaryString(value)
    if not IsValueNonSecret(value) then return false end
    return type(value) == "string"
end

local function IsFiniteNumber(value)
    if not IsValueNonSecret(value) then return false end
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsUnitInterval(value)
    return IsFiniteNumber(value) and value >= 0 and value <= 1
end

local function IsObjectAccessible(object)
    if not IsValueNonSecret(object) then return false end
    local objectType = type(object)
    if objectType ~= "table" and objectType ~= "userdata" then
        return false
    end

    local canBeAccessed = object.CanBeAccessedInContext
    if not IsValueNonSecret(canBeAccessed)
        or type(canBeAccessed) ~= "function"
    then
        return false
    end

    local accessible = canBeAccessed(object)
    if not IsValueNonSecret(accessible)
        or type(accessible) ~= "boolean"
    then
        return false
    end
    return accessible == true
end

local function HasOrdinaryMethods(object, methods)
    for index = 1, #methods do
        local method = object[methods[index]]
        if not IsValueNonSecret(method) or type(method) ~= "function" then
            return false
        end
    end
    return true
end

local function GetSetFont()
    if not IsOrdinaryTable(AF) then return false end
    local setFont = AF.SetFont
    if not IsValueNonSecret(setFont) or type(setFont) ~= "function" then
        return
    end
    return setFont
end

local function IsCurrentSetFont(setFont)
    local current = GetSetFont()
    return current ~= nil and rawequal(current, setFont)
end

local function IsOutOfCombat()
    local locked = InCombatLockdown()
    return IsOrdinaryBoolean(locked) and locked == false
end

local function MarkUnique(seen, object)
    if seen[object] then return false end
    seen[object] = true
    return true
end

local function HasExpectedParent(object, expected)
    local parent = object:GetParent()
    if not IsValueNonSecret(parent) then return false end
    if not rawequal(parent, expected) then return false end
    return IsObjectAccessible(parent)
end

local function ResolveTopology()
    local frame = _G.DebuffFrame
    if not IsObjectAccessible(frame)
        or not HasOrdinaryMethods(frame, REQUIRED_FRAME_METHODS)
    then
        return
    end

    local seen = {}
    if not MarkUnique(seen, frame) then return end

    local container = frame.AuraContainer
    if not IsObjectAccessible(container)
        or not MarkUnique(seen, container)
        or not HasOrdinaryMethods(container, REQUIRED_CONTAINER_METHODS)
        or not HasExpectedParent(container, frame)
    then
        return
    end

    local auraFrames = frame.auraFrames
    if not IsOrdinaryTable(auraFrames) then return end

    local maxAuras = frame.maxAuras
    if not IsFiniteNumber(maxAuras)
        or maxAuras ~= EXPECTED_DEBUFF_BUTTON_COUNT
    then
        return
    end

    local target = {
        buttons = {},
        container = container,
        frame = frame,
    }

    for index = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local button = auraFrames[index]
        if not IsObjectAccessible(button)
            or not MarkUnique(seen, button)
            or not HasOrdinaryMethods(button, REQUIRED_BUTTON_METHODS)
            or not HasExpectedParent(button, container)
        then
            return
        end

        local icon = button.Icon
        if not IsObjectAccessible(icon)
            or not MarkUnique(seen, icon)
            or not HasOrdinaryMethods(icon, REQUIRED_ICON_METHODS)
            or not HasExpectedParent(icon, button)
        then
            return
        end

        local border = button.DebuffBorder
        if not IsObjectAccessible(border)
            or not MarkUnique(seen, border)
            or not HasOrdinaryMethods(border, REQUIRED_BORDER_METHODS)
            or not HasExpectedParent(border, button)
        then
            return
        end

        local count = button.Count
        if not IsObjectAccessible(count)
            or not MarkUnique(seen, count)
            or not HasOrdinaryMethods(count, REQUIRED_COUNT_METHODS)
            or not HasExpectedParent(count, button)
        then
            return
        end

        local duration = button.Duration
        if not IsObjectAccessible(duration)
            or not MarkUnique(seen, duration)
            or not HasOrdinaryMethods(duration, REQUIRED_DURATION_METHODS)
            or not HasExpectedParent(duration, button)
        then
            return
        end

        target.buttons[index] = {
            border = border,
            button = button,
            count = count,
            duration = duration,
            icon = icon,
        }
    end

    return target
end

local function ReadColor(getter, object)
    local red, green, blue, alpha = getter(object)
    if not IsUnitInterval(red)
        or not IsUnitInterval(green)
        or not IsUnitInterval(blue)
        or not IsUnitInterval(alpha)
    then
        return
    end
    return {
        alpha = alpha,
        blue = blue,
        green = green,
        red = red,
    }
end

local function IsAllowedPointRelative(entry, relativeTo)
    if not IsValueNonSecret(relativeTo) then return false end
    if relativeTo == nil then return true end
    if not rawequal(relativeTo, entry.button)
        and not rawequal(relativeTo, entry.icon)
    then
        return false
    end
    return IsObjectAccessible(relativeTo)
end

local function SnapshotPoints(entry)
    local count = entry.count
    local numPoints = count:GetNumPoints()
    if not IsFiniteNumber(numPoints)
        or numPoints % 1 ~= 0
        or numPoints < 0
        or numPoints > MAX_SNAPSHOT_POINTS
    then
        return
    end

    local points = {}
    for index = 1, numPoints do
        local point, relativeTo, relativePoint, offsetX, offsetY =
            count:GetPoint(index)
        if not IsOrdinaryString(point)
            or not VALID_ANCHORS[point]
            or not IsAllowedPointRelative(entry, relativeTo)
            or not IsOrdinaryString(relativePoint)
            or not VALID_ANCHORS[relativePoint]
            or not IsFiniteNumber(offsetX)
            or not IsFiniteNumber(offsetY)
        then
            return
        end

        points[index] = {
            offsetX = offsetX,
            offsetY = offsetY,
            point = point,
            relativePoint = relativePoint,
            relativeTo = relativeTo,
        }
    end
    return points, numPoints
end

local function SnapshotButton(entry)
    local iconWidth = entry.icon:GetWidth()
    local iconHeight = entry.icon:GetHeight()
    if not IsFiniteNumber(iconWidth)
        or iconWidth < 0
        or not IsFiniteNumber(iconHeight)
        or iconHeight < 0
    then
        return
    end

    local upperLeftX, upperLeftY, lowerLeftX, lowerLeftY,
        upperRightX, upperRightY, lowerRightX, lowerRightY =
        entry.icon:GetTexCoord()
    if not IsFiniteNumber(upperLeftX)
        or not IsFiniteNumber(upperLeftY)
        or not IsFiniteNumber(lowerLeftX)
        or not IsFiniteNumber(lowerLeftY)
        or not IsFiniteNumber(upperRightX)
        or not IsFiniteNumber(upperRightY)
        or not IsFiniteNumber(lowerRightX)
        or not IsFiniteNumber(lowerRightY)
    then
        return
    end

    local borderWidth = entry.border:GetWidth()
    local borderHeight = entry.border:GetHeight()
    local borderAlpha = entry.border:GetAlpha()
    if not IsFiniteNumber(borderWidth)
        or borderWidth < 0
        or not IsFiniteNumber(borderHeight)
        or borderHeight < 0
        or not IsUnitInterval(borderAlpha)
    then
        return
    end

    local fontPath, fontSize, fontFlags = entry.count:GetFont()
    if not IsOrdinaryString(fontPath)
        or fontPath == ""
        or not IsFiniteNumber(fontSize)
        or fontSize <= 0
        or not IsOrdinaryString(fontFlags)
    then
        return
    end

    local countPoints, countPointCount = SnapshotPoints(entry)
    if not IsOrdinaryTable(countPoints)
        or not IsFiniteNumber(countPointCount)
    then
        return
    end

    local textColor = ReadColor(entry.count.GetTextColor, entry.count)
    local shadowColor = ReadColor(
        entry.count.GetShadowColor,
        entry.count
    )
    if not IsOrdinaryTable(textColor)
        or not IsOrdinaryTable(shadowColor)
    then
        return
    end

    local shadowOffsetX, shadowOffsetY = entry.count:GetShadowOffset()
    if not IsFiniteNumber(shadowOffsetX)
        or not IsFiniteNumber(shadowOffsetY)
    then
        return
    end

    local justifyH = entry.count:GetJustifyH()
    local justifyV = entry.count:GetJustifyV()
    if not IsOrdinaryString(justifyH)
        or (justifyH ~= "LEFT"
            and justifyH ~= "CENTER"
            and justifyH ~= "RIGHT")
        or not IsOrdinaryString(justifyV)
        or (justifyV ~= "TOP"
            and justifyV ~= "MIDDLE"
            and justifyV ~= "BOTTOM")
    then
        return
    end

    local countAlpha = entry.count:GetAlpha()
    local durationAlpha = entry.duration:GetAlpha()
    if not IsUnitInterval(countAlpha)
        or not IsUnitInterval(durationAlpha)
    then
        return
    end

    return {
        border = {
            alpha = borderAlpha,
            height = borderHeight,
            width = borderWidth,
        },
        count = {
            alpha = countAlpha,
            fontFlags = fontFlags,
            fontPath = fontPath,
            fontSize = fontSize,
            justifyH = justifyH,
            justifyV = justifyV,
            pointCount = countPointCount,
            points = countPoints,
            shadowColor = shadowColor,
            shadowOffsetX = shadowOffsetX,
            shadowOffsetY = shadowOffsetY,
            textColor = textColor,
        },
        duration = {
            alpha = durationAlpha,
        },
        icon = {
            height = iconHeight,
            lowerLeftX = lowerLeftX,
            lowerLeftY = lowerLeftY,
            lowerRightX = lowerRightX,
            lowerRightY = lowerRightY,
            upperLeftX = upperLeftX,
            upperLeftY = upperLeftY,
            upperRightX = upperRightX,
            upperRightY = upperRightY,
            width = iconWidth,
        },
    }
end

local function BuildCandidate()
    local candidate = ResolveTopology()
    if not candidate then return end

    for index = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local snapshot = SnapshotButton(candidate.buttons[index])
        if not snapshot then return end
        candidate.buttons[index].snapshot = snapshot
    end
    return candidate
end

local function TopologyMatches(first, second)
    if not rawequal(first.frame, second.frame)
        or not rawequal(first.container, second.container)
    then
        return false
    end

    for index = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local firstEntry = first.buttons[index]
        local secondEntry = second.buttons[index]
        if not rawequal(firstEntry.button, secondEntry.button)
            or not rawequal(firstEntry.icon, secondEntry.icon)
            or not rawequal(firstEntry.border, secondEntry.border)
            or not rawequal(firstEntry.count, secondEntry.count)
            or not rawequal(firstEntry.duration, secondEntry.duration)
        then
            return false
        end
    end
    return true
end

local function StoredTargetRemainsAccessible(target)
    if not IsOrdinaryTable(target)
        or not IsObjectAccessible(target.frame)
        or not IsObjectAccessible(target.container)
        or not IsOrdinaryTable(target.buttons)
    then
        return false
    end

    for buttonIndex = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local entry = target.buttons[buttonIndex]
        if not IsOrdinaryTable(entry)
            or not IsObjectAccessible(entry.button)
            or not IsObjectAccessible(entry.icon)
            or not IsObjectAccessible(entry.border)
            or not IsObjectAccessible(entry.count)
            or not IsObjectAccessible(entry.duration)
            or not IsOrdinaryTable(entry.snapshot)
            or not IsOrdinaryTable(entry.snapshot.count)
        then
            return false
        end

        local countSnapshot = entry.snapshot.count
        if not IsFiniteNumber(countSnapshot.pointCount)
            or countSnapshot.pointCount % 1 ~= 0
            or countSnapshot.pointCount < 0
            or countSnapshot.pointCount > MAX_SNAPSHOT_POINTS
            or not IsOrdinaryTable(countSnapshot.points)
        then
            return false
        end

        for pointIndex = 1, countSnapshot.pointCount do
            local point = countSnapshot.points[pointIndex]
            if not IsOrdinaryTable(point) then return false end
            local relativeTo = point.relativeTo
            if not IsAllowedPointRelative(entry, relativeTo) then
                return false
            end
        end
    end
    return true
end

local function RevalidateCandidate(candidate, originalTarget)
    local current = ResolveTopology()
    if not current
        or not StoredTargetRemainsAccessible(candidate)
        or not TopologyMatches(candidate, current)
    then
        return false
    end
    if originalTarget then
        if not StoredTargetRemainsAccessible(originalTarget)
            or not TopologyMatches(originalTarget, current)
        then
            return false
        end
    end
    return true
end

local function CompileColor(color)
    if not IsOrdinaryTable(color) then return end
    local red = color[1]
    local green = color[2]
    local blue = color[3]
    local alpha = color[4]
    if not IsUnitInterval(red)
        or not IsUnitInterval(green)
        or not IsUnitInterval(blue)
        or not IsUnitInterval(alpha)
    then
        return
    end
    return {
        alpha = alpha,
        blue = blue,
        green = green,
        red = red,
    }
end

local function CompileStyle(config)
    if not IsOrdinaryTable(config) then return end

    local enabled = config.enabled
    if not IsOrdinaryBoolean(enabled) then return end
    if not enabled then
        return {enabled = false}
    end

    local width = config.width
    local height = config.height
    if not IsFiniteNumber(width) or not IsFiniteNumber(height) then
        return
    end
    width = max(10, min(MAX_NATIVE_ICON_SIZE, width))
    height = max(10, min(MAX_NATIVE_ICON_SIZE, height))

    local stack = config.stack
    if not IsOrdinaryTable(stack) then return end
    local stackEnabled = stack.enabled
    if not IsOrdinaryBoolean(stackEnabled) then return end

    local font = stack.font
    if not IsOrdinaryTable(font) then return end
    local fontName = font[1]
    local fontSize = font[2]
    local fontOutline = font[3]
    local fontShadow = font[4]
    if not IsOrdinaryString(fontName)
        or fontName == ""
        or not IsFiniteNumber(fontSize)
        or fontSize <= 0
        or not IsOrdinaryString(fontOutline)
        or not VALID_FONT_OUTLINES[fontOutline]
        or not IsOrdinaryBoolean(fontShadow)
    then
        return
    end

    local position = stack.position
    if not IsOrdinaryTable(position) then return end
    local point = position[1]
    local relativePoint = position[2]
    local offsetX = position[3]
    local offsetY = position[4]
    if not IsOrdinaryString(point)
        or not VALID_ANCHORS[point]
        or not IsOrdinaryString(relativePoint)
        or not VALID_ANCHORS[relativePoint]
        or not IsFiniteNumber(offsetX)
        or not IsFiniteNumber(offsetY)
    then
        return
    end

    local stackColor = CompileColor(stack.color)
    if not stackColor then return end

    local duration = config.duration
    if not IsOrdinaryTable(duration) then return end
    local durationEnabled = duration.enabled
    if not IsOrdinaryBoolean(durationEnabled) then return end

    return {
        durationEnabled = durationEnabled,
        enabled = true,
        height = height,
        stackColor = stackColor,
        stackEnabled = stackEnabled,
        stackFontName = fontName,
        stackFontOutline = fontOutline,
        stackFontShadow = fontShadow,
        stackFontSize = fontSize,
        stackJustifyH = HORIZONTAL_JUSTIFICATION[point],
        stackJustifyV = VERTICAL_JUSTIFICATION[point],
        stackOffsetX = offsetX,
        stackOffsetY = offsetY,
        stackPoint = point,
        stackRelativePoint = relativePoint,
        width = width,
    }
end

local function ApplyStyle(target, style, setFont)
    for index = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local entry = target.buttons[index]
        entry.icon:SetSize(style.width, style.height)
        entry.icon:SetTexCoord(
            ICON_CROP_MIN,
            ICON_CROP_MAX,
            ICON_CROP_MIN,
            ICON_CROP_MAX
        )

        -- Preserve Blizzard's rounded, native-coloured carrier. AuraUtil uses
        -- IgnoreAtlasSize when it refreshes this atlas, so BFInfinite owns only
        -- its static size/alpha and never reads or replaces classification.
        entry.border:SetSize(style.width + 10, style.height + 10)
        entry.border:SetAlpha(1)

        setFont(
            entry.count,
            style.stackFontName,
            style.stackFontSize,
            style.stackFontOutline,
            style.stackFontShadow
        )
        entry.count:ClearAllPoints()
        entry.count:SetPoint(
            style.stackPoint,
            entry.button,
            style.stackRelativePoint,
            style.stackOffsetX,
            style.stackOffsetY
        )
        entry.count:SetJustifyH(style.stackJustifyH)
        entry.count:SetJustifyV(style.stackJustifyV)
        entry.count:SetTextColor(
            style.stackColor.red,
            style.stackColor.green,
            style.stackColor.blue,
            style.stackColor.alpha
        )
        entry.count:SetAlpha(style.stackEnabled and 1 or 0)

        -- Blizzard continues to own the value, abbreviation, font, colour,
        -- and anchoring. Only constant presentation alpha is configurable.
        entry.duration:SetAlpha(style.durationEnabled and 1 or 0)
    end
end

local function RestoreTarget(target)
    for index = 1, EXPECTED_DEBUFF_BUTTON_COUNT do
        local entry = target.buttons[index]
        local snapshot = entry.snapshot

        entry.icon:SetSize(snapshot.icon.width, snapshot.icon.height)
        entry.icon:SetTexCoord(
            snapshot.icon.upperLeftX,
            snapshot.icon.upperLeftY,
            snapshot.icon.lowerLeftX,
            snapshot.icon.lowerLeftY,
            snapshot.icon.upperRightX,
            snapshot.icon.upperRightY,
            snapshot.icon.lowerRightX,
            snapshot.icon.lowerRightY
        )
        entry.border:SetSize(
            snapshot.border.width,
            snapshot.border.height
        )
        entry.border:SetAlpha(snapshot.border.alpha)

        entry.count:SetFont(
            snapshot.count.fontPath,
            snapshot.count.fontSize,
            snapshot.count.fontFlags
        )
        entry.count:ClearAllPoints()
        for pointIndex = 1, snapshot.count.pointCount do
            local point = snapshot.count.points[pointIndex]
            entry.count:SetPoint(
                point.point,
                point.relativeTo,
                point.relativePoint,
                point.offsetX,
                point.offsetY
            )
        end
        entry.count:SetTextColor(
            snapshot.count.textColor.red,
            snapshot.count.textColor.green,
            snapshot.count.textColor.blue,
            snapshot.count.textColor.alpha
        )
        entry.count:SetShadowColor(
            snapshot.count.shadowColor.red,
            snapshot.count.shadowColor.green,
            snapshot.count.shadowColor.blue,
            snapshot.count.shadowColor.alpha
        )
        entry.count:SetShadowOffset(
            snapshot.count.shadowOffsetX,
            snapshot.count.shadowOffsetY
        )
        entry.count:SetJustifyH(snapshot.count.justifyH)
        entry.count:SetJustifyV(snapshot.count.justifyV)
        entry.count:SetAlpha(snapshot.count.alpha)
        entry.duration:SetAlpha(snapshot.duration.alpha)
    end
end

local function RestoreActiveTarget()
    if not activeTarget then return true end

    local candidate = BuildCandidate()
    if not candidate
        or not RevalidateCandidate(candidate, activeTarget)
    then
        return false
    end
    if not IsOutOfCombat() then return false end

    RestoreTarget(activeTarget)
    activeTarget = nil
    styleState.active = false
    styleState.snapshotsCreated = 0
    styleState.styledButtonCount = 0
    return true
end

function BD.HasBlizzardDebuffStyleCapability()
    if not IsOutOfCombat() then return false end
    local setFont = GetSetFont()
    if not setFont then return false end
    local candidate = BuildCandidate()
    return candidate ~= nil
        and RevalidateCandidate(candidate)
        and IsCurrentSetFont(setFont)
        and IsOutOfCombat()
end

function BD.UpdateBlizzardDebuffStyle(config)
    if not IsOutOfCombat() then return false end
    local setFont = GetSetFont()
    if not setFont then return false end

    -- SavedVariables are fully compiled to ordinary named operands before any
    -- native object or getter is touched.
    local style = CompileStyle(config)
    if not style then return false end

    if not style.enabled then
        if activeTarget then return RestoreActiveTarget() end
        local candidate = BuildCandidate()
        return candidate ~= nil
            and RevalidateCandidate(candidate)
            and IsCurrentSetFont(setFont)
            and IsOutOfCombat()
    end

    local candidate = BuildCandidate()
    if not candidate
        or not RevalidateCandidate(candidate, activeTarget)
    then
        return false
    end
    if not IsCurrentSetFont(setFont) or not IsOutOfCombat() then
        return false
    end

    ApplyStyle(candidate, style, setFont)
    if not activeTarget then
        activeTarget = candidate
        styleState.snapshotsCreated = EXPECTED_DEBUFF_BUTTON_COUNT
    end
    styleState.active = true
    styleState.styledButtonCount = EXPECTED_DEBUFF_BUTTON_COUNT
    return true
end

function BD.DisableBlizzardDebuffStyle()
    if not IsOutOfCombat() then return false end
    return RestoreActiveTarget()
end

function BD.GetBlizzardDebuffStyleState()
    return {
        active = styleState.active,
        snapshotsCreated = styleState.snapshotsCreated,
        styledButtonCount = styleState.styledButtonCount,
    }
end
