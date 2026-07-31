---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
local F = BFI.funcs
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
local menuHighlights = setmetatable({}, {__mode = "kv"})

local function IsPublicNumber(value)
    return F.isValueNonSecret(value) and type(value) == "number"
end

local function StyleMenuHighlightRows(menu)
    if menu.ScrollBox then
        local shown = menu.ScrollBox:IsShown()
        if not F.isValueNonSecret(shown) or shown then return end
    end

    local menuLeft = menu:GetLeft()
    if not IsPublicNumber(menuLeft) then return end

    local menuRight = menu:GetRight()
    if not IsPublicNumber(menuRight) then return end

    local scale = menu:GetEffectiveScale()
    if not IsPublicNumber(scale) or scale <= 0 then return end

    local children = {menu:GetChildren()}
    local onePixel = AF.GetNearestPixelSize(1, scale)
    if not IsPublicNumber(onePixel) or onePixel <= 0 then return end

    local targetLeft = menuLeft + onePixel
    local targetRight = menuRight - onePixel
    local columnLeft

    -- Every ordinary menu element is a direct includeInLayout child. A second
    -- left edge identifies a grid, whose cells keep native highlight bounds.
    for _, frame in next, children do
        if frame.includeInLayout then
            local left = frame:GetLeft()
            if not IsPublicNumber(left) then return end
            if columnLeft and abs(left - columnLeft) > onePixel then return end
            columnLeft = columnLeft or left
        end
    end
    if not columnLeft then return end

    local highlightRows = {}
    for _, frame in next, children do
        local highlight = menuHighlights[frame]
        if frame.includeInLayout
            and highlight
            and highlight == frame.highlight
        then
            local frameLeft = frame:GetLeft()
            if not IsPublicNumber(frameLeft) then return end

            local frameRight = frame:GetRight()
            if not IsPublicNumber(frameRight) then return end

            local leftGap = frameLeft - targetLeft
            local rightGap = targetRight - frameRight
            if leftGap >= -onePixel and rightGap >= -onePixel then
                highlightRows[#highlightRows + 1] = {
                    frame = frame,
                    highlight = highlight,
                    leftGap = max(0, leftGap),
                    rightGap = max(0, rightGap),
                }
            end
        end
    end

    for _, row in next, highlightRows do
        row.highlight:ClearAllPoints()
        row.highlight:SetPoint(
            "TOPLEFT", row.frame, "TOPLEFT", -row.leftGap, 0
        )
        row.highlight:SetPoint(
            "BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", row.rightGap, 0
        )
    end
end

local function StyleMenu(menu)
    S.RemoveTextures(menu)

    if not backdrops[menu] then
        backdrops[menu] = true

        S.CreateBackdrop(menu)
        menu.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget", 0.9))
        AF.ClearPoints(menu.BFIBackdrop)
        -- MenuStyle1 offsets rows by 8 at the top and 15 at the bottom.
        -- Match AF dropdown lists by leaving one unit inside each border.
        AF.SetPoint(menu.BFIBackdrop, "TOPLEFT", menu, 0, -7)
        AF.SetPoint(menu.BFIBackdrop, "BOTTOMRIGHT", menu, 0, 14)

        -- Acquired submenu callbacks run before Blizzard lays out their rows.
        hooksecurefunc(menu, "Layout", StyleMenuHighlightRows)
    end

    -- Root menu hooks run after OpenMenu has completed its initial layout.
    StyleMenuHighlightRows(menu)

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

local function StyleMenuHighlight(frame)
    local highlight = frame.highlight
    if not highlight then return end

    -- Match AF Normal Dropdown 1: transparent at rest, then the configured
    -- addon accent hover color through ordinary alpha blending.
    local hoverColor = AF.GetButtonHoverColor("BFI_transparent")
    highlight:SetColorTexture(AF.UnpackColor(hoverColor))
    highlight:SetBlendMode("BLEND")
    menuHighlights[frame] = highlight
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
    hooksecurefunc(_G.MenuVariants, "CreateHighlight", StyleMenuHighlight)
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
