---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local type = type
local pairs = pairs
local ipairs = ipairs

local DESIRED_WIDTH = 170
local COLLAPSED_WIDTH = 40
local CONTENT_GAP = 8
local ROW_HEIGHT = 26
local HEADING_HEIGHT = 22
local ICON_SIZE = 16
local ACCENT_COLOR = "BFI"
local FALLBACK_ICON = "Bag_Misc"

-- AF's shared tree list has no built-in icon-by-id mapping: it only ever
-- renders entry.icon. This allowlist is BFI's own product mapping, applied
-- before every model handoff to AF.CreateSidebarRail.
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

local OPTIONS = {
    expandedWidth = DESIRED_WIDTH,
    collapsedWidth = COLLAPSED_WIDTH,
    rowHeight = ROW_HEIGHT,
    headingHeight = HEADING_HEIGHT,
    iconSize = ICON_SIZE,
    accentColor = ACCENT_COLOR,
    fallbackIcon = FALLBACK_ICON,
}

local Sidebar = B.Sidebar or {}
B.Sidebar = Sidebar

local rail
-- Buffered until Initialize creates the rail; AF.CreateSidebarRail becomes
-- the single source of truth for this state once it exists.
local pendingShown = true
local pendingAutoHide = false
local onSelected
local onAutoHideChanged
local onPresentationWidthChanged

-- Shallow-copies every id entry (recursively, headings pass through
-- untouched) to fill in a missing icon from ICON_BY_ID without mutating the
-- caller's model table.
local function ApplyIconDefaults(entries)
    local output = {}
    for index, source in ipairs(entries) do
        if type(source) == "table" and source.kind ~= "heading" and source.id ~= nil then
            local entry = {}
            for key, value in pairs(source) do
                entry[key] = value
            end
            entry.icon = entry.icon or ICON_BY_ID[entry.id]
            if type(source.children) == "table" then
                entry.children = ApplyIconDefaults(source.children)
            end
            output[index] = entry
        else
            output[index] = source
        end
    end
    return output
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
        return rail
    end

    rail = AF.CreateSidebarRail(parent, OPTIONS)
    Sidebar.frame = rail
    rail:SetShown(pendingShown)
    rail:SetAutoHide(pendingAutoHide)
    if onSelected then
        rail.treeList:SetOnSelected(onSelected)
    end
    if onAutoHideChanged then
        rail:SetOnAutoHideChanged(onAutoHideChanged)
    end
    if onPresentationWidthChanged then
        rail:SetOnPresentationWidthChanged(onPresentationWidthChanged)
    end
    return rail
end

---@param nextModel table[] hierarchical headings and selectable nodes
---@return boolean accepted
function Sidebar.SetModel(nextModel)
    if type(nextModel) ~= "table" then return false end
    if not rail then return false end
    return rail.treeList:SetModel(ApplyIconDefaults(nextModel))
end

---@param id any
---@return boolean selected
function Sidebar.SetSelection(id)
    if not rail then return false end
    return rail.treeList:SetSelection(id)
end

---@param id any
---@param expanded boolean
---@return boolean accepted
function Sidebar.SetExpanded(id, expanded)
    if not rail then return false end
    return rail.treeList:SetExpanded(id, expanded)
end

---@param id any
---@return boolean accepted
function Sidebar.ToggleExpanded(id)
    if not rail then return false end
    return rail.treeList:ToggleExpanded(id)
end

---@param nextShown boolean
---@return boolean accepted
function Sidebar.SetShown(nextShown)
    if type(nextShown) ~= "boolean" then return false end
    if rail then return rail:SetShown(nextShown) end
    pendingShown = nextShown
    return true
end

---@param nextAutoHide boolean
---@return boolean accepted
function Sidebar.SetAutoHide(nextAutoHide)
    if type(nextAutoHide) ~= "boolean" then return false end
    if rail then return rail:SetAutoHide(nextAutoHide) end
    if pendingAutoHide == nextAutoHide then return true end
    pendingAutoHide = nextAutoHide
    if onPresentationWidthChanged then
        onPresentationWidthChanged(Sidebar.GetDesiredWidth(), Sidebar.GetDesiredWidth())
    end
    return true
end

---@return boolean autoHideEnabled
function Sidebar.GetAutoHide()
    if rail then return rail:GetAutoHide() end
    return pendingAutoHide
end

---@return boolean enabled
function Sidebar.ToggleAutoHide()
    if rail then return rail:ToggleAutoHide() end

    local enabled = not pendingAutoHide
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
    if rail then
        return rail.treeList:SetOnSelected(callback)
    end
    return true
end

---@param callback? fun(enabled:boolean)
---@return boolean accepted
function Sidebar.SetOnAutoHideChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onAutoHideChanged = callback
    if rail then
        return rail:SetOnAutoHideChanged(callback)
    end
    return true
end

---@param callback? fun(presentationWidth:number, reservedWidth:number)
---@return boolean accepted
function Sidebar.SetOnPresentationWidthChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onPresentationWidthChanged = callback
    if rail then
        return rail:SetOnPresentationWidthChanged(callback)
    end
    if callback then
        callback(Sidebar.GetDesiredWidth(), Sidebar.GetDesiredWidth())
    end
    return true
end

---@return number width
function Sidebar.GetDesiredWidth()
    if rail then return rail:GetDesiredWidth() end
    return pendingAutoHide and COLLAPSED_WIDTH or DESIRED_WIDTH
end

---@return number inset
function Sidebar.GetContentInset()
    if rail then return rail:GetContentInset(CONTENT_GAP) end
    return Sidebar.GetDesiredWidth() + CONTENT_GAP
end
