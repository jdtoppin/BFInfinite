---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local max = math.max
local type = type

local DESIRED_WIDTH = 170
local CONTENT_GAP = 8
local ROW_HEIGHT = 26
local ROW_SPACING = 4
local ROW_PITCH = ROW_HEIGHT + ROW_SPACING
local ICON_SIZE = 16
local SCROLL_STEP = ROW_PITCH * 3

local VALID_MODES = {
    combined = true,
    categories = true,
    individual = true,
}

local ICON_BY_ID = {
    all = "Bag_All",
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
local FALLBACK_ICON_BY_MODE = {
    combined = "Menu4",
    categories = "Layout",
    individual = "Layers",
}

local Sidebar = B.Sidebar or {}
B.Sidebar = Sidebar

Sidebar.DESIRED_WIDTH = DESIRED_WIDTH
Sidebar.CONTENT_GAP = CONTENT_GAP
Sidebar.Icons = ICON_BY_ID

local rail
local scrollFrame
local scrollContent
local mode = "combined"
local onSelected
local rows = {}
local activeRows = {}
local entriesByMode = {
    combined = {},
    categories = {},
    individual = {},
}
local entriesByIdByMode = {
    combined = {},
    categories = {},
    individual = {},
}
local selectionByMode = {}

local function SetIndicator(row, state)
    AF.ClearPoints(row.indicator)
    row.indicator:SetPoint("TOPLEFT")
    row.indicator:SetPoint("BOTTOMLEFT")

    if state == "selected" then
        row.indicator:SetPoint("RIGHT")
        row.indicator:Show()
    elseif state == "hover" then
        AF.SetWidth(row.indicator, 7)
        row.indicator:Show()
    else
        AF.SetWidth(row.indicator, 1)
        row.indicator:Show()
    end
end

local function PaintRow(row)
    if row.id == selectionByMode[mode] then
        SetIndicator(row, "selected")
        row.label:SetColor("white")
    elseif row.hovered then
        SetIndicator(row, "hover")
        row.label:SetColor("white")
    else
        SetIndicator(row)
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
    if not scrollFrame then return end

    local selectedId = selectionByMode[mode]
    if selectedId == nil then return end

    local offset = scrollFrame:GetVerticalScroll()
    local bottom = offset + scrollFrame:GetHeight()
    for index, row in ipairs(activeRows) do
        if row.id == selectedId then
            local rowTop = (index - 1) * ROW_PITCH
            local rowBottom = rowTop + ROW_HEIGHT
            if rowTop < offset then
                SetScroll(rowTop)
            elseif rowBottom > bottom then
                SetScroll(rowBottom - scrollFrame:GetHeight())
            end
            return
        end
    end
end

local function SelectFromClick(row)
    if row.id == selectionByMode[mode] then return end

    selectionByMode[mode] = row.id
    for _, activeRow in ipairs(activeRows) do
        PaintRow(activeRow)
    end
    EnsureSelectedRowVisible()

    if onSelected then
        onSelected(row.id, row.entry, mode)
    end
end

local function CreateRow()
    local row = _G.CreateFrame("Button", nil, scrollContent)
    AF.SetHeight(row, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.indicator = AF.CreateGradientTexture(
        row,
        "HORIZONTAL",
        AF.GetColorTable(AF.player.class, 0.9),
        AF.GetColorTable(AF.player.class, 0),
        nil,
        "BORDER"
    )
    SetIndicator(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 8, 0)
    AF.SetSize(row.icon, ICON_SIZE, ICON_SIZE)
    row.icon:SetVertexColor(AF.GetColorRGB(AF.player.class))

    row.label = AF.CreateFontString(row, nil, "white")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnClick", SelectFromClick)
    row:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintRow(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = nil
        PaintRow(self)
    end)

    rows[#rows + 1] = row
    return row
end

local function AcquireRow(index)
    return rows[index] or CreateRow()
end

local function ApplyEntries()
    if not rail or not scrollContent then return end

    local entries = entriesByMode[mode]
    for index, entry in ipairs(entries) do
        local row = AcquireRow(index)
        activeRows[index] = row
        row.entry = entry
        row.id = entry.id
        row.hovered = nil
        row.label:SetText(entry.label)
        if AF.hasBagIcons and AF.SetAdaptiveIcon then
            AF.SetAdaptiveIcon(row.icon, entry.icon)
        else
            row.icon:SetTexture(AF.GetIcon(FALLBACK_ICON_BY_MODE[mode]))
        end
        row.icon:SetTexCoord(0, 1, 0, 1)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -((index - 1) * ROW_PITCH))
        row:SetPoint("RIGHT", scrollContent, "RIGHT")
        PaintRow(row)
        row:Show()
    end

    for index = #entries + 1, #rows do
        local row = rows[index]
        activeRows[index] = nil
        row.entry = nil
        row.id = nil
        row.hovered = nil
        row:Hide()
    end

    local contentHeight = #entries > 0
        and (#entries * ROW_HEIGHT) + ((#entries - 1) * ROW_SPACING)
        or 1
    AF.SetHeight(scrollContent, contentHeight)
    SetScroll(scrollFrame:GetVerticalScroll())
    EnsureSelectedRowVisible()
end

local function ApplyDesiredState()
    if not rail then return end

    if mode == "combined" then
        rail:Hide()
        return
    end

    ApplyEntries()
    rail:Show()
end

local function RequestApply()
    ApplyDesiredState()
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
---@param callback? fun(id:any, entry:table, mode:string)
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

---@param newMode "combined"|"categories"|"individual"
---@return boolean accepted
function Sidebar.SetMode(newMode)
    if not VALID_MODES[newMode] then return false end
    if mode == newMode then return true end

    mode = newMode
    RequestApply()
    return true
end

---@param entries table[] entries with id, label, and icon fields
function Sidebar.SetEntries(entries)
    local normalized = {}
    local entriesById = {}

    if type(entries) == "table" then
        for _, entry in ipairs(entries) do
            if type(entry) == "table" and entry.id ~= nil then
                local normalizedEntry = {
                    id = entry.id,
                    label = entry.label or "",
                    icon = entry.icon or ICON_BY_ID[entry.id] or ICON_BY_ID[mode],
                }
                if not entriesById[normalizedEntry.id] then
                    normalized[#normalized + 1] = normalizedEntry
                    entriesById[normalizedEntry.id] = normalizedEntry
                end
            end
        end
    end

    entriesByMode[mode] = normalized
    entriesByIdByMode[mode] = entriesById
    if selectionByMode[mode] ~= nil
        and not entriesById[selectionByMode[mode]] then
        selectionByMode[mode] = nil
    end
    RequestApply()
end

---@param id any
---@return boolean selected
function Sidebar.SetSelection(id)
    if id ~= nil and not entriesByIdByMode[mode][id] then
        id = nil
    end
    selectionByMode[mode] = id
    RequestApply()
    return id ~= nil
end

---@param callback? fun(id:any, entry:table, mode:string)
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
    return mode == "combined" and 0 or DESIRED_WIDTH + CONTENT_GAP
end
