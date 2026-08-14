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

local function loadRenderer(
    initialNativeEnabled,
    savedRestoreEnabled,
    availableSessionCount,
    objectiveTrackerAvailable,
    objectiveDockFrameAvailable
)
    local state = {
        ambiguousInputs = {},
        ambiguousOutputs = {},
        available = true,
        availableSessions = {
            {
                durationSeconds = 95,
                name = "Training Dummy",
                sessionID = 91,
            },
        },
        classColorInputs = {},
        callbacks = {},
        currentSessions = {},
        deathRecapCalls = {},
        deathRecapEvents = {},
        detailSourceCalls = {},
        detailSources = {},
        fires = {},
        formatInputs = {},
        formatOutputs = {},
        frames = {},
        historicalSessions = {
            [91] = {},
        },
        namedFrames = {},
        nativeEnabled = initialNativeEnabled ~= false,
        nativeOverrideState = {},
        nativeSetCalls = {},
        openOptionsCalls = {},
        overallSessions = {},
        timers = {},
        tooltipSpellCalls = {},
        unsafeOperations = 0,
        inCombat = false,
        secretGeometryToken = {},
    }
    if type(savedRestoreEnabled) == "boolean" then
        state.nativeOverrideState.damageMeterNativeEnabledBeforeBFI =
            savedRestoreEnabled
    end
    if type(availableSessionCount) == "number" then
        state.availableSessions = {}
        for sessionID = 1, availableSessionCount do
            state.availableSessions[sessionID] = {
                durationSeconds = sessionID,
                name = "Session " .. sessionID,
                sessionID = sessionID,
            }
            state.historicalSessions[sessionID] =
                state.historicalSessions[sessionID] or {}
        end
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

    local function newSecretName(label)
        return setmetatable({
            label = label,
        }, {
            __eq = unsafeOperation,
        })
    end
    state.newSecretName = newSecretName

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
        self.points = {}
        self.allPoints = relativeTo or true
    end

    function frameMethods:ClearAllPoints()
        self.points = {}
        self.allPoints = nil
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
        self.sizeChangeCount = (self.sizeChangeCount or 0) + 1
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

    function frameMethods:EnableMouseWheel(enabled)
        self.mouseWheelEnabled = enabled
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

    function frameMethods:SetFontHeight(height)
        self.fontHeight = height
    end

    function frameMethods:SetText(text)
        self.text = text
    end

    function frameMethods:SetTexture(texture, dimensions, anchor)
        self.atlas = nil
        self.texture = texture
        self.textureDimensions = dimensions
        self.textureAnchor = anchor
    end

    function frameMethods:SetAtlas(atlas, useAtlasSize, filterMode, resetTexCoords)
        self.atlas = atlas
        self.texture = nil
        self.useAtlasSize = useAtlasSize
        self.filterMode = filterMode
        self.resetTexCoords = resetTexCoords
        if resetTexCoords then self.hasDefaultTexCoord = false end
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
    local objectiveTracker
    local objectiveTrackerDockFrame
    if objectiveTrackerAvailable ~= false then
        objectiveTracker = newFrame(
            "ObjectiveTrackerFrame",
            uiParent,
            "ObjectiveTrackerFrame",
            260,
            805
        )
        objectiveTracker.isOnLeftSideOfScreen = false
        objectiveTracker.NineSlice = newFrame(
            "ObjectiveTrackerNineSlice",
            objectiveTracker,
            nil,
            272,
            400
        )
        if objectiveDockFrameAvailable ~= false then
            objectiveTrackerDockFrame = newFrame(
                "ObjectiveTrackerDockFrame",
                objectiveTracker,
                "BFIObjectiveTrackerDockFrame",
                272,
                400
            )
        end
    end
    state.objectiveTrackerDockFrame = objectiveTrackerDockFrame

    local AF = {}

    function AF.CreateFrame(parent, name, width, height)
        return newFrame("AFFrame", parent, name, width, height)
    end

    function AF.CreateBorderedFrame(
        parent,
        name,
        width,
        height,
        color,
        borderColor
    )
        local frame = newFrame(
            "BorderedFrame",
            parent,
            name,
            width,
            height
        )
        frame.backgroundColorName = color
        frame.borderColorName = borderColor
        return frame
    end

    function AF.CreateFontString(parent)
        return newFrame("FontString", parent)
    end

    function AF.CreateTexture(parent)
        return newFrame("Texture", parent)
    end

    function AF.CreateGradientTexture(
        parent,
        orientation,
        color1,
        color2
    )
        local texture = newFrame("GradientTexture", parent)
        texture.gradientOrientation = orientation
        texture.gradientColor1 = color1
        texture.gradientColor2 = color2
        return texture
    end

    function AF.CreateButton(parent, name, _, width, height)
        return newFrame("Button", parent, name, width, height)
    end

    function AF.CreateDropdown(parent, width)
        local dropdown = newFrame("Dropdown", parent, nil, width, 20)
        dropdown.button = newFrame("Button", dropdown)
        dropdown.button.bg = newFrame("Texture", dropdown.button)

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

    function AF.CreateResizeButton(target, minWidth, minHeight, maxWidth, maxHeight)
        local resize = newFrame("ResizeButton", target, nil, 16, 16)
        target:SetResizable(true)
        resize.minWidth = minWidth
        resize.minHeight = minHeight
        resize.maxWidth = maxWidth
        resize.maxHeight = maxHeight

        function resize:SetMinHeight(height)
            self.minHeight = height
        end

        return resize
    end

    function AF.CloseDropdown()
        state.closedDropdowns = (state.closedDropdowns or 0) + 1
    end

    function AF.Fire(...)
        state.fires[#state.fires + 1] = {...}
    end

    function AF.RegisterCallback(name, registeredCallback)
        state.callbacks[name] = registeredCallback
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

    AF.hasLockIcons = true

    function AF.GetAdaptiveIcon(name)
        return "adaptive-icon:" .. name .. ".tga"
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
            return 0, 0, 0, alpha or 1
        elseif name == "header" then
            return 0.18, 0.18, 0.18, alpha
        elseif name == "none" then
            return 0, 0, 0, 0
        end
        return 0.04, 0.04, 0.04, alpha
    end

    function AF.GetColorTable(name, alpha)
        return {AF.GetColorRGB(name, alpha)}
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
        alwaysShowPlayer = true,
        backgroundAlpha = 0.82,
        barAlpha = 0.9,
        barHeight = 20,
        classColor = true,
        enabled = true,
        headerHeight = 22,
        height = 220,
        dockToObjectiveTracker = true,
        locked = false,
        numberMode = "both",
        padding = 4,
        rowTextSize = 11,
        showSpecIcon = true,
        spacing = 2,
        texture = "AF",
        width = 300,
        windowCount = 3,
        windowSessions = {
            {mode = "current"},
            {mode = "current"},
            {mode = "current"},
        },
        windowSyncSessions = {
            true,
            true,
            true,
        },
        windowAnchors = {
            {
                relativeTo = 0,
                point = "TOPRIGHT",
                relativePoint = "TOPRIGHT",
                x = -4,
                y = -4,
            },
            {
                relativeTo = 1,
                point = "TOPRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = 0,
                y = -4,
            },
            {
                relativeTo = 2,
                point = "TOPRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = 0,
                y = -4,
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

    function DM.Data.GetOverallSession(meterType)
        return state.overallSessions[meterType]
    end

    function DM.Data.GetHistoricalSession(sessionID, meterType)
        local sessionsByType = state.historicalSessions[sessionID]
        return sessionsByType and sessionsByType[meterType]
    end

    function DM.Data.GetAvailableSessions()
        return state.availableSessions
    end

    function DM.Data.GetCurrentSource(
        meterType,
        sourceGUID,
        sourceCreatureID
    )
        state.detailSourceCalls[#state.detailSourceCalls + 1] = {
            mode = "current",
            meterType = meterType,
            sourceCreatureID = sourceCreatureID,
            sourceGUID = sourceGUID,
        }
        return state.detailSources[meterType]
    end

    function DM.Data.GetOverallSource(
        meterType,
        sourceGUID,
        sourceCreatureID
    )
        state.detailSourceCalls[#state.detailSourceCalls + 1] = {
            mode = "overall",
            meterType = meterType,
            sourceCreatureID = sourceCreatureID,
            sourceGUID = sourceGUID,
        }
        return state.detailSources[meterType]
    end

    function DM.Data.GetHistoricalSource(
        sessionID,
        meterType,
        sourceGUID,
        sourceCreatureID
    )
        state.detailSourceCalls[#state.detailSourceCalls + 1] = {
            mode = "history",
            meterType = meterType,
            sessionID = sessionID,
            sourceCreatureID = sourceCreatureID,
            sourceGUID = sourceGUID,
        }
        return state.detailSources[meterType]
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
            isValueNonSecret = function(value)
                return value ~= state.secretGeometryToken
            end,
            OpenOptionsFrame = function(section)
                state.openOptionsCalls[#state.openOptionsCalls + 1] =
                    section
            end,
        },
        media = {
            bar = "fallback-bar-texture",
        },
        name = "BFInfinite",
        modules = {
            DamageMeter = DM,
            UIWidgets = {
                objectiveTrackerDockFrame = objectiveTrackerDockFrame,
            },
        },
    }
    state.uiWidgets = BFI.modules.UIWidgets

    local environment = {
        AbstractFramework = AF,
        Ambiguate = function(value, style)
            state.ambiguousInputs[#state.ambiguousInputs + 1] = {
                style = style,
                value = value,
            }
            if type(value) == "string" then
                return value
            end
            local output = state.ambiguousOutputs[value]
            if not output then
                output = newOpaqueValue("ambiguous")
                state.ambiguousOutputs[value] = output
            end
            return output
        end,
        BFICVarBackup = state.nativeOverrideState,
        AbbreviateLargeNumbers = function(value)
            return tostring(math.floor(value + 0.5))
        end,
        ACTION_SWING = "Melee",
        C_DeathRecap = {
            GetRecapEvents = function(recapID)
                return state.deathRecapEvents[recapID] or {}
            end,
            GetRecapMaxHealth = function()
                return 1000
            end,
        },
        C_Spell = {
            GetSpellName = function(spellID)
                return "Spell " .. spellID
            end,
            GetSpellTexture = function(spellID)
                return 2000 + spellID
            end,
        },
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
        GetBuildInfo = function()
            return "12.1.0", "68914", "Jul 31 2026", 120100
        end,
        GetClassAtlas = function(classFilename)
            if classFilename == "MAGE" then
                return "classicon-mage"
            end
        end,
        GameTooltip = {
            Hide = function(self)
                self.hidden = true
            end,
            SetOwner = function(self, owner, anchor)
                self.owner = owner
                self.anchor = anchor
            end,
            SetSpellByID = function(self, spellID)
                state.tooltipSpellCalls[#state.tooltipSpellCalls + 1] =
                    spellID
            end,
            Show = function(self)
                self.shown = true
            end,
        },
        HEALING = "Healing",
        InCombatLockdown = function()
            return state.inCombat
        end,
        MINIMIZE = "Minimize",
        OpenDeathRecapUI = function(deathRecapID)
            state.deathRecapCalls[#state.deathRecapCalls + 1] =
                deathRecapID
        end,
        SecondsToClock = function()
            return "1:35"
        end,
        SETTINGS = "Settings",
        ObjectiveTrackerFrame = objectiveTracker,
        UIParent = uiParent,
        ipairs = ipairs,
        math = math,
        pairs = pairs,
        select = select,
        string = string,
        table = table,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    state.environment = environment

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
            isLocalPlayer = false,
            name = newOpaqueValue("name-" .. index),
            specIconID = 1000 + index,
            sourceCreatureID = nil,
            sourceGUID = "source-guid-" .. index,
            totalAmount = newOpaqueValue("total-" .. index),
            deathRecapID = 0,
        }
        local session = {
            combatSources = {
                source,
            },
            durationSeconds = 10,
            maxAmount = newOpaqueValue("maximum-" .. index),
            totalAmount = newOpaqueValue("session-total-" .. index),
        }
        sources[index] = source
        sessions[index] = session
        state.detailSources[meterType] = {
            combatSpells = {
                {
                    amountPerSecond = 25,
                    combatSpellDetails = {
                        classification = "",
                        isMob = false,
                        isPet = false,
                        specIconID = 3000 + index,
                        unitClassFilename = "MAGE",
                        unitName = "Detail Player " .. index,
                    },
                    creatureName = "",
                    spellID = 100 + index,
                    totalAmount = 250,
                },
            },
            maxAmount = 250,
            totalAmount = 250,
        }
        state.currentSessions[meterType] = session
        state.overallSessions[meterType] = session
        state.historicalSessions[91][meterType] = session
    end

    local chunk, loadError = loadfile(
        "Modules/DamageMeter/Renderer.lua"
    )
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return DM.Renderer,
        DM,
        state,
        sources,
        sessions,
        uiParent,
        objectiveTracker
end

local Renderer, DM, state, sources, sessions, uiParent, objectiveTracker =
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
assertEqual(first.clamped, true,
    "unresolved tracker geometry keeps normal screen clamping")
assertEqual(
    first.kind,
    "BorderedFrame",
    "window uses the shared bordered surface"
)
assertEqual(first.backgroundColorName, "background", "window background")
assertEqual(first.borderColorName, "border", "window border token")
assertEqual(first.backdropColor.r, 0.04, "window gray red")
assertEqual(first.backdropColor.g, 0.04, "window gray green")
assertEqual(first.backdropColor.b, 0.04, "window gray blue")
assertEqual(first.backdropColor.a, 0.82, "window background alpha")
assertEqual(first.borderColor.r, 0, "window border red")
assertEqual(first.borderColor.g, 0, "window border green")
assertEqual(first.borderColor.b, 0, "window border blue")
assertEqual(first.borderColor.a, 1, "window border is opaque")
assertEqual(first.header.hasBorderlessBackdrop, nil, "header is transparent")
assertEqual(first.body.hasBorderlessBackdrop, nil, "body is transparent")
assertEqual(first.header.tex, nil, "title bar has no gradient texture")
assertEqual(first.typeDropdown.backdropColor.a, 0, "type dropdown is flat")
assertEqual(first.typeDropdown.borderColor.a, 0, "type border is hidden")
assertEqual(
    first.typeDropdown.button.borderColor.a,
    0,
    "type arrow border is hidden"
)
assertEqual(
    first.typeDropdown.button.bg.shown,
    false,
    "type arrow background is hidden"
)
assertEqual(
    first.sessionDropdown.backdropColor.a,
    0,
    "session dropdown is flat"
)
assertEqual(first.dragGrip.texture, "icon:Link", "dock control uses link icon")
assertEqual(
    first.dragGrip.tooltipBody,
    "Drag this window on top to another highlighted window and release to anchor it",
    "dock tooltip explains highlighted drop target"
)
assertEqual(
    first.lock.texture,
    "adaptive-icon:Unlock.tga",
    "unlocked meters use the dedicated unlock icon"
)
assertEqual(first.lock.textureColor, "gray", "unlocked icon is subdued")
assertEqual(first.shown, true, "first window shown")
assertEqual(second.shown, true, "second window shown")
assertEqual(third.shown, true, "third window shown")
assertPoint(
    first,
    1,
    "TOPRIGHT",
    state.objectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "first default anchor starts below the Objective Tracker"
)
assertEqual(
    DM.config.windowAnchors[1].relativeTo,
    0,
    "Objective Tracker frame is never persisted in the profile"
)
assertPoint(
    second,
    1,
    "TOPRIGHT",
    first,
    "BOTTOMRIGHT",
    0,
    -4,
    "second default anchor"
)
assertPoint(
    third,
    1,
    "TOPRIGHT",
    second,
    "BOTTOMRIGHT",
    0,
    -4,
    "third default anchor"
)

local EarlyRenderer, _, earlyState, _, _, _, earlyObjectiveTracker =
    loadRenderer(nil, nil, nil, true, false)
assertEqual(
    EarlyRenderer.SetEnabled(true),
    true,
    "renderer starts before the BFI tracker surface is ready"
)
local earlyFirst = earlyState.namedFrames.BFIDamageMeterWindow1
assertPoint(
    earlyFirst,
    1,
    "TOPRIGHT",
    earlyObjectiveTracker.NineSlice,
    "BOTTOMRIGHT",
    0,
    -8,
    "native content bounds provide a temporary tracker fallback"
)
local readyDockFrame = {}
earlyState.uiWidgets.objectiveTrackerDockFrame = readyDockFrame
assertEqual(
    type(earlyState.callbacks.BFI_ObjectiveTrackerDockFrameChanged),
    "function",
    "Objective Tracker dock-frame callback registered"
)
earlyState.callbacks.BFI_ObjectiveTrackerDockFrameChanged()
assertPoint(
    earlyFirst,
    1,
    "TOPRIGHT",
    readyDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "ready BFI tracker surface replaces the temporary fallback"
)
EarlyRenderer.SetEnabled(false)

local FallbackRenderer, _, fallbackState, _, _, fallbackUIParent =
    loadRenderer(nil, nil, nil, false)
assertEqual(
    FallbackRenderer.SetEnabled(true),
    true,
    "renderer starts before the Objective Tracker addon"
)
local fallbackFirst = fallbackState.namedFrames.BFIDamageMeterWindow1
assertPoint(
    fallbackFirst,
    1,
    "TOPRIGHT",
    fallbackUIParent,
    "TOPRIGHT",
    -4,
    -4,
    "unloaded Objective Tracker uses the safe screen fallback"
)
local lateObjectiveTracker = {
    isOnLeftSideOfScreen = false,
}
local lateObjectiveTrackerDockFrame = {}
fallbackState.environment.ObjectiveTrackerFrame = lateObjectiveTracker
fallbackState.uiWidgets.objectiveTrackerDockFrame =
    lateObjectiveTrackerDockFrame
local fallbackEventFrame
for _, frame in ipairs(fallbackState.frames) do
    if frame.events.ADDON_LOADED then
        fallbackEventFrame = frame
        break
    end
end
assertEqual(
    type(fallbackEventFrame),
    "table",
    "Objective Tracker load listener registered"
)
fallbackEventFrame:RunScript(
    "OnEvent",
    "ADDON_LOADED",
    "Blizzard_ObjectiveTracker"
)
assertPoint(
    fallbackFirst,
    1,
    "TOPRIGHT",
    lateObjectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "late Objective Tracker load reapplies the below-tracker anchor"
)
FallbackRenderer.SetEnabled(false)

local OptOutRenderer, optOutDM, optOutState, _, _, optOutUIParent =
    loadRenderer()
optOutDM.config.dockToObjectiveTracker = false
assertEqual(
    OptOutRenderer.SetEnabled(true),
    true,
    "renderer honors saved Objective Tracker docking opt-out"
)
assertPoint(
    optOutState.namedFrames.BFIDamageMeterWindow1,
    1,
    "TOPRIGHT",
    optOutUIParent,
    "TOPRIGHT",
    -4,
    -4,
    "explicit opt-out retains the screen-relative anchor"
)
OptOutRenderer.SetEnabled(false)

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

local expandedHeight = first.height
first.minimize:Click()
assertEqual(first.height, DM.config.headerHeight, "minimized window height")
assertEqual(first.body.shown, false, "minimized window hides its body")
assertEqual(first.backdropColor.a, 0.82, "minimized background alpha")
assertEqual(first.borderColor.r, 0, "minimized border remains black")
assertEqual(first.borderColor.a, 1, "minimized border remains opaque")
first.minimize:Click()
assertEqual(first.height, expandedHeight, "expanded window height restored")
assertEqual(first.body.shown, true, "expanded window restores its body")
assertEqual(#state.nativeSetCalls, 1, "minimize keeps native override stable")

local firstRow = first.rows[1]
assertEqual(firstRow.rank.justifyH, "LEFT", "row number is left aligned")
assertEqual(firstRow.rank.width, 16, "row number uses a compact column")
assertEqual(firstRow.rank.fontHeight, 11, "row rank uses compact text")
assertEqual(firstRow.name.fontHeight, 11, "row name uses compact text")
assertEqual(firstRow.total.fontHeight, 11, "row total uses compact text")
assertEqual(firstRow.perSecond.fontHeight, 11, "row rate uses compact text")
assertEqual(firstRow.total.width, 52, "compact text shrinks the total column")
assertEqual(firstRow.perSecond.width, 52,
    "compact text shrinks the per-second column")
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
    sessions[1].totalAmount,
    "opaque group total reaches approved formatter unchanged"
)
assertSame(
    firstRow.hoverCard.groupTotalValue.text,
    state.formatOutputs[sessions[1].totalAmount],
    "formatted group total reaches hover sink"
)
assertSame(
    firstRow.hoverCard.shareBar.maximum,
    sessions[1].totalAmount,
    "opaque group total reaches hover StatusBar unchanged"
)
assertSame(
    firstRow.hoverCard.shareBar.value,
    sources[1].totalAmount,
    "opaque source total reaches hover StatusBar unchanged"
)
assertSame(
    state.formatInputs[2],
    sources[1].totalAmount,
    "opaque total reaches approved formatter unchanged"
)
assertSame(
    state.formatInputs[4],
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
    state.formatInputs[3],
    sources[1].totalAmount,
    "hover total uses a separate approved number pipeline"
)
assertSame(
    state.formatInputs[5],
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

sources[1].specIconID = 0
Renderer.Refresh()
assertEqual(
    firstRow.icon.atlas,
    "classicon-mage",
    "followers without a spec icon use their public class atlas"
)
assertEqual(
    firstRow.iconHolder.shown,
    true,
    "class atlas keeps the follower icon visible"
)
assertEqual(
    firstRow.icon.resetTexCoords,
    true,
    "class atlas resets the specialization texture crop"
)

sources[1].classFilename = ""
Renderer.Refresh()
assertEqual(firstRow.icon.texture, nil, "missing source icon clears texture")
assertEqual(firstRow.icon.atlas, nil, "missing source icon clears atlas")
assertEqual(
    firstRow.iconHolder.shown,
    false,
    "missing source icon hides the empty holder"
)

sources[1].classFilename = "MAGE"
sources[1].specIconID = 1001
Renderer.Refresh()
assertEqual(firstRow.icon.texture, 1001, "spec icon takes precedence")
assertEqual(
    firstRow.icon.hasDefaultTexCoord,
    true,
    "switching from a class atlas reapplies the specialization crop"
)

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
    #first.sessionDropdown.items,
    3,
    "session picker exposes current, overall, and available history"
)
assertEqual(
    first.sessionDropdown.items[1].value,
    "current",
    "session picker starts with current"
)
assertEqual(
    first.sessionDropdown.items[2].value,
    "overall",
    "session picker includes overall"
)
assertEqual(
    first.sessionDropdown.items[3].value,
    "history:91",
    "session picker keys historical IDs without source data"
)
assertEqual(
    first.sessionDropdown.items[3].text,
    "Training Dummy [1:35]",
    "historical session shows safe label and duration metadata"
)
assertEqual(
    first.sessionDropdown.width,
    120,
    "session picker has practical room for historical labels"
)
DM.config.width = 220
Renderer.ApplySettings()
assertEqual(
    first.sessionDropdown.width,
    71,
    "compact meters preserve room for both header dropdowns"
)
DM.config.width = 300
Renderer.ApplySettings()
assertEqual(
    Renderer.SetWindowSession(1.5, "current"),
    false,
    "session setter rejects fractional window indexes"
)
first.sessionDropdown:Select("overall")
assertEqual(DM.config.windowSessions[1].mode, "overall", "first overall")
assertEqual(DM.config.windowSessions[2].mode, "overall", "syncs second")
assertEqual(DM.config.windowSessions[3].mode, "overall", "syncs third")
DM.config.windowSyncSessions[2] = false
first.sessionDropdown:Select("history:91")
local firstSessionMode, firstHistoricalSessionID =
    Renderer.GetWindowSession(1)
assertEqual(firstSessionMode, "history", "first runtime history")
assertEqual(firstHistoricalSessionID, 91, "runtime history ID retained")
assertEqual(
    DM.config.windowSessions[1].mode,
    "overall",
    "historical choice does not replace durable mode"
)
assertEqual(
    DM.config.windowSessions[1].sessionID,
    nil,
    "historical ID is never persisted"
)
assertEqual(
    DM.config.windowSessions[2].mode,
    "overall",
    "opted-out second retains its session"
)
local thirdSessionMode, thirdHistoricalSessionID =
    Renderer.GetWindowSession(3)
assertEqual(thirdSessionMode, "history", "third runtime history stays synced")
assertEqual(thirdHistoricalSessionID, 91, "third runtime history ID")
assertEqual(
    DM.config.windowSessions[3].mode,
    "overall",
    "synced history keeps third durable mode"
)
state.historicalSessions[91][11] = nil
Renderer.Refresh()
assertEqual(
    Renderer.GetWindowSession(1),
    "overall",
    "missing runtime history restores the durable first mode"
)
assertEqual(
    first.sessionDropdown.selectedValue,
    "overall",
    "missing runtime history updates the visible selection"
)
state.historicalSessions[91][11] = sessions[1]
first.sessionDropdown:Select("history:91")
Renderer.ClearRuntimeSessions()
assertEqual(
    Renderer.GetWindowSession(1),
    "overall",
    "clearing runtime history restores durable first mode"
)
assertEqual(
    Renderer.GetWindowSession(3),
    "overall",
    "clearing runtime history restores durable third mode"
)
Renderer.Refresh()
assertEqual(
    first.sessionDropdown.selectedValue,
    "overall",
    "runtime clear is reflected on refresh"
)
first.sessionDropdown:Select("history:91")
first.sessionDropdown:Select("current")
DM.config.windowSyncSessions[2] = true
second.sessionDropdown:Select("current")
assertEqual(DM.config.windowSessions[1].mode, "current", "first restored")
assertEqual(DM.config.windowSessions[2].mode, "current", "second restored")
assertEqual(DM.config.windowSessions[3].mode, "current", "third restored")

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

sources[10].deathRecapID = 77
state.deathRecapEvents[77] = {
    {
        amount = 600,
        currentHP = 0,
        event = "SPELL_DAMAGE",
        overkill = 100,
        spellId = 901,
        spellName = "Final Blow",
        timestamp = 100,
    },
    {
        amount = 300,
        currentHP = 400,
        event = "SPELL_DAMAGE",
        spellId = 902,
        spellName = "Earlier Hit",
        timestamp = 98,
    },
}
first.typeDropdown:Select("Deaths")
assertEqual(
    firstRow.hoverCard.recapHint.shown,
    true,
    "death rows advertise the detailed report"
)
firstRow:RunScript("OnMouseUp", "LeftButton")
assertEqual(first.detailOpen, true, "death row opens an in-meter report")
assertEqual(first.detailPanel.shown, true, "death report panel is visible")
assertEqual(firstRow.shown, false, "death report replaces summary rows")
assertEqual(
    first.detailRows[1].label.text,
    "-2.0s  Earlier Hit",
    "death events are displayed chronologically"
)
assertEqual(
    first.detailRows[2].label.text,
    "-0.0s  Final Blow",
    "final death event appears last"
)
assertEqual(
    first.detailRows[1].value.text,
    "-300  40%",
    "death report includes amount and remaining health"
)
assertEqual(#state.detailSourceCalls, 0, "death report uses recap data only")
first.detailPanel:RunScript("OnMouseUp", "RightButton")
assertEqual(first.detailOpen, nil, "right click returns from death report")
assertEqual(firstRow.shown, true, "summary rows return after right click")
sources[10].deathRecapID = 0
Renderer.Refresh()
firstRow:RunScript("OnMouseUp", "LeftButton")
assertEqual(first.detailOpen, nil, "zero recap ID is ignored")
first.typeDropdown:Select("DamageDone")

local scrollingSources = {}
for index = 1, 11 do
    scrollingSources[index] = sources[index]
    sources[index].isLocalPlayer = index == 11
end
sessions[1].combatSources = scrollingSources
Renderer.Refresh()

local eighthRow = first.rows[8]
assertEqual(
    first.body.mouseWheelEnabled,
    true,
    "meter body accepts mouse-wheel scrolling"
)
assertEqual(
    firstRow.mouseWheelEnabled,
    true,
    "rows forward mouse-wheel scrolling without a scrollbar"
)
assertEqual(firstRow.rank.text, 1, "scrolling starts in Blizzard order")
assertEqual(
    eighthRow.rank.text,
    11,
    "local player below the viewport remains pinned"
)
assertSame(
    eighthRow.name.text,
    state.ambiguousOutputs[sources[11].name],
    "pinned local player keeps the approved name pipeline"
)
DM.config.alwaysShowPlayer = false
Renderer.Refresh()
assertEqual(
    eighthRow.rank.text,
    8,
    "always-show setting can disable the local-player pin"
)
DM.config.alwaysShowPlayer = true
Renderer.Refresh()
assertEqual(eighthRow.rank.text, 11, "always-show setting restores the pin")

first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 2, "wheel down advances one source")
assertEqual(
    eighthRow.rank.text,
    11,
    "local player stays visible after scrolling"
)
firstRow:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 4, "wheel reaches the clamped bottom")
first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 4, "wheel cannot pass the session end")
first.body:RunScript("OnMouseWheel", 1)
assertEqual(firstRow.rank.text, 3, "wheel up moves toward the top")

Renderer.ClearRuntimeSessions()
Renderer.Refresh()
assertEqual(
    firstRow.rank.text,
    1,
    "runtime session clear also clears per-window scroll maps"
)
first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 3, "current scroll state rebuilt after clear")

Renderer.SetWindowSession(1, "overall", nil, {sync = false})
assertEqual(firstRow.rank.text, 1, "new session key starts at the top")
first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 2, "new session key scrolls independently")
Renderer.SetWindowSession(1, "current", nil, {sync = false})
assertEqual(
    firstRow.rank.text,
    3,
    "returning to a session key restores its own offset"
)

local damageMeterEventFrame
for _, frame in ipairs(state.frames) do
    if frame.events.DAMAGE_METER_CURRENT_SESSION_UPDATED then
        damageMeterEventFrame = frame
        break
    end
end
assertEqual(
    type(damageMeterEventFrame),
    "table",
    "Damage Meter event frame found"
)
assertEqual(
    damageMeterEventFrame.events.EDIT_MODE_LAYOUTS_UPDATED,
    true,
    "Damage Meter follows Objective Tracker Edit Mode layouts"
)
objectiveTracker.isOnLeftSideOfScreen = true
damageMeterEventFrame:RunScript("OnEvent", "EDIT_MODE_LAYOUTS_UPDATED")
assertPoint(
    first,
    1,
    "TOPRIGHT",
    state.objectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "Edit Mode keeps meters below the Objective Tracker"
)
objectiveTracker.isOnLeftSideOfScreen = false
damageMeterEventFrame:RunScript("OnEvent", "EDIT_MODE_LAYOUTS_UPDATED")
assertPoint(
    first,
    1,
    "TOPRIGHT",
    state.objectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "right-side Objective Tracker retains the vertical lane"
)
Renderer.SetWindowSession(1, "history", 91, {sync = false})
first.body:RunScript("OnMouseWheel", -1)
assertEqual(firstRow.rank.text, 2, "historical viewport has scroll state")

state.availableSessions = {}
damageMeterEventFrame:RunScript(
    "OnEvent",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED"
)
state.timers[#state.timers].callback()
assertEqual(
    firstRow.rank.text,
    2,
    "high-frequency combat-session updates retain scroll position"
)
assertEqual(
    #first.sessionDropdown.items,
    3,
    "combat data updates do not rebuild historical metadata"
)
first.sessionDropdown.button:RunScript("OnMouseDown", "LeftButton")
assertEqual(
    #first.sessionDropdown.items,
    2,
    "opening the picker refreshes historical metadata on demand"
)
assertEqual(
    first.sessionDropdown.selectedValue,
    "current",
    "opening the picker clears an expired runtime selection"
)
assertEqual(
    firstRow.rank.text,
    3,
    "opening the picker refreshes rows for the durable session fallback"
)

damageMeterEventFrame:RunScript(
    "OnEvent",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED"
)
state.timers[#state.timers].callback()
assertEqual(
    firstRow.rank.text,
    1,
    "new current-session identity discards Current scroll position"
)
assertEqual(
    #first.sessionDropdown.items,
    2,
    "new current-session identity rebuilds historical metadata"
)

state.availableSessions = {
    {
        durationSeconds = 95,
        name = "Training Dummy",
        sessionID = 91,
    },
}
damageMeterEventFrame:RunScript(
    "OnEvent",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED"
)
state.timers[#state.timers].callback()
Renderer.SetWindowSession(1, "history", 91, {sync = false})
assertEqual(
    firstRow.rank.text,
    1,
    "reappearing historical IDs do not inherit stale scroll state"
)
Renderer.SetWindowSession(1, "overall", nil, {sync = false})
assertEqual(
    firstRow.rank.text,
    2,
    "current-session changes leave Overall scroll position intact"
)
Renderer.SetWindowSession(1, "current", nil, {sync = false})
first.body:RunScript("OnMouseWheel", -1)
damageMeterEventFrame:RunScript("OnEvent", "DAMAGE_METER_RESET")
state.timers[#state.timers].callback()
assertEqual(firstRow.rank.text, 1, "explicit meter reset clears offsets")

Renderer.SetWindowSession(1, "overall", nil, {sync = false})
Renderer.SetWindowSession(1, "history", 91, {sync = false})
damageMeterEventFrame:RunScript("OnEvent", "DAMAGE_METER_RESET")
state.timers[#state.timers].callback()
assertEqual(
    Renderer.GetWindowSession(1),
    "overall",
    "meter reset clears runtime history without changing durable mode"
)
Renderer.SetWindowSession(1, "current", nil, {sync = false})

first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
first.typeDropdown:Select("Dps")
assertEqual(firstRow.rank.text, 1, "new meter type starts at its own offset")
first.typeDropdown:Select("DamageDone")
assertEqual(
    firstRow.rank.text,
    1,
    "explicit meter-type selection resets that type offset"
)

sessions[2].combatSources = scrollingSources
Renderer.Refresh()
second.body:RunScript("OnMouseWheel", -1)
local secondFirstRow = second.rows[1]
assertEqual(
    secondFirstRow.rank.text,
    2,
    "second meter keeps an independent scroll offset"
)
assertEqual(firstRow.rank.text, 1, "second meter scroll leaves first unchanged")

first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
sources[11].isLocalPlayer = false
sources[1].isLocalPlayer = true
Renderer.Refresh()
assertEqual(
    firstRow.rank.text,
    1,
    "local player above the viewport remains pinned"
)
assertEqual(
    first.rows[2].rank.text,
    3,
    "sources after a top pin retain Blizzard order"
)
first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
assertEqual(
    eighthRow.rank.text,
    11,
    "top-pinned player still allows the final source to be reached"
)
sources[1].isLocalPlayer = false
sources[11].isLocalPlayer = true

sessions[10].combatSources = scrollingSources
first.typeDropdown:Select("Deaths")
assertEqual(
    eighthRow.rank.text,
    8,
    "types Blizzard does not pin keep the unmodified viewport"
)
first.typeDropdown:Select("DamageDone")
assertEqual(firstRow.rank.text, 1, "type selection resets the active offset")

first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
first.body:RunScript("OnMouseWheel", -1)
sessions[1].combatSources = {
    sources[1],
    sources[2],
}
Renderer.Refresh()
assertEqual(firstRow.rank.text, 1, "shorter session clamps offset to zero")
assertEqual(
    first.rows[3].shown,
    false,
    "shorter session clears rows beyond its source count"
)

sessions[1].combatSources = {
    sources[1],
}
sessions[2].combatSources = {
    sources[2],
}
sessions[10].combatSources = {
    sources[10],
}
sources[11].isLocalPlayer = false
Renderer.Refresh()
assertEqual(state.unsafeOperations, 0, "scrolling never inspects opaque data")

state.currentSessions[11] = nil
Renderer.Refresh()
assertEqual(firstRow.shown, false, "missing session safely clears rows")
state.currentSessions[11] = {
    maxAmount = sessions[1].maxAmount,
}
Renderer.Refresh()
assertEqual(firstRow.shown, false, "missing source list safely clears rows")
state.currentSessions[11] = sessions[1]
Renderer.Refresh()

first.lock:Click()
assertEqual(DM.config.locked, true, "lock button locks all meters")
assertEqual(
    first.lock.texture,
    "adaptive-icon:Lock.tga",
    "lock icon reflects locked state"
)
assertEqual(first.lock.textureColor, "white", "locked icon is highlighted")
assertEqual(first.resizable, false, "lock disables first resize")
assertEqual(second.resizable, false, "lock disables second resize")
assertEqual(first.resize.shown, false, "lock hides first resize grip")
first.dragGrip:RunScript("OnDragStart")
assertEqual(first.moving, nil, "locked drag grip cannot start moving")
second.lock:Click()
assertEqual(DM.config.locked, false, "any lock button unlocks all")
assertEqual(
    first.lock.texture,
    "adaptive-icon:Unlock.tga",
    "unlock icon reflects movable state"
)
assertEqual(first.lock.textureColor, "gray", "unlocked icon returns to gray")
assertEqual(first.resizable, true, "unlock restores first resize")
assertEqual(third.resize.shown, true, "unlock restores resize grips")

local firesBeforeResize = #state.fires
first:SetSize(410, 275)
assertEqual(#state.fires, firesBeforeResize, "drag resize does not reload options")
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
assertEqual(#state.fires, firesBeforeResize + 1, "resize fires one callback")
assertEqual(
    state.fires[#state.fires][1],
    "BFI_RefreshOptions",
    "resize refreshes open options"
)
assertEqual(
    state.fires[#state.fires][2],
    "damageMeter",
    "resize refresh targets Damage Meter options"
)

local function SeedUpwardDockingScenario()
    DM.config.windowAnchors = {
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
    }
    Renderer.ApplySettings()
end

-- The generic drag/drop coverage exercises both insertion directions using a
-- dedicated upward chain; default placement is asserted separately above.
SeedUpwardDockingScenario()

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
assertSame(
    first.dockPreview.allPoints,
    first,
    "top drop highlights the complete target window"
)
assertEqual(
    #first.dockPreview.points,
    0,
    "top docking preview has no split anchors"
)
state.cursorY = 250
third:RunScript("OnUpdate")
assertSame(
    first.dockPreview.allPoints,
    first,
    "crossing the midpoint preserves one target highlight"
)
state.cursorY = 350
third:RunScript("OnUpdate")
third.dragGrip:RunScript("OnDragStop")
assertEqual(first.dockPreview.shown, false, "preview clears on drop")
assertEqual(
    first.dockPreview.allPoints,
    nil,
    "preview clears its full-window anchor on drop"
)
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
assertSame(
    first.dockPreview.allPoints,
    first,
    "bottom drop keeps one complete target highlight"
)
assertEqual(
    #first.dockPreview.points,
    0,
    "bottom docking preview has no split anchors"
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
local widthBeforePositionReset = DM.config.width
local heightsBeforePositionReset = {
    DM.config.windowHeights[1],
    DM.config.windowHeights[2],
    DM.config.windowHeights[3],
}
assertEqual(Renderer.ResetPosition(), true, "reset restores default stack")
assertEqual(
    DM.config.dockToObjectiveTracker,
    true,
    "reset restores Objective Tracker coexistence"
)
assertEqual(DM.config.width, widthBeforePositionReset,
    "position reset preserves the user-selected width")
for index = 1, 3 do
    assertEqual(DM.config.windowHeights[index], heightsBeforePositionReset[index],
        "position reset preserves window height " .. index)
end
assertPoint(
    first,
    1,
    "TOPRIGHT",
    state.objectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "reset places the stack below the Objective Tracker"
)
assertPoint(
    second,
    1,
    "TOPRIGHT",
    first,
    "BOTTOMRIGHT",
    0,
    -4,
    "reset restores vertical stack"
)

SeedUpwardDockingScenario()

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
assertPoint(
    second,
    1,
    "TOPRIGHT",
    state.objectiveTrackerDockFrame,
    "BOTTOMRIGHT",
    0,
    -8,
    "moving the root transfers below-tracker placement to its neighbor"
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
local thirdRow = third.rows[1]
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
DM.config.rowTextSize = 8
DM.config.showSpecIcon = false
DM.config.classColor = false
DM.config.backgroundAlpha = 0.65
DM.config.barAlpha = 0.55
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
assertEqual(
    first.backdropColor.r,
    0.04,
    "window keeps its gray surface"
)
assertEqual(
    first.backdropColor.a,
    0.65,
    "window follows the live transparency"
)
assertEqual(
    first.header.tex,
    nil,
    "title bar remains gradient-free after live settings"
)
assertEqual(firstRow.height, 24, "live bar height")
assertEqual(firstRow.name.fontHeight, 8, "live row text size")
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
assertEqual(first.borderColor.r, 0, "live window border remains black")
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

local HistoryRenderer, _, historyState =
    loadRenderer(nil, nil, 25)
assertEqual(
    HistoryRenderer.SetEnabled(true),
    true,
    "history retention renderer enables"
)
local historyDropdown =
    historyState.namedFrames.BFIDamageMeterWindow1.sessionDropdown
assertEqual(
    #historyDropdown.items,
    27,
    "session picker keeps every Blizzard history plus current and overall"
)
assertEqual(
    historyDropdown.items[3].value,
    "history:1",
    "history retention preserves Blizzard's first returned session"
)
assertEqual(
    historyDropdown.items[27].value,
    "history:25",
    "history retention preserves Blizzard's last returned session"
)
assertEqual(
    historyDropdown.width,
    120,
    "history picker width stays balanced"
)
assertEqual(
    HistoryRenderer.SetEnabled(false),
    true,
    "history retention renderer disables"
)

local function RunDetailReportTests()
    local detailRenderer, _, detailState, detailSources =
        loadRenderer()
    assertEqual(
        detailRenderer.SetEnabled(true),
        true,
        "detail-report renderer enables"
    )

    local window = detailState.namedFrames.BFIDamageMeterWindow1
    local row = window.rows[1]
    detailSources[1].name = "Damage Player"
    detailSources[11].name = "Training Dummy"
    detailState.detailSources[11] = {
        combatSpells = {
            {
                combatSpellDetails = {},
                spellID = 101,
                totalAmount = 600,
            },
            {
                combatSpellDetails = {},
                spellID = 102,
                totalAmount = 400,
            },
        },
        maxAmount = 600,
        totalAmount = 1000,
    }
    detailState.detailSources[36] = {
        combatSpells = {
            {
                combatSpellDetails = {
                    specIconID = 4101,
                    unitClassFilename = "MAGE",
                    unitName = "Damage Player",
                },
                spellID = 401,
                totalAmount = 300,
            },
            {
                combatSpellDetails = {
                    specIconID = 4101,
                    unitClassFilename = "MAGE",
                    unitName = "Damage Player",
                },
                spellID = 402,
                totalAmount = 200,
            },
            {
                combatSpellDetails = {
                    specIconID = 4102,
                    unitClassFilename = "PRIEST",
                    unitName = "Healer",
                },
                spellID = 403,
                totalAmount = 250,
            },
        },
        maxAmount = 300,
        totalAmount = 750,
    }
    detailRenderer.Refresh()

    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(window.detailOpen, true, "left click opens details")
    assertEqual(window.detailPanel.shown, true, "detail panel is visible")
    assertEqual(row.shown, false, "summary row hides while details are open")
    assertEqual(window.detailTitle.text, "Damage Player", "detail title")
    assertEqual(window.detailTitle.fontHeight, 11, "detail title uses meter text size")
    assertEqual(window.detailRows[1].rank.fontHeight, 11,
        "detail rank uses meter text size")
    assertEqual(window.detailRows[1].label.fontHeight, 11,
        "detail label uses meter text size")
    assertEqual(window.detailRows[1].value.fontHeight, 11,
        "detail value uses meter text size")
    assertEqual(window.detailRows[1].label.text, "Spell 101", "spell label")
    assertEqual(
        window.detailRows[1].value.text,
        "600  60.0%",
        "spell row includes total and percentage"
    )
    assertEqual(window.detailRows[1].icon.texture, 2101, "spell icon")
    assertEqual(
        detailState.detailSourceCalls[1].mode,
        "current",
        "current details use the current-session source API"
    )
    window.detailRows[1]:RunScript("OnEnter")
    assertEqual(
        detailState.tooltipSpellCalls[1],
        101,
        "detail spell hover opens the spell tooltip"
    )
    assertEqual(
        window.detailRows[1].highlight.shown,
        true,
        "detail rows retain hover highlighting"
    )
    window.detailRows[1]:RunScript("OnLeave")
    window.detailRows[1]:RunScript("OnMouseUp", "RightButton")
    assertEqual(window.detailOpen, nil, "right click returns to summary")
    assertEqual(row.shown, true, "summary row returns after details")

    window.typeDropdown:Select("Dps")
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        window.detailRows[1].value.text,
        "25/s  250  100.0%",
        "DPS details show rate first, then total and percentage"
    )
    assertEqual(
        window.detailRows[1].bar.value,
        25,
        "DPS detail bars use the per-second value"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")
    window.typeDropdown:Select("DamageDone")

    detailState.inCombat = true
    local callsBeforeCombat = #detailState.detailSourceCalls
    row:RunScript("OnEnter")
    assertEqual(
        row.hoverCard.recapHint.text,
        "Detailed information is secret while in combat.",
        "combat hover explains secret detail behavior"
    )
    assertEqual(
        row.hoverCard.shareBar.shown,
        false,
        "combat hover does not retain the out-of-combat share bar"
    )
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(window.detailOpen, nil, "combat click does not open details")
    assertEqual(
        #detailState.detailSourceCalls,
        callsBeforeCombat,
        "combat click never queries source-detail APIs"
    )
    row:RunScript("OnLeave")

    detailState.inCombat = false
    row:RunScript("OnMouseUp", "LeftButton")
    local eventFrame
    for _, frame in ipairs(detailState.frames) do
        if frame.events.PLAYER_REGEN_DISABLED then
            eventFrame = frame
            break
        end
    end
    assertEqual(type(eventFrame), "table", "combat event frame registered")
    local callsBeforeCombatStart = #detailState.detailSourceCalls
    detailState.inCombat = true
    eventFrame:RunScript("OnEvent", "PLAYER_REGEN_DISABLED")
    assertEqual(window.detailOpen, nil, "combat start closes open details")
    assertEqual(window.detailSourceIndex, nil, "combat clears source index")
    assertEqual(window.detailTitle.text, "", "combat clears detail title")
    assertEqual(
        window.detailRows[1].label.text,
        "",
        "combat clears rendered detail text"
    )
    assertEqual(
        #detailState.detailSourceCalls,
        callsBeforeCombatStart,
        "combat teardown does not query source-detail APIs"
    )

    detailState.inCombat = false
    window.sessionDropdown:Select("overall")
    local overallCall = #detailState.detailSourceCalls + 1
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        detailState.detailSourceCalls[overallCall].mode,
        "overall",
        "overall details use the overall source API"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")

    window.sessionDropdown:Select("history:91")
    local historyCall = #detailState.detailSourceCalls + 1
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        detailState.detailSourceCalls[historyCall].mode,
        "history",
        "historical details use the historical source API"
    )
    assertEqual(
        detailState.detailSourceCalls[historyCall].sessionID,
        91,
        "historical details retain the selected session ID"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")

    window.sessionDropdown:Select("current")
    window.typeDropdown:Select("EnemyDamageTaken")
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        window.detailRows[1].label.text,
        "Spell 401",
        "enemy report retains Blizzard spell rows"
    )
    assertEqual(
        window.detailRows[1].value.text,
        "300  40.0%",
        "enemy spell row retains its amount"
    )
    assertEqual(
        window.detailRows[2].label.text,
        "Spell 402",
        "enemy report does not group player names"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")

    local manySpells = {}
    for index = 1, 46 do
        manySpells[index] = {
            combatSpellDetails = {},
            spellID = 200 + index,
            totalAmount = 100,
        }
    end
    detailState.detailSources[11] = {
        combatSpells = manySpells,
        maxAmount = 100,
        totalAmount = 4600,
    }
    window.typeDropdown:Select("DamageDone")
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        window.detailMaxOffset > 0,
        true,
        "long detail reports expose a scroll range"
    )
    assertEqual(window.detailRows[1].label.text, "Spell 201", "scroll start")
    window.detailPanel:RunScript("OnMouseWheel", -1)
    assertEqual(window.detailOffset, 1, "detail wheel advances one row")
    assertEqual(
        window.detailRows[1].label.text,
        "Spell 202",
        "detail scrolling advances the bounded row pool"
    )
    for _ = 1, 50 do
        window.detailPanel:RunScript("OnMouseWheel", -1)
    end
    assertEqual(
        window.detailOffset,
        39,
        "detail scrolling reaches the full uncapped report"
    )
    assertEqual(
        window.detailRows[5].label.text,
        "Spell 244",
        "spell entries beyond the former 40-row boundary remain reachable"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")

    detailSources[1].name = detailState.newSecretName("follower source")
    detailState.detailSources[36] = {
        combatSpells = {
            {
                combatSpellDetails = {
                    unitName = detailState.newSecretName("follower detail"),
                },
                spellID = 401,
                totalAmount = 300,
            },
        },
        maxAmount = 300,
        totalAmount = 300,
    }
    window.typeDropdown:Select("EnemyDamageTaken")
    row:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        window.detailOpen,
        true,
        "secret follower details open without a name comparison"
    )
    assertEqual(
        window.detailRows[1].label.text,
        "Spell 401",
        "secret follower detail source is rendered"
    )
    assertEqual(
        detailState.unsafeOperations,
        0,
        "secret follower names never reach a Lua operation"
    )
    window.detailPanel:RunScript("OnMouseUp", "RightButton")

    assertEqual(
        detailRenderer.SetEnabled(false),
        true,
        "detail-report renderer disables"
    )

    local fittedRenderer, fittedDM, fittedState = loadRenderer()
    fittedDM.config.width = 240
    fittedDM.config.headerHeight = 20
    fittedDM.config.barHeight = 18
    fittedDM.config.spacing = 2
    fittedDM.config.padding = 3
    fittedDM.config.windowHeights[1] = 124
    fittedDM.config.windowHeights[2] = 84
    fittedDM.config.windowHeights[3] = 84
    assertEqual(
        fittedRenderer.SetEnabled(true),
        true,
        "fitted default renderer enables"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow1.visibleRowCount,
        5,
        "fitted first meter retains five rows"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow2.visibleRowCount,
        3,
        "fitted middle meter retains three rows"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow3.visibleRowCount,
        3,
        "fitted top meter retains three rows"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow2.height,
        84,
        "fitted middle meter uses the compact three-row height"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow3.height,
        84,
        "fitted top meter uses the compact three-row height"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow2.resize.minHeight,
        84,
        "default density permits the compact three-row resize height"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow1.width,
        240,
        "fitted meter uses the compact tracker-width default"
    )
    fittedDM.config.headerHeight = 36
    fittedDM.config.barHeight = 36
    fittedDM.config.padding = 12
    fittedRenderer.ApplySettings()
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow2.resize.minHeight,
        96,
        "dense meter appearance keeps a complete row resize minimum"
    )
    assertEqual(
        fittedState.namedFrames.BFIDamageMeterWindow2.height,
        96,
        "dense meter appearance clamps the compact saved height to one row"
    )
    assertEqual(
        fittedRenderer.SetEnabled(false),
        true,
        "fitted default renderer disables"
    )

    local compactRenderer, compactDM, compactState = loadRenderer()
    compactDM.config.headerHeight = 36
    compactDM.config.barHeight = 36
    compactDM.config.padding = 12
    compactDM.config.spacing = 8
    for index = 1, 3 do
        compactDM.config.windowHeights[index] = 120
    end
    assertEqual(
        compactRenderer.SetEnabled(true),
        true,
        "compact detail renderer enables"
    )
    local compactWindow =
        compactState.namedFrames.BFIDamageMeterWindow1
    local compactRow = compactWindow.rows[1]
    assertEqual(compactWindow.visibleRowCount, 1, "compact meter has one row")
    compactRow:RunScript("OnMouseUp", "LeftButton")
    assertEqual(
        compactWindow.visibleDetailRowCount,
        1,
        "compact report keeps one visible detail row"
    )
    assertEqual(
        compactWindow.detailTitle.shown,
        false,
        "compact report releases the in-body title row"
    )
    assertEqual(
        compactWindow.detailRows[1].points[1].y,
        -12,
        "compact detail row stays inside the meter body"
    )
    compactWindow.detailPanel:RunScript("OnMouseUp", "RightButton")
    assertEqual(
        compactRenderer.SetEnabled(false),
        true,
        "compact detail renderer disables"
    )
end

RunDetailReportTests()

local function RunObjectiveTrackerLaneFitTests()
    local fitRenderer, fitDM, fitState, _, _, fitUIParent =
        loadRenderer()
    local dockFrame = fitState.objectiveTrackerDockFrame
    fitUIParent.bottom = 0
    dockFrame.bottom = 260

    fitDM.config.width = 240
    fitDM.config.headerHeight = 20
    fitDM.config.barHeight = 18
    fitDM.config.spacing = 2
    fitDM.config.padding = 3
    fitDM.config.windowHeights[1] = 124
    fitDM.config.windowHeights[2] = 104
    fitDM.config.windowHeights[3] = 104

    assertEqual(
        fitRenderer.SetEnabled(true),
        true,
        "tracker-lane renderer enables"
    )
    local firstWindow = fitState.namedFrames.BFIDamageMeterWindow1
    local secondWindow = fitState.namedFrames.BFIDamageMeterWindow2
    local thirdWindow = fitState.namedFrames.BFIDamageMeterWindow3
    local editModeEventFrame
    for _, frame in ipairs(fitState.frames) do
        if frame.events.EDIT_MODE_LAYOUTS_UPDATED then
            editModeEventFrame = frame
            break
        end
    end
    assertEqual(type(editModeEventFrame), "table",
        "tracker-lane renderer listens for native Edit Mode saves")
    assertEqual(firstWindow.visibleRowCount, 3,
        "constrained first meter keeps three rows")
    assertEqual(secondWindow.visibleRowCount, 3,
        "constrained second meter keeps three rows")
    assertEqual(thirdWindow.visibleRowCount, 2,
        "constrained third meter keeps two rows")
    assertEqual(firstWindow.height, 84,
        "constrained first height fits whole rows")
    assertEqual(secondWindow.height, 84,
        "constrained second height fits whole rows")
    assertEqual(thirdWindow.height, 64,
        "constrained third height fits whole rows")
    assertEqual(firstWindow.clamped, false,
        "tracker-lane root does not clamp over objectives")
    assertEqual(secondWindow.clamped, false,
        "tracker-lane child does not clamp over its sibling")
    assertEqual(firstWindow.resizable, false,
        "runtime fitting cannot overwrite the saved height")
    assertEqual(fitDM.config.windowHeights[1], 124,
        "runtime fitting preserves the first saved height")
    assertEqual(fitDM.config.windowHeights[2], 104,
        "runtime fitting preserves the second saved height")

    dockFrame.bottom = 400
    editModeEventFrame:RunScript("OnEvent", "EDIT_MODE_LAYOUTS_UPDATED")
    assertEqual(firstWindow.visibleRowCount, 5,
        "native height change restores first rows")
    assertEqual(secondWindow.visibleRowCount, 4,
        "native height change restores stacked rows")
    assertEqual(firstWindow.height, 124,
        "native height change restores saved first height")
    assertEqual(secondWindow.height, 104,
        "native height change restores saved second height")
    assertEqual(firstWindow.resizable, true,
        "restored saved height can be resized")
    local unchangedSizeCount = firstWindow.sizeChangeCount
    editModeEventFrame:RunScript("OnEvent", "EDIT_MODE_LAYOUTS_UPDATED")
    assertEqual(firstWindow.sizeChangeCount, unchangedSizeCount,
        "unchanged native height does not reflow the meters")

    dockFrame.bottom = 80
    fitState.callbacks.BFI_ObjectiveTrackerDockFrameChanged()
    assertEqual(firstWindow.runtimeMinimized, true,
        "full tracker collapses the first meter body")
    assertEqual(secondWindow.runtimeMinimized, true,
        "full tracker collapses the second meter body")
    assertEqual(thirdWindow.runtimeMinimized, true,
        "full tracker collapses the third meter body")
    assertEqual(firstWindow.height + secondWindow.height
        + thirdWindow.height + 8, 68,
        "header-only stack remains inside the 72-unit lane")
    assertEqual(firstWindow.body.shown, false,
        "runtime-minimized body stays hidden")
    assertEqual(thirdWindow.shown, true,
        "compact headers keep every configured meter reachable")
    firstWindow.minimize:Click()
    assertEqual(firstWindow.minimized, nil,
        "automatic collapse does not become a user collapse")

    dockFrame.bottom = 30
    fitState.callbacks.BFI_ObjectiveTrackerDockFrameChanged()
    assertEqual(firstWindow.shown, true,
        "the highest-priority meter header uses the final lane space")
    assertEqual(secondWindow.shown, false,
        "lower-priority meters hide when even headers cannot fit")
    assertEqual(thirdWindow.shown, false,
        "runtime hiding prevents an impossible stack from overlapping")
    assertEqual(fitDM.config.windowCount, 3,
        "runtime hiding preserves the configured meter count")

    fitDM.config.windowAnchors[1].x = -30
    fitState.callbacks.BFI_ObjectiveTrackerDockFrameChanged()
    assertEqual(firstWindow.height, 124,
        "custom root restores the user-owned saved height")
    assertEqual(firstWindow.clamped, true,
        "custom root keeps normal screen clamping")
    assertEqual(firstWindow.runtimeConstrained, false,
        "custom root opts out of tracker-lane fitting")

    fitDM.config.windowAnchors[1].x = -4
    dockFrame.bottom = fitState.secretGeometryToken
    fitState.callbacks.BFI_ObjectiveTrackerDockFrameChanged()
    assertEqual(firstWindow.height, 124,
        "secret tracker geometry leaves the saved height untouched")
    assertEqual(firstWindow.clamped, true,
        "secret tracker geometry fails closed to screen clamping")

    assertEqual(
        fitRenderer.SetEnabled(false),
        true,
        "tracker-lane renderer disables"
    )
end

RunObjectiveTrackerLaneFitTests()

print("damage_meter_renderer_test.lua: ok")
