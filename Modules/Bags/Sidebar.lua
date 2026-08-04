---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local type = type

local DESIRED_WIDTH = 170
local COLLAPSED_WIDTH = 40
local CONTENT_GAP = 8
local ROW_HEIGHT = 26
local HEADING_HEIGHT = 22
local ICON_SIZE = 16
local ACCENT_COLOR = "BFI"
local FALLBACK_ICON = "Bag_Misc"
-- Match the RGB TreeList.lua's ApplyNodeIcon already renders string/glyph
-- row icons at: the "else" (glyph) branch resets row.icon to
-- SetVertexColor(1, 1, 1, ROW_ICON_ALPHA) -- full white at the row's
-- existing baseline alpha (AbstractFramework/Widgets/TreeList.lua, commit
-- 973d708d144971970176f3fff2429cda17aaae2b on codex/bag-sidebar-foundation).
-- Reusing that exact RGB here means the new native atlas/texture category
-- icons desaturate to the same flat white tone as the rail's remaining
-- Bag_* glyph rows, instead of showing their own full-color native art.
local TEXTURE_TINT = {1, 1, 1}

local OPTIONS = {
    expandedWidth = DESIRED_WIDTH,
    collapsedWidth = COLLAPSED_WIDTH,
    rowHeight = ROW_HEIGHT,
    headingHeight = HEADING_HEIGHT,
    iconSize = ICON_SIZE,
    accentColor = ACCENT_COLOR,
    fallbackIcon = FALLBACK_ICON,
    textureTint = TEXTURE_TINT,
}

local Sidebar = B.Sidebar or {}
B.Sidebar = Sidebar

local rail
-- Buffered until Initialize creates the rail; AF.CreateSidebarRail becomes
-- the single source of truth for this state once it exists.
local pendingShown = true
local pendingCollapsed = false
local onSelected
local onCollapsedChanged
local onPresentationWidthChanged

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
    rail:SetCollapsed(pendingCollapsed, true)
    if onSelected then
        rail.treeList:SetOnSelected(onSelected)
    end
    if onCollapsedChanged then
        rail:SetOnCollapsedChanged(onCollapsedChanged)
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
    return rail.treeList:SetModel(nextModel)
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

---@param collapsed boolean
---@param silent? boolean suppress onCollapsedChanged (presentation-width callback still fires)
---@return boolean changed true if the collapsed state actually changed
function Sidebar.SetCollapsed(collapsed, silent)
    if type(collapsed) ~= "boolean" then return false end
    if rail then return rail:SetCollapsed(collapsed, silent) end
    if pendingCollapsed == collapsed then return false end
    pendingCollapsed = collapsed
    if onPresentationWidthChanged then
        onPresentationWidthChanged(Sidebar.GetDesiredWidth(), Sidebar.GetDesiredWidth())
    end
    if not silent and onCollapsedChanged then
        onCollapsedChanged(collapsed)
    end
    return true
end

---@return boolean collapsed
function Sidebar.GetCollapsed()
    if rail then return rail:GetCollapsed() end
    return pendingCollapsed
end

---@return boolean collapsed the new state
function Sidebar.ToggleCollapsed()
    if rail then return rail:ToggleCollapsed() end

    local collapsed = not pendingCollapsed
    Sidebar.SetCollapsed(collapsed)
    return collapsed
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

---@param callback? fun(collapsed:boolean)
---@return boolean accepted
function Sidebar.SetOnCollapsedChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    onCollapsedChanged = callback
    if rail then
        return rail:SetOnCollapsedChanged(callback)
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
    return pendingCollapsed and COLLAPSED_WIDTH or DESIRED_WIDTH
end

---@return number inset
function Sidebar.GetContentInset()
    if rail then return rail:GetContentInset(CONTENT_GAP) end
    return Sidebar.GetDesiredWidth() + CONTENT_GAP
end
