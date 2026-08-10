---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local type = type

local DESIRED_WIDTH = 170
-- 40px carries the compact icon + chevron; the extra 10px is AF's dedicated
-- transient-scrollbar lane, preventing it from covering a parent chevron.
local COLLAPSED_WIDTH = 50
local CONTENT_GAP = 8
local HEADING_HEIGHT = 22
local ACCENT_COLOR = "BFI"
local FALLBACK_ICON = "Bag_Misc"

-- Task 3 (sidebar v3): rowHeight/iconSize and textureTint are no longer
-- passed here. AbstractFramework/Widgets/TreeList.lua (codex/bag-sidebar-
-- foundation) now renders every row's icon at full native color on a
-- squared plate -- textureTint has been deleted from the widget entirely
-- (passing it would be inert), and texture-shaped icons are auto-cropped to
-- the plate by ApplyNodeIcon/AF.ApplyDefaultTexCoord, so BFI no longer
-- desaturates category icons to the rail's flat glyph-row white. rowHeight/
-- iconSize are also dropped so AF's own defaults govern (DEFAULT_ROW_HEIGHT
-- = 28, DEFAULT_ICON_SIZE = 20 in TreeList.lua), matching Task 2's sizing
-- baseline instead of this module's previous 26/16 override.
local OPTIONS = {
    expandedWidth = DESIRED_WIDTH,
    collapsedWidth = COLLAPSED_WIDTH,
    headingHeight = HEADING_HEIGHT,
    accentColor = ACCENT_COLOR,
    fallbackIcon = FALLBACK_ICON,
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

-- Deliberate return asymmetry: SetShown's boolean means "accepted" (true
-- even when nextShown matches the current state), while SetCollapsed's
-- boolean means "state changed" (false on a no-op call) -- callers must
-- not treat the two return values interchangeably.
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
