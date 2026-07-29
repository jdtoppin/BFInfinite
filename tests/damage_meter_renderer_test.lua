local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertSame(actual, expected, message)
    if not rawequal(actual, expected) then
        error(message, 2)
    end
end

local function assertPoint(
    frame,
    index,
    point,
    relativeTo,
    relativePoint,
    x,
    y,
    message
)
    local anchor = frame.points[index]
    assertEqual(type(anchor), "table", message .. " exists")
    assertEqual(anchor.point, point, message .. " point")
    assertSame(anchor.relativeTo, relativeTo, message .. " relative frame")
    assertEqual(
        anchor.relativePoint,
        relativePoint,
        message .. " relative point"
    )
    assertEqual(anchor.x, x, message .. " x")
    assertEqual(anchor.y, y, message .. " y")
end

local function loadRenderer(initialNativeEnabled, savedRestoreEnabled)
    local state = {
        ambiguousInputs = {},
        ambiguousOutputs = {},
        available = true,
        classColorInputs = {},
        currentSessions = {},
        formatInputs = {},
        formatOutputs = {},
        frames = {},
        namedFrames = {},
        nativeEnabled = initialNativeEnabled ~= false,
        nativeOverrideState = {},
        nativeSetCalls = {},
        openOptionsCalls = {},
        timers = {},
        unsafeOperations = 0,
    }
    if type(savedRestoreEnabled) == "boolean" then
        state.nativeOverrideState.damageMeterNativeEnabledBeforeBFI =
            savedRestoreEnabled
    end

    local function unsafeOperation()
        state.unsafeOperations = state.unsafeOperations + 1
        error("opaque combat value was inspected")
    end

    local opaqueMetatable = {
        __add = unsafeOperation,
        __sub = unsafeOperation,
        __mul = unsafeOperation,
        __div = unsafeOperation,
        __mod = unsafeOperation,
        __pow = unsafeOperation,
        __unm = unsafeOperation,
        __concat = unsafeOperation,
        __lt = unsafeOperation,
        __le = unsafeOperation,
    }

    local function newOpaqueValue(label)
        return setmetatable({
            label = label,
        }, opaqueMetatable)
    end

    local frameMethods = {}

    function frameMethods:GetParent()
        return self.parent
    end

    function frameMethods:GetFrameLevel()
        return self.frameLevel
    end

    function frameMethods:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frameMethods:SetAllPoints(relativeTo)
        self.allPoints = relativeTo or true
    end

    function frameMethods:ClearAllPoints()
        self.points = {}
    end

    function frameMethods:SetPoint(
        point,
        relativeTo,
        relativePoint,
        x,
        y
    )
        self.points[#self.points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end

    function frameMethods:SetSize(width, height)
        self.width = width
        self.height = height
        if self.scripts.OnSizeChanged then
            self.scripts.OnSizeChanged(self, width, height)
        end
    end

    function frameMethods:SetWidth(width)
        self.width = width
        if self.scripts.OnSizeChanged then
            self.scripts.OnSizeChanged(self, width, self.height)
        end
    end

    function frameMethods:SetHeight(height)
        self.height = height
        if self.scripts.OnSizeChanged then
            self.scripts.OnSizeChanged(self, self.width, height)
        end
    end

    function frameMethods:GetWidth()
        return self.width
    end

    function frameMethods:GetHeight()
        return self.height
    end

    function frameMethods:GetLeft()
        return self.left
    end

    function frameMethods:GetBottom()
        return self.bottom
    end

    function frameMethods:GetCenter()
        return self.centerX, self.centerY
    end

    function frameMethods:GetEffectiveScale()
        return self.effectiveScale or 1
    end

    function frameMethods:SetShown(shown)
        self.shown = shown == true
    end

    function frameMethods:Show()
        self.shown = true
    end

    function frameMethods:Hide()
        self.shown = false
    end

    function frameMethods:IsShown()
        return self.shown
    end

    function frameMethods:SetClampedToScreen(clamped)
        self.clamped = clamped
    end

    function frameMethods:SetMovable(movable)
        self.movable = movable
    end

    function frameMethods:SetResizable(resizable)
        self.resizable = resizable
    end

    function frameMethods:SetFrameStrata(strata)
        self.strata = strata
    end

    function frameMethods:SetBackdropColor(r, g, b, a)
        self.backdropColor = {
            r = r,
            g = g,
            b = b,
            a = a,
        }
    end

    function frameMethods:SetBackdropBorderColor(r, g, b, a)
        self.borderColor = {
            r = r,
            g = g,
            b = b,
            a = a,
        }
    end

    function frameMethods:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function frameMethods:RegisterForDrag(button)
        self.dragButton = button
    end

    function frameMethods:SetScript(scriptName, callback)
        self.scripts[scriptName] = callback
    end

    function frameMethods:GetScript(scriptName)
        return self.scripts[scriptName]
    end

    function frameMethods:HookScript(scriptName, callback)
        local previous = self.scripts[scriptName]
        self.scripts[scriptName] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end

    function frameMethods:RunScript(scriptName, ...)
        local callback = self.scripts[scriptName]
        if callback then
            callback(self, ...)
        end
    end

    function frameMethods:IsMouseOver()
        return self.mouseOver == true
    end

    function frameMethods:RegisterEvent(event)
        self.events[event] = true
    end

    function frameMethods:UnregisterAllEvents()
        self.events = {}
    end

    function frameMethods:StartMoving()
        self.moving = true
    end

    function frameMethods:StopMovingOrSizing()
        self.moving = false
    end

    function frameMethods:SetMinMaxValues(minimum, maximum)
        self.minimum = minimum
        self.maximum = maximum
    end

    function frameMethods:SetValue(value)
        self.value = value
    end

    function frameMethods:SetStatusBarTexture(texture)
        self.statusBarTexture = texture
    end

    function frameMethods:SetStatusBarColor(r, g, b, a)
        self.statusBarColor = {
            r = r,
            g = g,
            b = b,
            a = a,
        }
    end

    function frameMethods:SetJustifyH(justify)
        self.justifyH = justify
    end

    function frameMethods:SetWordWrap(enabled)
        self.wordWrap = enabled
    end

    function frameMethods:SetText(text)
        self.text = text
    end

    function frameMethods:SetTexture(texture, dimensions, anchor)
        self.texture = texture
        self.textureDimensions = dimensions
        self.textureAnchor = anchor
    end

    function frameMethods:SetTextureColor(color)
        self.textureColor = color
    end

    function frameMethods:SetTooltip(title, body)
        self.tooltipTitle = title
        self.tooltipBody = body
    end

    function frameMethods:SetOnClick(callback)
        self.onClick = callback
    end

    function frameMethods:Click()
        self.onClick()
    end

    local function newFrame(kind, parent, name, width, height)
        local frame = setmetatable({
            children = {},
            events = {},
            frameLevel = 1,
            height = height,
            kind = kind,
            name = name,
            parent = parent,
            points = {},
            scripts = {},
            shown = true,
            width = width,
        }, {
            __index = frameMethods,
        })

        state.frames[#state.frames + 1] = frame
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        if name then
            state.namedFrames[name] = frame
        end
        return frame
    end

    local uiParent = newFrame("UIParent")

    local AF = {}

    function AF.CreateFrame(parent, name, width, height)
        return newFrame("AFFrame", parent, name, width, height)
    end

    function AF.CreateFontString(parent)
        return newFrame("FontString", parent)
    end

    function AF.CreateTexture(parent)
        return newFrame("Texture", parent)
    end

    function AF.CreateButton(parent, name, _, width, height)
        return newFrame("Button", parent, name, width, height)
    end

    function AF.CreateDropdown(parent, width)
        local dropdown = newFrame("Dropdown", parent, nil, width, 20)

        function dropdown:SetItems(items)
            self.items = items
        end

        function dropdown:SetSelectedValue(value)
            self.selectedValue = value
        end

        function dropdown:SetOnSelect(callback)
            self.onSelect = callback
        end

        function dropdown:Select(value)
            self.selectedValue = value
            self.onSelect(value)
        end

        return dropdown
    end

    function AF.CreateResizeButton(target)
        local resize = newFrame("ResizeButton", target, nil, 16, 16)
        target:SetResizable(true)
        return resize
    end

    function AF.CloseDropdown()
        state.closedDropdowns = (state.closedDropdowns or 0) + 1
    end

    function AF.ApplyDefaultBackdrop_NoBorder(frame)
        frame.hasBorderlessBackdrop = true
    end

    function AF.ApplyDefaultBackdrop(frame)
        frame.hasBackdrop = true
    end

    function AF.ApplyDefaultBackdrop_NoBackground(frame)
        frame.hasBorderOnlyBackdrop = true
    end

    function AF.SetOnePixelInside(texture, parent)
        texture.onePixelInside = parent
    end

    function AF.ApplyDefaultTexCoord(texture)
        texture.hasDefaultTexCoord = true
    end

    function AF.SetTooltip(
        frame,
        anchor,
        x,
        y,
        title,
        body
    )
        frame.tooltipAnchor = anchor
        frame.tooltipX = x
        frame.tooltipY = y
        frame.tooltipTitle = title
        frame.tooltipBody = body
    end

    function AF.GetIcon(name)
        return "icon:" .. name
    end

    function AF.GetPlainTexture()
        return "plain-texture"
    end

    function AF.LSM_GetBarTexture(name)
        return "bar-texture:" .. name
    end

    function AF.GetColorRGB(name, alpha)
        if name == "BFI" then
            return 0.82, 0.37, 0.12, alpha
        elseif name == "border" then
            return 0.1, 0.1, 0.1, alpha
        elseif name == "header" then
            return 0.18, 0.18, 0.18, alpha
        end
        return 0.04, 0.04, 0.04, alpha
    end

    function AF.GetClassColor(classFilename)
        state.classColorInputs[#state.classColorInputs + 1] =
            classFilename
        return 0.24, 0.57, 0.91
    end

    function AF.FormatSecretNumber(value)
        state.formatInputs[#state.formatInputs + 1] = value
        local output = state.formatOutputs[value]
        if not output then
            output = newOpaqueValue("formatted")
            state.formatOutputs[value] = output
        end
        return output
    end

    local config = {
        accentHeader = true,
        backgroundAlpha = 0.82,
        barAlpha = 0.9,
        barHeight = 20,
        classColor = true,
        enabled = true,
        headerHeight = 22,
        height = 220,
        locked = false,
        numberMode = "both",
        padding = 4,
        showSpecIcon = true,
        spacing = 2,
        texture = "AF",
        width = 300,
        windowCount = 3,
        windowAnchors = {
            {
                relativeTo = 0,
                point = "BOTTOMRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = -4,
                y = 4,
            },
            {
                relativeTo = 1,
                point = "BOTTOMRIGHT",
                relativePoint = "TOPRIGHT",
                x = 0,
                y = 4,
            },
            {
                relativeTo = 2,
                point = "BOTTOMRIGHT",
                relativePoint = "TOPRIGHT",
                x = 0,
                y = 4,
            },
        },
        windowHeights = {
            220,
            220,
            220,
        },
        windowTypes = {
            "DamageDone",
            "HealingDone",
            "DamageTaken",
        },
    }

    local DM = {
        config = config,
        Data = {},
        Native = {},
    }

    function DM.Data.IsAvailable()
        return state.available
    end

    function DM.Data.GetCurrentSession(meterType)
        return state.currentSessions[meterType]
    end

    function DM.Native.GetEnabled()
        return state.nativeEnabled
    end

    function DM.Native.SetEnabled(enabled)
        state.nativeSetCalls[#state.nativeSetCalls + 1] = enabled
        state.nativeEnabled = enabled
        return true
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        funcs = {
            OpenOptionsFrame = function(section)
                state.openOptionsCalls[#state.openOptionsCalls + 1] =
                    section
            end,
        },
        media = {
            bar = "fallback-bar-texture",
        },
        modules = {
            DamageMeter = DM,
        },
    }

    local environment = {
        AbstractFramework = AF,
        Ambiguate = function(value, style)
            state.ambiguousInputs[#state.ambiguousInputs + 1] = {
                style = style,
                value = value,
            }
            local output = state.ambiguousOutputs[value]
            if not output then
                output = newOpaqueValue("ambiguous")
                state.ambiguousOutputs[value] = output
            end
            return output
        end,
        BFICVarBackup = state.nativeOverrideState,
        C_Timer = {
            NewTimer = function(_, callback)
                local timer = {
                    callback = callback,
                    cancelled = false,
                }
                function timer:Cancel()
                    self.cancelled = true
                end
                state.timers[#state.timers + 1] = timer
                return timer
            end,
        },
        CreateFrame = function(kind, name, parent)
            return newFrame(kind, parent, name)
        end,
        DAMAGE = "Damage",
        DAMAGE_TAKEN = "Damage Taken",
        Enum = {
            DamageMeterType = {
                DamageDone = 11,
                Dps = 12,
                HealingDone = 22,
                Hps = 23,
                Absorbs = 24,
                Interrupts = 25,
                Dispels = 26,
                DamageTaken = 33,
                AvoidableDamageTaken = 34,
                Deaths = 35,
                EnemyDamageTaken = 36,
            },
        },
        GetCursorPosition = function()
            return state.cursorX or 0, state.cursorY or 0
        end,
        HEALING = "Healing",
        InCombatLockdown = function()
            return false
        end,
        MINIMIZE = "Minimize",
        SETTINGS = "Settings",
        UIParent = uiParent,
        ipairs = ipairs,
        math = math,
        select = select,
        type = type,
    }
    environment._G = environment

    local sources = {}
    local sessions = {}
    local meterTypes = {
        11,
        22,
        33,
        12,
        23,
        24,
        25,
        26,
        34,
        35,
        36,
    }
    for index, meterType in ipairs(meterTypes) do
        local source = {
            amountPerSecond = newOpaqueValue(
                "per-second-" .. index
            ),
            classFilename = "MAGE",
            name = newOpaqueValue("name-" .. index),
            specIconID = 1000 + index,
            totalAmount = newOpaqueValue("total-" .. index),
        }
        local session = {
            combatSources = {
                source,
            },
            maxAmount = newOpaqueValue("maximum-" .. index),
        }
        sources[index] = source
        sessions[index] = session
        state.currentSessions[meterType] = session
    end

    local chunk, loadError = loadfile(
        "Modules/DamageMeter/Renderer.lua"
    )
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return DM.Renderer, DM, state, sources, sessions, uiParent
end

local Renderer, DM, state, sources, sessions, uiParent =
    loadRenderer()

assertEqual(Renderer.IsEnabled(), false, "renderer initially disabled")
assertEqual(Renderer.SetEnabled(true), true, "renderer enable")
assertEqual(Renderer.IsEnabled(), true, "renderer enabled state")

local first = state.namedFrames.BFIDamageMeterWindow1
local second = state.namedFrames.BFIDamageMeterWindow2
local third = state.namedFrames.BFIDamageMeterWindow3
assertEqual(type(first), "table", "first addon-owned window")
assertEqual(type(second), "table", "second addon-owned window")
assertEqual(type(third), "table", "third addon-owned window")
assertEqual(first.shown, true, "first window shown")
assertEqual(second.shown, true, "second window shown")
assertEqual(third.shown, true, "third window shown")
assertPoint(
    first,
    1,
    "BOTTOMRIGHT",
    uiParent,
    "BOTTOMRIGHT",
    -4,
    4,
    "first default anchor"
)
assertPoint(
    second,
    1,
    "BOTTOMRIGHT",
    first,
    "TOPRIGHT",
    0,
    4,
    "second default anchor"
)
assertPoint(
    third,
    1,
    "BOTTOMRIGHT",
    second,
    "TOPRIGHT",
    0,
    4,
    "third default anchor"
)

assertEqual(#state.nativeSetCalls, 1, "native hidden once on enable")
assertEqual(state.nativeSetCalls[1], false, "native hidden on enable")
assertEqual(state.nativeEnabled, false, "native disabled while BFI active")
assertEqual(
    state.nativeOverrideState.damageMeterNativeEnabledBeforeBFI,
    true,
    "native preference retained outside the profile"
)
assertEqual(
    DM.config.nativeEnabledBeforeBFI,
    nil,
    "native preference is not stored in the profile"
)

local firstRow = first.body.children[1]
assertSame(
    firstRow.bar.maximum,
    sessions[1].maxAmount,
    "opaque maximum reaches StatusBar unchanged"
)
assertSame(
    firstRow.bar.value,
    sources[1].totalAmount,
    "opaque total reaches StatusBar unchanged"
)
assertSame(
    state.ambiguousInputs[1].value,
    sources[1].name,
    "opaque name reaches Ambiguate unchanged"
)
assertEqual(
    state.ambiguousInputs[1].style,
    "short",
    "name uses approved short Ambiguate style"
)
assertSame(
    firstRow.name.text,
    state.ambiguousOutputs[sources[1].name],
    "Ambiguate output reaches name sink unchanged"
)
assertSame(
    state.formatInputs[1],
    sources[1].totalAmount,
    "opaque total reaches approved formatter unchanged"
)
assertSame(
    state.formatInputs[3],
    sources[1].amountPerSecond,
    "opaque rate reaches approved formatter unchanged"
)
assertSame(
    firstRow.total.text,
    state.formatOutputs[sources[1].totalAmount],
    "formatted total reaches number sink unchanged"
)
assertSame(
    firstRow.perSecond.text,
    state.formatOutputs[sources[1].amountPerSecond],
    "formatted rate reaches number sink unchanged"
)
assertSame(
    state.ambiguousInputs[2].value,
    sources[1].name,
    "hover title uses a separate approved name pipeline"
)
assertSame(
    firstRow.hoverCard.title.text,
    state.ambiguousOutputs[sources[1].name],
    "hover title receives approved name output"
)
assertSame(
    state.formatInputs[2],
    sources[1].totalAmount,
    "hover total uses a separate approved number pipeline"
)
assertSame(
    state.formatInputs[4],
    sources[1].amountPerSecond,
    "hover rate uses a separate approved number pipeline"
)
assertSame(
    firstRow.hoverCard.totalValue.text,
    state.formatOutputs[sources[1].totalAmount],
    "hover total reaches its FontString sink"
)
assertSame(
    firstRow.hoverCard.perSecondValue.text,
    state.formatOutputs[sources[1].amountPerSecond],
    "hover rate reaches its FontString sink"
)
firstRow:RunScript("OnEnter")
assertEqual(firstRow.highlight.shown, true, "row hover highlight shown")
assertEqual(firstRow.hoverCard.shown, true, "row hover card shown")
firstRow:RunScript("OnLeave")
assertEqual(firstRow.highlight.shown, false, "row hover highlight hidden")
assertEqual(firstRow.hoverCard.shown, false, "row hover card hidden")
assertEqual(state.unsafeOperations, 0, "opaque values never inspected")

assertEqual(
    state.classColorInputs[1],
    "MAGE",
    "row requests source class color"
)
assertEqual(firstRow.bar.statusBarColor.r, 0.24, "class bar red")
assertEqual(firstRow.bar.statusBarColor.g, 0.57, "class bar green")
assertEqual(firstRow.bar.statusBarColor.b, 0.91, "class bar blue")
assertEqual(firstRow.bar.statusBarColor.a, 0.9, "configured bar alpha")
assertEqual(firstRow.icon.texture, 1001, "spec icon applied")
assertEqual(firstRow.iconHolder.shown, true, "spec icon shown")

assertEqual(
    first.settings.tooltipAnchor,
    "TOPRIGHT",
    "settings tooltip expands inward"
)
assertEqual(
    first.settings.tooltipTitle,
    "Settings",
    "settings tooltip title"
)
assertEqual(
    first.settings.tooltipBody,
    "Open BFI Damage Meter Settings",
    "settings tooltip body"
)
first.settings:Click()
assertEqual(
    #state.openOptionsCalls,
    1,
    "settings gear invokes BFI options once"
)
assertEqual(
    state.openOptionsCalls[1],
    "damageMeter",
    "settings gear opens Damage Meter section"
)

assertEqual(
    #first.typeDropdown.items,
    11,
    "in-window filter exposes every 12.1 meter type"
)
assertEqual(
    first.typeDropdown.items[1].value,
    "DamageDone",
    "filter starts with damage done"
)
assertEqual(
    first.typeDropdown.items[5].value,
    "EnemyDamageTaken",
    "filter includes enemy damage taken"
)
assertEqual(
    first.typeDropdown.items[11].value,
    "Deaths",
    "filter follows Blizzard's category ordering"
)
first.typeDropdown:Select("Dps")
assertEqual(DM.config.windowTypes[1], "Dps", "filter selection persists")
assertEqual(
    first.typeDropdown.selectedValue,
    "Dps",
    "filter selection stays visible"
)
assertSame(
    firstRow.perSecond.points[1].relativeTo,
    firstRow,
    "DPS places rate in the primary right column"
)
assertSame(
    firstRow.total.points[1].relativeTo,
    firstRow.perSecond,
    "DPS places total in the secondary column"
)
first.typeDropdown:Select("Interrupts")
assertEqual(
    firstRow.total.shown,
    true,
    "interrupts keep their total count"
)
assertEqual(
    firstRow.perSecond.shown,
    false,
    "interrupts suppress meaningless rates"
)
assertEqual(
    firstRow.hoverCard.perSecondValue.shown,
    false,
    "interrupt hover card also suppresses rates"
)
first.typeDropdown:Select("EnemyDamageTaken")
assertEqual(
    firstRow.iconHolder.shown,
    false,
    "enemy damage suppresses source icons"
)
first.typeDropdown:Select("DamageDone")
assertEqual(
    firstRow.iconHolder.shown,
    true,
    "regular views restore configured icons"
)

first.lock:Click()
assertEqual(DM.config.locked, true, "lock button locks all meters")
assertEqual(first.resizable, false, "lock disables first resize")
assertEqual(second.resizable, false, "lock disables second resize")
assertEqual(first.resize.shown, false, "lock hides first resize grip")
first.dragGrip:RunScript("OnDragStart")
assertEqual(first.moving, nil, "locked drag grip cannot start moving")
second.lock:Click()
assertEqual(DM.config.locked, false, "any lock button unlocks all")
assertEqual(first.resizable, true, "unlock restores first resize")
assertEqual(third.resize.shown, true, "unlock restores resize grips")

first:SetSize(410, 275)
first.resize:RunScript("OnMouseUp", "LeftButton")
assertEqual(DM.config.width, 410, "resize stores shared width")
assertEqual(
    DM.config.windowHeights[1],
    275,
    "resize stores first independent height"
)
assertEqual(first.width, 410, "resized window keeps shared width")
assertEqual(second.width, 410, "second receives shared width")
assertEqual(third.width, 410, "third receives shared width")
assertEqual(second.height, 220, "second height remains independent")

first.mouseOver = true
first.centerY = 300
state.cursorY = 350
assertEqual(
    third.dragGrip.dragButton,
    "LeftButton",
    "dedicated grip is draggable"
)
third.dragGrip:RunScript("OnDragStart")
assertEqual(
    #third.points,
    1,
    "drag start preserves the current screen position"
)
third:RunScript("OnUpdate")
assertEqual(first.dockPreview.shown, true, "top docking preview shown")
assertEqual(
    first.dockPreview.points[1].point,
    "TOPLEFT",
    "top preview covers target top half"
)
third.dragGrip:RunScript("OnDragStop")
assertEqual(first.dockPreview.shown, false, "preview clears on drop")
assertEqual(
    DM.config.windowAnchors[3].relativeTo,
    1,
    "dropped meter persists target window"
)
assertEqual(
    DM.config.windowAnchors[3].point,
    "BOTTOMRIGHT",
    "top drop persists above anchor"
)
assertEqual(
    DM.config.windowAnchors[2].relativeTo,
    3,
    "occupied docking side inserts the dropped meter into the stack"
)
assertPoint(
    third,
    1,
    "BOTTOMRIGHT",
    first,
    "TOPRIGHT",
    0,
    4,
    "top docking anchor"
)
assertPoint(
    second,
    1,
    "BOTTOMRIGHT",
    third,
    "TOPRIGHT",
    0,
    4,
    "existing neighbor moves above the inserted meter"
)

state.cursorY = 250
third.header:RunScript("OnDragStart")
third:RunScript("OnUpdate")
assertEqual(first.dockPreview.shown, true, "bottom docking preview shown")
assertEqual(
    first.dockPreview.points[1].relativePoint,
    "LEFT",
    "bottom preview starts at target midpoint"
)
third.header:RunScript("OnDragStop")
assertEqual(
    DM.config.windowAnchors[3].point,
    "TOPRIGHT",
    "bottom drop persists below anchor"
)
assertEqual(
    DM.config.windowAnchors[2].relativeTo,
    1,
    "moving a middle meter closes its previous stack gap"
)
assertPoint(
    third,
    1,
    "TOPRIGHT",
    first,
    "BOTTOMRIGHT",
    0,
    -4,
    "bottom docking anchor"
)
assertPoint(
    second,
    1,
    "BOTTOMRIGHT",
    first,
    "TOPRIGHT",
    0,
    4,
    "old neighbor remains in the original stack without overlap"
)

first.mouseOver = false
third.header:RunScript("OnDragStart")
third.left = 111
third.bottom = 222
third:RunScript("OnUpdate")
third.header:RunScript("OnDragStop")
assertEqual(
    DM.config.windowAnchors[3].relativeTo,
    0,
    "free move detaches from another meter"
)
assertEqual(
    DM.config.windowAnchors[3].point,
    "BOTTOMLEFT",
    "free move stores a screen anchor"
)
assertEqual(DM.config.windowAnchors[3].x, 111, "free move stores x")
assertEqual(DM.config.windowAnchors[3].y, 222, "free move stores y")
assertPoint(
    third,
    1,
    "BOTTOMLEFT",
    uiParent,
    "BOTTOMLEFT",
    111,
    222,
    "free move reapplies persisted screen anchor"
)

DM.config.windowAnchors[1] = {
    relativeTo = 2,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
}
DM.config.windowAnchors[2] = {
    relativeTo = 1,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
}
assertEqual(Renderer.ApplySettings(), true, "cyclic anchors are repaired")
assertEqual(
    DM.config.windowAnchors[1].relativeTo,
    0,
    "cyclic anchor falls back to UIParent"
)
assertEqual(
    DM.config.windowAnchors[1].point,
    "CENTER",
    "cyclic anchor uses safe center fallback"
)
assertEqual(Renderer.ResetPosition(), true, "reset restores default stack")
assertPoint(
    second,
    1,
    "BOTTOMRIGHT",
    first,
    "TOPRIGHT",
    0,
    4,
    "reset restores vertical stack"
)

first.mouseOver = false
second.mouseOver = true
second.centerY = 300
state.cursorY = 250
third.header:RunScript("OnDragStart")
third:RunScript("OnUpdate")
third.header:RunScript("OnDragStop")
assertEqual(
    DM.config.windowAnchors[3].relativeTo,
    1,
    "drop beneath a target occupies the target's previous stack slot"
)
assertEqual(
    DM.config.windowAnchors[2].relativeTo,
    3,
    "target moves above an inserted meter when its parent occupied the side"
)
assertPoint(
    third,
    1,
    "BOTTOMRIGHT",
    first,
    "TOPRIGHT",
    0,
    4,
    "parent-side insertion places the dragged meter between neighbors"
)
assertPoint(
    second,
    1,
    "BOTTOMRIGHT",
    third,
    "TOPRIGHT",
    0,
    4,
    "parent-side insertion keeps the target on the far side"
)

Renderer.ResetPosition()
DM.config.windowAnchors[3] = {
    relativeTo = 0,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 250,
    y = 100,
}
Renderer.ApplySettings()
second.mouseOver = false
third.mouseOver = true
third.centerY = 300
state.cursorY = 250
first.header:RunScript("OnDragStart")
assertEqual(
    DM.config.windowAnchors[2].relativeTo,
    0,
    "moving a screen-rooted meter rehomes its docked neighbor"
)
first:RunScript("OnUpdate")
first.header:RunScript("OnDragStop")
assertEqual(
    DM.config.windowAnchors[1].relativeTo,
    3,
    "screen-rooted meter can dock without carrying its old stack"
)
assertEqual(
    DM.config.windowAnchors[2].relativeTo,
    0,
    "old stack stays rooted independently after the move"
)
Renderer.ResetPosition()

assertEqual(Renderer.SetEnabled(false), true, "renderer disable")
assertEqual(state.nativeEnabled, true, "native preference restored")
assertEqual(
    state.nativeSetCalls[#state.nativeSetCalls],
    true,
    "disable restores native CVar"
)
assertEqual(
    state.nativeOverrideState.damageMeterNativeEnabledBeforeBFI,
    nil,
    "restore metadata cleared"
)

assertEqual(Renderer.SetEnabled(true), true, "renderer re-enable")
assertEqual(state.nativeEnabled, false, "native hidden after re-enable")
local originalFirstWindow = first
local nativeCallsBeforeLiveApply = #state.nativeSetCalls
local thirdRow = third.body.children[1]
thirdRow:RunScript("OnEnter")
assertEqual(thirdRow.hoverCard.shown, true, "third hover card precondition")

DM.config.width = 360
DM.config.windowHeights[1] = 260
DM.config.windowHeights[2] = 240
DM.config.headerHeight = 26
DM.config.barHeight = 24
DM.config.spacing = 4
DM.config.texture = "LiveTexture"
DM.config.numberMode = "total"
DM.config.padding = 6
DM.config.showSpecIcon = false
DM.config.classColor = false
DM.config.backgroundAlpha = 0.65
DM.config.barAlpha = 0.55
DM.config.accentHeader = false
DM.config.windowCount = 2

assertEqual(Renderer.ApplySettings(), true, "live settings apply")
assertSame(
    state.namedFrames.BFIDamageMeterWindow1,
    originalFirstWindow,
    "live settings reuse existing window"
)
assertEqual(first.width, 360, "live width")
assertEqual(first.height, 260, "live height")
assertEqual(second.height, 240, "second window keeps its own height")
assertEqual(first.header.height, 26, "live header height")
assertEqual(firstRow.height, 24, "live bar height")
assertEqual(firstRow.points[1].x, 6, "live horizontal padding")
assertEqual(firstRow.points[1].y, -6, "live vertical padding")
assertEqual(
    firstRow.bar.statusBarTexture,
    "bar-texture:LiveTexture",
    "live bar texture"
)
assertEqual(firstRow.iconHolder.shown, false, "live icon visibility")
assertEqual(firstRow.total.shown, true, "total remains visible")
assertEqual(firstRow.perSecond.shown, false, "rate hides in total mode")
assertEqual(firstRow.bar.statusBarColor.r, 0.82, "accent bar red")
assertEqual(firstRow.bar.statusBarColor.g, 0.37, "accent bar green")
assertEqual(firstRow.bar.statusBarColor.b, 0.12, "accent bar blue")
assertEqual(firstRow.bar.statusBarColor.a, 0.55, "live bar alpha")
assertEqual(first.body.backdropColor.a, 0.65, "live background alpha")
assertEqual(second.shown, true, "second remains shown")
assertEqual(third.shown, false, "window count applies live")
assertEqual(
    thirdRow.hoverCard.shown,
    false,
    "window count reduction clears independent hover cards"
)
assertEqual(
    #state.nativeSetCalls,
    nativeCallsBeforeLiveApply,
    "live appearance does not rewrite native CVar"
)

state.currentSessions[11] = {
    combatSources = {},
    maxAmount = sessions[1].maxAmount,
}
assertEqual(Renderer.Refresh(), true, "empty session refresh")
assertEqual(firstRow.shown, false, "empty session clears stale row")

state.available = false
firstRow:RunScript("OnEnter")
assertEqual(Renderer.Refresh(), false, "unavailable API refresh")
assertEqual(first.shown, false, "unavailable API hides first window")
assertEqual(second.shown, false, "unavailable API hides second window")
assertEqual(third.shown, false, "unavailable API hides third window")
assertEqual(
    firstRow.hoverCard.shown,
    false,
    "unavailable API clears active hover cards"
)
assertEqual(state.nativeEnabled, true, "unavailable API restores native")

state.available = true
state.currentSessions[11] = sessions[1]
assertEqual(Renderer.Refresh(), true, "available API recovery")
assertEqual(first.shown, true, "recovery shows first window")
assertEqual(second.shown, true, "recovery shows configured windows")
assertEqual(third.shown, false, "recovery respects window count")
assertEqual(state.nativeEnabled, false, "recovery hides native again")
assertEqual(firstRow.shown, true, "recovery repopulates rows")
assertEqual(state.unsafeOperations, 0, "recovery remains opaque-safe")

firstRow:RunScript("OnEnter")
assertEqual(Renderer.SetEnabled(false), true, "final renderer disable")
assertEqual(state.nativeEnabled, true, "final disable restores native")
assertEqual(first.shown, false, "disable hides first window")
assertEqual(second.shown, false, "disable hides second window")
assertEqual(third.shown, false, "disable hides third window")
assertEqual(
    firstRow.hoverCard.shown,
    false,
    "disable clears active hover cards"
)

local ReloadRenderer, _, reloadState = loadRenderer(false, true)
assertEqual(
    ReloadRenderer.SetEnabled(true),
    true,
    "renderer enables after a UI reload"
)
assertEqual(
    reloadState.nativeEnabled,
    false,
    "renderer keeps the native meter hidden after reload"
)
assertEqual(
    ReloadRenderer.SetEnabled(false),
    true,
    "renderer disables after a UI reload"
)
assertEqual(
    reloadState.nativeEnabled,
    true,
    "saved non-profile state restores the pre-reload native preference"
)
assertEqual(
    reloadState.nativeOverrideState.damageMeterNativeEnabledBeforeBFI,
    nil,
    "reload restore metadata clears after disable"
)

print("damage_meter_renderer_test.lua: ok")
