---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local max = math.max
local min = math.min
local pairs = pairs
local type = type

local DESIRED_WIDTH = 170
local COLLAPSED_WIDTH = 40
local CONTENT_GAP = 8
local ROW_HEIGHT = 26
local HEADING_HEIGHT = 22
local ROW_SPACING = 2
local HEADING_TOP_GAP = 4
local ICON_SIZE = 16
local TOGGLE_SIZE = 18
local SCROLLBAR_WIDTH = 10
local SCROLLBAR_THUMB_MIN_HEIGHT = 20
local SCROLLBAR_FADE_DELAY = 0.9
local ROW_RIGHT_INSET = SCROLLBAR_WIDTH + 4
local COMPACT_ICON_AREA_WIDTH = COLLAPSED_WIDTH - ROW_RIGHT_INSET
local SCROLL_STEP = (ROW_HEIGHT + ROW_SPACING) * 3

local ICON_BY_ID = {
    all = "Bag_All",
    combined = "Bag_All",
    equipment = "Bag_Equipment",
    consumables = "Bag_Consumables",
    tradeGoods = "Bag_TradeGoods",
    tradegoods = "Bag_TradeGoods",
    recipes = "Bag_Recipes",
    quest = "Bag_Quest",
    misc = "Bag_Misc",
    housing = "Bag_Housing",
    empty = "Bag_Empty",
    backpack = "Bag_Backpack",
    reagent = "Bag_Reagent",
    individual = "Bag_IndividualBags",
}

local Sidebar = B.Sidebar or {}
B.Sidebar = Sidebar

Sidebar.DESIRED_WIDTH = DESIRED_WIDTH
Sidebar.COLLAPSED_WIDTH = COLLAPSED_WIDTH
Sidebar.CONTENT_GAP = CONTENT_GAP
Sidebar.Icons = ICON_BY_ID

local rail
local scrollFrame
local scrollContent
local scrollBar
local scrollThumb
local onSelected
local onAutoHideChanged
local onPresentationWidthChanged
local shown = true
local autoHide = false
local hoverExpanded = false
local presentationWidth = DESIRED_WIDTH
local scrollBarNeeded = false
local settingScrollBar
local scrollBarDragging
local scrollBarFadeGeneration = 0
local leaveGeneration = 0
local expandedScrollOffset = 0
local compactScrollOffset = 0
local showNestedEntries = false
local selectionId
local model = {}
local entriesById = {}
local expandedById = {}
local visibleEntries = {}
local rows = {}
local activeRows = {}
local modelAnimation

local function IsCompact()
    return autoHide and not hoverExpanded
end

local function IsNestedTreeShown()
    return not autoHide or showNestedEntries
end

local function StopResize(region)
    if not region or not region._animatedResizeTimer then return end
    region._animatedResizeTimer:Cancel()
    region._animatedResizeTimer = nil
end

local function PublishPresentationWidth(width)
    presentationWidth = width
    if onPresentationWidthChanged then
        onPresentationWidthChanged(
            width,
            autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH
        )
    end
end

local function SetRailWidth(width)
    if rail then
        AF.SetWidth(rail, width)
    end
    PublishPresentationWidth(width)
end

local function SetNavigationState(control, state, immediate)
    if control.navigationState == state then return end
    control.navigationState = state

    local highlight = control.highlight
    local targetWidth = state == "selected" and DESIRED_WIDTH
        or state == "hover" and 7
        or 1
    local shouldShow = state ~= "idle"

    if immediate then
        StopResize(highlight)
        AF.SetWidth(highlight, targetWidth)
        highlight:SetShown(shouldShow)
        return
    end

    if not shouldShow and not highlight:IsShown() then
        AF.SetWidth(highlight, 1)
        return
    end

    AF.AnimatedResize(
        highlight,
        targetWidth,
        nil,
        nil,
        nil,
        shouldShow and function()
            highlight:Show()
        end or nil,
        not shouldShow and function()
            if control.navigationState == "idle" then
                highlight:Hide()
            end
        end or nil
    )
end

local function IsSelectedRow(row)
    if row.id == selectionId then return true end
    if IsNestedTreeShown() and expandedById[row.id] then return false end

    local selected = entriesById[selectionId]
    while selected and selected.parentId do
        if selected.parentId == row.id then
            return true
        end
        selected = entriesById[selected.parentId]
    end
    return false
end

local function PaintRow(row, immediate)
    if row.kind == "heading" then
        row.label:SetTextColor(0.62, 0.62, 0.62, 1)
        SetNavigationState(row, "idle", true)
    else
        row.label:SetColor("white")
        local state = IsSelectedRow(row) and "selected"
            or row.hovered and "hover"
            or "idle"
        SetNavigationState(row, state, immediate)
    end
end

local function GetVerticalScrollRange()
    if not scrollFrame or not scrollContent then return 0 end
    return max(0, scrollContent:GetHeight() - scrollFrame:GetHeight())
end

local function SyncScrollBarValue(offset)
    if not scrollBar or settingScrollBar then return end
    settingScrollBar = true
    scrollBar:SetValue(offset)
    settingScrollBar = nil
end

local function SetScroll(offset)
    if not scrollFrame then return end

    local range = GetVerticalScrollRange()
    if offset < 0 then
        offset = 0
    elseif offset > range then
        offset = range
    end
    scrollFrame:SetVerticalScroll(offset)
    SyncScrollBarValue(offset)
    if IsCompact() then
        compactScrollOffset = offset
    else
        expandedScrollOffset = offset
    end
end

local function UpdateScrollBarGeometry()
    if not scrollBar or not scrollFrame then return end

    local range = GetVerticalScrollRange()
    scrollBar:SetMinMaxValues(0, range)

    local trackHeight = scrollBar:GetHeight()
    if range > 0 and trackHeight > 0 then
        local viewportHeight = scrollFrame:GetHeight()
        local thumbHeight = max(
            SCROLLBAR_THUMB_MIN_HEIGHT,
            trackHeight * (viewportHeight / (viewportHeight + range))
        )
        AF.SetHeight(scrollThumb, min(trackHeight, thumbHeight))
    end

    return range
end

local function HideScrollBar(immediate)
    if not scrollBar then return end

    scrollBarFadeGeneration = scrollBarFadeGeneration + 1
    scrollBar:EnableMouse(false)
    if immediate or not scrollBar:IsShown() then
        scrollBar:HideNow()
    else
        scrollBar:FadeOut()
    end
end

local function ScheduleScrollBarFadeOut()
    if not scrollBarNeeded then return end

    scrollBarFadeGeneration = scrollBarFadeGeneration + 1
    local generation = scrollBarFadeGeneration
    _G.C_Timer.After(SCROLLBAR_FADE_DELAY, function()
        if generation ~= scrollBarFadeGeneration
            or not scrollBarNeeded
            or scrollBarDragging
            or scrollBar:IsMouseOver() then
            return
        end
        HideScrollBar(false)
    end)
end

local function RevealScrollBar(scheduleFade)
    if not scrollBar or not scrollBarNeeded then return end

    scrollBarFadeGeneration = scrollBarFadeGeneration + 1
    scrollBar:EnableMouse(true)
    if not scrollBar:IsShown()
        or scrollBar:GetAlpha() < 1
        or scrollBar.fadeOut:IsPlaying() then
        scrollBar:FadeIn()
    end
    if scheduleFade ~= false then
        ScheduleScrollBarFadeOut()
    end
end

local function UpdateScrollBar()
    local range = UpdateScrollBarGeometry()
    if range == nil then return end

    SetScroll(scrollFrame:GetVerticalScroll())
    local needed = range > 0
    local changed = needed ~= scrollBarNeeded

    scrollBarNeeded = needed
    if not needed then
        HideScrollBar(false)
    elseif changed then
        RevealScrollBar()
    end
end

local function IsRailMouseOver()
    return rail and rail:IsMouseOver()
        or scrollBar and scrollBar:IsMouseOver()
end

local function SetScrollFromWheel(delta)
    if not scrollFrame then return end

    RevealScrollBar()
    SetScroll(scrollFrame:GetVerticalScroll() - (delta * SCROLL_STEP))
end

local function SetScrollBarDragging(dragging)
    if dragging then
        scrollBarDragging = true
        RevealScrollBar(false)
    elseif scrollBarDragging then
        scrollBarDragging = nil
        ScheduleScrollBarFadeOut()
    end
end

local function EnsureSelectedRowVisible()
    if not scrollFrame or selectionId == nil then return end

    local offset = scrollFrame:GetVerticalScroll()
    local bottom = offset + scrollFrame:GetHeight()
    for _, row in ipairs(activeRows) do
        if IsSelectedRow(row) then
            if row.layoutTop < offset then
                SetScroll(row.layoutTop)
            elseif row.layoutBottom > bottom then
                SetScroll(row.layoutBottom - scrollFrame:GetHeight())
            end
            return
        end
    end
end

local function BuildVisibleEntries()
    local flattened = {}

    local function Append(entries)
        for _, entry in ipairs(entries) do
            flattened[#flattened + 1] = entry
            if entry.hasChildren and IsNestedTreeShown() and expandedById[entry.id] then
                Append(entry.children)
            end
        end
    end
    Append(model)

    visibleEntries = flattened
end

local function SelectFromClick(row)
    if row.kind == "heading" or modelAnimation then return end

    local id = row.id
    local entry = row.entry
    local hasChildren = entry and entry.hasChildren
    if id ~= selectionId then
        selectionId = id
        for _, activeRow in ipairs(activeRows) do
            PaintRow(activeRow)
        end
        EnsureSelectedRowVisible()

        if onSelected then
            onSelected(id, entry)
        end
    end

    if hasChildren then
        Sidebar.ToggleExpanded(id)
    end
end

local function SetRowHovered(row, hovered)
    row.hovered = hovered or nil
    PaintRow(row)
end

local ApplyModel
local FinishModelAnimation

local function ExpandRail()
    leaveGeneration = leaveGeneration + 1
    if not rail or not shown or not autoHide then return end
    StopResize(rail)

    if not hoverExpanded then
        -- Keep the top-level icon under the pointer at the same scroll offset
        -- while its label is revealed. Nested rows open only on an explicit
        -- category title or chevron click.
        expandedScrollOffset = compactScrollOffset
        hoverExpanded = true
        ApplyModel()
    end
    if presentationWidth >= DESIRED_WIDTH then return end

    AF.AnimatedResize(
        rail,
        DESIRED_WIDTH,
        nil,
        nil,
        nil,
        nil,
        function()
            SetRailWidth(DESIRED_WIDTH)
        end,
        function(width)
            PublishPresentationWidth(width)
        end
    )
end

local function CollapseRail()
    if not rail or not shown or not autoHide or not hoverExpanded then return end
    if scrollBarDragging or IsRailMouseOver() then return end

    if FinishModelAnimation then
        FinishModelAnimation()
    end
    AF.AnimatedResize(
        rail,
        COLLAPSED_WIDTH,
        nil,
        nil,
        nil,
        nil,
        function()
            if scrollBarDragging or IsRailMouseOver() then
                ExpandRail()
                return
            end
            if not autoHide then return end
            SetRailWidth(COLLAPSED_WIDTH)
            showNestedEntries = false
            hoverExpanded = false
            ApplyModel()
        end,
        function(width)
            PublishPresentationWidth(width)
        end
    )
end

local function PointerEnter()
    leaveGeneration = leaveGeneration + 1
    RevealScrollBar()
    ExpandRail()
end

local function PointerLeave()
    leaveGeneration = leaveGeneration + 1
    local generation = leaveGeneration
    ScheduleScrollBarFadeOut()
    _G.C_Timer.After(0, function()
        if generation ~= leaveGeneration then return end
        CollapseRail()
    end)
end

local function RefreshRowHover(row)
    _G.C_Timer.After(0, function()
        if not row.entry then return end
        local hovered = row:IsMouseOver()
            or row.toggle:IsShown() and row.toggle:IsMouseOver()
        SetRowHovered(row, hovered)
    end)
end

local function CreateRow()
    local row = _G.CreateFrame("Button", nil, scrollContent)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = AF.CreateGradientTexture(
        row,
        "HORIZONTAL",
        AF.GetColorTable("BFI", 0.9),
        AF.GetColorTable("BFI", 0),
        nil,
        "BORDER"
    )
    row.highlight:SetPoint("TOPLEFT")
    row.highlight:SetPoint("BOTTOMLEFT")
    AF.SetWidth(row.highlight, 1)
    row.highlight:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    AF.SetSize(row.icon, ICON_SIZE, ICON_SIZE)
    row.icon:SetVertexColor(1, 1, 1, 0.9)

    row.label = AF.CreateFontString(row, nil, "white")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.toggle = _G.CreateFrame("Button", nil, row)
    AF.SetSize(row.toggle, TOGGLE_SIZE, TOGGLE_SIZE)
    row.toggle:SetPoint("RIGHT", -(SCROLLBAR_WIDTH + 2), 0)
    row.toggle:RegisterForClicks("LeftButtonUp")

    row.toggle.icon = row.toggle:CreateTexture(nil, "ARTWORK")
    row.toggle.icon:SetAllPoints()
    row.toggle.icon:SetVertexColor(1, 1, 1, 0.62)

    row:SetScript("OnClick", SelectFromClick)
    row:SetScript("OnEnter", function(self)
        SetRowHovered(self, true)
        PointerEnter()
    end)
    row:SetScript("OnLeave", function(self)
        RefreshRowHover(self)
        PointerLeave()
    end)
    row.toggle:SetScript("OnClick", function(self)
        Sidebar.ToggleExpanded(self.owner.id)
    end)
    row.toggle:SetScript("OnEnter", function(self)
        SetRowHovered(self.owner, true)
        PointerEnter()
    end)
    row.toggle:SetScript("OnLeave", function(self)
        RefreshRowHover(self.owner)
        PointerLeave()
    end)
    row.toggle.owner = row

    rows[#rows + 1] = row
    return row
end

local function AcquireRow(index)
    return rows[index] or CreateRow()
end

local function ResetRowForEntry(row, entry)
    if row.id == entry.id and row.kind == entry.kind then return end
    StopResize(row.highlight)
    row.navigationState = nil
    AF.SetWidth(row.highlight, 1)
    row.highlight:Hide()
end

local function ApplyEntry(row, entry)
    ResetRowForEntry(row, entry)
    row:SetAlpha(1)
    row.entry = entry
    row.id = entry.id
    row.kind = entry.kind
    row.hovered = nil
    row.label:SetText(entry.label)
    row.label:ClearAllPoints()
    row.label:Show()
    row.toggle:EnableMouse(true)

    if entry.kind == "heading" then
        row:EnableMouse(false)
        row.label:SetFontObject("AF_FONT_SMALL")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -ROW_RIGHT_INSET, 0)
        row.label:SetShown(not IsCompact())
        row.icon:Hide()
        row.toggle:Hide()
        return
    end

    local compact = IsCompact()
    row:EnableMouse(true)
    row.label:SetFontObject("AF_FONT_NORMAL")
    row.label:SetShown(not compact)

    local leftInset = compact and ((COMPACT_ICON_AREA_WIDTH - ICON_SIZE) / 2)
        or 8 + ((entry.depth or 0) * 22)
    local icon = entry.icon or compact and "Bag_Misc"
    if icon then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", leftInset, 0)
        if AF.hasBagIcons and AF.SetAdaptiveIcon then
            AF.SetAdaptiveIcon(row.icon, icon)
        else
            row.icon:SetTexture(AF.GetIcon("Menu4"))
        end
        row.icon:SetTexCoord(0, 1, 0, 1)
        row.icon:Show()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    else
        row.icon:Hide()
        row.label:SetPoint("LEFT", leftInset, 0)
    end

    if entry.hasChildren and not compact then
        row.toggle.icon:SetTexture(AF.GetIcon(
            IsNestedTreeShown() and expandedById[entry.id]
                and "ArrowDown1" or "ArrowRight1"
        ))
        row.toggle:Show()
        row.label:SetPoint("RIGHT", row.toggle, "LEFT", -3, 0)
    else
        row.toggle:Hide()
        row.label:SetPoint("RIGHT", -ROW_RIGHT_INSET, 0)
    end
end

ApplyModel = function()
    if not rail or not scrollContent then return end

    BuildVisibleEntries()

    local offset = 0
    for index, entry in ipairs(visibleEntries) do
        local row = AcquireRow(index)
        activeRows[index] = row
        ApplyEntry(row, entry)

        local height = entry.kind == "heading" and HEADING_HEIGHT or ROW_HEIGHT
        if entry.kind == "heading" and index > 1 then
            offset = offset + HEADING_TOP_GAP
        end
        row.layoutTop = offset
        row.layoutBottom = offset + height
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -offset)
        row:SetPoint("RIGHT", scrollContent, "RIGHT")
        AF.SetHeight(row, height)
        row:Show()
        row.hovered = row:IsMouseOver()
            or row.toggle:IsShown() and row.toggle:IsMouseOver()
        PaintRow(row)
        offset = row.layoutBottom + ROW_SPACING
    end

    for index = #visibleEntries + 1, #rows do
        local row = rows[index]
        activeRows[index] = nil
        row.entry = nil
        row.id = nil
        row.kind = nil
        row.hovered = nil
        row:Hide()
    end

    AF.SetHeight(scrollContent, max(1, offset - ROW_SPACING))
    SetScroll(IsCompact() and compactScrollOffset or expandedScrollOffset)
    EnsureSelectedRowVisible()
    UpdateScrollBar()
end

local function BuildEntryLayout(entries)
    local layout = {}
    local offset = 0
    for index, entry in ipairs(entries) do
        local height = entry.kind == "heading" and HEADING_HEIGHT or ROW_HEIGHT
        if entry.kind == "heading" and index > 1 then
            offset = offset + HEADING_TOP_GAP
        end

        local key = entry.id or entry
        layout[key] = {
            top = offset,
            bottom = offset + height,
            height = height,
        }
        offset = offset + height + ROW_SPACING
    end
    return layout, max(1, offset - ROW_SPACING)
end

local function PositionAnimatedRows(animation, progress)
    for _, state in ipairs(animation.rows) do
        local row = state.row
        local top = state.fromTop + ((state.toTop - state.fromTop) * progress)
        local alpha = state.fromAlpha + ((state.toAlpha - state.fromAlpha) * progress)
        row.layoutTop = top
        row.layoutBottom = top + state.height
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -top)
        row:SetPoint("RIGHT", scrollContent, "RIGHT")
        AF.SetHeight(row, state.height)
        row:SetAlpha(alpha)
        row:Show()
    end
end

local function UpdateModelAnimation(animation, currentHeight)
    if modelAnimation ~= animation then return end

    local heightDelta = animation.targetHeight - animation.startHeight
    local progress = heightDelta == 0
        and 1
        or (currentHeight - animation.startHeight) / heightDelta
    progress = max(0, min(1, progress))
    PositionAnimatedRows(animation, progress)
    UpdateScrollBarGeometry()
    SetScroll(
        animation.startOffset
            + ((animation.targetOffset - animation.startOffset) * progress)
    )
end

FinishModelAnimation = function()
    if not modelAnimation then return end

    StopResize(scrollContent)
    modelAnimation = nil
    ApplyModel()
    ScheduleScrollBarFadeOut()
end

local function AnimateExpandedChange(id, expanded)
    if not rail or not scrollContent or not shown or not rail:IsShown() then
        expandedById[id] = expanded
        ApplyModel()
        return
    end

    local oldRowsByKey = {}
    local oldLayout = {}
    for _, row in ipairs(activeRows) do
        if row.entry then
            local key = row.id or row.entry
            oldRowsByKey[key] = row
            oldLayout[key] = {
                top = row.layoutTop,
                bottom = row.layoutBottom,
                height = row.layoutBottom - row.layoutTop,
            }
        end
    end

    local startHeight = scrollContent:GetHeight()
    local startOffset = scrollFrame:GetVerticalScroll()
    expandedById[id] = expanded
    if autoHide and hoverExpanded and expanded then
        showNestedEntries = true
    end
    BuildVisibleEntries()

    local targetLayout, targetHeight = BuildEntryLayout(visibleEntries)
    local targetOffset = min(
        startOffset,
        max(0, targetHeight - scrollFrame:GetHeight())
    )
    if targetHeight == startHeight then
        ApplyModel()
        SetScroll(targetOffset)
        return
    end

    local parentLayout = targetLayout[id] or oldLayout[id]
    local branchTop = parentLayout and (parentLayout.bottom + ROW_SPACING) or 0
    local animation = {
        rows = {},
        startHeight = startHeight,
        targetHeight = targetHeight,
        startOffset = startOffset,
        targetOffset = targetOffset,
    }
    local usedRows = {}
    local nextPoolIndex = #activeRows + 1

    for _, entry in ipairs(visibleEntries) do
        local key = entry.id or entry
        local row = oldRowsByKey[key]
        local incoming = row == nil
        if incoming then
            row = AcquireRow(nextPoolIndex)
            nextPoolIndex = nextPoolIndex + 1
        end

        ApplyEntry(row, entry)
        PaintRow(row, true)
        row:EnableMouse(false)
        row.toggle:EnableMouse(false)
        usedRows[row] = true
        local target = targetLayout[key]
        local previous = oldLayout[key]
        local fromTop = previous and previous.top or branchTop
        if incoming and entry.parentId then
            local parent = oldLayout[entry.parentId]
                or targetLayout[entry.parentId]
            if parent then
                fromTop = parent.bottom + ROW_SPACING
            end
        end
        animation.rows[#animation.rows + 1] = {
            row = row,
            height = target.height,
            fromTop = fromTop,
            toTop = target.top,
            fromAlpha = incoming and 0 or 1,
            toAlpha = 1,
        }
    end

    for _, row in ipairs(activeRows) do
        if row.entry and not usedRows[row] then
            row:EnableMouse(false)
            row.toggle:EnableMouse(false)
            local parentId = row.entry.parentId
            local survivingParent
            while parentId do
                survivingParent = targetLayout[parentId]
                if survivingParent then break end
                local parent = entriesById[parentId]
                parentId = parent and parent.parentId
            end
            animation.rows[#animation.rows + 1] = {
                row = row,
                height = row.layoutBottom - row.layoutTop,
                fromTop = row.layoutTop,
                toTop = survivingParent
                    and (survivingParent.bottom + ROW_SPACING)
                    or branchTop,
                fromAlpha = 1,
                toAlpha = 0,
            }
        end
    end

    modelAnimation = animation
    PositionAnimatedRows(animation, 0)
    scrollBarNeeded = max(startHeight, targetHeight) > scrollFrame:GetHeight()
    UpdateScrollBarGeometry()
    RevealScrollBar()
    AF.AnimatedResize(
        scrollContent,
        nil,
        targetHeight,
        0.015,
        10,
        nil,
        function()
            if modelAnimation ~= animation then return end
            modelAnimation = nil
            ApplyModel()
            SetScroll(animation.targetOffset)
            ScheduleScrollBarFadeOut()
        end,
        function(_, currentHeight)
            UpdateModelAnimation(animation, currentHeight)
        end
    )
end

local function ApplyDesiredState()
    if not rail then return end

    if FinishModelAnimation then
        FinishModelAnimation()
    end
    StopResize(rail)
    if shown then
        if autoHide then
            showNestedEntries = false
        end
        hoverExpanded = not autoHide or rail:IsMouseOver()
        if autoHide and hoverExpanded then
            expandedScrollOffset = compactScrollOffset
        end
        SetRailWidth(IsCompact() and COLLAPSED_WIDTH or DESIRED_WIDTH)
        rail:Show()
        ApplyModel()
    else
        hoverExpanded = false
        SetRailWidth(autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH)
        if scrollBar then
            scrollBarNeeded = false
            HideScrollBar(true)
        end
        rail:Hide()
    end
end

local function CreateScrollBar()
    scrollBar = _G.CreateFrame("Slider", nil, rail)
    scrollBar:SetPoint("TOPRIGHT", rail, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT")
    AF.SetWidth(scrollBar, SCROLLBAR_WIDTH)
    AF.SetFrameLevel(scrollBar, 10, scrollContent)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(false)
    scrollBar:SetMinMaxValues(0, 0)

    scrollBar.track = scrollBar:CreateTexture(nil, "BACKGROUND")
    scrollBar.track:SetPoint("TOP", 0, -2)
    scrollBar.track:SetPoint("BOTTOM", 0, 2)
    AF.SetWidth(scrollBar.track, 2)
    scrollBar.track:SetColorTexture(AF.GetColorRGB("border", 0.45))

    scrollThumb = scrollBar:CreateTexture(nil, "ARTWORK")
    AF.SetSize(scrollThumb, 5, SCROLLBAR_THUMB_MIN_HEIGHT)
    scrollThumb:SetColorTexture(AF.GetColorRGB("BFI", 0.9))
    scrollBar:SetThumbTexture(scrollThumb)

    AF.CreateFadeInOutAnimation(scrollBar, 0.18)
    scrollBar:SetAlpha(0)
    scrollBar:EnableMouse(false)
    scrollBar:Hide()

    scrollBar:SetScript("OnValueChanged", function(_, value)
        if not settingScrollBar then
            RevealScrollBar(not scrollBarDragging)
            SetScroll(value)
        end
    end)
    scrollBar:SetScript("OnMouseDown", function()
        SetScrollBarDragging(true)
        PointerEnter()
    end)
    scrollBar:SetScript("OnMouseUp", function()
        SetScrollBarDragging(false)
        PointerLeave()
    end)
    scrollBar:SetScript("OnEnter", function()
        RevealScrollBar(false)
        PointerEnter()
    end)
    scrollBar:SetScript("OnLeave", PointerLeave)
    scrollBar:SetScript("OnMouseWheel", function(_, delta)
        SetScrollFromWheel(delta)
    end)
    scrollBar:SetScript("OnHide", function()
        local wasDragging = scrollBarDragging
        scrollBarDragging = nil
        if wasDragging then
            PointerLeave()
        end
    end)
end

local function CreateRail(parent)
    rail = AF.CreateFrame(parent)
    Sidebar.frame = rail
    SetRailWidth(autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH)
    AF.SetFrameLevel(rail, 30, parent)
    rail:EnableMouse(true)

    local background = rail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(AF.GetColorRGB("background", 0.96))

    scrollFrame = _G.CreateFrame("ScrollFrame", nil, rail)
    scrollFrame:SetPoint("TOPLEFT")
    scrollFrame:SetPoint("BOTTOMRIGHT")
    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)

    scrollContent = AF.CreateFrame(scrollFrame)
    AF.SetWidth(scrollContent, DESIRED_WIDTH)
    AF.SetHeight(scrollContent, 1)
    scrollFrame:SetScrollChild(scrollContent)

    CreateScrollBar()

    rail:SetScript("OnEnter", PointerEnter)
    rail:SetScript("OnLeave", PointerLeave)
    scrollFrame:SetScript("OnEnter", PointerEnter)
    scrollFrame:SetScript("OnLeave", PointerLeave)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        SetScrollFromWheel(delta)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        SetScroll(scrollFrame:GetVerticalScroll())
        EnsureSelectedRowVisible()
        UpdateScrollBar()
    end)

    ApplyDesiredState()
    return rail
end

---@param parent Frame
---@param callback? fun(id:any, entry:table)
---@return Frame|nil railFrame
function Sidebar.Initialize(parent, callback)
    if callback ~= nil then
        Sidebar.SetOnSelected(callback)
    end
    if not parent then return nil end

    if rail then
        if rail:GetParent() ~= parent then
            rail:SetParent(parent)
            AF.SetFrameLevel(rail, 30, parent)
        end
        ApplyDesiredState()
        return rail
    end

    return CreateRail(parent)
end

---@param nextModel table[] hierarchical headings and selectable nodes
---@return boolean accepted
function Sidebar.SetModel(nextModel)
    if type(nextModel) ~= "table" then return false end
    if FinishModelAnimation then
        FinishModelAnimation()
    end

    local normalizedModel = {}
    local normalizedById = {}

    local function Normalize(entries, output, depth, parentId)
        for _, source in ipairs(entries) do
            if type(source) == "table" then
                if source.kind == "heading" then
                    output[#output + 1] = {
                        kind = "heading",
                        label = source.label or "",
                        depth = 0,
                    }
                elseif source.id ~= nil and not normalizedById[source.id] then
                    local entry = {}
                    for key, value in pairs(source) do
                        if key ~= "children" then
                            entry[key] = value
                        end
                    end
                    entry.kind = entry.kind or "row"
                    entry.label = entry.label or ""
                    entry.icon = entry.icon or ICON_BY_ID[entry.id]
                    entry.depth = depth
                    entry.parentId = parentId
                    entry.children = {}
                    normalizedById[entry.id] = entry
                    output[#output + 1] = entry

                    if type(source.children) == "table" then
                        Normalize(source.children, entry.children, depth + 1, entry.id)
                    end
                    entry.hasChildren = #entry.children > 0
                    if entry.hasChildren and expandedById[entry.id] == nil then
                        expandedById[entry.id] = source.expanded == true
                    end
                end
            end
        end
    end

    Normalize(nextModel, normalizedModel, 0, nil)
    model = normalizedModel
    entriesById = normalizedById
    if selectionId ~= nil and not entriesById[selectionId] then
        selectionId = nil
    end
    ApplyModel()
    return true
end

local function ExpandAncestors(entry)
    local parentId = entry and entry.parentId
    while parentId do
        expandedById[parentId] = true
        parentId = entriesById[parentId].parentId
    end
end

---@param id any
---@return boolean selected
function Sidebar.SetSelection(id)
    if id == nil then
        if FinishModelAnimation then
            FinishModelAnimation()
        end
        selectionId = nil
        ApplyModel()
        return false
    end
    local entry = entriesById[id]
    if not entry or entry.kind == "heading" then return false end

    if FinishModelAnimation then
        FinishModelAnimation()
    end
    selectionId = id
    ExpandAncestors(entry)
    ApplyModel()
    return true
end

---@param id any
---@param expanded boolean
---@return boolean accepted
function Sidebar.SetExpanded(id, expanded)
    local entry = entriesById[id]
    if not entry or not entry.hasChildren or type(expanded) ~= "boolean" then
        return false
    end
    if modelAnimation then return false end

    local revealNested = autoHide and hoverExpanded and expanded
        and not showNestedEntries
    if expandedById[id] == expanded and not revealNested then return true end

    AnimateExpandedChange(id, expanded)
    return true
end


---@param id any
---@return boolean accepted
function Sidebar.ToggleExpanded(id)
    local entry = entriesById[id]
    if not entry or not entry.hasChildren then return false end
    if modelAnimation then return false end

    local expanded
    if autoHide and hoverExpanded and not showNestedEntries then
        expanded = true
    else
        expanded = not expandedById[id]
    end
    AnimateExpandedChange(id, expanded)
    return true
end

---@param nextShown boolean
---@return boolean accepted
function Sidebar.SetShown(nextShown)
    if type(nextShown) ~= "boolean" then return false end
    if shown == nextShown then return true end
    shown = nextShown
    ApplyDesiredState()
    return true
end

---@param nextAutoHide boolean
---@return boolean accepted
function Sidebar.SetAutoHide(nextAutoHide)
    if type(nextAutoHide) ~= "boolean" then return false end
    if autoHide == nextAutoHide then return true end

    autoHide = nextAutoHide
    if FinishModelAnimation then
        FinishModelAnimation()
    end
    if rail then
        StopResize(rail)
        if autoHide then
            showNestedEntries = false
        end
        hoverExpanded = not autoHide or rail:IsMouseOver()
        if autoHide and hoverExpanded then
            expandedScrollOffset = compactScrollOffset
        end
        SetRailWidth(IsCompact() and COLLAPSED_WIDTH or DESIRED_WIDTH)
        ApplyModel()
    else
        SetRailWidth(autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH)
    end
    return true
end

---@return boolean autoHideEnabled
function Sidebar.GetAutoHide()
    return autoHide
end

---@return boolean enabled
function Sidebar.ToggleAutoHide()
    local enabled = not autoHide
    Sidebar.SetAutoHide(enabled)
    if onAutoHideChanged then
        onAutoHideChanged(enabled)
    end
    return enabled
end

---@param callback? fun(id:any, entry:table)
---@return boolean accepted
function Sidebar.SetOnSelected(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onSelected = callback
    return true
end

---@param callback? fun(enabled:boolean)
---@return boolean accepted
function Sidebar.SetOnAutoHideChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onAutoHideChanged = callback
    return true
end

---@param callback? fun(presentationWidth:number, reservedWidth:number)
---@return boolean accepted
function Sidebar.SetOnPresentationWidthChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onPresentationWidthChanged = callback
    if callback then
        callback(
            presentationWidth,
            autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH
        )
    end
    return true
end

---@return number width
function Sidebar.GetDesiredWidth()
    return autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH
end

---@return number inset
function Sidebar.GetContentInset()
    return Sidebar.GetDesiredWidth() + CONTENT_GAP
end
