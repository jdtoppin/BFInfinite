---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

-- local function OpenMenu(manager, ownerRegion, menuDescription, anchor)
--     print("OpenMenu called with:", manager, ownerRegion, menuDescription, anchor)
-- end

-- local function OpenContextMenu(manager, ownerRegion, menuDescription)
--     print("OpenContextMenu called with:", manager, ownerRegion, menuDescription)
-- end

local menuHooksInstalled
local backdrops = {}

local function StyleMenu(menu)
    S.RemoveTextures(menu)

    if backdrops[menu] then return end
    backdrops[menu] = true

    S.CreateBackdrop(menu)
    menu.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget", 0.9))
    AF.ClearPoints(menu.BFIBackdrop)
    AF.SetPoint(menu.BFIBackdrop, "TOPLEFT", menu, 0, -1)
    AF.SetPoint(menu.BFIBackdrop, "BOTTOMRIGHT", menu, 0, 8)

    -- texplore({menu:GetChildren()})
    -- TODO: .ScrollBar
end

local function Manager_OpenMenu(manager, ownerRegion, menuDescription)
    local menu = manager:GetOpenMenu()
    if not menu then return end
    StyleMenu(menu)
    menuDescription:AddMenuAcquiredCallback(StyleMenu) -- submenus
end

function S.StyleMenuSelection(frame, selectedSize)
    local selectionBox = frame.leftTexture1
    if not selectionBox then return end

    -- Modern menu selections are compositor textures rather than CheckButtons.
    local layer, subLevel = selectionBox:GetDrawLayer()
    local border = frame:AttachTexture()
    border:SetDrawLayer(layer, subLevel - 1)
    border:SetColorTexture(AF.GetColorRGB("border"))
    AF.SetSize(border, 15, 15)
    AF.SetPoint(border, "CENTER", selectionBox)

    -- Mainline radios use a -3px icon offset and only a 1px text gap,
    -- while checkboxes use the roomier alignment adopted by BFI. Normalize
    -- both compositor variants so mixed menu rows share one text column.
    AF.ClearPoints(selectionBox)
    AF.SetPoint(selectionBox, "LEFT")
    selectionBox:SetAtlas("")
    selectionBox:SetColorTexture(AF.GetColorRGB("widget"))
    AF.SetSize(selectionBox, 13, 13)

    local fontString = frame.fontString
    if fontString then
        AF.ClearPoints(fontString)
        AF.SetPoint(fontString, "LEFT", selectionBox, "RIGHT", 7, 1)
    end

    local selected = frame.leftTexture2
    if selected then
        selected:SetAtlas("")
        selected:SetColorTexture(AF.GetColorRGB("BFI", 0.7))
        AF.ClearPoints(selected)
        AF.SetPoint(selected, "CENTER", selectionBox)
        AF.SetSize(selected, selectedSize or 13, selectedSize or 13)
    end
end

local function StyleMenuCheckbox(_, frame)
    S.StyleMenuSelection(frame)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    if menuHooksInstalled then return end

    -- Interface\AddOns\Blizzard_Menu\Menu.lua
    local manager = _G.Menu.GetManager()
    if not manager or not _G.MenuVariants then return end

    menuHooksInstalled = true
    hooksecurefunc(manager, "OpenMenu", Manager_OpenMenu)
    hooksecurefunc(manager, "OpenContextMenu", Manager_OpenMenu)
    hooksecurefunc(_G.MenuVariants, "CreateCheckbox", StyleMenuCheckbox)
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
