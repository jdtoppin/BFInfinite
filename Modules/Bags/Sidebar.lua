---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local max = math.max
local min = math.min
local pairs = pairs
local type = type

local DESIRED_WIDTH = 170
local COLLAPSED_WIDTH = 40
local CONTENT_GAP = 8
local UTILITY_HEIGHT = 26
local UTILITY_GAP = 4
local ROW_HEIGHT = 26
local HEADING_HEIGHT = 22
local ROW_SPACING = 2
local HEADING_TOP_GAP = 4
local ICON_SIZE = 16
local TOGGLE_SIZE = 18
local SCROLLBAR_WIDTH = 10
local SCROLLBAR_THUMB_MIN_HEIGHT = 20
local ROW_RIGHT_INSET = SCROLLBAR_WIDTH + 4
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
local autoHideClip
local autoHideButton
local scrollFrame
local scrollContent
local scrollBar
local scrollThumb
local onSelected
local onAutoHideChanged
local shown = true
local autoHide = false
local hoverExpanded = false
local scrollBarNeeded = false
local settingScrollBar
local scrollBarDragging
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

local function ApplyAutoHideButton(immediate)
    if not autoHideButton then return end

    autoHideButton.label:SetShown(not IsCompact())
    local icon = autoHide and "Unlock" or "Lock"
    if AF.SetAdaptiveIcon then
        AF.SetAdaptiveIcon(autoHideButton.icon, icon)
    else
        autoHideButton.icon:SetTexture(AF.GetIcon(icon))
    end
    autoHideButton.icon:SetTexCoord(0, 1, 0, 1)

    local state = autoHide and "selected"
        or autoHideButton.hovered and "hover"
        or "idle"
    SetNavigationState(autoHideButton, state, immediate)
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

local function UpdateScrollBar()
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

    SetScroll(scrollFrame:GetVerticalScroll())
    local needed = range > 0
    if needed == scrollBarNeeded then return end

    scrollBarNeeded = needed
    if needed then
        scrollBar:FadeIn()
    else
        scrollBar:FadeOut()
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
    if row.kind == "heading" or row.id == selectionId then return end

    selectionId = row.id
    for _, activeRow in ipairs(activeRows) do
        PaintRow(activeRow)
    end
    EnsureSelectedRowVisible()

    if onSelected then
        onSelected(row.id, row.entry)
    end
end

local function SetRowHovered(row, hovered)
    row.hovered = hovered or nil
    PaintRow(row)
end

local function SetAutoHideButtonHovered(hovered)
    autoHideButton.hovered = hovered or nil
    ApplyAutoHideButton()
end

local ApplyModel

local function ExpandRail()
    leaveGeneration = leaveGeneration + 1
    if not rail or not shown or not autoHide then return end

    if not hoverExpanded then
        -- Keep the top-level icon under the pointer at the same scroll offset
        -- while its label is revealed. Nested rows open only on chevron click.
        expandedScrollOffset = compactScrollOffset
        hoverExpanded = true
        ApplyAutoHideButton()
        ApplyModel()
    end
    AF.AnimatedResize(rail, DESIRED_WIDTH)
end

local function IsRailMouseOver()
    return rail and rail:IsMouseOver()
        or scrollBar and scrollBar:IsMouseOver()
end

local function CollapseRail()
    if not rail or not shown or not autoHide or not hoverExpanded then return end
    if scrollBarDragging or IsRailMouseOver() then return end

    AF.AnimatedResize(rail, COLLAPSED_WIDTH, nil, nil, nil, nil, function()
        if not autoHide or scrollBarDragging or IsRailMouseOver() then return end
        showNestedEntries = false
        hoverExpanded = false
        ApplyAutoHideButton()
        ApplyModel()
    end)
end

local function PointerEnter()
    leaveGeneration = leaveGeneration + 1
    ExpandRail()
end

local function PointerLeave()
    leaveGeneration = leaveGeneration + 1
    local generation = leaveGeneration
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
    row.entry = entry
    row.id = entry.id
    row.kind = entry.kind
    row.hovered = nil
    row.label:SetText(entry.label)
    row.label:ClearAllPoints()
    row.label:Show()

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

    local leftInset = compact and ((COLLAPSED_WIDTH - ICON_SIZE) / 2)
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

local function ApplyDesiredState()
    if not rail then return end

    StopResize(rail)
    if shown then
        if autoHide then
            showNestedEntries = false
        end
        hoverExpanded = not autoHide or rail:IsMouseOver()
        if autoHide and hoverExpanded then
            expandedScrollOffset = compactScrollOffset
        end
        AF.SetWidth(rail, IsCompact() and COLLAPSED_WIDTH or DESIRED_WIDTH)
        rail:Show()
        ApplyAutoHideButton(true)
        ApplyModel()
    else
        hoverExpanded = false
        AF.SetWidth(rail, autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH)
        if scrollBar then
            scrollBar:HideNow()
            scrollBarNeeded = false
        end
        rail:Hide()
    end
end

local function CreateAutoHideControl()
    autoHideClip = _G.CreateFrame("ScrollFrame", nil, rail)
    autoHideClip:SetPoint("TOPLEFT")
    autoHideClip:SetPoint("TOPRIGHT")
    AF.SetHeight(autoHideClip, UTILITY_HEIGHT)

    autoHideButton = _G.CreateFrame("Button", nil, autoHideClip)
    AF.SetSize(autoHideButton, DESIRED_WIDTH, UTILITY_HEIGHT)
    autoHideButton:RegisterForClicks("LeftButtonUp")
    autoHideClip:SetScrollChild(autoHideButton)

    autoHideButton.highlight = AF.CreateGradientTexture(
        autoHideButton,
        "HORIZONTAL",
        AF.GetColorTable("BFI", 0.9),
        AF.GetColorTable("BFI", 0),
        nil,
        "BORDER"
    )
    autoHideButton.highlight:SetPoint("TOPLEFT")
    autoHideButton.highlight:SetPoint("BOTTOMLEFT")
    AF.SetWidth(autoHideButton.highlight, 1)
    autoHideButton.highlight:Hide()

    autoHideButton.icon = autoHideButton:CreateTexture(nil, "ARTWORK")
    AF.SetSize(autoHideButton.icon, ICON_SIZE, ICON_SIZE)
    autoHideButton.icon:SetPoint("LEFT", (COLLAPSED_WIDTH - ICON_SIZE) / 2, 0)
    autoHideButton.icon:SetVertexColor(1, 1, 1, 0.9)

    autoHideButton.label = AF.CreateFontString(autoHideButton, L["Auto Hide"], "white")
    autoHideButton.label:SetPoint("LEFT", autoHideButton.icon, "RIGHT", 7, 0)
    autoHideButton.label:SetPoint("RIGHT", -6, 0)
    autoHideButton.label:SetJustifyH("LEFT")
    autoHideButton.label:SetWordWrap(false)

    autoHideButton:SetScript("OnClick", function()
        Sidebar.ToggleAutoHide()
    end)
    autoHideButton:SetScript("OnEnter", function()
        SetAutoHideButtonHovered(true)
        PointerEnter()
    end)
    autoHideButton:SetScript("OnLeave", function(self)
        _G.C_Timer.After(0, function()
            SetAutoHideButtonHovered(self:IsMouseOver())
        end)
        PointerLeave()
    end)
end

local function CreateScrollBar()
    scrollBar = _G.CreateFrame("Slider", nil, rail)
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT")
    AF.SetWidth(scrollBar, SCROLLBAR_WIDTH)
    AF.SetFrameLevel(scrollBar, 10, scrollContent)
    scrollBar:SetOrientation("VERTICAL")
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
    scrollBar:Hide()

    scrollBar:SetScript("OnValueChanged", function(_, value)
        if not settingScrollBar then
            SetScroll(value)
        end
    end)
    scrollBar:SetScript("OnMouseDown", function()
        scrollBarDragging = true
        PointerEnter()
    end)
    scrollBar:SetScript("OnMouseUp", function()
        scrollBarDragging = nil
        PointerLeave()
    end)
    scrollBar:SetScript("OnEnter", PointerEnter)
    scrollBar:SetScript("OnLeave", PointerLeave)
    scrollBar:SetScript("OnHide", function()
        scrollBarDragging = nil
        PointerLeave()
    end)
end

local function CreateRail(parent)
    rail = AF.CreateFrame(parent)
    Sidebar.frame = rail
    AF.SetWidth(rail, autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH)
    AF.SetFrameLevel(rail, 30, parent)
    rail:EnableMouse(true)

    local background = rail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(AF.GetColorRGB("background", 0.96))

    CreateAutoHideControl()

    scrollFrame = _G.CreateFrame("ScrollFrame", nil, rail)
    scrollFrame:SetPoint("TOPLEFT", 0, -(UTILITY_HEIGHT + UTILITY_GAP))
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
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        SetScroll(self:GetVerticalScroll() - (delta * SCROLL_STEP))
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
        selectionId = nil
        ApplyModel()
        return false
    end
    local entry = entriesById[id]
    if not entry or entry.kind == "heading" then return false end

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

    expandedById[id] = expanded
    if autoHide and hoverExpanded and expanded then
        showNestedEntries = true
    end
    ApplyModel()
    return true
end


---@param id any
---@return boolean accepted
function Sidebar.ToggleExpanded(id)
    local entry = entriesById[id]
    if not entry or not entry.hasChildren then return false end

    if autoHide and hoverExpanded and not showNestedEntries then
        showNestedEntries = true
        expandedById[id] = true
    else
        expandedById[id] = not expandedById[id]
    end
    ApplyModel()
    return true
end

---@param nextShown boolean
---@return boolean accepted
function Sidebar.SetShown(nextShown)
    if type(nextShown) ~= "boolean" then return false end
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
    if rail then
        StopResize(rail)
        if autoHide then
            showNestedEntries = false
        end
        hoverExpanded = not autoHide or rail:IsMouseOver()
        if autoHide and hoverExpanded then
            expandedScrollOffset = compactScrollOffset
        end
        AF.SetWidth(rail, IsCompact() and COLLAPSED_WIDTH or DESIRED_WIDTH)
        ApplyAutoHideButton(true)
        ApplyModel()
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

---@return number width
function Sidebar.GetDesiredWidth()
    return autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH
end

---@return number inset
function Sidebar.GetContentInset()
    return Sidebar.GetDesiredWidth() + CONTENT_GAP
end
