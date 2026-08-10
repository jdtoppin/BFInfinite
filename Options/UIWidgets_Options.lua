---@type BFI
local BFI = select(2, ...)
---@class Funcs
local F = BFI.funcs
local L = BFI.L
local W = BFI.modules.UIWidgets
---@type AbstractFramework
local AF = _G.AbstractFramework

local created = {}
local builder = {}
local options = {}

local function AlignSliderLabelLeft(slider)
    if not slider or not slider.label then return end
    AF.ClearPoints(slider.label)
    AF.SetPoint(
        slider.label,
        "BOTTOMLEFT",
        slider,
        "TOPLEFT",
        2,
        2
    )
    slider.label:SetJustifyH("LEFT")
end

---------------------------------------------------------------------
-- settings
---------------------------------------------------------------------
local settings = {
    microMenu = {
        "width,height",
        "alpha",
        "buttonsPerRow",
        "spacing",
    },
    readyPull = {
        {
            AF.WrapTextInColor(L["Ready"], "BFI"),
            AF.WrapTextInColor(L["Left-click: "], "tip") .. _G.READY_CHECK,
            AF.WrapTextInColor(L["Right-click: "], "tip") .. _G.ROLE_POLL,
            "",
            AF.WrapTextInColor(L["Pull"], "BFI"),
            AF.WrapTextInColor(L["Left-click: "], "tip") .. L["Start countdown"],
            AF.WrapTextInColor(L["Right-click: "], "tip") .. L["Cancel countdown"],
        },
        "countdown",
        "width,height",
        "arrangement_simple",
        "spacing",
        "ready,pull",
        "font",
    },
    markers = {
        {
            AF.WrapTextInColor(L["Target Markers"], "BFI"),
            AF.WrapTextInColor(L["Left-click: "], "tip") .. L["Toggle marker"],
            AF.WrapTextInColor(L["Right-click: "], "tip") .. L["Clear marker"],
            "",
            AF.WrapTextInColor(L["World Markers"], "BFI"),
            AF.WrapTextInColor(L["Left-click: "], "tip") .. L["Place marker"],
            AF.WrapTextInColor(L["Right-click: "], "tip") .. L["Clear marker"],
        },
        "markerOptions",
        "width,height",
        "arrangement_complex",
        "markerSpacing",
    },
    objectiveTracker = {
        "objectiveTrackerNativeHeight",
        "objectiveTrackerBackground",
        "objectiveTrackerQuestAutomation",
        "font",
    },
    mythicPlus = {
        "mythicPlusDisplay",
        "mythicPlusWidth",
        "mythicPlusExtendedRun",
        "mythicPlusPreview",
        "mythicPlusHistory",
        "font",
    },
}

---------------------------------------------------------------------
-- reset
---------------------------------------------------------------------
builder["reset"] = function(parent)
    if created["reset"] then return created["reset"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Reset", nil, 30)
    created["reset"] = pane
    pane:Hide()

    local reset = AF.CreateButton(pane, _G.RESET, "red_hover", 110, 20)
    AF.SetPoint(reset, "LEFT", 15, 0)
    reset:SetOnClick(function()
        local dialog = AF.GetDialog(BFIOptionsFrame_UIWidgetsPanel, AF.WrapTextInColor(L["Reset to default settings?"], "BFI") .. "\n" .. pane.t.ownerName, 250)
        dialog:SetPoint("TOP", pane, "BOTTOM")
        dialog:SetOnConfirm(function()
            W.ResetToDefaults(pane.t.id)
            AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
            AF.Fire("BFI_RefreshOptions", "uiWidgets")
        end)
    end)

    function pane.Load(t)
        pane.t = t
    end

    return pane
end

---------------------------------------------------------------------
-- enabled
---------------------------------------------------------------------
builder["enabled"] = function(parent)
    if created["enabled"] then return created["enabled"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Enabled", nil, 30)
    created["enabled"] = pane

    local enabled = AF.CreateCheckButton(pane, L["Enabled"])
    AF.SetPoint(enabled, "LEFT", 15, 0)

    local function UpdateColor(checked)
        if checked then
            enabled.label:SetTextColor(AF.GetColorRGB("softlime"))
        else
            enabled.label:SetTextColor(AF.GetColorRGB("firebrick"))
        end
    end

    enabled:SetOnCheck(function(checked)
        pane.t.cfg.enabled = checked
        UpdateColor(checked)
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
        pane.t:SetTextColor(checked and "white" or "disabled")
        if pane.t.id == "mythicPlus" then
            AF.Fire("BFI_RefreshOptions", "uiWidgets")
        end
    end)

    function pane.Load(t)
        pane.t = t
        UpdateColor(t.cfg.enabled)
        enabled:SetChecked(t.cfg.enabled)
    end

    return pane
end

---------------------------------------------------------------------
-- tips
---------------------------------------------------------------------
builder["tips"] = function(parent)
    if created["tips"] then return created["tips"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Tips")
    created["tips"] = pane
    pane:SetBorderColor("BFI")

    local tips = AF.CreateFontString(pane)
    AF.SetPoint(tips, "TOPLEFT", 15, -9)
    AF.SetPoint(tips, "RIGHT", -15, 0)
    tips:SetSpacing(5)
    tips:SetJustifyH("LEFT")
    tips:SetJustifyV("TOP")

    local function UpdateHeight()
        pane:SetHeight(tips:GetStringHeight() + 20)

        if parent._contentHeights then
            parent._contentHeights[pane.index] = tostring(pane:GetHeight()) -- update height
            AF.ReSize(parent) -- call AF.SetScrollContentHeight
        end
    end

    function pane.SetTips(text)
        tips:SetText(text)
        RunNextFrame(UpdateHeight)
    end

    pane.Load = AF.noop

    return pane
end

---------------------------------------------------------------------
-- showTooltips
---------------------------------------------------------------------
-- builder["showTooltips"] = function(parent)
--     if created["showTooltips"] then return created["showTooltips"] end

--     local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_ShowTooltips", nil, 30)
--     created["showTooltips"] = pane

--     local showTooltips = AF.CreateCheckButton(pane, L["Show Tooltips"])
--     AF.SetPoint(showTooltips, "LEFT", 15, 0)

--     showTooltips:SetOnCheck(function(checked)
--         pane.t.cfg.showTooltips = checked
--         -- AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
--     end)

--     function pane.Load(t)
--         pane.t = t
--         showTooltips:SetChecked(t.cfg.showTooltips)
--     end

--     return pane
-- end

---------------------------------------------------------------------
-- restrictPingsTo
---------------------------------------------------------------------
-- TODO: move to data broker
-- local SetRestrictPings = C_PartyInfo.SetRestrictPings
-- local GetRestrictPings = C_PartyInfo.GetRestrictPings
-- local RestrictPingsTo = Enum.RestrictPingsTo

-- builder["restrictPingsTo"] = function(parent)
--     if created["restrictPingsTo"] then return created["restrictPingsTo"] end

--     local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_RestrictPingsTo", nil, 54)
--     created["restrictPingsTo"] = pane

--     local dropdown = AF.CreateDropdown(pane, 150)
--     AF.SetPoint(dropdown, "TOPLEFT", 15, -25)
--     dropdown:SetLabel(string.utf8sub(_G.RAID_MANAGER_RESTRICT_PINGS_TO, 1, -2)) -- remove colon
--     dropdown:SetItems({
--         {text = _G.NONE, value = RestrictPingsTo.None},
--         {text = _G.RAID_MANAGER_RESTRICT_PINGS_TO_LEAD, value = RestrictPingsTo.Lead},
--         {text = _G.RAID_MANAGER_RESTRICT_PINGS_TO_ASSIST, value = RestrictPingsTo.Assist},
--         {text = _G.RAID_MANAGER_RESTRICT_PINGS_TO_TANKS_HEALERS, value = RestrictPingsTo.TankHealer},
--     })

--     dropdown:SetTooltip(L["This group only"])

--     dropdown:SetOnSelect(function(value)
--         SetRestrictPings(value)
--     end)

--     function pane.Load(t)
--         pane.t = t
--         dropdown:SetSelectedValue(GetRestrictPings())
--     end

--     return pane
-- end

---------------------------------------------------------------------
-- width,height
---------------------------------------------------------------------
builder["width,height"] = function(parent)
    if created["width,height"] then return created["width,height"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_WidthHeight", nil, 55)
    created["width,height"] = pane

    local width = AF.CreateSlider(pane, L["Width"], 150, 10, 200, 1, nil, true)
    AF.SetPoint(width, "LEFT", 15, 0)
    width:SetOnValueChanged(function(value)
        pane.t.cfg.width = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local height = AF.CreateSlider(pane, L["Height"], 150, 10, 200, 1, nil, true)
    AF.SetPoint(height, "TOPLEFT", width, 185, 0)
    height:SetOnValueChanged(function(value)
        pane.t.cfg.height = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        width:SetValue(t.cfg.width)
        height:SetValue(t.cfg.height)
    end

    return pane
end

---------------------------------------------------------------------
-- mythicPlusDisplay
---------------------------------------------------------------------
builder["mythicPlusDisplay"] = function(parent)
    if created["mythicPlusDisplay"] then
        return created["mythicPlusDisplay"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_MythicPlusDisplay",
        nil,
        118
    )
    created["mythicPlusDisplay"] = pane

    local definitions = {
        {"hideObjectiveTracker", L["Hide Objective Tracker"]},
        {"showThresholds", L["Show +2 / +3 Thresholds"]},
        {"showAffixes", L["Show Affixes"]},
        {"showObjectives", L["Show Objectives"]},
        {"showSplits", L["Show Split Comparisons"]},
        {"showPullCount", L["Show Pull Counter"]},
        {"showExecution", L["Show Execution Data"]},
        {"showDebrief", L["Show End-of-Run Debrief"]},
        {"showPlayerBreakdown", L["Show Player Breakdown"]},
    }
    local controls = {}

    local function UpdateDependencies()
        if controls.showSplits then
            controls.showSplits:SetEnabled(
                pane.t.cfg.showObjectives ~= false
            )
        end
        if controls.showPlayerBreakdown then
            controls.showPlayerBreakdown:SetEnabled(
                pane.t.cfg.showDebrief ~= false
            )
        end
    end

    local function CreateToggle(key, label, x, y)
        local control = AF.CreateCheckButton(pane, label)
        AF.SetPoint(control, "TOPLEFT", x, y)
        control:SetOnCheck(function(checked)
            pane.t.cfg[key] = checked
            UpdateDependencies()
            AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
        end)
        controls[key] = control
    end

    for index, definition in ipairs(definitions) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        CreateToggle(
            definition[1],
            definition[2],
            15 + column * 185,
            -8 - row * 22
        )
    end

    function pane.Load(t)
        pane.t = t
        for key, control in pairs(controls) do
            control:SetChecked(t.cfg[key] ~= false)
        end
        UpdateDependencies()
    end

    return pane
end

---------------------------------------------------------------------
-- mythicPlusWidth
---------------------------------------------------------------------
builder["mythicPlusWidth"] = function(parent)
    if created["mythicPlusWidth"] then return created["mythicPlusWidth"] end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_MythicPlusWidth",
        nil,
        120
    )
    created["mythicPlusWidth"] = pane

    local width = AF.CreateSlider(pane, L["Width"], 150, 260, 500, 1, nil, true)
    AF.SetPoint(width, "TOPLEFT", 15, -25)
    AlignSliderLabelLeft(width)
    width:SetOnValueChanged(function(value)
        pane.t.cfg.width = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local xOffset = AF.CreateSlider(
        pane,
        L["X Offset"],
        150,
        -500,
        500,
        1,
        nil,
        true
    )
    AF.SetPoint(xOffset, "TOPLEFT", width, 185, 0)
    AlignSliderLabelLeft(xOffset)
    xOffset:SetAfterValueChanged(function(value)
        pane.t.cfg.position[2] = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local yOffset = AF.CreateSlider(
        pane,
        L["Y Offset"],
        150,
        -500,
        500,
        1,
        nil,
        true
    )
    AF.SetPoint(yOffset, "TOPLEFT", width, "BOTTOMLEFT", 0, -40)
    AlignSliderLabelLeft(yOffset)
    yOffset:SetAfterValueChanged(function(value)
        pane.t.cfg.position[3] = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        width:SetValue(t.cfg.width)
        xOffset:SetValue(t.cfg.position[2])
        yOffset:SetValue(t.cfg.position[3])
    end

    return pane
end

---------------------------------------------------------------------
-- mythicPlusExtendedRun
---------------------------------------------------------------------
builder["mythicPlusExtendedRun"] = function(parent)
    if created["mythicPlusExtendedRun"] then
        return created["mythicPlusExtendedRun"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_MythicPlusExtendedRun",
        nil,
        55
    )
    created["mythicPlusExtendedRun"] = pane

    local cutoff = AF.CreateSlider(
        pane,
        L["Extended-run Baseline Cutoff"],
        150,
        1.25,
        3,
        0.05,
        nil,
        true
    )
    AF.SetPoint(cutoff, "TOPLEFT", 15, -25)
    AlignSliderLabelLeft(cutoff)
    cutoff:SetOnValueChanged(function(value)
        pane.t.cfg.extendedRunMultiplier = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)
    cutoff:SetTooltip(
        L["Extended-run Baseline Cutoff"],
        L["Runs at or above this multiple of the dungeon timer are kept, but excluded from baselines."],
        L["The default is 1.50× the dungeon timer."]
    )

    function pane.Load(t)
        pane.t = t
        cutoff:SetValue(t.cfg.extendedRunMultiplier)
    end

    return pane
end

---------------------------------------------------------------------
-- mythicPlusPreview
---------------------------------------------------------------------
builder["mythicPlusPreview"] = function(parent)
    if created["mythicPlusPreview"] then
        return created["mythicPlusPreview"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_MythicPlusPreview",
        nil,
        30
    )
    created["mythicPlusPreview"] = pane

    local previewShown = false
    local preview = AF.CreateCheckButton(pane, L["Show Preview"])
    AF.SetPoint(preview, "LEFT", 15, 0)
    local function HidePreview()
        if not previewShown then return end
        previewShown = false
        preview:SetChecked(false)
        local module = W.MythicPlus
        if module and type(module.SetPreview) == "function" then
            module.SetPreview(false)
        end
    end
    preview:SetOnCheck(function(checked)
        previewShown = checked
        local module = W.MythicPlus
        if module and type(module.SetPreview) == "function" then
            module.SetPreview(checked)
        end
    end)
    AF.RegisterCallback("BFI_HideMythicPlusPreview", HidePreview)

    function pane.Load(t)
        pane.t = t
        if not t.cfg.enabled then
            HidePreview()
        end
        preview:SetEnabled(t.cfg.enabled == true)
        preview:SetChecked(previewShown)
    end

    return pane
end

---------------------------------------------------------------------
-- mythicPlusHistory
---------------------------------------------------------------------
builder["mythicPlusHistory"] = function(parent)
    if created["mythicPlusHistory"] then
        return created["mythicPlusHistory"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_MythicPlusHistory",
        nil,
        40
    )
    created["mythicPlusHistory"] = pane

    local clear = AF.CreateButton(
        pane,
        L["Clear Mythic+ History"],
        "red_hover",
        160,
        20
    )
    AF.SetPoint(clear, "LEFT", 15, 0)
    clear:SetOnClick(function()
        local dialog = AF.GetDialog(
            BFIOptionsFrame_UIWidgetsPanel,
            AF.WrapTextInColor(L["Clear Mythic+ history?"], "BFI")
                .. "\n"
                .. L["This permanently deletes this character's stored runs and baselines."],
            300
        )
        dialog:SetPoint("TOP", pane, "BOTTOM")
        dialog:SetOnConfirm(function()
            local module = W.MythicPlus
            if module and type(module.ClearHistory) == "function" then
                module.ClearHistory()
            end
        end)
    end)

    pane.Load = AF.noop
    return pane
end

---------------------------------------------------------------------
-- spacing
---------------------------------------------------------------------
builder["spacing"] = function(parent)
    if created["spacing"] then return created["spacing"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Spacing", nil, 55)
    created["spacing"] = pane

    local spacing = AF.CreateSlider(pane, L["Spacing"], 150, -1, 50, 1, nil, true)
    AF.SetPoint(spacing, "LEFT", 15, 0)
    spacing:SetOnValueChanged(function(value)
        pane.t.cfg.spacing = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        spacing:SetValue(t.cfg.spacing)
    end

    return pane
end

---------------------------------------------------------------------
-- alpha
---------------------------------------------------------------------
builder["alpha"] = function(parent)
    if created["alpha"] then return created["alpha"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Alpha", nil, 55)
    created["alpha"] = pane

    local alpha = AF.CreateSlider(pane, L["Alpha"], 150, 0, 1, 0.01, true, true)
    AF.SetPoint(alpha, "LEFT", 15, 0)
    alpha:SetOnValueChanged(function(value)
        pane.t.cfg.alpha = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        alpha:SetValue(t.cfg.alpha)
    end

    return pane
end

---------------------------------------------------------------------
-- objectiveTrackerNativeHeight
---------------------------------------------------------------------
builder["objectiveTrackerNativeHeight"] = function(parent)
    if created["objectiveTrackerNativeHeight"] then
        return created["objectiveTrackerNativeHeight"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_ObjectiveTrackerNativeHeight",
        nil,
        70
    )
    created["objectiveTrackerNativeHeight"] = pane

    local height = AF.CreateSlider(
        pane,
        L["Objective Tracker Height"],
        200,
        400,
        1000,
        10,
        nil,
        true
    )
    AF.SetPoint(height, "LEFT", 15, 0)

    local status = AF.CreateFontString(pane, nil, "disabled")
    AF.SetPoint(status, "LEFT", height, "RIGHT", 25, 0)
    AF.SetPoint(status, "RIGHT", -15, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)

    local unavailableTips = {
        busy = L["Objective Tracker height is temporarily busy."],
        combat = L["Leave combat before changing the Objective Tracker height."],
        customLayout = L["Select an Account or Character Blizzard Edit Mode layout before changing the Objective Tracker height."],
        customPosition = L["Move the Objective Tracker out of its default position in Blizzard Edit Mode before changing its height."],
        editMode = L["Close Blizzard Edit Mode before changing the Objective Tracker height."],
        invalid = L["Objective Tracker height is unavailable on this client."],
        unavailable = L["Objective Tracker height is unavailable on this client."],
    }
    local unavailableStatus = {
        busy = L["Saving Objective Tracker height..."],
        combat = L["Unavailable in combat."],
        customLayout = L["Use a custom Blizzard Edit Mode layout first."],
        customPosition = L["Move it in Blizzard Edit Mode first."],
        editMode = L["Finish editing in Blizzard Edit Mode first."],
        invalid = L["Unavailable on this client."],
        unavailable = L["Unavailable on this client."],
    }

    local function Refresh()
        local value, reason
        if type(W.GetObjectiveTrackerNativeHeight) == "function" then
            value, reason = W.GetObjectiveTrackerNativeHeight()
        else
            reason = "unavailable"
        end

        height:SetValue(value or 800)
        height:SetEnabled(reason == nil
            and type(W.SetObjectiveTrackerNativeHeight) == "function")
        status:SetText(reason and (
            unavailableStatus[reason] or unavailableStatus.unavailable
        ) or "")
        status:SetShown(reason ~= nil)

        local tooltip = L["Height is saved to the active Blizzard Edit Mode layout, not to a BFI profile. Blizzard can expand it for required objective content."]
        if reason then
            tooltip = tooltip .. "\n\n" .. (
                unavailableTips[reason] or unavailableTips.unavailable
            )
        end
        height:SetTooltip(L["Objective Tracker Height"], tooltip)
    end

    height:SetAfterValueChanged(function(value)
        if type(W.SetObjectiveTrackerNativeHeight) == "function" then
            W.SetObjectiveTrackerNativeHeight(value)
        end
        Refresh()
    end)

    function pane.Load(t)
        pane.t = t
        Refresh()
    end

    return pane
end

---------------------------------------------------------------------
-- objectiveTrackerBackground
---------------------------------------------------------------------
builder["objectiveTrackerBackground"] = function(parent)
    if created["objectiveTrackerBackground"] then
        return created["objectiveTrackerBackground"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_ObjectiveTrackerBackground",
        nil,
        55
    )
    created["objectiveTrackerBackground"] = pane

    local alpha = AF.CreateSlider(
        pane,
        L["Background Opacity"],
        150,
        0,
        1,
        0.01,
        true,
        true
    )
    AF.SetPoint(alpha, "LEFT", 15, 0)
    alpha:SetOnValueChanged(function(value)
        pane.t.cfg.backgroundAlpha = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        alpha:SetValue(t.cfg.backgroundAlpha)
    end

    return pane
end

---------------------------------------------------------------------
-- objectiveTrackerQuestAutomation
---------------------------------------------------------------------
builder["objectiveTrackerQuestAutomation"] = function(parent)
    if created["objectiveTrackerQuestAutomation"] then
        return created["objectiveTrackerQuestAutomation"]
    end

    local pane = AF.CreateBorderedFrame(
        parent,
        "BFI_UIWidgetOption_ObjectiveTrackerQuestAutomation",
        nil,
        34
    )
    created["objectiveTrackerQuestAutomation"] = pane

    local tooltip = L[
        "Hold Shift to pause quest automation. Item-started and remote completions, multiple reward choices, PvP confirmations, and payments stay manual."
    ]
    local definitions = {
        {"autoAcceptQuests", L["Auto Accept Quests"]},
        {"autoTurnInQuests", L["Auto Turn In Quests"]},
    }
    local controls = {}

    local function CreateToggle(key, label, x)
        local control = AF.CreateCheckButton(pane, label)
        AF.SetPoint(control, "LEFT", x, 0)
        control:SetTooltip(tooltip)
        control:SetOnCheck(function(checked)
            pane.t.cfg[key] = checked
        end)
        controls[key] = control
    end

    for index, definition in ipairs(definitions) do
        CreateToggle(
            definition[1],
            definition[2],
            15 + (index - 1) * 185
        )
    end

    function pane.Load(t)
        pane.t = t
        for key, control in pairs(controls) do
            control:SetChecked(t.cfg[key] == true)
        end
    end

    return pane
end

---------------------------------------------------------------------
-- buttonsPerRow
---------------------------------------------------------------------
builder["buttonsPerRow"] = function(parent)
    if created["buttonsPerRow"] then return created["buttonsPerRow"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_ButtonsPerRow", nil, 55)
    created["buttonsPerRow"] = pane

    local buttonsPerRow = AF.CreateSlider(pane, L["Buttons Per Row"], 150, 1, 12, 1, nil, true)
    AF.SetPoint(buttonsPerRow, "LEFT", 15, 0)
    buttonsPerRow:SetOnValueChanged(function(value)
        pane.t.cfg.buttonsPerRow = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        buttonsPerRow:SetValue(t.cfg.buttonsPerRow)
    end

    return pane
end

---------------------------------------------------------------------
-- markerSpacing
---------------------------------------------------------------------
builder["markerSpacing"] = function(parent)
    if created["markerSpacing"] then return created["markerSpacing"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_MarkerSpacing", nil, 55)
    created["markerSpacing"] = pane

    local groupSpacing = AF.CreateSlider(pane, L["Group Spacing"], 150, -1, 50, 1, nil, true)
    AF.SetPoint(groupSpacing, "LEFT", 15, 0)
    groupSpacing:SetOnValueChanged(function(value)
        pane.t.cfg.groupSpacing = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local markerSpacing = AF.CreateSlider(pane, L["Marker Spacing"], 150, -1, 50, 1, nil, true)
    AF.SetPoint(markerSpacing, "TOPLEFT", groupSpacing, 185, 0)
    markerSpacing:SetOnValueChanged(function(value)
        pane.t.cfg.markerSpacing = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        groupSpacing:SetValue(t.cfg.groupSpacing)
        markerSpacing:SetValue(t.cfg.markerSpacing)
    end

    return pane
end

---------------------------------------------------------------------
-- countdown
---------------------------------------------------------------------
builder["countdown"] = function(parent)
    if created["countdown"] then return created["countdown"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Countdown", nil, 55)
    created["countdown"] = pane

    local countdown = AF.CreateSlider(pane, _G.COUNTDOWN, 150, 1, 30, 1, nil, true)
    AF.SetPoint(countdown, "LEFT", 15, 0)
    countdown:SetAfterValueChanged(function(value)
        pane.t.cfg.countdown = value
        -- AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        countdown:SetValue(t.cfg.countdown)
    end

    return pane
end

---------------------------------------------------------------------
-- arrangement_complex
---------------------------------------------------------------------
builder["arrangement_complex"] = function(parent)
    if created["arrangement_complex"] then return created["arrangement_complex"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_ArrangementComplex", nil, 54)
    created["arrangement_complex"] = pane

    local arrangement = AF.CreateDropdown(pane, 200)
    arrangement:SetLabel(L["Arrangement"])
    AF.SetPoint(arrangement, "TOPLEFT", 15, -25)
    arrangement:SetItems(AF.GetDropdownItems_Arrangement_Complex())

    arrangement:SetOnSelect(function(value)
        pane.t.cfg.arrangement = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        arrangement:SetSelectedValue(t.cfg.arrangement)
    end

    return pane
end

---------------------------------------------------------------------
-- arrangement_simple
---------------------------------------------------------------------
builder["arrangement_simple"] = function(parent)
    if created["arrangement_simple"] then return created["arrangement_simple"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_ArrangementSimple", nil, 54)
    created["arrangement_simple"] = pane

    local arrangement = AF.CreateDropdown(pane, 150)
    arrangement:SetLabel(L["Arrangement"])
    AF.SetPoint(arrangement, "TOPLEFT", 15, -25)
    arrangement:SetItems(AF.GetDropdownItems_Arrangement_Simple())

    arrangement:SetOnSelect(function(value)
        pane.t.cfg.arrangement = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        arrangement:SetSelectedValue(t.cfg.arrangement)
    end

    return pane
end

---------------------------------------------------------------------
-- font
---------------------------------------------------------------------
builder["font"] = function(parent)
    if created["font"] then return created["font"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_Font", nil, 103)
    created["font"] = pane

    local fontDropdown = AF.CreateDropdown(pane, 150)
    fontDropdown:SetLabel(L["Font"])
    AF.SetPoint(fontDropdown, "TOPLEFT", 15, -25)
    fontDropdown:SetItems(AF.LSM_GetFontDropdownItems())
    fontDropdown:SetOnSelect(function(value)
        pane.t.cfg.font[1] = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local fontOutlineDropdown = AF.CreateDropdown(pane, 150)
    fontOutlineDropdown:SetLabel(L["Outline"])
    AF.SetPoint(fontOutlineDropdown, "TOPLEFT", fontDropdown, 185, 0)
    fontOutlineDropdown:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    fontOutlineDropdown:SetOnSelect(function(value)
        pane.t.cfg.font[3] = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local fontSizeSlider = AF.CreateSlider(pane, L["Size"], 150, 5, 50, 1, nil, true)
    AF.SetPoint(fontSizeSlider, "TOPLEFT", fontDropdown, "BOTTOMLEFT", 0, -25)
    fontSizeSlider:SetOnValueChanged(function(value)
        pane.t.cfg.font[2] = value
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local shadowCheckButton = AF.CreateCheckButton(pane, L["Shadow"])
    AF.SetPoint(shadowCheckButton, "LEFT", fontSizeSlider, 185, 0)
    shadowCheckButton:SetOnCheck(function(checked)
        pane.t.cfg.font[4] = checked
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        fontDropdown:SetSelectedValue(t.cfg.font[1])
        fontSizeSlider:SetValue(t.cfg.font[2])
        fontOutlineDropdown:SetSelectedValue(t.cfg.font[3])
        shadowCheckButton:SetChecked(t.cfg.font[4])
    end

    return pane
end

---------------------------------------------------------------------
-- ready,pull
---------------------------------------------------------------------
builder["ready,pull"] = function(parent)
    if created["ready,pull"] then return created["ready,pull"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_ReadyPull", nil, 54)
    created["ready,pull"] = pane

    local ready = AF.CreateEditBox(pane, L["Use default if empty"], 150, 20)
    ready:SetLabelAlt(L["Ready"])
    AF.SetPoint(ready, "TOPLEFT", 15, -25)
    ready:SetOnTextChanged(function(text, userChanged)
        if not userChanged then return end
        pane.t.cfg.ready = text
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local pull = AF.CreateEditBox(pane, L["Use default if empty"], 150, 20)
    pull:SetLabelAlt(L["Pull"])
    AF.SetPoint(pull, "TOPLEFT", ready, 185, 0)
    pull:SetOnTextChanged(function(text, userChanged)
        if not userChanged then return end
        pane.t.cfg.pull = text
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    function pane.Load(t)
        pane.t = t
        ready:SetText(t.cfg.ready)
        pull:SetText(t.cfg.pull)
    end

    return pane
end

---------------------------------------------------------------------
-- markerOptions
---------------------------------------------------------------------
builder["markerOptions"] = function(parent)
    if created["markerOptions"] then return created["markerOptions"] end

    local pane = AF.CreateBorderedFrame(parent, "BFI_UIWidgetOption_MarkerOptions", nil, 51)
    created["markerOptions"] = pane

    local targetMarkers = AF.CreateCheckButton(pane, L["Target Markers"])
    AF.SetPoint(targetMarkers, "TOPLEFT", 15, -8)

    local worldMarkers = AF.CreateCheckButton(pane, L["World Markers"])
    AF.SetPoint(worldMarkers, "TOPLEFT", targetMarkers, 185, 0)
    worldMarkers:SetOnCheck(function(checked)
        pane.t.cfg.worldMarkers = checked
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    local showIfSolo = AF.CreateCheckButton(pane, L["Show If Solo"])
    AF.SetPoint(showIfSolo, "TOPLEFT", targetMarkers, "BOTTOMLEFT", 0, -7)
    showIfSolo:SetOnCheck(function(checked)
        pane.t.cfg.showIfSolo = checked
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
    end)

    targetMarkers:SetOnCheck(function(checked)
        pane.t.cfg.targetMarkers = checked
        AF.Fire("BFI_UpdateModule", "uiWidgets", pane.t.id)
        showIfSolo:SetEnabled(checked)
    end)

    function pane.Load(t)
        pane.t = t
        targetMarkers:SetChecked(t.cfg.targetMarkers)
        worldMarkers:SetChecked(t.cfg.worldMarkers)
        showIfSolo:SetChecked(t.cfg.showIfSolo)
        showIfSolo:SetEnabled(t.cfg.targetMarkers)
    end

    return pane
end

---------------------------------------------------------------------
-- get
---------------------------------------------------------------------
function F.GetUIWidgetOptions(parent, info)
    for _, pane in pairs(created) do
        pane:Hide()
        AF.ClearPoints(pane)
    end

    wipe(options)
    tinsert(options, builder["reset"](parent))
    created["reset"]:Show()
    tinsert(options, builder["enabled"](parent))
    created["enabled"]:Show()

    local setting = info.id
    if not settings[setting] then return options end

    for _, option in pairs(settings[setting]) do
        if type(option) == "table" then
            local pane = builder["tips"](parent)
            tinsert(options, pane)
            pane:Show()
            pane.SetTips(AF.TableToString(option, "\n"))
        elseif builder[option] then
            local pane = builder[option](parent)
            tinsert(options, pane)
            pane:Show()
        end
    end

    return options
end
