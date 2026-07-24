---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
local L = BFI.L
---@type Style
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local ceil = math.ceil
local floor = math.floor
local sort = table.sort
local band = _G.bit.band
local GetCVarBool = _G.GetCVarBool
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local GetItemClassInfo = _G.C_Item.GetItemClassInfo
local GetItemSubClassInfo = _G.C_Item.GetItemSubClassInfo
local SetCVar = _G.SetCVar

local BAG_TOP_WITH_SLOTS = 100
local BAG_TOP_WITHOUT_SLOTS = 64
local CATEGORY_HEADER_HEIGHT = 18
local CATEGORY_HEADER_GAP = 4
local CATEGORY_SPACING = 7
local CATEGORY_SECTION_SPACING = 12
local CATEGORY_MIN_COLUMNS = 3
local CATEGORY_TARGET_ROWS = 4
local ITEM_SIZE = 37
local HORIZONTAL_PADDING = 12
local FOOTER_PADDING = 12
local MIN_FRAME_WIDTH = 320
local SCREEN_EDGE_MARGIN = 16
local CATEGORY_VIEW_ICON = AF.GetIcon("Layout")
local COMBINED_VIEW_ICON = AF.GetIcon("Menu4")
local BAG_BUTTON_ATLAS = "bag-main"
local BACKPACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local EMPTY_BAG_ICON = 133633

local equipmentSlotAliases = {
    INVTYPE_ROBE = "INVTYPE_CHEST",
    INVTYPE_SHIELD = "INVTYPE_WEAPONOFFHAND",
    INVTYPE_HOLDABLE = "INVTYPE_WEAPONOFFHAND",
    INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED",
    INVTYPE_THROWN = "INVTYPE_RANGED",
}
local equipmentSlotOrder = {
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_CLOAK = 4,
    INVTYPE_CHEST = 5,
    INVTYPE_WRIST = 6,
    INVTYPE_HAND = 7,
    INVTYPE_WAIST = 8,
    INVTYPE_LEGS = 9,
    INVTYPE_FEET = 10,
    INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 12,
    INVTYPE_WEAPONMAINHAND = 13,
    INVTYPE_WEAPONOFFHAND = 14,
    INVTYPE_WEAPON = 15,
    INVTYPE_2HWEAPON = 16,
    INVTYPE_RANGED = 17,
    INVTYPE_BODY = 18,
    INVTYPE_TABARD = 19,
    INVTYPE_PROFESSION_TOOL = 20,
    INVTYPE_PROFESSION_GEAR = 21,
    INVTYPE_BAG = 22,
}

local inventoryConstants = _G.Constants.InventoryConstants
local REAGENT_BAG_ID = inventoryConstants.NumBagSlots + inventoryConstants.NumReagentBagSlots

local combinedFrame
local categoryButton
local bagSlotsButton
local categoryButtonShowsCombinedView
local emptyCountOverlay
local emptyCountText
local initialized
local moduleEnabled
local refreshPending
local layoutInProgress
local layoutScale = 1
local layoutEntryCount = 0
local layoutEmptyRepresentative
local layoutEmptyEntryIndex
local layoutEmptyCount = 0
local emptyButtonCount = 0
local layoutAddSlotsTarget
local layoutEpoch = 0
local snapshotCount = 0
local snapshotCategories
local snapshotShowBagSlots
local snapshotColumns
local snapshotSpacing
local snapshotWidth
local snapshotHeight
local snapshotFooterHeight
local hoveredBagID
local portraitWasShown
local portraitMouseEnabled
local portraitAlpha
local UpdateEmptyRepresentativeForCursor
local previousCombinedBags
local hasPreviousCombinedBags
local suppressedReagentFrame
local suppressedReagentAlpha

local bagButtons = {}
local categoryHeaders = {}
local categoryCache = {}
local categoryGroups = {}
local categoryGroupPool = {}
local categoryGroupByKey = {}
local reagentItemButtons = {}
local suppressedMouseStates = {}
local portraitProxyMouseStates = {}
local emptyCountsByBag = {}
local bagFamilies = {}
local emptyButtons = {}
local emptyButtonBagIDs = {}
local emptyButtonFamilies = {}
local layoutObjects = {}
local layoutObjectX = {}
local layoutObjectY = {}
local snapshotButtons = {}
local snapshotBagIDs = {}
local snapshotSlotIDs = {}
local snapshotItemIDs = {}
local snapshotExtended = {}

-- API and lifecycle evidence: Retail 12.0.7
-- Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua and
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua. The native combined
-- container owns item interaction, search, sorting, currency, and its
-- show-only event registrations. BFI only extends its pooled layout.

local function IsEnabled()
    return moduleEnabled and B.config and B.config.enabled
end

local function ApplyPosition()
    if not IsEnabled() or not combinedFrame or not combinedFrame:IsShown() then return end
    if combinedFrame.mover and combinedFrame.mover.isDragging then return end
    combinedFrame:SetScale(layoutScale)
    AF.LoadPosition(combinedFrame, B.config.position)
end

local function GetCategory(itemID)
    if not itemID then
        return "empty", _G.EMPTY or "Empty", 1000
    end

    local cached = categoryCache[itemID]
    if cached then
        return cached[1], cached[2], cached[3]
    end

    local _, _, _, itemEquipLoc, _, classID, subclassID = _G.C_Item.GetItemInfoInstant(itemID)
    local itemClass = _G.Enum.ItemClass
    local key
    local label
    local order

    if itemEquipLoc and itemEquipLoc ~= "" then
        itemEquipLoc = equipmentSlotAliases[itemEquipLoc] or itemEquipLoc
        key = "equipment:" .. itemEquipLoc
        label = L["Equipment - %s"]:format(_G[itemEquipLoc] or itemEquipLoc)
        order = 100 + (equipmentSlotOrder[itemEquipLoc] or 99)
    elseif classID == itemClass.Consumable then
        key = "consumables"
        label = _G.BAG_FILTER_CONSUMABLES or GetItemClassInfo(classID) or "Consumables"
        order = 200
    elseif classID == itemClass.Gem then
        key = "gems"
        label = GetItemClassInfo(classID) or _G.GEMS or "Gems"
        order = 300
    elseif classID == itemClass.Tradegoods
        or classID == itemClass.Reagent
        or classID == itemClass.ItemEnhancement
        or classID == itemClass.Profession then
        local className = GetItemClassInfo(classID) or "Reagents"
        local subclassName = GetItemSubClassInfo(classID, subclassID)
        label = subclassName and (className .. " - " .. subclassName) or className
        key = "profession:" .. (classID or -1) .. ":" .. (subclassID or -1)
        order = 400
    elseif classID == itemClass.Recipe then
        key = "recipes"
        label = GetItemClassInfo(classID) or "Recipes"
        order = 500
    elseif classID == itemClass.Questitem then
        key = "quest"
        label = _G.BAG_FILTER_QUEST_ITEMS or GetItemClassInfo(classID) or "Quest Items"
        order = 800
    else
        key = "class:" .. (classID or -1)
        label = (classID and GetItemClassInfo(classID)) or _G.MISCELLANEOUS or "Miscellaneous"
        order = 600
    end

    cached = {key, label, order}
    categoryCache[itemID] = cached
    return key, label, order
end

local function ResetCategoryGroups()
    wipe(categoryGroupByKey)
    for index, group in ipairs(categoryGroups) do
        wipe(group.items)
        group.key = nil
        group.label = nil
        group.order = nil
        group.layoutX = nil
        group.layoutY = nil
        group.layoutColumns = nil
        group.layoutWidth = nil
        categoryGroupPool[index] = group
    end
    wipe(categoryGroups)
end

local function AcquireCategoryGroup(key, label, order)
    local group = categoryGroupByKey[key]
    if group then return group end

    local index = #categoryGroups + 1
    group = categoryGroupPool[index]
    if not group then
        group = {items = {}}
    end

    group.key = key
    group.label = label
    group.order = order
    categoryGroups[index] = group
    categoryGroupByKey[key] = group
    return group
end

local function CompareCategoryGroups(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.label < b.label
end

local function ItemButtonOnEnter(button)
    if UpdateEmptyRepresentativeForCursor then
        UpdateEmptyRepresentativeForCursor(button)
    end
end

local function StyleItemButton(button)
    if button._BFIBagStyled then return end
    button._BFIBagStyled = true
    button:HookScript("OnEnter", ItemButtonOnEnter)

    local icon = button.Icon or button.icon
    if icon then
        S.StyleIcon(icon)
    end

    S.CreateBackdrop(button, true, nil, 1)
    if button.IconBorder then
        S.StyleIconBorder(button.IconBorder, button.BFIBackdrop)
    end
    if button.ItemSlotBackground then
        button.ItemSlotBackground:SetAlpha(0)
    end
    local normalTexture = button:GetNormalTexture()
    if normalTexture then
        normalTexture:SetAlpha(0)
    end
    if button.BagIndicator then
        button.BagIndicator:ClearAllPoints()
        button.BagIndicator:SetAllPoints(button)
        button.BagIndicator:SetVertexColor(AF.GetColorRGB("BFI"))
    end
end

local function GetCategoryHeader(index)
    local header = categoryHeaders[index]
    if header then return header end

    header = AF.CreateFontString(combinedFrame, nil, "BFI")
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    categoryHeaders[index] = header
    return header
end

local function HideUnusedHeaders(firstUnused)
    for index = firstUnused, #categoryHeaders do
        categoryHeaders[index]:Hide()
    end
end

local function UpdateBagButton(button)
    local bagID = button.bagID
    local inventoryID = bagID > 0 and _G.C_Container.ContainerIDToInventoryID(bagID)
    local texture = inventoryID and GetInventoryItemTexture("player", inventoryID)
    button.icon:SetTexture(texture or (bagID == 0 and BACKPACK_ICON) or EMPTY_BAG_ICON)
    button.count:SetText(_G.C_Container.GetContainerNumSlots(bagID))
end

local function UpdateAggregateEmptyState()
    if not layoutEmptyRepresentative then return end

    local hoveredEmptyCount
    if hoveredBagID ~= nil then
        hoveredEmptyCount = emptyCountsByBag[hoveredBagID] or 0
    end
    emptyCountText:SetText(hoveredEmptyCount ~= nil and hoveredEmptyCount or layoutEmptyCount)
    if hoveredEmptyCount and hoveredEmptyCount > 0 and layoutEmptyRepresentative:IsShown() then
        layoutEmptyRepresentative.BagIndicator:SetShown(true)
    end
end

local function BagButtonOnEnter(button)
    hoveredBagID = button.bagID
    combinedFrame:SetItemsMatchingBagHighlighted(button.bagID, true)
    UpdateAggregateEmptyState()

    _G.GameTooltip:SetOwner(button, "ANCHOR_TOP")
    local inventoryID = button.bagID > 0 and _G.C_Container.ContainerIDToInventoryID(button.bagID)
    if not inventoryID or not _G.GameTooltip:SetInventoryItem("player", inventoryID) then
        local name = _G.C_Container.GetBagName(button.bagID)
        _G.GameTooltip_SetTitle(_G.GameTooltip, name or L["Bag Slots"])
    end
    _G.GameTooltip:Show()
end

local function BagButtonOnLeave(button)
    combinedFrame:SetItemsMatchingBagHighlighted(button.bagID, false)
    hoveredBagID = nil
    UpdateAggregateEmptyState()
    _G.GameTooltip_Hide()
end

local function CreateBagButtons()
    for bagID = _G.Enum.BagIndex.Backpack, REAGENT_BAG_ID do
        local button = _G.CreateFrame("Button", nil, combinedFrame, "BackdropTemplate")
        button.bagID = bagID
        AF.ApplyDefaultBackdropWithColors(button, "widget")

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(AF.GetDefaultTexCoord())

        button.count = AF.CreateFontString(button, nil, "white", "AF_FONT_OUTLINE")
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)

        button:SetScript("OnEnter", BagButtonOnEnter)
        button:SetScript("OnLeave", BagButtonOnLeave)
        bagButtons[#bagButtons + 1] = button
    end
end

local function LayoutBagButtons(spacing)
    local show = B.config.showBagSlots
    local size = 34

    for index, button in ipairs(bagButtons) do
        button:SetShown(show)
        if show then
            AF.SetSize(button, size, size)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", HORIZONTAL_PADDING + ((index - 1) * (size + spacing)), -58)
            UpdateBagButton(button)
        end
    end
end

local function UpdateCategoryButtonState()
    local showCombinedView = B.config.categories
    if categoryButtonShowsCombinedView == showCombinedView then return end
    categoryButtonShowsCombinedView = showCombinedView

    if showCombinedView then
        categoryButton:SetTexture(COMBINED_VIEW_ICON, {16, 16}, {"CENTER", 0, 0})
        categoryButton:SetTooltip(L["Show Combined View"])
    else
        categoryButton:SetTexture(CATEGORY_VIEW_ICON, {16, 16}, {"CENTER", 0, 0})
        categoryButton:SetTooltip(L["Group Items by Category"])
    end
end

local function LayoutControls(width)
    local searchBox = _G.BagItemSearchBox
    local sortButton = _G.BagItemAutoSortButton
    local sortIsAttached = sortButton and sortButton:GetParent() == combinedFrame
    if sortIsAttached then
        sortButton:ClearAllPoints()
        sortButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end

    categoryButton:ClearAllPoints()
    if sortIsAttached then
        categoryButton:SetPoint("RIGHT", sortButton, "LEFT", -3, 0)
    else
        categoryButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end
    categoryButton:Show()
    UpdateCategoryButtonState()
    if B.config.categories then
        categoryButton:LockHighlight()
    else
        categoryButton:UnlockHighlight()
    end

    bagSlotsButton:ClearAllPoints()
    bagSlotsButton:SetPoint("RIGHT", categoryButton, "LEFT", -3, 0)
    bagSlotsButton:Show()
    if B.config.showBagSlots then
        bagSlotsButton:LockHighlight()
    else
        bagSlotsButton:UnlockHighlight()
    end

    if searchBox and searchBox:GetParent() == combinedFrame then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", HORIZONTAL_PADDING, -31)
        searchBox:SetWidth(math.max(80, width - 121))
    end

    local tokenFrame = _G.BackpackTokenFrame
    if tokenFrame and tokenFrame:GetParent() == combinedFrame and tokenFrame.Border then
        tokenFrame.Border:SetAlpha(0)
    end
end

local function SetShownIfChanged(object, shown)
    if shown then
        if not object:IsShown() then
            object:Show()
        end
    elseif object:IsShown() then
        object:Hide()
    end
end

local function ClearLayoutEntries()
    for index = 1, layoutEntryCount do
        layoutObjects[index] = nil
        layoutObjectX[index] = nil
        layoutObjectY[index] = nil
    end
    layoutEntryCount = 0
end

local function AddLayoutEntry(object, isHeader, x, y)
    layoutEntryCount = layoutEntryCount + 1
    layoutObjects[layoutEntryCount] = object
    layoutObjectX[layoutEntryCount] = x
    layoutObjectY[layoutEntryCount] = y
    if not isHeader then
        object._BFIBagLayoutEpoch = layoutEpoch
    end
    return layoutEntryCount
end

local function GetBagFamily(bagID)
    local bagFamily = bagFamilies[bagID]
    if bagFamily == nil then
        local _
        _, bagFamily = _G.C_Container.GetContainerNumFreeSlots(bagID)
        bagFamily = bagFamily or -1
        bagFamilies[bagID] = bagFamily
    end
    return bagFamily
end

local function InvalidateLayoutSnapshot()
    wipe(snapshotButtons)
    wipe(snapshotBagIDs)
    wipe(snapshotSlotIDs)
    wipe(snapshotItemIDs)
    wipe(snapshotExtended)
    snapshotCount = 0
    snapshotCategories = nil
    snapshotShowBagSlots = nil
    snapshotColumns = nil
    snapshotSpacing = nil
    snapshotWidth = nil
    snapshotHeight = nil
    snapshotFooterHeight = nil
end

local function ClearLayoutState()
    if layoutEmptyRepresentative and layoutEmptyRepresentative.BagIndicator then
        layoutEmptyRepresentative.BagIndicator:Hide()
    end
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
    end
    emptyButtonCount = 0
    ClearLayoutEntries()
    InvalidateLayoutSnapshot()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
    layoutEmptyRepresentative = nil
    layoutEmptyEntryIndex = nil
    layoutEmptyCount = 0
    layoutAddSlotsTarget = nil
    hoveredBagID = nil
end

local function CaptureLayoutSnapshot(force)
    local footerHeight = combinedFrame:CalculateExtraHeight() + FOOTER_PADDING
    local screenWidth = floor(_G.UIParent:GetWidth())
    local screenHeight = floor(_G.UIParent:GetHeight())
    local itemCount = #combinedFrame.Items
    local changed = force
        or itemCount ~= snapshotCount
        or B.config.categories ~= snapshotCategories
        or B.config.showBagSlots ~= snapshotShowBagSlots
        or B.config.columns ~= snapshotColumns
        or B.config.spacing ~= snapshotSpacing
        or screenWidth ~= snapshotWidth
        or screenHeight ~= snapshotHeight
        or footerHeight ~= snapshotFooterHeight

    for index, itemButton in ipairs(combinedFrame.Items) do
        local bagID = itemButton:GetBagID()
        local slotID = itemButton:GetID()
        local itemID = _G.C_Container.GetContainerItemID(bagID, slotID) or false
        local isExtended = itemButton:IsExtended()

        if itemButton ~= snapshotButtons[index]
            or bagID ~= snapshotBagIDs[index]
            or slotID ~= snapshotSlotIDs[index]
            or itemID ~= snapshotItemIDs[index]
            or isExtended ~= snapshotExtended[index] then
            changed = true
        end

        snapshotButtons[index] = itemButton
        snapshotBagIDs[index] = bagID
        snapshotSlotIDs[index] = slotID
        snapshotItemIDs[index] = itemID
        snapshotExtended[index] = isExtended
    end

    for index = itemCount + 1, snapshotCount do
        snapshotButtons[index] = nil
        snapshotBagIDs[index] = nil
        snapshotSlotIDs[index] = nil
        snapshotItemIDs[index] = nil
        snapshotExtended[index] = nil
    end

    snapshotCount = itemCount
    snapshotCategories = B.config.categories
    snapshotShowBagSlots = B.config.showBagSlots
    snapshotColumns = B.config.columns
    snapshotSpacing = B.config.spacing
    snapshotWidth = screenWidth
    snapshotHeight = screenHeight
    snapshotFooterHeight = footerHeight
    return changed, footerHeight, screenWidth, screenHeight
end

local function RenderLayout()
    for index = 1, layoutEntryCount do
        local object = layoutObjects[index]
        object:ClearAllPoints()
        object:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", layoutObjectX[index], layoutObjectY[index])
        SetShownIfChanged(object, true)
    end

    if layoutEmptyRepresentative and layoutEmptyRepresentative:IsShown() then
        emptyCountOverlay:ClearAllPoints()
        emptyCountOverlay:SetAllPoints(layoutEmptyRepresentative)
        emptyCountOverlay:SetFrameLevel(layoutEmptyRepresentative:GetFrameLevel() + 2)
        emptyCountOverlay:Show()
        UpdateAggregateEmptyState()
    else
        emptyCountOverlay:Hide()
    end

    local addSlotsButton = combinedFrame.AddSlotsButton
    if addSlotsButton then
        local showAddSlots = layoutAddSlotsTarget
            and layoutAddSlotsTarget:IsShown()
            and not _G.IsAccountSecured()
        if showAddSlots then
            addSlotsButton:ClearAllPoints()
            addSlotsButton:SetPoint("LEFT", layoutAddSlotsTarget, "LEFT", -14, -2)
        end
        SetShownIfChanged(addSlotsButton, showAddSlots)
    end
end

-- Keep one visual empty slot while retaining native drop validation: when
-- general storage is full, swap its backing button to a compatible bag family.
UpdateEmptyRepresentativeForCursor = function(button)
    if button ~= layoutEmptyRepresentative or not layoutEmptyEntryIndex or not _G.CursorHasItem() then return end

    local cursorItemLocation = _G.C_Cursor.GetCursorItem()
    if not cursorItemLocation then return end

    local itemID = _G.C_Item.GetItemID(cursorItemLocation)
    if not itemID then return end

    local itemFamily = _G.C_Item.GetItemFamily(itemID) or 0
    local isCraftingReagent = select(17, _G.C_Item.GetItemInfo(itemID))
    local compatibleButton
    local compatiblePriority = math.huge

    for index = 1, emptyButtonCount do
        local emptyButton = emptyButtons[index]
        local bagID = emptyButtonBagIDs[index]
        local bagFamily = emptyButtonFamilies[index]
        local isStillEmpty = not _G.C_Container.GetContainerItemID(bagID, emptyButton:GetID())
        local isCompatible
        local priority

        if bagID == REAGENT_BAG_ID then
            isCompatible = isCraftingReagent
            priority = 4
        elseif bagID == _G.Enum.BagIndex.Backpack then
            isCompatible = true
            priority = 1
        elseif bagFamily == 0 then
            isCompatible = true
            priority = 2
        elseif bagFamily > 0 and itemFamily > 0 then
            isCompatible = band(bagFamily, itemFamily) ~= 0
            priority = 3
        end

        if isStillEmpty and isCompatible and priority < compatiblePriority then
            compatibleButton = emptyButton
            compatiblePriority = priority
        end
    end

    if not compatibleButton or compatibleButton == layoutEmptyRepresentative then return end

    local previousRepresentative = layoutEmptyRepresentative
    previousRepresentative._BFIBagLayoutEpoch = nil
    compatibleButton._BFIBagLayoutEpoch = layoutEpoch
    layoutObjects[layoutEmptyEntryIndex] = compatibleButton
    layoutEmptyRepresentative = compatibleButton

    if previousRepresentative.BagIndicator then
        previousRepresentative.BagIndicator:Hide()
    end
    SetShownIfChanged(previousRepresentative, false)
    AF.SetSize(compatibleButton, ITEM_SIZE, ITEM_SIZE)

    if hoveredBagID then
        combinedFrame:SetItemsMatchingBagHighlighted(hoveredBagID, true)
    end
    RenderLayout()
end

-- WoW's Lua runtime limits each function to 60 captured upvalues, so keep the
-- layout pipeline split into focused phases instead of merging these helpers.
local function ResetLayoutModel()
    layoutEpoch = layoutEpoch + 1
    layoutAddSlotsTarget = nil
    ResetCategoryGroups()
    ClearLayoutEntries()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
    end
    emptyButtonCount = 0
end

local function BuildItemGroups(showCategories)
    local emptyRepresentative
    local emptyRepresentativePriority = math.huge
    local emptyCount = 0
    local normalBagLimit = inventoryConstants.NumBagSlots

    local flatGroup
    if not showCategories then
        flatGroup = AcquireCategoryGroup("all", "", 1)
    end

    for index, itemButton in ipairs(combinedFrame.Items) do
        StyleItemButton(itemButton)

        local bagID = snapshotBagIDs[index]
        local itemID = snapshotItemIDs[index]
        if itemID == false then
            itemID = nil
        end

        if itemID then
            local group = flatGroup
            if showCategories then
                local key, label, order = GetCategory(itemID)
                group = AcquireCategoryGroup(key, label, order)
            end
            group.items[#group.items + 1] = itemButton
        elseif snapshotExtended[index] then
            layoutAddSlotsTarget = layoutAddSlotsTarget or itemButton
            local group = flatGroup
            if showCategories then
                group = AcquireCategoryGroup("locked", L["Bag Slots"], 900)
            end
            group.items[#group.items + 1] = itemButton
        else
            emptyCount = emptyCount + 1
            emptyCountsByBag[bagID] = (emptyCountsByBag[bagID] or 0) + 1
            local bagFamily = GetBagFamily(bagID)
            emptyButtonCount = emptyButtonCount + 1
            emptyButtons[emptyButtonCount] = itemButton
            emptyButtonBagIDs[emptyButtonCount] = bagID
            emptyButtonFamilies[emptyButtonCount] = bagFamily

            local priority
            if bagID == _G.Enum.BagIndex.Backpack then
                priority = 1
            elseif bagID <= normalBagLimit then
                priority = bagFamily == 0 and 2 or 3
            else
                priority = 4
            end

            if priority < emptyRepresentativePriority then
                emptyRepresentative = itemButton
                emptyRepresentativePriority = priority
            end
        end
    end

    if emptyRepresentative then
        local group = flatGroup
        if showCategories then
            group = AcquireCategoryGroup("empty", _G.EMPTY or "Empty", 1000)
        end
        group.items[#group.items + 1] = emptyRepresentative
    end

    local groupCount = #categoryGroups
    if showCategories then
        sort(categoryGroups, CompareCategoryGroups)
    end
    return emptyRepresentative, emptyCount, groupCount
end

local function GetGridWidth(columnCount, spacing)
    return (columnCount * ITEM_SIZE) + ((columnCount - 1) * spacing)
end

local function GetGridHeight(itemCount, columnCount, spacing)
    local rowCount = ceil(itemCount / columnCount)
    if rowCount == 0 then return 0 end
    return (rowCount * ITEM_SIZE) + ((rowCount - 1) * spacing)
end

local function GetLayoutConstraints(spacing, screenWidth, screenHeight)
    local maxFrameWidth = math.max(
        ITEM_SIZE + (HORIZONTAL_PADDING * 2),
        screenWidth - (SCREEN_EDGE_MARGIN * 2)
    )
    local maxColumns = math.max(
        1,
        floor((maxFrameWidth - (HORIZONTAL_PADDING * 2) + spacing) / (ITEM_SIZE + spacing))
    )
    local maxFrameHeight = math.max(1, screenHeight - (SCREEN_EDGE_MARGIN * 2))
    return maxColumns, maxFrameHeight, math.min(MIN_FRAME_WIDTH, maxFrameWidth)
end

local function CalculateFlatLayoutMetrics(
    itemCount,
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(spacing, screenWidth, screenHeight)
    local columns = math.min(requestedColumns, maxColumns)
    local height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight
    end

    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + GetGridWidth(columns, spacing)
    )
    return columns, width, height
end

local function MeasureCategoryGroups(columnCount, spacing, groupCount)
    local contentWidth = GetGridWidth(columnCount, spacing)
    local rowX = 0
    local rowY = 0
    local rowHeight = 0

    for groupIndex = 1, groupCount do
        local group = categoryGroups[groupIndex]
        local itemCount = #group.items
        local groupColumns = math.min(
            columnCount,
            math.max(CATEGORY_MIN_COLUMNS, ceil(itemCount / CATEGORY_TARGET_ROWS))
        )
        local groupWidth = GetGridWidth(groupColumns, spacing)
        local groupHeight = CATEGORY_HEADER_HEIGHT
            + CATEGORY_HEADER_GAP
            + GetGridHeight(itemCount, groupColumns, spacing)

        if rowX > 0 and rowX + groupWidth > contentWidth then
            rowY = rowY + rowHeight + CATEGORY_SPACING
            rowX = 0
            rowHeight = 0
        end

        group.layoutX = rowX
        group.layoutY = rowY
        group.layoutColumns = groupColumns
        group.layoutWidth = groupWidth

        rowX = rowX + groupWidth + CATEGORY_SECTION_SPACING
        rowHeight = math.max(rowHeight, groupHeight)
    end

    return rowY + rowHeight
end

local function CalculateCategoryLayoutMetrics(
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight,
    groupCount
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(spacing, screenWidth, screenHeight)
    local columns = math.min(requestedColumns, maxColumns)
    local contentHeight = MeasureCategoryGroups(columns, spacing, groupCount)
    local height = top + contentHeight + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        contentHeight = MeasureCategoryGroups(columns, spacing, groupCount)
        height = top + contentHeight + footerHeight
    end

    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + GetGridWidth(columns, spacing)
    )
    return width, height
end

local function PrepareLayoutFrame(emptyRepresentative, emptyCount, width, height)
    local previousEmptyRepresentative = layoutEmptyRepresentative
    layoutEmptyRepresentative = emptyRepresentative
    layoutEmptyEntryIndex = nil
    layoutEmptyCount = emptyCount

    if previousEmptyRepresentative
        and previousEmptyRepresentative ~= emptyRepresentative
        and previousEmptyRepresentative.BagIndicator then
        previousEmptyRepresentative.BagIndicator:Hide()
    end
    if hoveredBagID then
        combinedFrame:SetItemsMatchingBagHighlighted(hoveredBagID, true)
    end

    combinedFrame:SetSize(width, height)
end

local function BuildFlatLayoutEntries(columns, spacing, top, emptyRepresentative)
    local group = categoryGroups[1]
    if not group then return end

    local cursorY = -top
    for itemIndex, itemButton in ipairs(group.items) do
        local row = floor((itemIndex - 1) / columns)
        local column = (itemIndex - 1) % columns
        AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
        local entryIndex = AddLayoutEntry(
            itemButton,
            false,
            HORIZONTAL_PADDING + (column * (ITEM_SIZE + spacing)),
            cursorY - (row * (ITEM_SIZE + spacing))
        )
        if itemButton == emptyRepresentative then
            layoutEmptyEntryIndex = entryIndex
        end
    end
end

local function BuildCategoryLayoutEntries(spacing, top, groupCount, emptyRepresentative)
    for groupIndex = 1, groupCount do
        local group = categoryGroups[groupIndex]
        local groupX = HORIZONTAL_PADDING + group.layoutX
        local headerY = -top - group.layoutY
        local header = GetCategoryHeader(groupIndex)
        header:SetText(group.label)
        header:SetSize(group.layoutWidth, CATEGORY_HEADER_HEIGHT)
        AddLayoutEntry(header, true, groupX, headerY)

        local itemTop = headerY - CATEGORY_HEADER_HEIGHT - CATEGORY_HEADER_GAP
        for itemIndex, itemButton in ipairs(group.items) do
            local row = floor((itemIndex - 1) / group.layoutColumns)
            local column = (itemIndex - 1) % group.layoutColumns
            AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
            local entryIndex = AddLayoutEntry(
                itemButton,
                false,
                groupX + (column * (ITEM_SIZE + spacing)),
                itemTop - (row * (ITEM_SIZE + spacing))
            )
            if itemButton == emptyRepresentative then
                layoutEmptyEntryIndex = entryIndex
            end
        end
    end
end

local function FinalizeLayoutEntries(spacing, groupCount, showCategories)
    for _, itemButton in ipairs(combinedFrame.Items) do
        if itemButton._BFIBagLayoutEpoch ~= layoutEpoch then
            SetShownIfChanged(itemButton, false)
        end
    end

    HideUnusedHeaders(showCategories and (groupCount + 1) or 1)
    LayoutBagButtons(spacing)
end

local function LayoutItemsInternal(force)
    local changed, footerHeight, screenWidth, screenHeight = CaptureLayoutSnapshot(force)
    if not changed then return end

    local showCategories = B.config.categories
    local requestedColumns = B.config.columns
    local spacing = B.config.spacing
    local top = B.config.showBagSlots and BAG_TOP_WITH_SLOTS or BAG_TOP_WITHOUT_SLOTS

    ResetLayoutModel()
    local emptyRepresentative, emptyCount, groupCount = BuildItemGroups(showCategories)
    local width
    local height

    if showCategories then
        width, height = CalculateCategoryLayoutMetrics(
            requestedColumns,
            spacing,
            top,
            footerHeight,
            screenWidth,
            screenHeight,
            groupCount
        )
        PrepareLayoutFrame(emptyRepresentative, emptyCount, width, height)
        BuildCategoryLayoutEntries(spacing, top, groupCount, emptyRepresentative)
    else
        local itemCount = groupCount > 0 and #categoryGroups[1].items or 0
        local columns
        columns, width, height = CalculateFlatLayoutMetrics(
            itemCount,
            requestedColumns,
            spacing,
            top,
            footerHeight,
            screenWidth,
            screenHeight
        )
        PrepareLayoutFrame(emptyRepresentative, emptyCount, width, height)
        BuildFlatLayoutEntries(columns, spacing, top, emptyRepresentative)
    end
    FinalizeLayoutEntries(spacing, groupCount, showCategories)

    -- Both modes keep full-size items and expand to their natural height.
    -- Category sections shelf-pack side by side instead of using a viewport.
    layoutScale = 1
    combinedFrame:SetScale(layoutScale)
    LayoutControls(width)
    RenderLayout()
    ApplyPosition()
end

local function LayoutItems(force)
    if layoutInProgress or not IsEnabled() or not combinedFrame or not combinedFrame.Items then return end
    layoutInProgress = true
    local success = xpcall(function()
        LayoutItemsInternal(force)
    end, _G.geterrorhandler())
    layoutInProgress = nil
    if not success then
        InvalidateLayoutSnapshot()
    end
end

local function AppendReagentBagSlots(frame)
    if not IsEnabled() then return end

    wipe(reagentItemButtons)
    local size = _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID)
    for index = 1, size do
        local itemButton = frame:AcquireNewItemButton()
        local slotID = size - index + 1
        itemButton:Initialize(REAGENT_BAG_ID, slotID)
        reagentItemButtons[slotID] = itemButton
    end
    -- ContainerFrameCombinedBagsMixin:SetBagSize intentionally ignores its
    -- argument, so extend the BaseContainerFrameMixin iterator count directly.
    frame.size = #frame.Items
end

local function DisableMouseRecursively(frame)
    suppressedMouseStates[frame] = frame:IsMouseEnabled()
    frame:EnableMouse(false)
    for _, child in ipairs({frame:GetChildren()}) do
        DisableMouseRecursively(child)
    end
end

local function SuppressReagentFrame()
    if not IsEnabled() then return end

    local frame = _G.ContainerFrameUtil_GetShownFrameForID(REAGENT_BAG_ID)
    if not frame or frame == combinedFrame then return end

    if suppressedReagentFrame ~= frame then
        suppressedReagentFrame = frame
        suppressedReagentAlpha = frame:GetAlpha()
        wipe(suppressedMouseStates)
        DisableMouseRecursively(frame)
    end
    frame:SetAlpha(0)
end

local function RestoreReagentFrame()
    if not suppressedReagentFrame then return end
    suppressedReagentFrame:SetAlpha(suppressedReagentAlpha or 1)
    for frame, mouseEnabled in next, suppressedMouseStates do
        frame:EnableMouse(mouseEnabled)
    end
    wipe(suppressedMouseStates)
    suppressedReagentFrame = nil
    suppressedReagentAlpha = nil
    _G.UpdateContainerFrameAnchors()
end

local function RefreshContents(rebuildSlots)
    if not IsEnabled() or not combinedFrame or not combinedFrame:IsShown() then return end

    if rebuildSlots then
        combinedFrame:UpdateItemSlots()
        combinedFrame:UpdateFrameSize()
        combinedFrame:UpdateItemLayout()
    end
    combinedFrame:Update()
end

local function QueueRefresh(rebuildSlots)
    if refreshPending == "rebuild" or (refreshPending and not rebuildSlots) then return end
    refreshPending = rebuildSlots and "rebuild" or "update"

    _G.C_Timer.After(0, function()
        local pending = refreshPending
        refreshPending = nil
        RefreshContents(pending == "rebuild")
    end)
end

local function OnCombinedFrameShow()
    if not IsEnabled() then return end
    B:RegisterEvent("BAG_UPDATE", B.BAG_UPDATE)
    B:RegisterEvent("ITEM_LOCK_CHANGED", B.ITEM_LOCK_CHANGED)
    B:RegisterEvent("DISPLAY_SIZE_CHANGED", B.DISPLAY_SIZE_CHANGED)

    -- Keep the suppressed reagent container logically open alongside the
    -- combined container so Blizzard's unmodified ToggleAllBags accounting
    -- continues to close both on the next hotkey press.
    _G.C_Timer.After(0, function()
        if IsEnabled()
            and combinedFrame:IsShown()
            and _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID) > 0
            and not _G.IsBagOpen(REAGENT_BAG_ID) then
            _G.OpenBag(REAGENT_BAG_ID)
        end
    end)
end

local function OnCombinedFrameHide()
    B:UnregisterEvent("BAG_UPDATE")
    B:UnregisterEvent("ITEM_LOCK_CHANGED")
    B:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    wipe(categoryCache)
    ResetCategoryGroups()
    ClearLayoutState()
    HideUnusedHeaders(1)
    emptyCountOverlay:Hide()

    _G.C_Timer.After(0, function()
        if IsEnabled() and not combinedFrame:IsShown() then
            if _G.IsBagOpen(REAGENT_BAG_ID) then
                _G.CloseBag(REAGENT_BAG_ID)
            end
            RestoreReagentFrame()
        end
    end)
end

local function SetCombinedBags()
    if not GetCVarBool("combinedBags") then
        SetCVar("combinedBags", 1)
    end
end

local function SuppressCombinedMenu()
    local portraitButton = combinedFrame.PortraitButton
    if portraitButton then
        if portraitWasShown == nil then
            portraitWasShown = portraitButton:IsShown()
            portraitMouseEnabled = portraitButton:IsMouseEnabled()
            portraitAlpha = portraitButton:GetAlpha()
        end
        portraitButton:Hide()
        portraitButton:EnableMouse(false)
        portraitButton:SetAlpha(0)
    end

    for _, child in ipairs({combinedFrame:GetChildren()}) do
        if child.routeToSibling == "PortraitButton" then
            if portraitProxyMouseStates[child] == nil then
                portraitProxyMouseStates[child] = child:IsMouseEnabled()
            end
            child:EnableMouse(false)
        end
    end
end

local function RestoreCombinedMenu()
    local portraitButton = combinedFrame.PortraitButton
    if portraitButton and portraitWasShown ~= nil then
        portraitButton:SetAlpha(portraitAlpha or 1)
        portraitButton:EnableMouse(portraitMouseEnabled)
        portraitButton:SetShown(portraitWasShown)
    end
    for child, mouseEnabled in next, portraitProxyMouseStates do
        child:EnableMouse(mouseEnabled)
    end

    wipe(portraitProxyMouseStates)
    portraitWasShown = nil
    portraitMouseEnabled = nil
    portraitAlpha = nil
end

local function StyleCombinedFrame()
    S.StyleTitledFrame(combinedFrame)
    combinedFrame:SetClampedToScreen(true)
    SuppressCombinedMenu()

    if combinedFrame.MoneyFrame and combinedFrame.MoneyFrame.Border then
        combinedFrame.MoneyFrame.Border:SetAlpha(0)
    end

    S.StyleEditBox(_G.BagItemSearchBox, -3, -2, 3, 2)
    S.StyleIconButton(_G.BagItemAutoSortButton, AF.GetIcon("Refresh"), 16, nil, "gray")
    AF.SetSize(_G.BagItemAutoSortButton, 24, 22)

    categoryButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)
    UpdateCategoryButtonState()
    categoryButton:SetOnClick(function()
        B.config.categories = not B.config.categories
        AF.HideTooltip()
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

    bagSlotsButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)
    bagSlotsButton:SetTexture(BAG_BUTTON_ATLAS, {18, 18}, {"CENTER", 0, 0}, true)
    bagSlotsButton:SetTooltip(L["Show Bags"])
    bagSlotsButton:SetOnClick(function()
        B.config.showBagSlots = not B.config.showBagSlots
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

    emptyCountOverlay = _G.CreateFrame("Frame", nil, combinedFrame)
    emptyCountOverlay:EnableMouse(false)
    AF.SetSize(emptyCountOverlay, ITEM_SIZE, ITEM_SIZE)
    emptyCountText = AF.CreateFontString(emptyCountOverlay, nil, "white", "AF_FONT_OUTLINE")
    emptyCountText:SetPoint("CENTER")
    emptyCountOverlay:Hide()

    CreateBagButtons()

    AF.SetDraggable(combinedFrame.BFIHeader, combinedFrame, true, nil, function(frame)
        AF.SavePositionAsTable(frame, B.config.position)
    end)
    AF.CreateMover(combinedFrame, "BFI: " .. L["Bags"], L["Bags"], B.config.position)
end

local function Initialize()
    if initialized then return true end

    combinedFrame = _G.ContainerFrameCombinedBags
    if not combinedFrame then
        B:RegisterEvent("ADDON_LOADED", B.ADDON_LOADED)
        return false
    end

    initialized = true
    B:UnregisterEvent("ADDON_LOADED")
    StyleCombinedFrame()

    hooksecurefunc(combinedFrame, "UpdateItemSlots", AppendReagentBagSlots)
    hooksecurefunc(combinedFrame, "UpdateItemLayout", function()
        LayoutItems(true)
    end)
    hooksecurefunc(combinedFrame, "UpdateItems", function()
        if IsEnabled() then
            LayoutItems(false)
        end
    end)
    hooksecurefunc(combinedFrame, "UpdateSearchBox", function()
        if IsEnabled() then
            LayoutControls(combinedFrame:GetWidth())
        end
    end)
    hooksecurefunc("OpenBag", function(bagID)
        if bagID == REAGENT_BAG_ID then
            SuppressReagentFrame()
            if IsEnabled() and not combinedFrame:IsShown() then
                _G.OpenBag(_G.Enum.BagIndex.Backpack)
            end
        end
    end)
    hooksecurefunc("ToggleBag", function(bagID)
        if not IsEnabled() or bagID ~= REAGENT_BAG_ID then return end
        if _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID) == 0 then return end

        if _G.IsBagOpen(REAGENT_BAG_ID) then
            SuppressReagentFrame()
            if not combinedFrame:IsShown() then
                _G.OpenBag(_G.Enum.BagIndex.Backpack)
            end
        elseif combinedFrame:IsShown() then
            _G.CloseBackpack()
        end
    end)
    hooksecurefunc("UpdateContainerFrameAnchors", ApplyPosition)

    combinedFrame:HookScript("OnShow", OnCombinedFrameShow)
    combinedFrame:HookScript("OnHide", OnCombinedFrameHide)
    return true
end

local function EnableModule()
    if not Initialize() then return end

    if not moduleEnabled then
        previousCombinedBags = GetCVarBool("combinedBags")
        hasPreviousCombinedBags = true
    end

    moduleEnabled = true
    SuppressCombinedMenu()
    AF.UpdateMoverSave(combinedFrame, B.config.position)
    B:RegisterEvent("USE_COMBINED_BAGS_CHANGED", B.USE_COMBINED_BAGS_CHANGED)
    SetCombinedBags()

    local combinedWasShown = combinedFrame:IsShown()
    if _G.IsBagOpen(REAGENT_BAG_ID) then
        SuppressReagentFrame()
        if not combinedWasShown then
            _G.OpenBag(_G.Enum.BagIndex.Backpack)
        end
    end

    if combinedWasShown then
        OnCombinedFrameShow()
        SuppressReagentFrame()
        RefreshContents(true)
    end
end

local function DisableModule()
    moduleEnabled = nil
    B:UnregisterAllEvents()
    if not initialized then return end

    RestoreReagentFrame()
    wipe(reagentItemButtons)
    wipe(categoryCache)
    ResetCategoryGroups()
    ClearLayoutState()
    layoutScale = 1
    combinedFrame:SetScale(1)

    categoryButton:Hide()
    bagSlotsButton:Hide()
    emptyCountOverlay:Hide()
    for _, button in ipairs(bagButtons) do
        button:Hide()
    end
    HideUnusedHeaders(1)

    if combinedFrame:IsShown() then
        combinedFrame:SetBagSize()
        combinedFrame:UpdateItemSlots()
        combinedFrame:UpdateFrameSize()
        combinedFrame:UpdateItemLayout()
        combinedFrame:Update()
    end

    RestoreCombinedMenu()

    if hasPreviousCombinedBags then
        SetCVar("combinedBags", previousCombinedBags and 1 or 0)
        hasPreviousCombinedBags = nil
    end
end

function B:ADDON_LOADED(_, addonName)
    if addonName == "Blizzard_UIPanels_Game" then
        B:UnregisterEvent("ADDON_LOADED")
        if B.config and B.config.enabled then
            EnableModule()
        end
    end
end

function B:USE_COMBINED_BAGS_CHANGED(_, useCombinedBags)
    if IsEnabled() and not useCombinedBags then
        SetCombinedBags()
    end
end

function B:BAG_UPDATE(_, bagID)
    if bagID == REAGENT_BAG_ID then
        QueueRefresh(false)
    end
end

function B:ITEM_LOCK_CHANGED(_, bagID, slotID)
    if bagID ~= REAGENT_BAG_ID or not slotID then return end
    local itemButton = reagentItemButtons[slotID]
    if not itemButton then return end

    local info = _G.C_Container.GetContainerItemInfo(bagID, slotID)
    _G.SetItemButtonDesaturated(itemButton, info and info.isLocked)
end

function B:DISPLAY_SIZE_CHANGED()
    LayoutItems(true)
end

function B.Refresh()
    if IsEnabled() and combinedFrame and combinedFrame:IsShown() then
        LayoutItems(true)
    end
end

local function UpdateBags(_, module)
    if module and module ~= "bags" then return end
    if not B.config then return end

    if B.config.enabled then
        EnableModule()
    else
        DisableModule()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateBags)
