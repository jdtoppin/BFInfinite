local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function record(harness, name, ...)
    harness.events[#harness.events + 1] = {
        name = name,
        args = {...},
    }
end

local function eventIndex(harness, name, predicate)
    for index, event in ipairs(harness.events) do
        if event.name == name
            and (not predicate or predicate(event))
        then
            return index
        end
    end
end

local function lastEvent(harness, name)
    for index = #harness.events, 1, -1 do
        if harness.events[index].name == name then
            return harness.events[index]
        end
    end
end

local function baseConfig()
    return {
        enabled = true,
        scope = "player",
        types = {
            magic = true,
            curse = true,
            disease = true,
            poison = true,
            bleed = true,
        },
        appearance = "bottom_gradient",
        alpha = 0.5,
        blendMode = "ADD",
    }
end

local function makeHarness()
    local harness = {
        events = {},
        frames = {},
        controllers = {},
    }
    local secretToken = setmetatable({}, {
        __tostring = function()
            error("secret token was coerced to text", 2)
        end,
    })
    local rawType = type
    local function guardedType(value)
        if rawequal(value, secretToken) then
            error("secret token reached type()", 2)
        end
        return rawType(value)
    end

    local UF = {
        config = {
            party = {
                indicators = {
                    healthBar = {
                        frameLevel = 3,
                    },
                },
            },
        },
    }
    local AF = {}
    local F = {}

    function AF.Copy(value)
        return copy(value)
    end

    function AF.GetTexture(name)
        return "texture:" .. name
    end

    function AF.GetColorRGB(name)
        local colors = {
            aura_magic = {0.2, 0.6, 1},
            aura_curse = {0.6, 0, 1},
            aura_disease = {0.6, 0.4, 0},
            aura_poison = {0, 0.6, 0},
            aura_bleed = {0.8, 0, 0},
            disabled = {0.3, 0.3, 0.3},
        }
        local color = assert(colors[name], "unexpected preview color")
        return unpack(color)
    end

    function AF.SetFrameLevel(frame, level, relativeTo)
        frame.frameLevel = level
        frame.frameLevelRelativeTo = relativeTo
        record(harness, "af.frame-level", frame, level, relativeTo)
    end

    function AF.Fire(event, ...)
        record(harness, "af.fire", event, ...)
    end

    AF.noop = function()
    end

    function F.isValueNonSecret(value)
        record(harness, "secret.check", value)
        return not rawequal(value, secretToken)
    end

    local textureMethods = {}

    function textureMethods:SetAllPoints(target)
        self.allPointsTarget = target
    end

    function textureMethods:SetTexture(texture)
        self.texture = texture
        self.solidColor = nil
    end

    function textureMethods:SetColorTexture(...)
        self.solidColor = {...}
        self.texture = nil
    end

    function textureMethods:SetVertexColor(...)
        self.vertexColor = {...}
    end

    function textureMethods:SetAlpha(alpha)
        self.alpha = alpha
    end

    function textureMethods:SetBlendMode(blendMode)
        self.blendMode = blendMode
    end

    local frameMethods = {}

    function frameMethods:GetName()
        return self.name
    end

    function frameMethods:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function frameMethods:SetAllPoints(target)
        self.allPointsTarget = target
    end

    function frameMethods:CreateTexture(_, drawLayer, _, subLevel)
        local texture = setmetatable({
            drawLayer = drawLayer,
            subLevel = subLevel,
        }, {
            __index = textureMethods,
        })
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end

    function frameMethods:Show()
        self.shown = true
        record(harness, "frame.show", self)
    end

    function frameMethods:Hide()
        self.shown = false
        record(harness, "frame.hide", self)
    end

    local function newFrame(_, name, parent)
        local frame = setmetatable({
            name = name,
            parent = parent,
            shown = false,
        }, {
            __index = frameMethods,
        })
        harness.frames[#harness.frames + 1] = frame
        record(harness, "frame.create", frame)
        return frame
    end

    function UF.HasNativeAuraContainerBackend()
        return true
    end

    function UF.CreateNativeGroupAuraContainerController(
        parent,
        name,
        seed
    )
        local frame = newFrame("Frame", name, parent)
        local controller = {
            frame = frame,
            seed = seed,
        }

        function controller:GetFrame()
            return self.frame
        end

        function controller:Rebuild(spec)
            self.spec = spec
            self.built = true
            record(harness, "controller.rebuild", self, spec)
        end

        function controller:ApplyTuning(tuning)
            self.tuning = tuning
            record(harness, "controller.tuning", self, tuning)
        end

        function controller:SetUnit(unit)
            self.unit = unit
            record(harness, "controller.unit", self, unit)
        end

        function controller:SetEnabled(enabled)
            self.enabled = enabled
            record(harness, "controller.enabled", self, enabled)
        end

        function controller:SetShown(shown)
            self.shown = shown
            record(harness, "controller.shown", self, shown)
        end

        function controller:IsPresentationApplied()
            return self.enabled == true and self.shown == true
        end

        function controller:Refresh()
            record(harness, "controller.refresh", self)
        end

        function controller:Destroy()
            self.destroyed = true
            record(harness, "controller.destroy", self)
        end

        harness.controllers[#harness.controllers + 1] = controller
        return controller
    end

    local function forbidden(name)
        return function()
            error("forbidden aura data access: " .. name, 2)
        end
    end
    local function forbiddenTable(name)
        return setmetatable({}, {
            __index = function(_, key)
                error("forbidden aura data access: "
                    .. name .. "." .. tostring(key), 2)
            end,
        })
    end

    local BFI = {
        funcs = F,
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        AuraContainerSortMethod = {
            UnitFrameDebuff = 301,
        },
        AuraContainerSortDirection = {
            Normal = 401,
        },
        CustomAuraContainerAuraProcessingPolicy = {
            None = 501,
        },
        CreateFrame = newFrame,
        C_UnitAuras = forbiddenTable("C_UnitAuras"),
        C_TooltipInfo = forbiddenTable("C_TooltipInfo"),
        GetUnitAuraInstanceIDs = forbidden("GetUnitAuraInstanceIDs"),
        assert = assert,
        error = error,
        ipairs = ipairs,
        math = math,
        pairs = pairs,
        rawequal = rawequal,
        select = select,
        tonumber = tonumber,
        tostring = tostring,
        type = guardedType,
        unpack = unpack,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected dispel runtime global: "
                .. tostring(key), 2)
        end,
    })

    for _, path in ipairs({
        "Modules/UnitFrames/DispelSpec.lua",
        "Modules/UnitFrames/DispelRuntime.lua",
    }) do
        local chunk, loadError = loadfile(path)
        assertTrue(chunk, loadError)
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end

    function harness:NewRuntime(unit)
        local healthBar = {
            _configuredFrameLevel = 3,
            enabled = true,
        }
        local root = setmetatable({
            effectiveUnit = unit,
            inConfigMode = false,
            indicators = {
                healthBar = healthBar,
            },
            name = "BFI_PartyUnitButton1",
            unit = unit,
            _nativeAuraContainers = {
                dispels = {
                    name = "dispel-seed",
                },
            },
        }, {
            __index = frameMethods,
        })
        local runtime = UF.CreateGroupNativeDispelHighlight(
            root,
            root.name .. "_Dispels",
            "dispels"
        )
        return runtime, root, healthBar,
            harness.controllers[#harness.controllers]
    end

    function harness:ClearEvents()
        self.events = {}
    end

    harness.AF = AF
    harness.BFI = BFI
    harness.secretToken = secretToken
    harness.UF = UF
    return harness
end

local function testCompilerUsesOnlyNativeFilterContracts()
    local harness = makeHarness()
    local anchor = {}
    local config = baseConfig()
    local descriptor = harness.UF.CompileNativeDispelHighlightSpec(
        "party1",
        config,
        anchor,
        7.4
    )
    local slot = descriptor.completeSpec.slots[1]

    assertEqual(slot.kind, "dispelOverlay", "overlay slot kind")
    assertEqual(slot.anchorTarget, anchor, "health-bar anchor identity")
    assertEqual(slot.filterString, "HARMFUL|RAID",
        "player-dispel filter")
    assertEqual(slot.sortMethod, 301,
        "native UnitFrameDebuff sort")
    assertEqual(slot.sortDirection, 401,
        "native normal sort direction")
    assertEqual(countKeys(slot.candidateFilters.includeDispelTypes), 5,
        "all dispel types")
    assertEqual(slot.overlayStyle.drawLayer, "ARTWORK",
        "overlay draw layer")
    assertEqual(slot.overlayStyle.frameLevelOffset, 0,
        "overlay frame-level offset")
    assertEqual(slot.overlayStyle.texture,
        "texture:Gradient_Linear_Bottom",
        "bottom-gradient texture")
    assertEqual(descriptor.constructionKey.anchorFrameLevel, 7,
        "sanitized anchor frame level")
    assertEqual(descriptor.tuning.slots[1].kind, nil,
        "dynamic tuning does not reconstruct overlay")

    config.scope = "group"
    config.types.magic = false
    config.types.bleed = false
    local group = harness.UF.CompileNativeDispelHighlightSpec(
        "party1",
        config,
        anchor,
        7
    )
    local include = group.tuning.slots[1]
        .candidateFilters.includeDispelTypes
    assertEqual(group.tuning.slots[1].filterString,
        "HARMFUL|RAID_PLAYER_DISPELLABLE",
        "group-dispel filter")
    assertEqual(include.Magic, nil, "Magic exclusion")
    assertEqual(include.Bleed, nil, "Bleed exclusion")
    assertEqual(countKeys(include), 3, "selected dispel types")
    assertEqual(group.constructionKey.appearance,
        descriptor.constructionKey.appearance,
        "scope and types are dynamic")

    config.scope = "any"
    local any = harness.UF.CompileNativeDispelHighlightSpec(
        "party1",
        config,
        anchor,
        101
    )
    assertEqual(any.tuning.slots[1].filterString,
        "HARMFUL|DISPELLABLE",
        "any-dispel filter")
    assertEqual(any.constructionKey.anchorFrameLevel, 100,
        "anchor frame-level upper clamp")
end

local function testSecretUnitsFailClosedAndHideBeforeRetarget()
    local harness = makeHarness()
    local runtime, root, _, controller =
        harness:NewRuntime("party1")
    runtime.enabled = true
    runtime:LoadConfig(baseConfig())
    runtime:Enable()

    harness:ClearEvents()
    runtime:SetUnit(harness.secretToken)
    local hideIndex = eventIndex(
        harness,
        "controller.shown",
        function(event)
            return event.args[2] == false
        end
    )
    local unitIndex = eventIndex(
        harness,
        "controller.unit",
        function(event)
            return event.args[2] == "none"
        end
    )
    assertTrue(hideIndex, "secret retarget hides stale overlay")
    assertTrue(unitIndex, "secret retarget selects inert unit")
    assertTrue(hideIndex < unitIndex,
        "stale overlay hides before secret retarget")
    assertEqual(runtime:GetNativeDispelState().unit, "none",
        "explicit secret remains fail-closed")
    assertEqual(controller.enabled, false,
        "secret retarget disables native overlay")

    harness:ClearEvents()
    root.effectiveUnit = harness.secretToken
    root.unit = "party1"
    runtime:Update(true)
    assertEqual(runtime:GetNativeDispelState().unit, "none",
        "secret effective unit does not fall back to root unit")

    root.effectiveUnit = "party2"
    root.unit = "party2"
    harness:ClearEvents()
    runtime:SetUnit("party2")
    hideIndex = eventIndex(
        harness,
        "controller.shown",
        function(event)
            return event.args[2] == false
        end
    )
    unitIndex = eventIndex(
        harness,
        "controller.unit",
        function(event)
            return event.args[2] == "party2"
        end
    )
    assertTrue(hideIndex and unitIndex and hideIndex < unitIndex,
        "clean retarget hides stale overlay before SetUnit")
end

local function testHealthBarGatePreviewAndReloadDependencies()
    local harness = makeHarness()
    local runtime, root, healthBar, controller =
        harness:NewRuntime("party1")
    local config = baseConfig()
    runtime.enabled = true
    runtime:LoadConfig(config)
    runtime:Enable()
    assertEqual(controller.enabled, true,
        "enabled runtime drives native overlay")

    healthBar.enabled = false
    runtime:Update(true)
    assertEqual(controller.enabled, false,
        "disabled health bar suppresses native overlay")

    healthBar.enabled = true
    runtime:EnableConfigMode()
    local preview = runtime._preview
    assertTrue(preview, "synthetic config preview")
    assertEqual(preview.parent, root, "preview ownership")
    assertEqual(preview.allPointsTarget, healthBar,
        "preview health-bar bounds")
    assertEqual(preview.mouseEnabled, false,
        "preview mouse disabled")
    assertEqual(preview.shown, true,
        "preview shown in config mode")
    assertEqual(controller.enabled, false,
        "native container disabled in config mode")
    assertEqual(preview.texture.texture,
        "texture:Gradient_Linear_Bottom",
        "preview uses configured appearance")

    local dynamic = baseConfig()
    dynamic.scope = "group"
    dynamic.types.magic = false
    assertEqual(runtime:RequiresReloadForConfig(dynamic), false,
        "scope and type changes tune live")
    harness:ClearEvents()
    runtime:LoadConfig(dynamic)
    assertEqual(lastEvent(harness, "af.fire"), nil,
        "dynamic tuning does not request reload")

    healthBar._configuredFrameLevel = 4
    assertEqual(runtime:RequiresReloadForConfig(dynamic), true,
        "health-bar frame level is a construction dependency")
    harness:ClearEvents()
    runtime:LoadConfig(dynamic)
    assertEqual(runtime:GetNativeDispelState().reloadRequired, true,
        "frame-level mutation quiesces pending reload")
    assertEqual(lastEvent(harness, "controller.enabled").args[2],
        false,
        "pending reload disables old overlay")
    local reloadEvent = lastEvent(harness, "af.fire")
    assertTrue(reloadEvent, "pending reload is announced")
    assertEqual(reloadEvent.args[1],
        "BFI_NativeAuraReloadRequired",
        "pending reload callback")

    for _, event in ipairs(harness.events) do
        assertTrue(event.name ~= "managed-button.frame-level",
            "runtime must not restack a managed AuraButton")
    end
end

testCompilerUsesOnlyNativeFilterContracts()
testSecretUnitsFailClosedAndHideBeforeRetarget()
testHealthBarGatePreviewAndReloadDependencies()

print("unit_frame_dispel_highlight_test.lua: ok")
