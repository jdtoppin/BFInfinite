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

local function assertContains(value, expected, message)
    assertTrue(
        type(value) == "string"
            and value:find(expected, 1, true) ~= nil,
        message
    )
end

local function assertNotContains(value, expected, message)
    assertTrue(
        type(value) ~= "string"
            or value:find(expected, 1, true) == nil,
        message
    )
end

local CANONICAL_FIELDS = {
    "all",
    "player",
    "notPlayer",
    "raidInCombat",
    "raidPlayerDispellable",
    "bigDefensive",
    "externalDefensive",
}

local LEGACY_FIELDS = {
    "castByMe",
    "castByOthers",
    "castByUnit",
    "castByNPC",
    "isBossAura",
    "dispellable",
    "canBeDispelled",
}

local function updateMockStringHeight(widget)
    if widget.kind ~= "fontString" then return end

    local length = #(widget.text or "")
    if not widget.wordWrap or length <= 60 then
        widget.stringHeight = 12
    elseif length <= 120 then
        widget.stringHeight = 24
    else
        widget.stringHeight = 36
    end
end

local function makeWidget(kind, harness, parent, text)
    local widget = {
        enabled = true,
        initialText = text,
        kind = kind,
        parent = parent,
        shown = true,
        text = text,
    }

    function widget:EnablePushEffect()
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:GetLineHeight()
        return 12
    end

    function widget:GetStringHeight()
        return self.stringHeight or 12
    end

    function widget:Hide()
        self.shown = false
    end

    function widget:HookOnEnter(callback)
        self.onEnter = callback
    end

    function widget:HookOnLeave(callback)
        self.onLeave = callback
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:RegisterForClicks()
    end

    function widget:SetAllPoints()
    end

    function widget:SetBorderColor()
    end

    function widget:SetChecked(value)
        self.checked = value
    end

    function widget:SetColor()
    end

    function widget:SetEnabled(value)
        self.enabled = value
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetJustifyH(value)
        self.justifyH = value
    end

    function widget:SetJustifyV(value)
        self.justifyV = value
    end

    function widget:SetLabel(value)
        self.label = value
    end

    function widget:SetOnCheck(callback)
        self.onCheck = callback
    end

    function widget:SetOnClick(callback)
        self.onClick = callback
    end

    function widget:SetOnEnterPressed(callback)
        self.onEnterPressed = callback
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetOnTextChanged(callback)
        self.onTextChanged = callback
    end

    function widget:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetSpacing()
    end

    function widget:SetText(value)
        self.text = value
        updateMockStringHeight(self)
    end

    function widget:SetTextJustifyH()
    end

    function widget:SetTexture()
    end

    function widget:SetTooltip(title, body)
        self.tooltipTitle = title
        self.tooltipBody = body
    end

    function widget:SetValue(value)
        self.value = value
    end

    function widget:SetWordWrap(value)
        self.wordWrap = value
        updateMockStringHeight(self)
    end

    function widget:Show()
        self.shown = true
    end

    harness.widgets[#harness.widgets + 1] = widget
    if parent and parent.widgets then
        parent.widgets[#parent.widgets + 1] = widget
    end
    updateMockStringHeight(widget)
    return widget
end

local function makeParent()
    local parent = {
        _contentHeights = {},
    }

    function parent:GetParent()
        return self
    end

    return parent
end

local function findWidget(pane, kind, field, value)
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == kind and widget[field] == value then
            return widget
        end
    end
end

local function hasPoint(widget, point, relativeTo, relativePoint)
    for _, values in ipairs(widget.points or {}) do
        if values[1] == point
            and (relativeTo == nil or values[2] == relativeTo)
            and (
                relativePoint == nil
                or values[3] == relativePoint
            )
        then
            return true
        end
    end
    return false
end

local function makeHarness(isRetail, hasNativeBackend)
    local harness = {
        configLoads = {},
        panes = {},
        setCalls = {},
        widgets = {},
        resizeCalls = 0,
    }
    local UF = {}
    local AF = {
        isRetail = isRetail,
    }
    local F = {}
    local paneIndex = 0
    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })

    function F.ResolveUnitFrameAuraFilters(baseFilter, config)
        if baseFilter ~= "HELPFUL" and baseFilter ~= "HARMFUL" then
            return
        end
        if type(config) ~= "table" then return end

        local hasCanonical = false
        for _, field in ipairs(CANONICAL_FIELDS) do
            if config[field] ~= nil then
                hasCanonical = true
                break
            end
        end

        if hasCanonical then
            local all = config.all == true
            local player = config.player == true
            local notPlayer = config.notPlayer == true
            if player and notPlayer then
                all = true
            end
            return {
                all = all,
                player = not all and player,
                notPlayer = not all and notPlayer,
                raidInCombat =
                    not all and config.raidInCombat == true,
                raidPlayerDispellable =
                    not all
                    and config.raidPlayerDispellable == true,
                bigDefensive =
                    not all
                    and baseFilter == "HELPFUL"
                    and config.bigDefensive == true,
                externalDefensive =
                    not all
                    and baseFilter == "HELPFUL"
                    and config.externalDefensive == true,
            }, {
                legacy = false,
                legacySourceFilterUsesSuperset = false,
                bossAuraUsesCuratedRaidInCombat = false,
            }
        end

        local castByMe = config.castByMe == true
        local castByOthers = config.castByOthers == true
        local castByUnit = config.castByUnit == true
        local castByNPC = config.castByNPC == true
        local exactNotPlayer = castByOthers and castByNPC
        local notPlayer = castByOthers or castByNPC
        local exactAll = castByMe and exactNotPlayer
        local all = castByUnit or (castByMe and notPlayer)
        local migration = {
            legacy = true,
            legacySourceFilterUsesSuperset =
                (notPlayer and not exactNotPlayer)
                or (all and not exactAll),
            bossAuraUsesCuratedRaidInCombat =
                not all and config.isBossAura == true,
        }
        if all then
            return {
                all = true,
                player = false,
                notPlayer = false,
                raidInCombat = false,
                raidPlayerDispellable = false,
                bigDefensive = false,
                externalDefensive = false,
            }, migration
        end

        return {
            all = false,
            player = castByMe,
            notPlayer = notPlayer,
            raidInCombat = config.isBossAura == true,
            raidPlayerDispellable =
                config.dispellable == true
                or config.canBeDispelled == true,
            bigDefensive = false,
            externalDefensive = false,
        }, migration
    end

    function F.SetUnitFrameAuraFilter(
        baseFilter,
        config,
        field,
        value
    )
        local supported = false
        for _, candidate in ipairs(CANONICAL_FIELDS) do
            if candidate == field then
                supported = true
                break
            end
        end
        if not supported or type(value) ~= "boolean" then
            return false
        end
        if baseFilter ~= "HELPFUL"
            and (
                field == "bigDefensive"
                or field == "externalDefensive"
            )
        then
            return false
        end

        local resolved =
            F.ResolveUnitFrameAuraFilters(baseFilter, config)
        if not resolved then return false end
        resolved[field] = value
        if field == "all" and value then
            for _, canonical in ipairs(CANONICAL_FIELDS) do
                if canonical ~= "all" then
                    resolved[canonical] = false
                end
            end
        elseif field ~= "all" and value then
            resolved.all = false
            if resolved.player and resolved.notPlayer then
                resolved.all = true
                resolved.player = false
                resolved.notPlayer = false
            end
        end
        for _, canonical in ipairs(CANONICAL_FIELDS) do
            config[canonical] = resolved[canonical]
        end
        for _, legacy in ipairs(LEGACY_FIELDS) do
            config[legacy] = nil
        end
        harness.setCalls[#harness.setCalls + 1] = {
            baseFilter = baseFilter,
            field = field,
            value = value,
        }
        return true
    end

    function AF.ClearPoints(widget)
        widget.points = {}
    end

    function AF.ClearTooltip(widget)
        widget.tooltipTitle = nil
        widget.tooltipBody = nil
    end

    function AF.CreateBorderedFrame(
        parent,
        name,
        _,
        height
    )
        paneIndex = paneIndex + 1
        local pane = {
            height = height or 0,
            index = paneIndex,
            name = name,
            parent = parent,
            widgets = {},
        }

        function pane:GetHeight()
            return self.height
        end

        function pane:SetHeight(value)
            self.height = value
        end

        function pane:SetOnHide(callback)
            self.onHide = callback
        end

        harness.panes[#harness.panes + 1] = pane
        return pane
    end

    function AF.CreateButton(parent, _, _, _, _)
        return makeWidget("button", harness, parent)
    end

    function AF.CreateCheckButton(parent, text)
        return makeWidget(
            "checkButton",
            harness,
            parent,
            text
        )
    end

    function AF.CreateDropdown(parent)
        return makeWidget("dropdown", harness, parent)
    end

    function AF.CreateFontString(parent, text)
        return makeWidget(
            "fontString",
            harness,
            parent,
            text
        )
    end

    function AF.CreateObjectPool(factory, release)
        local pool = {
            active = {},
        }

        function pool:Acquire()
            local object = factory()
            self.active[#self.active + 1] = object
            return object
        end

        function pool:ReleaseAll()
            for _, object in ipairs(self.active) do
                release(self, object)
            end
            self.active = {}
        end

        return pool
    end

    function AF.CreateSlider(parent, text)
        local slider =
            makeWidget("slider", harness, parent, text)
        slider.label = text
        return slider
    end

    function AF.Debug()
    end

    function AF.GetColorStr()
        return ""
    end

    function AF.GetDropdownItems_Arrangement_Simple()
        return {
            {text = "Left to Right", value = "left_to_right"},
        }
    end

    function AF.GetEditBox(parent)
        return makeWidget("editBox", harness, parent)
    end

    function AF.GetGradientText(text)
        return text
    end

    function AF.GetIcon(name)
        return name
    end

    function AF.GetIconString(name)
        return "<" .. name .. ">"
    end

    function AF.GetSpellInfo(spell)
        return "Spell " .. tostring(spell), "Icon " .. tostring(spell)
    end

    function AF.ReSize()
        harness.resizeCalls = harness.resizeCalls + 1
    end

    function AF.Remove(values, expected)
        for index, value in ipairs(values) do
            if value == expected then
                table.remove(values, index)
                return
            end
        end
    end

    function AF.SetEnabled(enabled, ...)
        for index = 1, select("#", ...) do
            select(index, ...):SetEnabled(enabled)
        end
    end

    function AF.SetListHeight(
        pane,
        itemNum,
        itemHeight,
        itemSpacing,
        topPadding,
        bottomPadding
    )
        pane.listTopPadding = topPadding
        pane.height = itemNum * itemHeight
            + (itemNum - 1) * itemSpacing
            + topPadding
            + bottomPadding
    end

    function AF.SetPoint(widget, ...)
        widget.points = widget.points or {}
        widget.points[#widget.points + 1] = {...}
    end

    function AF.SpellExists()
        return true
    end

    function AF.WrapTextInColor(text)
        return text
    end

    AF.Tooltip2 = {
        Hide = function()
        end,
        SetOwner = function()
        end,
        SetPoint = function()
        end,
        SetSpellByID = function()
        end,
        Show = function()
        end,
    }

    function UF.HasNativeAuraContainerBackend()
        return hasNativeBackend
    end

    function UF.LoadIndicatorConfig(frame, id, config)
        harness.configLoads[#harness.configLoads + 1] = {
            config = config,
            frame = frame,
            id = id,
        }
    end

    function UF.LoadIndicatorPosition()
    end

    local BFI = {
        funcs = F,
        L = L,
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        BFIOptionsFrame_UnitFramesPanel = {},
        NONE = "None",
        ceil = math.ceil,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        string = string,
        table = table,
        tinsert = table.insert,
        tostring = tostring,
        type = type,
        RunNextFrame = function(callback)
            callback()
        end,
        wipe = function(value)
            for key in pairs(value) do
                value[key] = nil
            end
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected aura filter option global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local chunk, loadError =
        loadfile("Options/UnitFrames_Options.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local builders
    local index = 1
    while true do
        local name, value =
            debug.getupvalue(F.GetUnitFrameOptions, index)
        if not name then break end
        if name == "builder" then
            builders = value
            break
        end
        index = index + 1
    end
    assertTrue(builders, "options builder registry")

    harness.AF = AF
    harness.builders = builders
    harness.F = F
    harness.UF = UF

    function harness:ClearLoads()
        self.configLoads = {}
    end

    return harness
end

local function newFrame(id, runtimeKind)
    local frame = {
        indicators = {
            buffs = {},
            debuffs = {},
        },
    }
    if runtimeKind then
        local indicator = {
            LoadConfig = function()
            end,
        }
        if runtimeKind == "native" then
            indicator.GetNativeAuraState = function()
                return {}
            end
        end
        frame.indicators[id] = indicator
    end
    return frame
end

local function newInfo(id, owner, filters, runtimeKind)
    owner = owner or "target"
    local target
    if owner == "party" or owner == "raid" then
        local count = owner == "party" and 5 or 40
        target = {
            header = {},
        }
        for index = 1, count do
            target.header[index] = newFrame(id, runtimeKind)
        end
    elseif owner == "boss" then
        target = {}
        for index = 1, 8 do
            target[index] = newFrame(id, runtimeKind)
        end
    else
        target = newFrame(id, runtimeKind)
    end

    return {
        cfg = {
            auraTypeColor = {
                castByMe = true,
                debuffType = true,
                dispellable = true,
            },
            blacklist = {12345},
            cooldownStyle = "clock_with_leading_edge",
            filters = filters or {},
            height = 19,
            mode = "blacklist",
            numPerLine = 11,
            numTotal = 22,
            orientation = "left_to_right",
            spacingX = 1,
            spacingY = 1,
            subFrame = {
                desaturated = true,
                enabled = true,
                filter = "notCastByMe",
                height = 17,
                width = 17,
            },
            whitelist = {},
            width = 19,
        },
        id = id,
        owner = owner,
        target = target,
    }
end

local function assertItemValues(widget, expected, message)
    assertEqual(#widget.items, #expected, message .. " count")
    for index, value in ipairs(expected) do
        assertEqual(
            widget.items[index].value,
            value,
            message .. " item " .. index
        )
    end
end

local function assertFanout(harness, info, expected, message)
    assertEqual(#harness.configLoads, expected, message .. " count")
    for _, call in ipairs(harness.configLoads) do
        assertEqual(call.id, info.id, message .. " indicator")
        assertEqual(call.config, info.cfg, message .. " config")
    end
end

local function assertCanonical(config, expected, message)
    for _, field in ipairs(CANONICAL_FIELDS) do
        assertEqual(
            config[field],
            expected[field],
            message .. " " .. field
        )
        assertEqual(
            type(config[field]),
            "boolean",
            message .. " " .. field .. " type"
        )
    end
    for _, field in ipairs(LEGACY_FIELDS) do
        assertEqual(
            config[field],
            nil,
            message .. " retired " .. field
        )
    end
end

local function testRetailCanonicalFilters(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)
    local parent = makeParent()
    local pane =
        harness.builders.auraBaseFilters(parent)
    local info = newInfo("buffs", "boss", {
        castByMe = true,
        castByOthers = false,
        castByUnit = true,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    })

    pane.Load(info)
    local allAuras = findWidget(
        pane,
        "checkButton",
        "text",
        "All Auras"
    )
    local player = findWidget(
        pane,
        "checkButton",
        "text",
        "Player, Pet, or Vehicle"
    )
    local notPlayer = findWidget(
        pane,
        "checkButton",
        "text",
        "Not Player, Pet, or Vehicle"
    )
    local bigDefensive = findWidget(
        pane,
        "checkButton",
        "text",
        "Big Defensive"
    )
    local externalDefensive = findWidget(
        pane,
        "checkButton",
        "text",
        "External Defensive"
    )
    local raidInCombat = findWidget(
        pane,
        "checkButton",
        "text",
        "Raid In Combat"
    )
    local raidDispellable = findWidget(
        pane,
        "checkButton",
        "text",
        "Raid Player-Dispellable"
    )
    local retiredDispellable = findWidget(
        pane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    local tip = findWidget(
        pane,
        "fontString",
        "initialText",
        "The aura will show if any enabled filter is met"
    )

    assertTrue(allAuras and player and notPlayer,
        version .. " base and source-partition controls")
    assertTrue(bigDefensive and externalDefensive,
        version .. " defensive category controls")
    assertTrue(raidInCombat,
        version .. " raid-in-combat category control")
    assertTrue(raidDispellable,
        version .. " raid-dispellable category control")
    assertContains(
        tip.text,
        "All Auras overrides",
        version .. " category explanation"
    )
    assertEqual(tip.wordWrap, true,
        version .. " category explanation word wrap")
    assertEqual(tip.justifyH, "LEFT",
        version .. " category explanation horizontal alignment")
    assertEqual(tip.justifyV, "TOP",
        version .. " category explanation vertical alignment")
    assertTrue(
        hasPoint(tip, "TOPLEFT")
            and hasPoint(tip, "TOPRIGHT"),
        version .. " category explanation width bounds"
    )
    assertTrue(
        hasPoint(
            allAuras,
            "TOPLEFT",
            tip,
            "BOTTOMLEFT"
        ),
        version .. " category controls follow explanation"
    )
    assertTrue(
        pane.height > 117,
        version .. " category pane wrapped height"
    )
    assertEqual(
        parent._contentHeights[pane.index],
        tostring(pane.height),
        version .. " category scroll height"
    )
    assertTrue(
        harness.resizeCalls > 0,
        version .. " category scroll recalculation"
    )
    assertEqual(retiredDispellable.shown, false,
        version .. " legacy dispellable visibility")
    assertEqual(allAuras.checked, true,
        version .. " migrated all state")
    assertEqual(player.checked, false,
        version .. " migrated player state")
    assertEqual(notPlayer.checked, false,
        version .. " migrated not-player state")
    assertEqual(bigDefensive.checked, false,
        version .. " migrated big defensive state")
    assertEqual(externalDefensive.checked, false,
        version .. " migrated external defensive state")
    assertEqual(raidInCombat.checked, false,
        version .. " migrated raid-in-combat state")
    assertEqual(raidDispellable.checked, false,
        version .. " migrated raid-dispellable state")
    assertEqual(
        allAuras.tooltipTitle,
        "Conservative Legacy Migration",
        version .. " widened source migration warning"
    )
    assertContains(
        allAuras.tooltipBody,
        "not silently lost",
        version .. " widened source migration explanation"
    )

    harness:ClearLoads()
    local actions = {
        {widget = allAuras, field = "all", value = false},
        {widget = player, field = "player", value = true},
        {
            widget = notPlayer,
            field = "notPlayer",
            value = true,
        },
        {widget = allAuras, field = "all", value = false},
        {
            widget = bigDefensive,
            field = "bigDefensive",
            value = true,
        },
        {
            widget = externalDefensive,
            field = "externalDefensive",
            value = true,
        },
        {
            widget = raidInCombat,
            field = "raidInCombat",
            value = true,
        },
        {
            widget = raidDispellable,
            field = "raidPlayerDispellable",
            value = true,
        },
    }
    for index, action in ipairs(actions) do
        action.widget.onCheck(action.value)
        assertEqual(
            harness.setCalls[index].field,
            action.field,
            version .. " callback field " .. index
        )
        assertEqual(
            harness.setCalls[index].baseFilter,
            "HELPFUL",
            version .. " callback base filter " .. index
        )
        assertEqual(
            #harness.configLoads,
            index * 8,
            version .. " callback fan-out " .. index
        )
    end
    assertFanout(
        harness,
        info,
        64,
        version .. " canonical callback fan-out"
    )
    assertCanonical(info.cfg.filters, {
        all = false,
        player = false,
        notPlayer = false,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
    }, version .. " canonical materialization")

    local harmful = newInfo("debuffs", "target", {
        player = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
    })
    pane.Load(harmful)
    assertEqual(bigDefensive.checked, false,
        version .. " harmful big defensive state")
    assertEqual(externalDefensive.checked, false,
        version .. " harmful external defensive state")
    assertEqual(bigDefensive.enabled, false,
        version .. " harmful big defensive enabled state")
    assertEqual(externalDefensive.enabled, false,
        version .. " harmful external defensive enabled state")
    assertEqual(raidDispellable.enabled, true,
        version .. " hostile raid-dispellable enabled state")
    assertEqual(allAuras.enabled, true,
        version .. " harmful all enabled state")
    assertEqual(notPlayer.enabled, true,
        version .. " harmful not-player enabled state")

    local friendly = newInfo("buffs", "party", {
        player = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
    })
    pane.Load(friendly)
    assertEqual(raidDispellable.enabled, false,
        version .. " friendly raid-dispellable enabled state")

    local sourceOnly = newInfo("debuffs", "target", {
        castByMe = false,
        castByOthers = true,
        castByUnit = false,
        castByNPC = false,
        isBossAura = false,
        dispellable = false,
    })
    pane.Load(sourceOnly)
    assertEqual(allAuras.checked, false,
        version .. " source-only all state")
    assertEqual(notPlayer.checked, true,
        version .. " source-only not-player state")

    local bossOnly = newInfo("debuffs", "target", {
        castByMe = false,
        castByOthers = false,
        castByUnit = false,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    })
    pane.Load(bossOnly)
    assertEqual(raidInCombat.checked, true,
        version .. " legacy boss curated state")
    assertEqual(
        raidInCombat.tooltipTitle,
        "Conservative Legacy Migration",
        version .. " legacy boss approximation warning"
    )
end

local function testRetailSpellLists(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)
    local parent = makeParent()
    local pane = harness.builders.auraBlackListWhitelist(parent)
    local info = newInfo(
        hasNativeBackend and "debuffs" or "buffs",
        "target"
    )

    pane.Load(info)
    local mode = findWidget(pane, "dropdown", "kind", "dropdown")
    local tip = findWidget(pane, "fontString", "kind", "fontString")
    local addButton
    local spellButton
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == "button" and widget.spell == 12345 then
            spellButton = widget
        elseif widget.kind == "button" and not widget.spell then
            addButton = addButton or widget
        end
    end

    assertEqual(mode.enabled, false,
        version .. " spell-list mode enabled state")
    assertEqual(addButton.enabled, false,
        version .. " spell-list add enabled state")
    assertEqual(spellButton.enabled, false,
        version .. " spell-list entry enabled state")
    assertEqual(tip.wordWrap, true,
        version .. " spell-list explanation word wrap")
    assertEqual(tip.justifyH, "LEFT",
        version .. " spell-list explanation horizontal alignment")
    assertEqual(tip.justifyV, "TOP",
        version .. " spell-list explanation vertical alignment")
    assertTrue(
        hasPoint(tip, "TOPLEFT")
            and hasPoint(tip, "TOPRIGHT"),
        version .. " spell-list explanation width bounds"
    )
    assertTrue(
        hasPoint(
            spellButton,
            "TOPLEFT",
            tip,
            "BOTTOMLEFT"
        ),
        version .. " spell-list controls follow explanation"
    )
    assertTrue(
        pane.listTopPadding > 36,
        version .. " spell-list wrapped top padding"
    )
    assertEqual(
        parent._contentHeights[pane.index],
        tostring(pane.height),
        version .. " spell-list scroll height"
    )
    assertTrue(
        harness.resizeCalls > 0,
        version .. " spell-list scroll recalculation"
    )
    assertEqual(mode.items[1].text,
        "Exclude Spell IDs (Reaction-Limited)",
        version .. " blacklist label")
    assertEqual(mode.items[2].text,
        "Include Only Spell IDs (Reaction-Limited)",
        version .. " whitelist label")
    assertItemValues(
        mode,
        {"blacklist", "whitelist"},
        version .. " spell-list modes"
    )
    if hasNativeBackend then
        assertContains(
            tip.text,
            "friendly buffs and enemy debuffs",
            version .. " spell-list warning"
        )
        assertContains(
            tip.text,
            "Never Secret aura",
            version .. " spell-list reaction warning"
        )
        assertContains(
            tip.text,
            "disabled pending live reaction and secret validation",
            version .. " spell-list read-only warning"
        )
    else
        assertContains(
            tip.text,
            "require the Retail 12.1 native aura container",
            version .. " spell-list backend warning"
        )
        assertContains(
            tip.text,
            "editing is unavailable",
            version .. " spell-list read-only warning"
        )
    end
end

local ALL_AURA_OWNERS = {
    "player",
    "target",
    "focus",
    "pet",
    "targettarget",
    "focustarget",
    "pettarget",
    "party",
    "raid",
    "boss",
}

local NATIVE_BUFF_OWNERS = {
    "player",
    "pet",
    "party",
    "raid",
}

local LEGACY_BUFF_OWNERS = {
    "target",
    "focus",
    "targettarget",
    "focustarget",
    "pettarget",
    "boss",
}

local function testRetailIndicatorAwareNativeWording()
    local harness = makeHarness(true, true)
    local spellParent = makeParent()
    local spellPane =
        harness.builders.auraBlackListWhitelist(spellParent)
    local arrangementPane =
        harness.builders.auraArrangement(makeParent())
    local mode = findWidget(
        spellPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    local tip = findWidget(
        spellPane,
        "fontString",
        "kind",
        "fontString"
    )
    local maximum = findWidget(
        arrangementPane,
        "slider",
        "initialText",
        "Max Displayed"
    )
    local nativeTopPadding

    local function assertNativePresentation(
        id,
        owner,
        runtimeKind
    )
        local label = owner .. " " .. id
        local info = newInfo(id, owner, nil, runtimeKind)

        spellPane.Load(info)
        assertEqual(
            mode.items[1].text,
            "Exclude Spell IDs (Reaction-Limited)",
            label .. " native spell-list label"
        )
        assertContains(
            tip.text,
            "can apply saved spell-ID lists",
            label .. " native spell-list message"
        )
        assertNotContains(
            tip.text,
            "not applied here",
            label .. " inactive spell-list message"
        )
        if nativeTopPadding then
            assertEqual(
                spellPane.listTopPadding,
                nativeTopPadding,
                label .. " repeated native wrapped height"
            )
        else
            nativeTopPadding = spellPane.listTopPadding
        end
        assertEqual(
            spellParent._contentHeights[spellPane.index],
            tostring(spellPane.height),
            label .. " native scroll height"
        )

        arrangementPane.Load(info)
        assertEqual(
            maximum.label,
            "Max Per Enabled Category",
            label .. " native maximum label"
        )
        assertContains(
            maximum.tooltipBody,
            "maximum combined capacity",
            label .. " native maximum warning"
        )
    end

    local function assertLegacyBuffPresentation(owner, runtimeKind)
        local label = owner .. " buffs"
        local info = newInfo(
            "buffs",
            owner,
            nil,
            runtimeKind
        )

        spellPane.Load(info)
        assertEqual(
            mode.items[1].text,
            "Saved Blacklist (Not Applied Here)",
            label .. " inactive blacklist label"
        )
        assertEqual(
            mode.items[2].text,
            "Saved Whitelist (Not Applied Here)",
            label .. " inactive whitelist label"
        )
        assertContains(
            tip.text,
            "legacy Retail aura list",
            label .. " legacy implementation message"
        )
        assertContains(
            tip.text,
            "not applied here",
            label .. " inactive spell-list message"
        )
        assertNotContains(
            tip.text,
            "can apply saved spell-ID lists",
            label .. " native spell-list message"
        )
        assertTrue(
            spellPane.listTopPadding < nativeTopPadding,
            label .. " inactive wrapped height shrinks"
        )
        assertEqual(
            spellParent._contentHeights[spellPane.index],
            tostring(spellPane.height),
            label .. " inactive scroll height"
        )

        arrangementPane.Load(info)
        assertEqual(
            maximum.label,
            "Max Displayed",
            label .. " legacy maximum label"
        )
        assertEqual(
            maximum.tooltipTitle,
            nil,
            label .. " stale native maximum tooltip"
        )
        assertEqual(
            maximum.tooltipBody,
            nil,
            label .. " stale native maximum warning"
        )
    end

    for _, owner in ipairs(NATIVE_BUFF_OWNERS) do
        assertNativePresentation("buffs", owner)
    end
    for _, owner in ipairs(ALL_AURA_OWNERS) do
        assertNativePresentation("debuffs", owner)
    end
    for _, owner in ipairs(LEGACY_BUFF_OWNERS) do
        assertLegacyBuffPresentation(owner)
    end

    -- An instantiated runtime is authoritative over the fallback integration
    -- map. This keeps the wording honest while branches are tested alone or
    -- if a later integration changes which aura factory owns a row.
    assertLegacyBuffPresentation("player", "legacy")
    assertNativePresentation("buffs", "target", "native")
end

local COOLDOWN_STYLES = {
    "none",
    "vertical",
    "block_vertical",
    "clock",
    "block_clock",
    "clock_with_leading_edge",
    "block_clock_with_leading_edge",
}

local function testRetailPresentation(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)

    local colorPane =
        harness.builders.auraTypeColor(makeParent())
    local debuffs = newInfo("debuffs", "target")
    colorPane.Load(debuffs)
    local sourceColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Cast By Me"
    )
    local dispelColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    local debuffColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Debuff Type"
    )
    assertEqual(colorPane.IsApplicable(debuffs), true,
        version .. " debuff color applicability")
    assertEqual(
        colorPane.IsApplicable(newInfo("buffs", "target")),
        false,
        version .. " buff color applicability"
    )
    assertEqual(sourceColor.shown, false,
        version .. " source-color visibility")
    assertEqual(dispelColor.shown, false,
        version .. " dispel-color visibility")
    assertEqual(debuffColor.shown, true,
        version .. " debuff-color visibility")
    assertEqual(debuffColor.enabled, true,
        version .. " debuff-color enabled state")

    local partitionPane =
        harness.builders.auraSubFrame(makeParent())
    partitionPane.Load(debuffs)
    local partition = findWidget(
        partitionPane,
        "checkButton",
        "initialText",
        "Enable Sub Frame"
    )
    local partitionFilter = findWidget(
        partitionPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertEqual(
        partition.text,
        "Separate Auras Not from Player, Pet, or Vehicle",
        version .. " target partition label"
    )
    assertContains(
        partition.tooltipBody,
        "For target units, this separates the complement of Blizzard's PLAYER category",
        version .. " target partition explanation"
    )
    assertEqual(partitionFilter.shown, false,
        version .. " target partition filter visibility")
    assertEqual(
        partitionFilter.selectedValue,
        "notCastByMe",
        version .. " target partition fixed filter"
    )
    assertEqual(partitionPane.IsApplicable(debuffs), true,
        version .. " target partition applicability")
    assertEqual(
        partitionPane.IsApplicable(newInfo("debuffs", "party")),
        false,
        version .. " non-target partition applicability"
    )

    harness:ClearLoads()
    partition.onCheck(false)
    assertEqual(debuffs.cfg.subFrame.enabled, false,
        version .. " target partition toggle")
    assertFanout(
        harness,
        debuffs,
        1,
        version .. " target partition callback"
    )

    local arrangementPane =
        harness.builders.auraArrangement(makeParent())
    arrangementPane.Load(debuffs)
    local maximum = findWidget(
        arrangementPane,
        "slider",
        "initialText",
        "Max Displayed"
    )
    if hasNativeBackend then
        assertEqual(maximum.label, "Max Per Enabled Category",
            version .. " native maximum label")
        assertContains(
            maximum.tooltipBody,
            "maximum combined capacity",
            version .. " native maximum warning"
        )
    else
        assertEqual(maximum.label, "Max Displayed",
            version .. " legacy maximum label")
    end

    local cooldownPane =
        harness.builders.cooldownStyle(makeParent())
    cooldownPane.Load(debuffs)
    local cooldown = findWidget(
        cooldownPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertItemValues(
        cooldown,
        COOLDOWN_STYLES,
        version .. " cooldown styles"
    )
    assertContains(
        cooldown.tooltipBody,
        "opaque aura duration",
        version .. " cooldown explanation"
    )
    harness:ClearLoads()
    for _, style in ipairs(COOLDOWN_STYLES) do
        cooldown.onSelect(style)
        assertEqual(
            debuffs.cfg.cooldownStyle,
            style,
            version .. " cooldown callback " .. style
        )
    end
    assertFanout(
        harness,
        debuffs,
        #COOLDOWN_STYLES,
        version .. " cooldown callback fan-out"
    )
end

local function testNonRetailSemantics()
    local harness = makeHarness(false, true)
    local parent = makeParent()
    local info = newInfo("buffs", "boss", {
        castByMe = true,
        castByOthers = false,
        castByUnit = true,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    })

    local filterPane =
        harness.builders.auraBaseFilters(parent)
    filterPane.Load(info)
    local castByMe = findWidget(
        filterPane,
        "checkButton",
        "initialText",
        "Cast By Me"
    )
    local dispellable = findWidget(
        filterPane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    assertEqual(castByMe.text, "Cast By Me",
        "non-Retail source filter label")
    assertEqual(dispellable.shown, true,
        "non-Retail dispellable visibility")
    harness:ClearLoads()
    castByMe.onCheck(false)
    assertEqual(info.cfg.filters.castByMe, false,
        "non-Retail legacy filter callback")
    assertEqual(info.cfg.filters.player, nil,
        "non-Retail canonical materialization")
    assertFanout(
        harness,
        info,
        8,
        "non-Retail filter callback fan-out"
    )

    local spellPane =
        harness.builders.auraBlackListWhitelist(parent)
    spellPane.Load(info)
    local mode = findWidget(
        spellPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertEqual(mode.enabled, true,
        "non-Retail spell-list mode enabled state")
    assertEqual(mode.items[1].text, "Blacklist",
        "non-Retail blacklist label")
    assertEqual(mode.items[2].text, "Whitelist",
        "non-Retail whitelist label")
    for _, widget in ipairs(spellPane.widgets) do
        if widget.kind == "button" then
            assertEqual(widget.enabled, true,
                "non-Retail spell-list button enabled state")
        end
    end

    local colorPane =
        harness.builders.auraTypeColor(parent)
    colorPane.Load(info)
    assertEqual(colorPane.IsApplicable(info), true,
        "non-Retail buff color applicability")
    assertEqual(
        findWidget(
            colorPane,
            "checkButton",
            "initialText",
            "Cast By Me"
        ).shown,
        true,
        "non-Retail source-color visibility"
    )

    local partitionPane =
        harness.builders.auraSubFrame(parent)
    local target = newInfo("debuffs", "target")
    partitionPane.Load(target)
    assertEqual(
        findWidget(
            partitionPane,
            "dropdown",
            "kind",
            "dropdown"
        ).shown,
        true,
        "non-Retail partition filter visibility"
    )
    assertEqual(
        findWidget(
            partitionPane,
            "checkButton",
            "initialText",
            "Enable Sub Frame"
        ).text,
        "Enable Sub Frame",
        "non-Retail partition label"
    )

    local arrangementPane =
        harness.builders.auraArrangement(parent)
    arrangementPane.Load(target)
    assertEqual(
        findWidget(
            arrangementPane,
            "slider",
            "initialText",
            "Max Displayed"
        ).label,
        "Max Displayed",
        "non-Retail maximum label"
    )

    local cooldownPane =
        harness.builders.cooldownStyle(parent)
    cooldownPane.Load(target)
    local cooldown = findWidget(
        cooldownPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertItemValues(
        cooldown,
        COOLDOWN_STYLES,
        "non-Retail cooldown styles"
    )
    assertContains(
        cooldown.tooltipBody,
        "Block type",
        "non-Retail cooldown explanation"
    )
end

for _, hasNativeBackend in ipairs({false, true}) do
    testRetailCanonicalFilters(hasNativeBackend)
    testRetailSpellLists(hasNativeBackend)
    testRetailPresentation(hasNativeBackend)
end
testRetailIndicatorAwareNativeWording()
testNonRetailSemantics()

print("unit_frame_aura_filter_options_test.lua: ok")
