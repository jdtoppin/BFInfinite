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
local SetCVar = _G.SetCVar
local GetCurrentItemLevel = _G.C_Item.GetCurrentItemLevel
local IsEquippableItem = _G.C_Item.IsEquippableItem
local ItemLocation = _G.ItemLocation

local ITEM_CLASS = _G.Enum.ItemClass
local BAG_TOP_WITH_SLOTS = 100
local BAG_TOP_WITHOUT_SLOTS = 64
local SIDEBAR_TOP = 58
local SIDEBAR_MIN_HEIGHT = 180
local SECTION_HEADER_HEIGHT = 18
local SECTION_HEADER_GAP = 4
local SECTION_SPACING = 7
local ITEM_SIZE = 37
local HORIZONTAL_PADDING = 12
local FOOTER_PADDING = 12
local MIN_FRAME_WIDTH = 320
local SCREEN_EDGE_MARGIN = 16
local SHOW_BAGS_ICON = AF.GetIcon("Layers")
local REAGENT_SPACE_ICON = "bags-icon-reagents"
local HEADER_ICON_COLOR = AF.player.class
local BACKPACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local EMPTY_BAG_ICON = 133633
local EMPTY_KIND_BAG = 1
local EMPTY_KIND_REAGENT = 2
local NON_EQUIPMENT_LOCATION = "INVTYPE_NON_EQUIP_IGNORE"

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
local categoryOrderByClass = {
    [ITEM_CLASS.Consumable] = 200,
    [ITEM_CLASS.Gem] = 300,
    [ITEM_CLASS.Tradegoods] = 400,
    [ITEM_CLASS.Reagent] = 400,
    [ITEM_CLASS.ItemEnhancement] = 400,
    [ITEM_CLASS.Profession] = 400,
    [ITEM_CLASS.Recipe] = 500,
    [ITEM_CLASS.Questitem] = 800,
}
local categoryIconByClass = {
    [ITEM_CLASS.Consumable] = "Bag_Consumables",
    [ITEM_CLASS.Gem] = "Bag_TradeGoods",
    [ITEM_CLASS.Tradegoods] = "Bag_TradeGoods",
    [ITEM_CLASS.Reagent] = "Bag_Reagent",
    [ITEM_CLASS.ItemEnhancement] = "Bag_TradeGoods",
    [ITEM_CLASS.Profession] = "Bag_TradeGoods",
    [ITEM_CLASS.Recipe] = "Bag_Recipes",
    [ITEM_CLASS.Questitem] = "Bag_Quest",
}
-- Retail 12.1.0.68914 ItemConstantsDocumentation.lua (wow-ui-source
-- d3915c78aba7) adds ItemClass.Housing. Keep the nil guard for the supported
-- 12.0.7 client, where that enum member is not available.
if ITEM_CLASS.Housing then
    categoryOrderByClass[ITEM_CLASS.Housing] = 600
    categoryIconByClass[ITEM_CLASS.Housing] = "Bag_Housing"
end

local inventoryConstants = _G.Constants.InventoryConstants
local REAGENT_BAG_ID = inventoryConstants.NumBagSlots + inventoryConstants.NumReagentBagSlots

local combinedFrame
local bagSlotsButton
local bagSidebar
local initialized
local moduleEnabled
local itemLevelDisplayActive
local refreshPending
local layoutInProgress
local layoutScale = 1
local layoutEntryCount = 0
local emptyButtonCount = 0
local layoutAddSlotsTarget
local layoutEpoch = 0
local snapshotCount = 0
local snapshotViewMode
local snapshotCategoryKey
local snapshotShowBagSlots
local snapshotColumns
local snapshotSpacing
local snapshotSidebarAutoHide
local snapshotWidth
local snapshotHeight
local snapshotFooterHeight
local hoveredBagID
local activeCategoryKey
local portraitWasShown
local portraitMouseEnabled
local portraitAlpha
local UpdateEmptyRepresentativeForCursor
local previousCombinedBags
local hasPreviousCombinedBags
local suppressedReagentFrame
local suppressedReagentAlpha

local bagButtons = {}
local sectionHeaders = {}
local categoryCache = {}
local categoryGroups = {}
local categoryGroupPool = {}
local categoryGroupByKey = {}
local categoryGroupPoolCount = 0
local individualGroups = {}
local individualGroupPool = {}
local individualGroupByBag = {}
local flatGroup = {items = {}}
local reagentItemButtons = {}
local suppressedMouseStates = {}
local portraitProxyMouseStates = {}
local emptyCountsByBag = {}
local bagFamilies = {}
local emptyButtons = {}
local emptyButtonBagIDs = {}
local emptyButtonFamilies = {}
local emptyButtonKinds = {}
local emptyStates = {
    [EMPTY_KIND_BAG] = {},
    [EMPTY_KIND_REAGENT] = {},
}
local styledItemButtons = setmetatable({}, {__mode = "k"})
local itemLevelButtons = setmetatable({}, {__mode = "k"})
local layoutObjects = {}
local layoutObjectX = {}
local layoutObjectY = {}
local snapshotButtons = {}
local snapshotBagIDs = {}
local snapshotSlotIDs = {}
local snapshotItemIDs = {}
local snapshotExtended = {}
local blizzardBagBarWasShown
local hasBlizzardBagBarState
local cleanupTooltipState = {}
local sidebarModel = {}

local VIEW_MODE_COMBINED = "combined"
local VIEW_MODE_CATEGORIES = "categories"
local VIEW_MODE_INDIVIDUAL = "individual"

-- API and lifecycle evidence: Retail 12.0.7
-- Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua and
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua. The native combined
-- container owns item interaction, search, sorting, currency, and its
-- show-only event registrations. BFI only extends its pooled layout.
-- Blizzard_MainMenuBarBagButtons/Shared/BagsBar.lua and
-- Blizzard_FrameXMLBase/Mainline/FrameLocks.lua show that BagsBar separately
-- owns the persistent HUD buttons and may have a lock-managed logical state.
-- Item-level evidence: Retail 12.0.7.68887 source commit
-- 4383ced30106d51b27e3e86d1987f1552f0d259d and Retail 12.1.0.68914
-- source commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9.
-- ItemDocumentation.lua documents IsEquippableItem and GetCurrentItemLevel;
-- ContainerFrame.lua waits on ContinuableContainer before UpdateItems.
-- ItemButtonTemplate.xml gives stack counts NumberFontNormal, while
-- ItemButtonTemplate.lua applies HIGHLIGHT_FONT_COLOR; item levels mirror both.

local function IsEnabled()
    return moduleEnabled and B.config and B.config.enabled
end

local function GetViewMode()
    local mode = B.config and B.config.viewMode
    if mode == VIEW_MODE_COMBINED or mode == VIEW_MODE_INDIVIDUAL then
        return mode
    end
    return VIEW_MODE_COMBINED
end

local function GetDisplayMode()
    if activeCategoryKey then
        return VIEW_MODE_CATEGORIES
    end
    return GetViewMode()
end

local function IsBlizzardBagBarLogicallyShown(bagsBar)
    if _G.IsFrameSmartShown then
        return _G.IsFrameSmartShown(bagsBar)
    end
    return bagsBar:IsShown()
end

local function ShouldShowBlizzardBagBar()
    return B.config.showBlizzardBagBar
        and not _G.C_GameRules.IsGameRuleActive(_G.Enum.GameRule.BagsUIDisabled)
end

local function SetBlizzardBagBarShown(bagsBar, shown)
    if shown then
        bagsBar:Show()
    else
        bagsBar:Hide()
    end
end

local function UpdateBlizzardBagBarVisibility()
    if not IsEnabled() then return end

    local bagsBar = _G.BagsBar
    if not bagsBar then
        B:RegisterEvent("ADDON_LOADED", B.ADDON_LOADED)
        return
    end

    if not hasBlizzardBagBarState then
        blizzardBagBarWasShown = IsBlizzardBagBarLogicallyShown(bagsBar)
        hasBlizzardBagBarState = true
    end

    local shouldShow = ShouldShowBlizzardBagBar()
    if IsBlizzardBagBarLogicallyShown(bagsBar) ~= shouldShow then
        SetBlizzardBagBarShown(bagsBar, shouldShow)
    end
end

local function RestoreBlizzardBagBar()
    local bagsBar = _G.BagsBar
    if hasBlizzardBagBarState and bagsBar
        and IsBlizzardBagBarLogicallyShown(bagsBar) ~= blizzardBagBarWasShown then
        SetBlizzardBagBarShown(bagsBar, blizzardBagBarWasShown)
    end

    blizzardBagBarWasShown = nil
    hasBlizzardBagBarState = nil
end

local function ApplyPosition()
    if not IsEnabled() or not combinedFrame or not combinedFrame:IsShown() then return end
    if combinedFrame.mover and combinedFrame.mover.isDragging then return end
    combinedFrame:SetScale(layoutScale)
    BFI.funcs.LoadPosition(combinedFrame, B.config.position)
end

local function GetCategory(itemID)
    local cached = categoryCache[itemID]
    if cached then
        return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6], cached[7]
    end

    local _, itemType, itemSubType, itemEquipLoc, _, classID, subclassID =
        _G.C_Item.GetItemInfoInstant(itemID)
    if classID == nil then
        classID = -1
        subclassID = -1
    end

    local parentKey
    local parentLabel
    local parentOrder
    local parentIcon
    local childKey
    local childLabel
    local childOrder

    -- Retail 12.0.7 uses this non-empty sentinel for non-equippable items.
    if itemEquipLoc
        and itemEquipLoc ~= ""
        and itemEquipLoc ~= NON_EQUIPMENT_LOCATION then
        itemEquipLoc = equipmentSlotAliases[itemEquipLoc] or itemEquipLoc
        parentKey = "parent:equipment"
        parentLabel = L["Equipment"]
        parentOrder = 100
        parentIcon = "Bag_Equipment"
        childKey = "equipment:" .. itemEquipLoc
        childLabel = _G[itemEquipLoc] or itemEquipLoc
        childOrder = equipmentSlotOrder[itemEquipLoc] or 99
    else
        parentKey = classID == ITEM_CLASS.Questitem
            and "parent:quest"
            or "parent:class:" .. classID
        if classID == ITEM_CLASS.Questitem then
            parentLabel = _G.BAG_FILTER_QUEST_ITEMS or itemType or L["Quest Items"]
        else
            parentLabel = itemType
            if not parentLabel or parentLabel == "" then
                parentLabel = L["Miscellaneous"]
            end
        end
        parentOrder = categoryOrderByClass[classID] or 600
        parentIcon = categoryIconByClass[classID] or "Bag_Misc"
        childKey = "class:" .. classID .. ":" .. (subclassID or -1)
        if itemSubType and itemSubType ~= "" and itemSubType ~= parentLabel then
            childLabel = itemSubType
        else
            childLabel = L["Other"]
        end
        childOrder = subclassID or 0
    end

    cached = {
        parentKey,
        parentLabel,
        parentOrder,
        parentIcon,
        childKey,
        childLabel,
        childOrder,
    }
    categoryCache[itemID] = cached
    return parentKey, parentLabel, parentOrder, parentIcon, childKey, childLabel, childOrder
end

local function ResetCategoryGroups()
    wipe(categoryGroupByKey)
    for index = 1, categoryGroupPoolCount do
        local group = categoryGroupPool[index]
        wipe(group.items)
        wipe(group.children)
        group.key = nil
        group.label = nil
        group.order = nil
        group.icon = nil
        group.parentKey = nil
    end
    categoryGroupPoolCount = 0
    wipe(categoryGroups)
end

local function AcquireCategoryGroup(key, label, order, icon, parent)
    local group = categoryGroupByKey[key]
    if group then return group end

    categoryGroupPoolCount = categoryGroupPoolCount + 1
    group = categoryGroupPool[categoryGroupPoolCount]
    if not group then
        group = {items = {}, children = {}}
        categoryGroupPool[categoryGroupPoolCount] = group
    end

    group.key = key
    group.label = label
    group.order = order
    group.icon = icon
    group.parentKey = parent and parent.key
    if parent then
        parent.children[#parent.children + 1] = group
    else
        categoryGroups[#categoryGroups + 1] = group
    end
    categoryGroupByKey[key] = group
    return group
end

local function AddItemToCategoryGroups(itemButton, itemID)
    local parentKey, parentLabel, parentOrder, parentIcon,
        childKey, childLabel, childOrder = GetCategory(itemID)
    local parent = AcquireCategoryGroup(
        parentKey,
        parentLabel,
        parentOrder,
        parentIcon
    )
    parent.items[#parent.items + 1] = itemButton

    local child = AcquireCategoryGroup(
        childKey,
        childLabel,
        childOrder,
        nil,
        parent
    )
    child.items[#child.items + 1] = itemButton
end

local function CompareCategoryGroups(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.label < b.label
end

local function SortCategoryGroups()
    sort(categoryGroups, CompareCategoryGroups)
    for _, group in ipairs(categoryGroups) do
        sort(group.children, CompareCategoryGroups)
    end
end

local function ItemButtonOnEnter(button)
    if UpdateEmptyRepresentativeForCursor then
        UpdateEmptyRepresentativeForCursor(button)
    end
end

local function ClearItemLevelText(button)
    local text = button.BFIItemLevel
    if not text then return end
    text:SetText("")
    text:Hide()
end

local function GetItemLevelText(button)
    local text = button.BFIItemLevel
    if text then return text end

    text = AF.CreateFontString(button, nil, nil, "NumberFontNormal", "ARTWORK")
    AF.SetPoint(text, "BOTTOMLEFT", 5, 2)
    text:SetJustifyH("LEFT")

    button.BFIItemLevel = text
    itemLevelButtons[button] = true
    return text
end

local function UpdateItemLevelText(button)
    local bagID = button:GetBagID()
    local slotID = button:GetID()
    local info = _G.C_Container.GetContainerItemInfo(
        bagID,
        slotID
    )
    local itemLink = info and info.hyperlink
    if not itemLink or not IsEquippableItem(itemLink) then
        ClearItemLevelText(button)
        return
    end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    local itemLevel = GetCurrentItemLevel(itemLocation)
    if not itemLevel then
        ClearItemLevelText(button)
        return
    end

    local text = GetItemLevelText(button)
    text:SetText(itemLevel)
    text:SetTextColor(_G.HIGHLIGHT_FONT_COLOR:GetRGB())
    text:Show()
end

local function HideItemLevelTexts()
    if not itemLevelDisplayActive then return end
    itemLevelDisplayActive = nil
    for button in next, itemLevelButtons do
        ClearItemLevelText(button)
    end
end

local function RefreshItemLevelTexts()
    if not B.config.showItemLevel then
        HideItemLevelTexts()
        return
    end
    if not combinedFrame or not combinedFrame.Items then return end

    itemLevelDisplayActive = true
    for _, button in ipairs(combinedFrame.Items) do
        UpdateItemLevelText(button)
    end
end

local function StyleItemButton(button)
    styledItemButtons[button] = true
    if button._BFIBagStyled then
        if button.BFIBagHighlight then
            button.BagIndicator = button.BFIBagHighlight
            button.BagIndicator:Hide()
            button.BagIndicator:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
        end
        if button._BFIBlizzardBagIndicator then
            button._BFIBlizzardBagIndicator:Hide()
        end
        return
    end
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

    -- Retail 12.0.7 only toggles BagIndicator with SetShown. Replace its
    -- padded store artwork with a crisp exterior border without disturbing
    -- the quality-colored BFIBackdrop underneath.
    if button.BagIndicator then
        button._BFIBlizzardBagIndicator = button.BagIndicator
        button._BFIBlizzardBagIndicator:Hide()

        local bagHighlight = _G.CreateFrame("Frame", nil, button, "BackdropTemplate")
        AF.ApplyDefaultBackdrop_NoBackground(bagHighlight)
        bagHighlight:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
        AF.SetOnePixelOutside(bagHighlight, button.BFIBackdrop)
        AF.SetFrameLevel(bagHighlight, 2, button)
        bagHighlight:EnableMouse(false)
        bagHighlight:Hide()
        AF.AddToPixelUpdater_CustomGroup("BFIStyled", bagHighlight)

        button.BFIBagHighlight = bagHighlight
        button.BagIndicator = bagHighlight
    end
end

local function GetSectionHeader(index)
    local header = sectionHeaders[index]
    if header then return header end

    header = AF.CreateFontString(combinedFrame, nil, "BFI")
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    sectionHeaders[index] = header
    return header
end

local function HideUnusedSectionHeaders(firstUnused)
    for index = firstUnused, #sectionHeaders do
        sectionHeaders[index]:Hide()
    end
end

local function UpdateBagButton(button)
    local bagID = button.bagID
    local inventoryID = bagID > 0 and _G.C_Container.ContainerIDToInventoryID(bagID)
    local texture = inventoryID and GetInventoryItemTexture("player", inventoryID)
    button.icon:SetTexture(texture or (bagID == 0 and BACKPACK_ICON) or EMPTY_BAG_ICON)
    button.count:SetText(_G.C_Container.GetContainerNumSlots(bagID))
end

local function ResetEmptyStates()
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if state.representative and state.representative.BagIndicator then
            state.representative.BagIndicator:Hide()
        end
        if state.overlay then
            state.overlay:Hide()
        end
        state.representative = nil
        state.representativePriority = nil
        state.entryIndex = nil
        state.count = 0
    end
end

local function ClearItemBagHighlights()
    for itemButton in next, styledItemButtons do
        if itemButton.BFIBagHighlight then
            itemButton.BFIBagHighlight:Hide()
        end
        if itemButton._BFIBlizzardBagIndicator then
            itemButton._BFIBlizzardBagIndicator:Hide()
        end
    end
end

local function RestoreItemBagIndicators()
    for itemButton in next, styledItemButtons do
        if itemButton._BFIBlizzardBagIndicator then
            itemButton.BFIBagHighlight:Hide()
            itemButton.BagIndicator = itemButton._BFIBlizzardBagIndicator
        end
    end
end

local function UpdateAggregateEmptyState()
    local hoveredKind
    if hoveredBagID ~= nil then
        hoveredKind = hoveredBagID == REAGENT_BAG_ID and EMPTY_KIND_REAGENT or EMPTY_KIND_BAG
    end

    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local displayedCount = state.count or 0
        if hoveredKind == kind then
            displayedCount = emptyCountsByBag[hoveredBagID] or 0
        end
        if state.text then
            state.text:SetText(displayedCount)
        end

        local representative = state.representative
        if representative and representative.BagIndicator then
            representative.BagIndicator:SetShown(
                hoveredKind == kind
                and displayedCount > 0
                and representative:IsShown()
            )
        end
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
        local button = _G.CreateFrame("Button", nil, combinedFrame)
        button.bagID = bagID
        AF.ApplyLightweightBackdropWithColors(button, "widget", "border")
        button.UpdatePixels = function(self)
            AF.DefaultUpdatePixels(self)
            AF.UpdateLightweightBackdropPixels(self)
        end
        AF.AddToPixelUpdater_CustomGroup("BFIStyled", button)

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

local function LayoutBagButtons(spacing, contentInset)
    local show = B.config.showBagSlots
    local size = 34

    for index, button in ipairs(bagButtons) do
        button:SetShown(show)
        if show then
            AF.SetSize(button, size, size)
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                combinedFrame,
                "TOPLEFT",
                HORIZONTAL_PADDING + contentInset + ((index - 1) * (size + spacing)),
                -58
            )
            UpdateBagButton(button)
        end
    end
end

local function LayoutControls(contentInset)
    contentInset = contentInset or (B.Sidebar and B.Sidebar.GetContentInset()) or 0
    local searchBox = _G.BagItemSearchBox
    local sortButton = _G.BagItemAutoSortButton
    local sortIsAttached = sortButton and sortButton:GetParent() == combinedFrame
    if sortIsAttached then
        sortButton:ClearAllPoints()
        sortButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end

    bagSlotsButton:ClearAllPoints()
    if sortIsAttached then
        bagSlotsButton:SetPoint("RIGHT", sortButton, "LEFT", -3, 0)
    else
        bagSlotsButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end
    bagSlotsButton:Show()
    bagSlotsButton:SetTextureColor(HEADER_ICON_COLOR)
    if B.config.showBagSlots then
        bagSlotsButton:LockHighlight()
    else
        bagSlotsButton:UnlockHighlight()
    end

    if searchBox and searchBox:GetParent() == combinedFrame then
        searchBox:ClearAllPoints()
        searchBox:SetPoint(
            "TOPLEFT",
            combinedFrame,
            "TOPLEFT",
            HORIZONTAL_PADDING + contentInset,
            -27
        )
        searchBox:SetPoint("TOPRIGHT", bagSlotsButton, "TOPLEFT", -3, 0)
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
    snapshotViewMode = nil
    snapshotCategoryKey = nil
    snapshotShowBagSlots = nil
    snapshotColumns = nil
    snapshotSpacing = nil
    snapshotSidebarAutoHide = nil
    snapshotWidth = nil
    snapshotHeight = nil
    snapshotFooterHeight = nil
end

local function ClearLayoutState()
    ClearItemBagHighlights()
    ResetEmptyStates()
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
        emptyButtonKinds[index] = nil
    end
    emptyButtonCount = 0
    ClearLayoutEntries()
    InvalidateLayoutSnapshot()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
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
        or GetDisplayMode() ~= snapshotViewMode
        or activeCategoryKey ~= snapshotCategoryKey
        or B.config.showBagSlots ~= snapshotShowBagSlots
        or B.config.columns ~= snapshotColumns
        or B.config.spacing ~= snapshotSpacing
        or B.config.sidebarAutoHide ~= snapshotSidebarAutoHide
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
    snapshotViewMode = GetDisplayMode()
    snapshotCategoryKey = activeCategoryKey
    snapshotShowBagSlots = B.config.showBagSlots
    snapshotColumns = B.config.columns
    snapshotSpacing = B.config.spacing
    snapshotSidebarAutoHide = B.config.sidebarAutoHide
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

    local showAggregateEmpty = GetDisplayMode() ~= VIEW_MODE_INDIVIDUAL
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local representative = state.representative
        if showAggregateEmpty and state.overlay and representative and representative:IsShown() then
            state.overlay:ClearAllPoints()
            state.overlay:SetAllPoints(representative)
            state.overlay:SetFrameLevel(representative:GetFrameLevel() + 3)
            state.overlay:Show()
        elseif state.overlay then
            state.overlay:Hide()
        end
    end
    UpdateAggregateEmptyState()

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

local function GetEmptyStateForButton(button)
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if state.representative == button then
            return state, kind
        end
    end
end

-- Each aggregate tile stays backed by a real empty slot. The general tile may
-- swap between bags 0-4 for native specialty-bag validation; the reagent tile
-- always remains backed by bag 5 so normal items continue to be rejected.
UpdateEmptyRepresentativeForCursor = function(button)
    local state, kind = GetEmptyStateForButton(button)
    if not state or not state.entryIndex or not _G.CursorHasItem() then return end
    if kind == EMPTY_KIND_REAGENT then return end

    local cursorItemLocation = _G.C_Cursor.GetCursorItem()
    if not cursorItemLocation then return end

    local itemID = _G.C_Item.GetItemID(cursorItemLocation)
    if not itemID then return end

    local itemFamily = _G.C_Item.GetItemFamily(itemID) or 0
    local compatibleButton
    local compatiblePriority = math.huge

    for index = 1, emptyButtonCount do
        if emptyButtonKinds[index] == kind then
            local emptyButton = emptyButtons[index]
            local bagID = emptyButtonBagIDs[index]
            local bagFamily = emptyButtonFamilies[index]
            local isStillEmpty = not _G.C_Container.GetContainerItemID(bagID, emptyButton:GetID())
            local isCompatible
            local priority

            if bagID == _G.Enum.BagIndex.Backpack then
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
    end

    if not compatibleButton or compatibleButton == state.representative then return end

    local previousRepresentative = state.representative
    previousRepresentative._BFIBagLayoutEpoch = nil
    compatibleButton._BFIBagLayoutEpoch = layoutEpoch
    layoutObjects[state.entryIndex] = compatibleButton
    state.representative = compatibleButton

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
local function ResetIndividualGroups()
    wipe(individualGroupByBag)
    for index, group in ipairs(individualGroups) do
        wipe(group.items)
        group.bagID = nil
        group.label = nil
        group.order = nil
        group.layoutY = nil
        group.layoutColumns = nil
        group.layoutWidth = nil
        individualGroupPool[index] = group
    end
    wipe(individualGroups)
end

local function ResetLayoutModel()
    layoutEpoch = layoutEpoch + 1
    layoutAddSlotsTarget = nil
    ClearItemBagHighlights()
    ResetEmptyStates()
    ResetCategoryGroups()
    ResetIndividualGroups()
    wipe(flatGroup.items)
    ClearLayoutEntries()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
        emptyButtonKinds[index] = nil
    end
    emptyButtonCount = 0
end

local function GetBagSectionLabel(bagID)
    if bagID == _G.Enum.BagIndex.Backpack then
        return L["Backpack"]
    elseif bagID == REAGENT_BAG_ID then
        return L["Reagent Bag"]
    end
    return L["Bag %d"]:format(bagID)
end

local function AcquireIndividualGroup(bagID)
    local group = individualGroupByBag[bagID]
    if group then return group end

    local index = #individualGroups + 1
    group = individualGroupPool[index]
    if not group then
        group = {items = {}}
    end

    group.bagID = bagID
    group.label = GetBagSectionLabel(bagID)
    group.order = bagID
    individualGroups[index] = group
    individualGroupByBag[bagID] = group
    return group
end

local function RegisterEmptyButton(itemButton, bagID)
    local kind = bagID == REAGENT_BAG_ID and EMPTY_KIND_REAGENT or EMPTY_KIND_BAG
    local state = emptyStates[kind]
    state.count = state.count + 1
    emptyCountsByBag[bagID] = (emptyCountsByBag[bagID] or 0) + 1
    local bagFamily = GetBagFamily(bagID)
    emptyButtonCount = emptyButtonCount + 1
    emptyButtons[emptyButtonCount] = itemButton
    emptyButtonBagIDs[emptyButtonCount] = bagID
    emptyButtonFamilies[emptyButtonCount] = bagFamily
    emptyButtonKinds[emptyButtonCount] = kind

    local priority
    if kind == EMPTY_KIND_REAGENT or bagID == _G.Enum.BagIndex.Backpack then
        priority = 1
    else
        priority = bagFamily == 0 and 2 or 3
    end

    if priority < (state.representativePriority or math.huge) then
        state.representative = itemButton
        state.representativePriority = priority
    end
end

local function AddAggregateEmptyGroups()
    local emptyGroup
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local representative = emptyStates[kind].representative
        if representative then
            flatGroup.items[#flatGroup.items + 1] = representative
            emptyGroup = emptyGroup or AcquireCategoryGroup(
                "empty",
                _G.EMPTY or "Empty",
                1000,
                "Bag_Empty"
            )
            emptyGroup.items[#emptyGroup.items + 1] = representative
        end
    end
end

local function BuildItemGroups()
    for index, itemButton in ipairs(combinedFrame.Items) do
        StyleItemButton(itemButton)

        local bagID = snapshotBagIDs[index]
        local itemID = snapshotItemIDs[index]
        if itemID == false then
            itemID = nil
        end

        local bagGroup = AcquireIndividualGroup(bagID)
        bagGroup.items[#bagGroup.items + 1] = itemButton

        if itemID then
            AddItemToCategoryGroups(itemButton, itemID)
            flatGroup.items[#flatGroup.items + 1] = itemButton
        elseif snapshotExtended[index] then
            layoutAddSlotsTarget = layoutAddSlotsTarget or itemButton
            flatGroup.items[#flatGroup.items + 1] = itemButton
            local lockedGroup = AcquireCategoryGroup(
                "locked",
                L["Bag Slots"],
                900,
                "Bag_Empty"
            )
            lockedGroup.items[#lockedGroup.items + 1] = itemButton
        else
            RegisterEmptyButton(itemButton, bagID)
        end
    end

    AddAggregateEmptyGroups()
    SortCategoryGroups()
    sort(individualGroups, function(a, b) return a.order < b.order end)
end

local function BuildSidebarModel()
    wipe(sidebarModel)
    sidebarModel[1] = {kind = "heading", label = L["Views"]}
    sidebarModel[2] = {
        id = "view:" .. VIEW_MODE_COMBINED,
        kind = "view",
        viewMode = VIEW_MODE_COMBINED,
        label = L["Combined View"],
        icon = "Bag_All",
    }
    sidebarModel[3] = {
        id = "view:" .. VIEW_MODE_INDIVIDUAL,
        kind = "view",
        viewMode = VIEW_MODE_INDIVIDUAL,
        label = L["Individual Bags View"],
        icon = "Bag_IndividualBags",
    }
    sidebarModel[4] = {kind = "heading", label = L["Categories"]}

    for _, group in ipairs(categoryGroups) do
        local node = {
            id = "category:" .. group.key,
            kind = "category",
            categoryKey = group.key,
            label = group.label,
            icon = group.icon,
        }
        if #group.children > 0 then
            node.children = {}
            for _, child in ipairs(group.children) do
                node.children[#node.children + 1] = {
                    id = "category:" .. child.key,
                    kind = "category",
                    categoryKey = child.key,
                    label = child.label,
                }
            end
        end
        sidebarModel[#sidebarModel + 1] = node
    end

    B.Sidebar.SetModel(sidebarModel)
    if activeCategoryKey and categoryGroupByKey[activeCategoryKey] then
        B.Sidebar.SetSelection("category:" .. activeCategoryKey)
        return categoryGroupByKey[activeCategoryKey]
    end

    activeCategoryKey = nil
    B.Sidebar.SetSelection("view:" .. GetViewMode())
    return flatGroup
end

local function GetGridWidth(columnCount, spacing)
    return (columnCount * ITEM_SIZE) + ((columnCount - 1) * spacing)
end

local function GetGridHeight(itemCount, columnCount, spacing)
    local rowCount = ceil(itemCount / columnCount)
    if rowCount == 0 then return 0 end
    return (rowCount * ITEM_SIZE) + ((rowCount - 1) * spacing)
end

local function GetLayoutConstraints(spacing, screenWidth, screenHeight, contentInset)
    local minimumFrameWidth = ITEM_SIZE + (HORIZONTAL_PADDING * 2) + contentInset
    local maxFrameWidth = math.max(
        minimumFrameWidth,
        screenWidth - (SCREEN_EDGE_MARGIN * 2)
    )
    local maxColumns = math.max(
        1,
        floor(
            (maxFrameWidth - (HORIZONTAL_PADDING * 2) - contentInset + spacing)
                / (ITEM_SIZE + spacing)
        )
    )
    local maxFrameHeight = math.max(1, screenHeight - (SCREEN_EDGE_MARGIN * 2))
    local minFrameWidth = math.min(MIN_FRAME_WIDTH + contentInset, maxFrameWidth)
    return maxColumns, maxFrameHeight, minFrameWidth
end

local function CalculateFlatLayoutMetrics(
    itemCount,
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight,
    contentInset
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(
        spacing,
        screenWidth,
        screenHeight,
        contentInset
    )
    local columns = math.min(requestedColumns, maxColumns)
    local height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight
    end

    if contentInset > 0 then
        height = math.max(height, math.min(maxFrameHeight, SIDEBAR_TOP + SIDEBAR_MIN_HEIGHT + footerHeight))
    end

    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + contentInset + GetGridWidth(columns, spacing)
    )
    return columns, width, height
end

local function MeasureIndividualGroups(columnCount, spacing)
    local contentHeight = 0
    local contentWidth = ITEM_SIZE

    for index, group in ipairs(individualGroups) do
        local itemCount = #group.items
        local groupColumns = math.min(columnCount, math.max(1, itemCount))
        local groupWidth = GetGridWidth(groupColumns, spacing)
        local groupHeight = SECTION_HEADER_HEIGHT
            + SECTION_HEADER_GAP
            + GetGridHeight(itemCount, groupColumns, spacing)

        group.layoutY = contentHeight
        group.layoutColumns = groupColumns
        group.layoutWidth = groupWidth
        contentWidth = math.max(contentWidth, groupWidth)
        contentHeight = contentHeight + groupHeight
        if index < #individualGroups then
            contentHeight = contentHeight + SECTION_SPACING
        end
    end

    return contentWidth, contentHeight
end

local function CalculateIndividualLayoutMetrics(
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight,
    contentInset
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(
        spacing,
        screenWidth,
        screenHeight,
        contentInset
    )
    local columns = math.min(requestedColumns, maxColumns)
    local contentWidth, contentHeight = MeasureIndividualGroups(columns, spacing)
    local height = top + contentHeight + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        contentWidth, contentHeight = MeasureIndividualGroups(columns, spacing)
        height = top + contentHeight + footerHeight
    end

    height = math.max(
        height,
        math.min(maxFrameHeight, SIDEBAR_TOP + SIDEBAR_MIN_HEIGHT + footerHeight)
    )
    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + contentInset + contentWidth
    )
    return width, height
end

local function PrepareLayoutFrame(width, height)
    if hoveredBagID then
        combinedFrame:SetItemsMatchingBagHighlighted(hoveredBagID, true)
    end

    combinedFrame:SetSize(width, height)
end

local function RecordEmptyEntryIndex(itemButton, entryIndex)
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if itemButton == state.representative then
            state.entryIndex = entryIndex
            return
        end
    end
end

local function BuildFlatLayoutEntries(columns, spacing, top, contentInset, group)
    if not group then return end

    local cursorY = -top
    for itemIndex, itemButton in ipairs(group.items) do
        local row = floor((itemIndex - 1) / columns)
        local column = (itemIndex - 1) % columns
        AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
        local entryIndex = AddLayoutEntry(
            itemButton,
            false,
            HORIZONTAL_PADDING + contentInset + (column * (ITEM_SIZE + spacing)),
            cursorY - (row * (ITEM_SIZE + spacing))
        )
        RecordEmptyEntryIndex(itemButton, entryIndex)
    end
end

local function BuildIndividualLayoutEntries(spacing, top, contentInset)
    for groupIndex, group in ipairs(individualGroups) do
        local groupX = HORIZONTAL_PADDING + contentInset
        local headerY = -top - group.layoutY
        local header = GetSectionHeader(groupIndex)
        header:SetText(group.label)
        header:SetSize(group.layoutWidth, SECTION_HEADER_HEIGHT)
        AddLayoutEntry(header, true, groupX, headerY)

        local itemTop = headerY - SECTION_HEADER_HEIGHT - SECTION_HEADER_GAP
        for itemIndex, itemButton in ipairs(group.items) do
            local row = floor((itemIndex - 1) / group.layoutColumns)
            local column = (itemIndex - 1) % group.layoutColumns
            AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
            AddLayoutEntry(
                itemButton,
                false,
                groupX + (column * (ITEM_SIZE + spacing)),
                itemTop - (row * (ITEM_SIZE + spacing))
            )
        end
    end
end

local function FinalizeLayoutEntries(spacing, contentInset, sectionCount)
    for _, itemButton in ipairs(combinedFrame.Items) do
        if itemButton._BFIBagLayoutEpoch ~= layoutEpoch then
            SetShownIfChanged(itemButton, false)
        end
    end

    HideUnusedSectionHeaders((sectionCount or 0) + 1)
    LayoutBagButtons(spacing, contentInset)
end

local function LayoutItemsInternal(force)
    B.Sidebar.SetAutoHide(B.config.sidebarAutoHide)
    local changed, footerHeight, screenWidth, screenHeight = CaptureLayoutSnapshot(force)
    if not changed then return end

    local requestedColumns = B.config.columns
    local spacing = B.config.spacing
    local top = B.config.showBagSlots and BAG_TOP_WITH_SLOTS or BAG_TOP_WITHOUT_SLOTS

    B.Sidebar.SetShown(true)
    local contentInset = B.Sidebar.GetContentInset()
    if bagSidebar then
        bagSidebar:ClearAllPoints()
        bagSidebar:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", HORIZONTAL_PADDING, -SIDEBAR_TOP)
        bagSidebar:SetPoint("BOTTOMLEFT", combinedFrame, "BOTTOMLEFT", HORIZONTAL_PADDING, footerHeight)
    end

    ResetLayoutModel()
    BuildItemGroups()
    local group = BuildSidebarModel()
    local viewMode = GetDisplayMode()
    local width
    local height
    local columns
    if viewMode == VIEW_MODE_INDIVIDUAL then
        width, height = CalculateIndividualLayoutMetrics(
            requestedColumns,
            spacing,
            top,
            footerHeight,
            screenWidth,
            screenHeight,
            contentInset
        )
        PrepareLayoutFrame(width, height)
        BuildIndividualLayoutEntries(spacing, top, contentInset)
        FinalizeLayoutEntries(spacing, contentInset, #individualGroups)
        layoutScale = math.min(
            1,
            (screenWidth - (SCREEN_EDGE_MARGIN * 2)) / width,
            (screenHeight - (SCREEN_EDGE_MARGIN * 2)) / height
        )
    else
        local itemCount = group and #group.items or 0
        columns, width, height = CalculateFlatLayoutMetrics(
            itemCount,
            requestedColumns,
            spacing,
            top,
            footerHeight,
            screenWidth,
            screenHeight,
            contentInset
        )
        PrepareLayoutFrame(width, height)
        BuildFlatLayoutEntries(columns, spacing, top, contentInset, group)
        FinalizeLayoutEntries(spacing, contentInset, 0)
        layoutScale = 1
    end

    -- Individual Bags keeps every physical slot in its own labeled section;
    -- Combined and category selections retain the compact aggregate-empty model.
    combinedFrame:SetScale(layoutScale)
    LayoutControls(contentInset)
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
    B.Cleanup:Cancel(false)
    HideItemLevelTexts()
    B:UnregisterEvent("BAG_UPDATE")
    B:UnregisterEvent("ITEM_LOCK_CHANGED")
    B:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    wipe(categoryCache)
    ResetCategoryGroups()
    ResetIndividualGroups()
    HideUnusedSectionHeaders(1)
    ClearLayoutState()
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

local function CreateEmptyStateOverlays()
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local overlay = _G.CreateFrame("Frame", nil, combinedFrame)
        overlay:EnableMouse(false)
        AF.SetSize(overlay, ITEM_SIZE, ITEM_SIZE)

        local icon = overlay:CreateTexture(nil, "ARTWORK")
        AF.SetSize(icon, 15, 15)
        icon:SetPoint("TOPLEFT", 3, -3)
        if kind == EMPTY_KIND_REAGENT then
            icon:SetAtlas(REAGENT_SPACE_ICON)
        else
            icon:SetTexture(SHOW_BAGS_ICON)
        end
        icon:SetVertexColor(AF.GetColorRGB(HEADER_ICON_COLOR))

        local text = AF.CreateFontString(overlay, nil, "white", "AF_FONT_OUTLINE")
        text:SetPoint("BOTTOMRIGHT", -3, 3)

        state.overlay = overlay
        state.icon = icon
        state.text = text
        overlay:Hide()
    end
end

local function UpdateCombinedFrameTitle(frame)
    if IsEnabled() then
        frame:SetTitle(L["Bags"])
    end
end

local function StyleBagSearchBox()
    local searchBox = _G.BagItemSearchBox
    S.StyleEditBox(searchBox)
    AF.SetHeight(searchBox, 22)
    searchBox:SetTextInsets(20, 22, 0, 0)

    searchBox.searchIcon:ClearAllPoints()
    searchBox.searchIcon:SetPoint("LEFT", 5, 0)

    searchBox.Instructions:ClearAllPoints()
    searchBox.Instructions:SetPoint("TOPLEFT", 20, 0)
    searchBox.Instructions:SetPoint("BOTTOMRIGHT", -22, 0)
end

local function CleanupButtonOnEnter(button)
    if not IsEnabled() then return end
    _G.GameTooltip:Hide()
    AF.ShowTooltip(button, "TOPLEFT", 0, 2, cleanupTooltipState.lines)
end

local function CleanupButtonOnLeave()
    AF.HideTooltip()
end

local function SetupCleanupTooltip()
    local button = _G.BagItemAutoSortButton
    if not button then return end

    cleanupTooltipState.lines = cleanupTooltipState.lines or {}
    cleanupTooltipState.lines[1] = _G.BAG_CLEANUP_BAGS
    cleanupTooltipState.lines[2] = _G.BAG_CLEANUP_BAGS_DESCRIPTION
    button.accentColor = "BFI"

    if not cleanupTooltipState.hooked then
        -- Preserve Blizzard and BFI scripts; our post-hook swaps the visible tooltip.
        cleanupTooltipState.hooked = true
        button:HookScript("OnEnter", CleanupButtonOnEnter)
        button:HookScript("OnLeave", CleanupButtonOnLeave)
    end
end

local function StyleCleanupButton()
    local button = _G.BagItemAutoSortButton
    S.StyleIconButton(button, AF.GetIcon("Refresh"), 16, HEADER_ICON_COLOR, "gray")
    AF.SetSize(button, 24, 22)
    SetupCleanupTooltip()
    B.Cleanup:Install(button)
end

local function StyleCombinedFrame()
    -- AF r30's lightweight panel primitive follows Retail 12.1.0.68914
    -- (wow-ui-source d3915c78aba7) without BackdropTemplate's nine regions
    -- and OnSizeChanged texture-coordinate work.
    S.StyleTitledFrame(combinedFrame, nil, true)
    combinedFrame:SetClampedToScreen(true)
    SuppressCombinedMenu()
    UpdateCombinedFrameTitle(combinedFrame)

    -- Retail 12.0.7 UpdateName restores COMBINED_BAG_TITLE during updates.
    hooksecurefunc(combinedFrame, "UpdateName", UpdateCombinedFrameTitle)

    if combinedFrame.MoneyFrame and combinedFrame.MoneyFrame.Border then
        combinedFrame.MoneyFrame.Border:SetAlpha(0)
    end

    StyleBagSearchBox()
    StyleCleanupButton()

    bagSlotsButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)
    bagSlotsButton:SetTexture(SHOW_BAGS_ICON, {16, 16}, {"CENTER", 0, 0})
    bagSlotsButton:SetTextureColor(HEADER_ICON_COLOR)
    bagSlotsButton:SetTooltip(L["Show Bags"])
    bagSlotsButton:SetOnClick(function()
        B.config.showBagSlots = not B.config.showBagSlots
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

    CreateEmptyStateOverlays()

    CreateBagButtons()

    B.Sidebar.SetAutoHide(B.config.sidebarAutoHide)
    bagSidebar = B.Sidebar.Initialize(combinedFrame, function(_, entry)
        if entry.kind == "view" then
            activeCategoryKey = nil
            B.config.viewMode = entry.viewMode
            AF.Fire("BFI_RefreshOptions", "bags")
        elseif entry.kind == "category" then
            activeCategoryKey = entry.categoryKey
        end
        LayoutItems(true)
    end)
    B.Sidebar.SetOnAutoHideChanged(function(enabled)
        B.config.sidebarAutoHide = enabled
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

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
    StyleCombinedFrame()

    hooksecurefunc(combinedFrame, "UpdateItemSlots", AppendReagentBagSlots)
    hooksecurefunc(combinedFrame, "UpdateItemLayout", function()
        LayoutItems(true)
    end)
    hooksecurefunc(combinedFrame, "UpdateItems", function()
        if IsEnabled() then
            RefreshItemLevelTexts()
            LayoutItems(false)
        end
    end)
    hooksecurefunc(combinedFrame, "UpdateSearchBox", function()
        if IsEnabled() then
            LayoutControls()
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
    moduleEnabled = true
    UpdateBlizzardBagBarVisibility()

    if not Initialize() then return end
    B.Sidebar.SetShown(true)
    SetupCleanupTooltip()
    B.Cleanup:Install(_G.BagItemAutoSortButton)

    if not hasPreviousCombinedBags then
        previousCombinedBags = GetCVarBool("combinedBags")
        hasPreviousCombinedBags = true
    end

    if _G.BagsBar then
        B:UnregisterEvent("ADDON_LOADED")
    end

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
    HideItemLevelTexts()
    RestoreBlizzardBagBar()
    B.Cleanup:Restore()
    B:UnregisterAllEvents()
    if not initialized then return end
    AF.HideTooltip()

    RestoreReagentFrame()
    wipe(reagentItemButtons)
    wipe(categoryCache)
    ResetCategoryGroups()
    ResetIndividualGroups()
    HideUnusedSectionHeaders(1)
    ClearLayoutState()
    RestoreItemBagIndicators()
    layoutScale = 1
    combinedFrame:SetScale(1)

    bagSlotsButton:Hide()
    B.Sidebar.SetShown(false)
    for _, button in ipairs(bagButtons) do
        button:Hide()
    end
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
    if addonName ~= "Blizzard_UIPanels_Game"
        and addonName ~= "Blizzard_MainMenuBarBagButtons" then
        return
    end

    if B.config and B.config.enabled then
        EnableModule()
    end
end

function B:USE_COMBINED_BAGS_CHANGED(_, useCombinedBags)
    if IsEnabled() and not useCombinedBags then
        SetCombinedBags()
    end
end

function B:BAG_UPDATE(_, bagID)
    if bagID == REAGENT_BAG_ID then
        if B.Cleanup:IsActive() then return end
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

function B.SetViewMode(mode)
    if mode ~= VIEW_MODE_COMBINED and mode ~= VIEW_MODE_INDIVIDUAL then return false end
    B.config.viewMode = mode
    activeCategoryKey = nil
    B.Refresh()
    return true
end

function B.Refresh()
    UpdateBlizzardBagBarVisibility()
    if IsEnabled() and not B.config.showItemLevel then
        HideItemLevelTexts()
    end
    if IsEnabled() and combinedFrame and combinedFrame:IsShown() then
        RefreshItemLevelTexts()
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

AF.RegisterCallback("BFI_UpdateProfile", function()
    -- Sidebar selection is transient navigation state. A newly selected
    -- profile must open its own persisted Combined/Individual default.
    activeCategoryKey = nil
    if B.config then
        B.Sidebar.SetAutoHide(B.config.sidebarAutoHide)
    end
end)
