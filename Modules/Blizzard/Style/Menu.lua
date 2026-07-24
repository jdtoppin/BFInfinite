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

local function StyleMenuCheckbox(_, frame)
    local checkBox = frame.leftTexture1
    if not checkBox then return end

    -- Modern menu checkboxes are compositor textures rather than
    -- CheckButtons, so give every one the same 15/13 BFI treatment.
    local layer, subLevel = checkBox:GetDrawLayer()
    local border = frame:AttachTexture()
    border:SetDrawLayer(layer, subLevel - 1)
    border:SetColorTexture(AF.GetColorRGB("border"))
    AF.SetSize(border, 15, 15)
    AF.SetPoint(border, "CENTER", checkBox)

    checkBox:SetAtlas("")
    checkBox:SetColorTexture(AF.GetColorRGB("widget"))
    AF.SetSize(checkBox, 13, 13)

    local checked = frame.leftTexture2
    if checked then
        checked:SetAtlas("")
        checked:SetColorTexture(AF.GetColorRGB("BFI", 0.7))
        AF.ClearPoints(checked)
        AF.SetPoint(checked, "CENTER", checkBox)
        AF.SetSize(checked, 13, 13)
    end
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
