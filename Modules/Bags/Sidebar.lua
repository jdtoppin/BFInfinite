---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local max = math.max
local pairs = pairs
local type = type

local DESIRED_WIDTH = 170
local CONTENT_GAP = 8
local ROW_HEIGHT = 26
local HEADING_HEIGHT = 22
local ROW_SPACING = 2
local HEADING_TOP_GAP = 4
local ICON_SIZE = 16
local TOGGLE_SIZE = 18
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
    empty = "Bag_Empty",
    backpack = "Bag_Backpack",
    reagent = "Bag_Reagent",
    individual = "Bag_IndividualBags",
}

local Sidebar = B.Sidebar or {}
B.Sidebar = Sidebar

Sidebar.DESIRED_WIDTH = DESIRED_WIDTH
Sidebar.CONTENT_GAP = CONTENT_GAP
Sidebar.Icons = ICON_BY_ID

local rail
local scrollFrame
local scrollContent
local onSelected
local shown = true
local selectionId
local model = {}
local entriesById = {}
local expandedById = {}
local visibleEntries = {}
local rows = {}
local activeRows = {}

local function IsSelectedRow(row)
    if row.id == selectionId then return true end
    if expandedById[row.id] then return false end

    local selected = entriesById[selectionId]
    while selected and selected.parentId do
        if selected.parentId == row.id then
            return true
        end
        selected = entriesById[selected.parentId]
    end
    return false
end

local function PaintRow(row)
    if row.kind == "heading" then
        row.highlight:Hide()
        row.label:SetTextColor(0.62, 0.62, 0.62, 1)
    elseif IsSelectedRow(row) then
        row.highlight:SetColorTexture(1, 1, 1, 0.11)
        row.highlight:Show()
        row.label:SetColor("white")
    elseif row.hovered then
        row.highlight:SetColorTexture(1, 1, 1, 0.06)
        row.highlight:Show()
        row.label:SetColor("white")
    else
        row.highlight:Hide()
        row.label:SetColor("white")
    end
end

local function GetVerticalScrollRange()
    if not scrollFrame or not scrollContent then return 0 end
    return max(0, scrollContent:GetHeight() - scrollFrame:GetHeight())
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
            if entry.hasChildren and expandedById[entry.id] then
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

local function SetToggleHovered(row, hovered)
    row.hovered = hovered or nil
    PaintRow(row)
end

local function CreateRow()
    local row = _G.CreateFrame("Button", nil, scrollContent)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    AF.SetSize(row.icon, ICON_SIZE, ICON_SIZE)
    row.icon:SetVertexColor(1, 1, 1, 0.9)

    row.label = AF.CreateFontString(row, nil, "white")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.toggle = _G.CreateFrame("Button", nil, row)
    AF.SetSize(row.toggle, TOGGLE_SIZE, TOGGLE_SIZE)
    row.toggle:SetPoint("RIGHT", -4, 0)
    row.toggle:RegisterForClicks("LeftButtonUp")

    row.toggle.icon = row.toggle:CreateTexture(nil, "ARTWORK")
    row.toggle.icon:SetAllPoints()
    row.toggle.icon:SetVertexColor(1, 1, 1, 0.62)

    row:SetScript("OnClick", SelectFromClick)
    row:SetScript("OnEnter", function(self)
        SetToggleHovered(self, true)
    end)
    row:SetScript("OnLeave", function(self)
        SetToggleHovered(self, false)
    end)
    row.toggle:SetScript("OnClick", function(self)
        Sidebar.ToggleExpanded(self.owner.id)
    end)
    row.toggle:SetScript("OnEnter", function(self)
        SetToggleHovered(self.owner, true)
    end)
    row.toggle:SetScript("OnLeave", function(self)
        SetToggleHovered(self.owner, false)
    end)
    row.toggle.owner = row

    rows[#rows + 1] = row
    return row
end

local function AcquireRow(index)
    return rows[index] or CreateRow()
end

local function ApplyEntry(row, entry)
    row.entry = entry
    row.id = entry.id
    row.kind = entry.kind
    row.hovered = nil
    row.label:SetText(entry.label)
    row.label:ClearAllPoints()

    if entry.kind == "heading" then
        row:EnableMouse(false)
        row.label:SetFontObject("AF_FONT_SMALL")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -6, 0)
        row.icon:Hide()
        row.toggle:Hide()
        PaintRow(row)
        return
    end

    row:EnableMouse(true)
    row.label:SetFontObject("AF_FONT_NORMAL")

    local leftInset = 8 + ((entry.depth or 0) * 22)
    if entry.icon then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", leftInset, 0)
        if AF.hasBagIcons and AF.SetAdaptiveIcon then
            AF.SetAdaptiveIcon(row.icon, entry.icon)
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

    if entry.hasChildren then
        row.toggle.icon:SetTexture(AF.GetIcon(
            expandedById[entry.id] and "ArrowDown1" or "ArrowRight1"
        ))
        row.toggle:Show()
        row.label:SetPoint("RIGHT", row.toggle, "LEFT", -3, 0)
    else
        row.toggle:Hide()
        row.label:SetPoint("RIGHT", -6, 0)
    end
    PaintRow(row)
end

local function ApplyModel()
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
    SetScroll(scrollFrame:GetVerticalScroll())
    EnsureSelectedRowVisible()
end

local function ApplyDesiredState()
    if not rail then return end

    if shown then
        ApplyModel()
        rail:Show()
    else
        rail:Hide()
    end
end

local function CreateRail(parent)
    rail = AF.CreateFrame(parent)
    Sidebar.frame = rail
    AF.SetWidth(rail, DESIRED_WIDTH)

    local background = rail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(AF.GetColorRGB("background", 0.72))

    scrollFrame = _G.CreateFrame("ScrollFrame", nil, rail)
    scrollFrame:SetAllPoints()
    scrollFrame:EnableMouseWheel(true)

    scrollContent = AF.CreateFrame(scrollFrame)
    AF.SetWidth(scrollContent, DESIRED_WIDTH)
    AF.SetHeight(scrollContent, 1)
    scrollFrame:SetScrollChild(scrollContent)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        SetScroll(self:GetVerticalScroll() - (delta * SCROLL_STEP))
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        SetScroll(scrollFrame:GetVerticalScroll())
        EnsureSelectedRowVisible()
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
    ApplyModel()
    return true
end

---@param id any
---@return boolean accepted
function Sidebar.ToggleExpanded(id)
    local entry = entriesById[id]
    if not entry or not entry.hasChildren then return false end

    expandedById[id] = not expandedById[id]
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

---@param callback? fun(id:any, entry:table)
---@return boolean accepted
function Sidebar.SetOnSelected(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onSelected = callback
    return true
end

---@return number width
function Sidebar.GetDesiredWidth()
    return DESIRED_WIDTH
end

---@return number inset
function Sidebar.GetContentInset()
    return DESIRED_WIDTH + CONTENT_GAP
end
