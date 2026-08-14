---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local floor, max, min, type = math.floor, math.max, math.min, type

local DEFAULT_DURATION_BAR = {
    height = 3,
    gap = 1,
    inset = 0,
    color = {1, 1, 1, 1},
    backgroundColor = {0, 0, 0, 0.75},
}

local DEFAULT_FRAME_HIGHLIGHT = {
    anchorTo = "healthBar",
    color = {1, 0.82, 0, 0.9},
    blendMode = "ADD",
    inset = 0,
    frameLevelOffset = 1,
}

local SORT_MODE_BLIZZARD = "blizzard"
local SORT_MODE_SPELL_LIST_PRIORITY = "spell_list_priority"
local NATIVE_PRIORITY_SPELL_RESERVATIONS = 10
local FALLBACK_RESERVATION_LIMIT = 40
local GetCollection

local function IsColor(value)
    if type(value) ~= "table" then return false end
    for index = 1, 4 do
        local component = value[index]
        if type(component) ~= "number"
            or component < 0
            or component > 1
        then
            return false
        end
    end
    return true
end

local function CopyColor(value)
    return {value[1], value[2], value[3], value[4]}
end

local function GetColor(config, key, fallback)
    local value = type(config) == "table" and config[key]
    return IsColor(value) and value or fallback
end

local function EnsureTable(config, key)
    if type(config[key]) ~= "table" then
        config[key] = {}
    end
    return config[key]
end

local function SetColor(config, key, fallback, r, g, b, a)
    local style = EnsureTable(config, key)
    if not IsColor(style.color) then
        style.color = CopyColor(fallback)
    end
    AF.FillColorTable(style.color, r, g, b, a)
end

local function GetFiniteNumber(value, fallback, minimum)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
        or minimum and value < minimum
    then
        return fallback
    end
    return value
end

local function GetSpellListLength(config)
    local list = type(config) == "table" and config.whitelist
    return type(list) == "table" and #list or 0
end

local function IsDisplayInList(displays, displayID)
    if type(displays) ~= "table" or type(displayID) ~= "string" then
        return false
    end
    for _, display in ipairs(displays) do
        if type(display) == "table" and display.id == displayID then
            return true
        end
    end
    return false
end

local function GetReservationSummary(info)
    local limit = type(UF.MAX_CHILD_BUFF_DISPLAY_INITIAL_RESERVATIONS)
            == "number"
        and UF.MAX_CHILD_BUFF_DISPLAY_INITIAL_RESERVATIONS
        or FALLBACK_RESERVATION_LIMIT
    local cost
    local overflow = false
    local fromCore = false
    local errorCode
    local capacityUsed
    local usedPreferredCost = false
    local usedPreferredLimit = false

    if type(UF.GetBuffDisplayReservationMetrics) == "function" then
        local metrics = UF.GetBuffDisplayReservationMetrics(info.cfg)
        if type(metrics) == "table" then
            local metricLimit = metrics.buttonCapacityLimit
            if type(metricLimit) == "number" then
                usedPreferredLimit = true
            else
                metricLimit = metrics.reservationLimit
            end
            if type(metricLimit) == "number" then
                limit = metricLimit
            end
            local metricCost = metrics.buttonCapacityCost
            if type(metricCost) == "number" then
                usedPreferredCost = true
            else
                metricCost = metrics.reservationCost
            end
            if type(metricCost) == "number" then
                cost = metricCost
                fromCore = true
            end
            overflow = metrics.buttonCapacityExceeded == true
                or metrics.capacityExceeded == true
            errorCode = metrics.errorCode
        end
    end

    if type(UF.GetActiveBuffDisplayReservationPlan) == "function" then
        local _, overflowDisplays, metrics =
            UF.GetActiveBuffDisplayReservationPlan(GetCollection(info))
        if type(metrics) == "table" then
            local metricLimit = metrics.buttonCapacityLimit
            if type(metricLimit) == "number" then
                limit = metricLimit
            elseif not usedPreferredLimit then
                local legacyLimit = metrics.initialReservationLimit
                if type(legacyLimit) == "number" then
                    limit = legacyLimit
                end
            end
            local costs = metrics.buttonCapacityCosts
                or metrics.capacityCosts
            if not usedPreferredCost
                and type(costs) == "table"
                and type(costs[info.displayID]) == "number"
            then
                cost = costs[info.displayID]
                fromCore = true
            elseif not usedPreferredCost and not fromCore then
                costs = metrics.reservationCosts
                if type(costs) == "table"
                    and type(costs[info.displayID]) == "number"
                then
                    cost = costs[info.displayID]
                    fromCore = true
                end
            end
            local displayMetrics = metrics.displayMetrics
            local currentMetrics = type(displayMetrics) == "table"
                and displayMetrics[info.displayID]
            if not errorCode and type(currentMetrics) == "table" then
                errorCode = currentMetrics.errorCode
            end
            local metricCapacityUsed = metrics.buttonCapacityUsed
            if type(metricCapacityUsed) ~= "number" then
                metricCapacityUsed = metrics.initialReservations
            end
            if type(metricCapacityUsed) == "number" then
                capacityUsed = metricCapacityUsed
            end
        end
        overflow = overflow
            or IsDisplayInList(overflowDisplays, info.displayID)
    end

    if not fromCore
        and info.cfg.sortMode == SORT_MODE_SPELL_LIST_PRIORITY
        and info.cfg.mode == "whitelist"
    then
        -- Retail 12.1 creates each exact-priority AuraGroup in a batch of ten.
        -- Max Active Auras clips presentation; it cannot reduce construction.
        cost = GetSpellListLength(info.cfg)
            * NATIVE_PRIORITY_SPELL_RESERVATIONS
        fromCore = true
    elseif type(cost) ~= "number" then
        cost = NATIVE_PRIORITY_SPELL_RESERVATIONS
    end

    if info.cfg.enabled ~= true
        and type(capacityUsed) == "number"
        and capacityUsed + cost > limit
    then
        overflow = true
    end

    return cost, limit, overflow or cost > limit, fromCore, errorCode,
        capacityUsed
end

local function GetReservationErrorText(errorCode)
    if errorCode == "SPELL_LIST_PRIORITY_REQUIRES_SINGLE_FILTER_GROUP" then
        return L[
            "Spell List Priority requires one native filter category. Select All or enable only one Buff category"
        ]
    elseif errorCode
        == "SPELL_LIST_PRIORITY_REQUIRES_UNIQUE_WHITELIST"
    then
        return L[
            "Spell List Priority requires unique spell IDs. Remove duplicate entries from the whitelist"
        ]
    elseif errorCode
        == "SPELL_LIST_PRIORITY_UNSUPPORTED_PRESENTATION"
    then
        return L[
            "Frame Highlight does not support Spell List Priority. Choose Blizzard Sort or another presentation"
        ]
    elseif errorCode == "SPELL_LIST_PRIORITY_REQUIRES_WHITELIST" then
        return L[
            "Spell List Priority requires Show Only Listed Spells"
        ]
    elseif errorCode == "INVALID_SPELL_ID_WHITELIST" then
        return L[
            "The whitelist contains an invalid spell ID. Remove or replace that entry"
        ]
    elseif errorCode
        == "FRAME_HIGHLIGHT_REQUIRES_SINGLE_FILTER_GROUP"
    then
        return L[
            "Frame Highlight requires one native filter category. Select All or enable only one Buff category"
        ]
    elseif errorCode == "INVALID_COUNTS" then
        return L[
            "Max Displayed must be a positive whole number"
        ]
    elseif errorCode == "INVALID_FILTER_SCHEMA" then
        return L[
            "The selected Buff filters cannot be compiled for the native aura display"
        ]
    elseif type(errorCode) == "string" then
        return L[
            "This display has an invalid native aura configuration (%s)"
        ]:format(errorCode)
    end
end

local function PriorityTooltipsAwaitLiveValidation(config)
    if type(UF.AreBuffDisplayPriorityTooltipsAvailable) == "function" then
        return UF.AreBuffDisplayPriorityTooltipsAvailable(config) ~= true
    end
    return true
end

local function IsGroupBuffDisplay(info)
    return info.id == "buffs"
        and (info.owner == "party" or info.owner == "raid")
end

GetCollection = function(info)
    return info.runtimeCfg or info.cfg
end

local function ApplyCollection(info)
    if info.target then
        F.LoadUnitFrameIndicatorConfig({
            cfg = GetCollection(info),
            id = "buffs",
            owner = info.owner,
            ownerName = info.ownerName,
            target = info.target,
        })
    else
        AF.Fire("BFI_UpdateModule", "unitFrames", info.owner)
    end
end

local function RefreshOptions()
    AF.Fire("BFI_RefreshOptions", "unitFrames")
end

local managerPane
F.RegisterUnitFrameOptionBuilder("buffDisplayManager", function(parent)
    if managerPane then return managerPane end
    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UnitFrameOption_BuffDisplayManager",
        nil,
        92
    )
    managerPane = pane

    local newDisplay = AF.CreateDropdown(pane, 220)
    newDisplay:SetLabel(L["New Buff Display"])
    AF.SetPoint(newDisplay, "TOPLEFT", 15, -25)
    newDisplay:SetItems({
        {text = L["Blank Display"], value = "blank"},
        {text = L["Healing Auras"], value = "healing_auras"},
        {text = L["Defensives"], value = "defensives"},
        {text = L["Externals"], value = "externals"},
    })

    local add = AF.CreateButton(pane, L["Add"], "BFI_hover", 90, 20)
    AF.SetPoint(add, "LEFT", newDisplay, "RIGHT", 10, 0)

    local limit = AF.CreateFontString(pane)
    limit:SetColor("tip")
    AF.SetPoint(limit, "TOPLEFT", newDisplay, "BOTTOMLEFT", 0, -9)
    AF.SetPoint(limit, "RIGHT", pane, -15, 0)
    limit:SetJustifyH("LEFT")

    local name = AF.CreateEditBox(pane, L["Name"], 220, 20, "trim")
    AF.SetPoint(name, "TOPLEFT", 15, -25)

    local duplicate = AF.CreateButton(
        pane,
        L["Duplicate"],
        "BFI_hover",
        90,
        20
    )
    AF.SetPoint(duplicate, "LEFT", name, "RIGHT", 10, 0)

    local moveUp = AF.CreateButton(pane, L["Move Up"], "BFI_hover", 90, 20)
    AF.SetPoint(moveUp, "TOPLEFT", name, "BOTTOMLEFT", 0, -10)

    local moveDown = AF.CreateButton(
        pane,
        L["Move Down"],
        "BFI_hover",
        90,
        20
    )
    AF.SetPoint(moveDown, "LEFT", moveUp, "RIGHT", 10, 0)

    local deleteDisplay = AF.CreateButton(
        pane,
        L["Delete"],
        "red_hover",
        90,
        20
    )
    AF.SetPoint(deleteDisplay, "LEFT", moveDown, "RIGHT", 10, 0)

    local selectedTemplate = "blank"
    newDisplay:SetOnSelect(function(value)
        selectedTemplate = value
    end)

    add:SetOnClick(function()
        local collection = GetCollection(pane.t)
        local template = selectedTemplate ~= "blank"
            and collection.displays[selectedTemplate]
            or nil
        local displayName = selectedTemplate == "blank"
            and L["Buff Display"]
            or L[template.name] .. " " .. L["Copy"]
        UF.CreateBuffDisplay(collection, displayName, template)
        RefreshOptions()
    end)

    name:SetOnEnterPressed(function(value)
        if pane.t.cfg.builtIn then return end
        if UF.RenameBuffDisplay(
            GetCollection(pane.t),
            pane.t.displayID,
            value
        ) then
            RefreshOptions()
        else
            name:SetText(pane.t.cfg.name)
        end
    end)

    duplicate:SetOnClick(function()
        local source = pane.t.cfg
        local sourceName = source.builtIn
            and L[source.name]
            or source.name
        UF.DuplicateBuffDisplay(
            GetCollection(pane.t),
            pane.t.displayID,
            sourceName .. " " .. L["Copy"]
        )
        RefreshOptions()
    end)

    local function MoveDisplay(offset)
        local collection = GetCollection(pane.t)
        local index
        for i, id in ipairs(collection.order) do
            if id == pane.t.displayID then
                index = i
                break
            end
        end
        if not index then return end
        local moved = UF.MoveBuffDisplay(
            collection,
            pane.t.displayID,
            index + offset
        )
        if moved then
            ApplyCollection(pane.t)
        end
        RefreshOptions()
    end

    moveUp:SetOnClick(function()
        MoveDisplay(-1)
    end)
    moveDown:SetOnClick(function()
        MoveDisplay(1)
    end)

    deleteDisplay:SetOnClick(function()
        local info = pane.t
        local function Delete()
            UF.DeleteBuffDisplay(
                GetCollection(info),
                info.displayID
            )
            ApplyCollection(info)
            RefreshOptions()
        end

        local action = info.cfg.builtIn
            and L["Disable"]
            or L["Delete"]
        local dialog = AF.GetDialog(
            BFIOptionsFrame_UnitFramesPanel,
            action .. " " .. (info.cfg.builtIn
                and L[info.cfg.name]
                or info.cfg.name) .. "?",
            250
        )
        dialog:SetPoint("TOP", pane, "BOTTOM")
        dialog:SetOnConfirm(Delete)
    end)

    function pane.Load(info)
        pane.t = info
        local isChild = info.displayID ~= nil

        newDisplay:SetShown(not isChild)
        add:SetShown(not isChild)
        limit:SetShown(not isChild)
        name:SetShown(isChild)
        duplicate:SetShown(isChild)
        moveUp:SetShown(isChild)
        moveDown:SetShown(isChild)
        deleteDisplay:SetShown(isChild)

        if not isChild then
            selectedTemplate = "blank"
            newDisplay:SetSelectedValue(selectedTemplate)
            local reserved, overflow =
                UF.GetActiveBuffDisplayReservationPlan(GetCollection(info))
            limit:SetText((
                L["%d of %d Buff Displays active"]
            ):format(
                #(reserved or {}),
                UF.MAX_ACTIVE_CHILD_BUFF_DISPLAYS
            ) .. (#(overflow or {}) > 0
                and ("  " .. L[
                    "Some enabled Buff Displays exceed the managed aura button capacity"
                ])
                or ""))
            return
        end

        name:SetText(info.cfg.builtIn and L[info.cfg.name] or info.cfg.name)
        name:SetEnabled(not info.cfg.builtIn)
        deleteDisplay:SetText(info.cfg.builtIn and L["Disable"] or L["Delete"])
    end

    function pane.IsApplicable(info)
        return IsGroupBuffDisplay(info)
    end

    return pane
end)

local presentationPane
F.RegisterUnitFrameOptionBuilder("buffDisplayPresentation", function(parent)
    if presentationPane then return presentationPane end
    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UnitFrameOption_BuffDisplayPresentation",
        nil,
        82
    )
    presentationPane = pane

    local presentation = AF.CreateDropdown(pane, 250)
    presentation:SetLabel(L["Presentation"])
    AF.SetPoint(presentation, "TOPLEFT", 15, -25)
    presentation:SetItems({
        {text = L["Icons"], value = "icons"},
        {
            text = L["Icon + Duration Bar"],
            value = "icon_duration_bar",
        },
        {text = L["Bar"], value = "bar"},
        {text = L["Frame Highlight"], value = "frame_highlight"},
    })

    local presentationTip = AF.CreateFontString(pane)
    presentationTip:SetColor("tip")
    AF.SetPoint(
        presentationTip,
        "TOPLEFT",
        presentation,
        "BOTTOMLEFT",
        0,
        -9
    )
    AF.SetPoint(presentationTip, "RIGHT", pane, -15, 0)
    presentationTip:SetJustifyH("LEFT")

    local sortMethod = AF.CreateDropdown(pane, 300)
    sortMethod:SetLabel(L["Sort Method"])
    AF.SetPoint(sortMethod, "TOPLEFT", 15, -100)
    sortMethod:SetItems({
        {
            text = L["Blizzard Sort (Efficient)"],
            value = SORT_MODE_BLIZZARD,
        },
        {
            text = L["Spell List Priority (Higher Resource Use)"],
            value = SORT_MODE_SPELL_LIST_PRIORITY,
        },
    })

    local sortTip = AF.CreateFontString(pane)
    sortTip:SetColor("tip")
    AF.SetPoint(sortTip, "TOPLEFT", sortMethod, "BOTTOMLEFT", 0, -9)
    AF.SetPoint(sortTip, "RIGHT", pane, -15, 0)
    sortTip:SetJustifyH("LEFT")

    local capacity = AF.CreateFontString(pane)
    capacity:SetColor("tip")
    AF.SetPoint(capacity, "TOPLEFT", sortTip, "BOTTOMLEFT", 0, -7)
    AF.SetPoint(capacity, "RIGHT", pane, -15, 0)
    capacity:SetJustifyH("LEFT")

    presentation:SetOnSelect(function(value)
        local config = pane.t.cfg
        local previous = config.presentation or "icons"
        if previous ~= "bar" and value == "bar" then
            local width = GetFiniteNumber(config.width, 18, 1)
            local height = GetFiniteNumber(config.height, 4, 1)
            config.width = max(18, width)
            config.height = height >= 10 and 4 or height
            local style = EnsureTable(config, "durationBar")
            local inset = GetFiniteNumber(style.inset, 0, 0)
            local maximumInset = max(0, floor((min(
                config.width,
                config.height
            ) - 1) / 2))
            style.inset = min(inset, maximumInset)
        elseif previous == "bar" and value ~= "bar" then
            local height = GetFiniteNumber(config.height, 12, 1)
            config.height = height < 10 and 12 or height
        end
        config.presentation = value
        ApplyCollection(pane.t)
        -- The selected presentation changes which settings panes are valid.
        -- Rebuild this row immediately instead of leaving stale icon controls
        -- visible until the user selects it again.
        RefreshOptions()
    end)

    local function LoadSortMode(info)
        local isWhitelist = info.cfg.mode == "whitelist"
        sortMethod:SetShown(isWhitelist)
        sortTip:SetShown(isWhitelist)
        capacity:SetShown(true)
        AF.ClearPoints(capacity)
        if isWhitelist then
            AF.SetPoint(
                capacity,
                "TOPLEFT",
                sortTip,
                "BOTTOMLEFT",
                0,
                -7
            )
            AF.SetPoint(capacity, "RIGHT", pane, -15, 0)
            pane:SetHeight(238)
        else
            AF.SetPoint(
                capacity,
                "TOPLEFT",
                presentationTip,
                "BOTTOMLEFT",
                0,
                -7
            )
            AF.SetPoint(capacity, "RIGHT", pane, -15, 0)
            pane:SetHeight(112)
        end

        local value = info.cfg.sortMode
            == SORT_MODE_SPELL_LIST_PRIORITY and isWhitelist
            and SORT_MODE_SPELL_LIST_PRIORITY
            or SORT_MODE_BLIZZARD
        if isWhitelist then
            sortMethod:SetSelectedValue(value)
        end

        local tooltip
        if isWhitelist and value == SORT_MODE_SPELL_LIST_PRIORITY then
            tooltip = L[
                "Uses the whitelist's top-to-bottom order. Active spells automatically compact into the first positions. Each listed spell reserves 10 managed aura buttons per unit frame"
            ]
            sortTip:SetText(L[
                "Priority follows the whitelist from top to bottom. Max Displayed limits the visible top results, but does not reduce the managed aura button cost"
            ])
        elseif isWhitelist then
            tooltip = L[
                "Active matching spells automatically compact into the first positions. Blizzard chooses their native order; whitelist order is ignored"
            ]
            sortTip:SetText(L[
                "Efficient mode uses one native aura group and Blizzard's supported sorting"
            ])
        end
        if isWhitelist then
            sortMethod:SetTooltip(L["Sort Method"], tooltip)
        end

        local cost, limit, overBudget, fromCore, errorCode,
            capacityUsed =
            GetReservationSummary(info)
        local summary = ""
        if isWhitelist and value == SORT_MODE_SPELL_LIST_PRIORITY then
            summary = L["Priority list: %d spells"]:format(
                GetSpellListLength(info.cfg)
            ) .. "\n"
        end
        if info.cfg.enabled == true then
            summary = summary .. (fromCore and L[
                "This display: %d managed aura buttons per unit frame"
            ] or L[
                "This display: approximately %d managed aura buttons per unit frame"
            ]):format(cost)
        else
            summary = summary .. (fromCore and L[
                "This display would use %d managed aura buttons per unit frame"
            ] or L[
                "This display would use approximately %d managed aura buttons per unit frame"
            ]):format(cost)
        end
        if type(capacityUsed) == "number" then
            summary = summary .. "\n" .. L[
                "Enabled child displays: %d of %d managed aura buttons per unit frame"
            ]:format(capacityUsed, limit)
        end
        if isWhitelist
            and value == SORT_MODE_SPELL_LIST_PRIORITY
            and PriorityTooltipsAwaitLiveValidation(info.cfg)
        then
            summary = summary .. "\n" .. L[
                "Spell tooltips are disabled in priority mode while its compact viewport awaits live 12.1 validation"
            ]
        end
        local errorText = GetReservationErrorText(errorCode)
        if errorText then
            summary = L["Configuration Error"] .. ": "
                .. errorText .. "\n" .. summary
        elseif overBudget then
            summary = L[
                "Over Budget: this display cannot be activated with the current managed aura button capacity"
            ] .. "\n" .. summary
        end
        capacity:SetText(summary)
    end

    sortMethod:SetOnSelect(function(value)
        if pane.t.cfg.mode ~= "whitelist" then return end
        pane.t.cfg.sortMode = value == SORT_MODE_SPELL_LIST_PRIORITY
            and SORT_MODE_SPELL_LIST_PRIORITY
            or SORT_MODE_BLIZZARD
        ApplyCollection(pane.t)
        LoadSortMode(pane.t)
        RefreshOptions()
    end)

    function pane.Load(info)
        pane.t = info
        local value = info.cfg.presentation or "icons"
        presentation:SetSelectedValue(value)
        if value == "icon_duration_bar" then
            presentationTip:SetText(L[
                "The configured height includes the icon and the thin duration bar"
            ])
        elseif value == "bar" then
            presentationTip:SetText(L[
                "A standalone thin duration bar without an icon; Width and Height control the complete bar"
            ])
        elseif value == "frame_highlight" then
            presentationTip:SetText(L[
                "The native aura slot highlights the Health Bar without reading managed aura state"
            ])
        else
            presentationTip:SetText(L[
                "Icons use the existing Buffs appearance, filters, and spell list"
            ])
        end
        LoadSortMode(info)
    end

    function pane.IsApplicable(info)
        return IsGroupBuffDisplay(info)
            and info.displayID ~= nil
    end

    return pane
end)

local presentationStylePane
F.RegisterUnitFrameOptionBuilder(
    "buffDisplayPresentationStyle",
    function(parent)
        if presentationStylePane then return presentationStylePane end
        local pane = AF.CreateBorderedFrame(
            parent,
            "BFI_UnitFrameOption_BuffDisplayPresentationStyle",
            nil,
            178
        )
        presentationStylePane = pane

        local barColor = AF.CreateColorPicker(
            pane,
            L["Duration Bar Color"],
            true
        )
        AF.SetPoint(barColor, "TOPLEFT", 15, -25)

        local barBackground = AF.CreateColorPicker(
            pane,
            L["Duration Bar Background"],
            true
        )
        AF.SetPoint(barBackground, "TOPLEFT", 200, -25)

        local barHeight = AF.CreateSlider(
            pane,
            L["Duration Bar Height"],
            150,
            1,
            8,
            1,
            nil,
            true
        )
        AF.SetPoint(barHeight, "TOPLEFT", 15, -75)

        local barGap = AF.CreateSlider(
            pane,
            L["Duration Bar Gap"],
            150,
            0,
            4,
            1,
            nil,
            true
        )
        AF.SetPoint(barGap, "TOPLEFT", 200, -75)

        local barInset = AF.CreateSlider(
            pane,
            L["Display Inset"],
            150,
            0,
            4,
            1,
            nil,
            true
        )
        AF.SetPoint(barInset, "TOPLEFT", 15, -125)

        local highlightColor = AF.CreateColorPicker(
            pane,
            L["Highlight Color"],
            true
        )
        AF.SetPoint(highlightColor, "TOPLEFT", 15, -25)

        local highlightAnchor = AF.CreateDropdown(pane, 150)
        highlightAnchor:SetLabel(L["Highlight Anchor"])
        AF.SetPoint(highlightAnchor, "TOPLEFT", 200, -25)
        highlightAnchor:SetItems({
            {text = L["Health Bar"], value = "healthBar"},
            {text = L["Unit Frame"], value = "root"},
        })

        local highlightBlend = AF.CreateDropdown(pane, 150)
        highlightBlend:SetLabel(L["Blend Mode"])
        AF.SetPoint(highlightBlend, "TOPLEFT", 15, -75)
        highlightBlend:SetItems({
            {text = "ADD", value = "ADD"},
            {text = "BLEND", value = "BLEND"},
            {text = "MOD", value = "MOD"},
            {text = "ALPHAKEY", value = "ALPHAKEY"},
            {text = "DISABLE", value = "DISABLE"},
        })

        local highlightInset = AF.CreateSlider(
            pane,
            L["Highlight Inset"],
            150,
            0,
            10,
            1,
            nil,
            true
        )
        AF.SetPoint(highlightInset, "TOPLEFT", 200, -75)

        local highlightLevel = AF.CreateSlider(
            pane,
            L["Frame Level Offset"],
            150,
            -10,
            10,
            1,
            nil,
            true
        )
        AF.SetPoint(highlightLevel, "TOPLEFT", 15, -125)

        local sharedBarWidgets = {
            barColor,
            barBackground,
            barInset,
        }
        local underbarOnlyWidgets = {
            barHeight,
            barGap,
        }
        local highlightWidgets = {
            highlightColor,
            highlightAnchor,
            highlightBlend,
            highlightInset,
            highlightLevel,
        }

        local function Apply()
            ApplyCollection(pane.t)
        end

        barColor:SetOnConfirm(function(r, g, b, a)
            SetColor(
                pane.t.cfg,
                "durationBar",
                DEFAULT_DURATION_BAR.color,
                r,
                g,
                b,
                a
            )
            Apply()
        end)
        barBackground:SetOnConfirm(function(r, g, b, a)
            local style = EnsureTable(pane.t.cfg, "durationBar")
            if not IsColor(style.backgroundColor) then
                style.backgroundColor = CopyColor(
                    DEFAULT_DURATION_BAR.backgroundColor
                )
            end
            AF.FillColorTable(style.backgroundColor, r, g, b, a)
            Apply()
        end)
        barHeight:SetAfterValueChanged(function(value)
            EnsureTable(pane.t.cfg, "durationBar").height = value
            Apply()
        end)
        barGap:SetAfterValueChanged(function(value)
            EnsureTable(pane.t.cfg, "durationBar").gap = value
            Apply()
        end)
        barInset:SetAfterValueChanged(function(value)
            EnsureTable(pane.t.cfg, "durationBar").inset = value
            Apply()
        end)

        highlightColor:SetOnConfirm(function(r, g, b, a)
            SetColor(
                pane.t.cfg,
                "frameHighlight",
                DEFAULT_FRAME_HIGHLIGHT.color,
                r,
                g,
                b,
                a
            )
            Apply()
        end)
        highlightAnchor:SetOnSelect(function(value)
            EnsureTable(pane.t.cfg, "frameHighlight").anchorTo = value
            Apply()
        end)
        highlightBlend:SetOnSelect(function(value)
            EnsureTable(pane.t.cfg, "frameHighlight").blendMode = value
            Apply()
        end)
        highlightInset:SetAfterValueChanged(function(value)
            EnsureTable(pane.t.cfg, "frameHighlight").inset = value
            Apply()
        end)
        highlightLevel:SetAfterValueChanged(function(value)
            EnsureTable(
                pane.t.cfg,
                "frameHighlight"
            ).frameLevelOffset = value
            Apply()
        end)

        function pane.Load(info)
            pane.t = info
            local isUnderbar = info.cfg.presentation
                == "icon_duration_bar"
            local isStandaloneBar = info.cfg.presentation == "bar"
            local isDurationBar = isUnderbar or isStandaloneBar
            for _, widget in ipairs(sharedBarWidgets) do
                widget:SetShown(isDurationBar)
            end
            for _, widget in ipairs(underbarOnlyWidgets) do
                widget:SetShown(isUnderbar)
            end
            for _, widget in ipairs(highlightWidgets) do
                widget:SetShown(not isDurationBar)
            end

            if isDurationBar then
                local style = type(info.cfg.durationBar) == "table"
                    and info.cfg.durationBar
                    or {}
                local totalHeight = GetFiniteNumber(info.cfg.height, 10, 1)
                local inset = GetFiniteNumber(
                    style.inset,
                    DEFAULT_DURATION_BAR.inset,
                    0
                )
                inset = min(inset, max(0, floor((totalHeight - 2) / 2)))
                local gap = GetFiniteNumber(
                    style.gap,
                    DEFAULT_DURATION_BAR.gap,
                    0
                )
                gap = min(gap, max(0, totalHeight - inset * 2 - 2))
                local height = GetFiniteNumber(
                    style.height,
                    DEFAULT_DURATION_BAR.height,
                    1
                )
                height = min(
                    height,
                    max(1, totalHeight - inset * 2 - gap - 1)
                )

                barColor:SetColor(GetColor(
                    style,
                    "color",
                    DEFAULT_DURATION_BAR.color
                ))
                barBackground:SetColor(GetColor(
                    style,
                    "backgroundColor",
                    DEFAULT_DURATION_BAR.backgroundColor
                ))
                barInset:SetMinMaxValues(
                    0,
                    max(0, min(4, floor((totalHeight - 1) / 2)))
                )
                barInset:SetValue(inset)
                if isStandaloneBar then return end

                barHeight:SetMinMaxValues(
                    1,
                    max(1, min(8, totalHeight - inset * 2 - gap - 1))
                )
                barGap:SetMinMaxValues(
                    0,
                    max(0, min(4, totalHeight - inset * 2 - height - 1))
                )
                barInset:SetMinMaxValues(
                    0,
                    max(0, min(
                        4,
                        floor((totalHeight - height - gap - 1) / 2)
                    ))
                )
                barHeight:SetValue(height)
                barGap:SetValue(gap)
                return
            end

            local style = type(info.cfg.frameHighlight) == "table"
                and info.cfg.frameHighlight
                or {}
            highlightColor:SetColor(GetColor(
                style,
                "color",
                DEFAULT_FRAME_HIGHLIGHT.color
            ))
            highlightAnchor:SetSelectedValue(
                style.anchorTo == "root" and "root" or "healthBar"
            )
            local blendMode = style.blendMode
            if blendMode ~= "BLEND"
                and blendMode ~= "MOD"
                and blendMode ~= "ALPHAKEY"
                and blendMode ~= "DISABLE"
            then
                blendMode = DEFAULT_FRAME_HIGHLIGHT.blendMode
            end
            highlightBlend:SetSelectedValue(blendMode)
            highlightInset:SetValue(min(
                10,
                GetFiniteNumber(
                    style.inset,
                    DEFAULT_FRAME_HIGHLIGHT.inset,
                    0
                )
            ))
            highlightLevel:SetValue(max(
                -10,
                min(10, GetFiniteNumber(
                    style.frameLevelOffset,
                    DEFAULT_FRAME_HIGHLIGHT.frameLevelOffset
                ))
            ))
        end

        function pane.IsApplicable(info)
            return IsGroupBuffDisplay(info)
                and info.displayID ~= nil
                and info.cfg.presentation ~= "icons"
        end

        return pane
    end
)
