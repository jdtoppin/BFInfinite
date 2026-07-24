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
local GetCVarBool = _G.GetCVarBool
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local GetItemClassInfo = _G.C_Item.GetItemClassInfo
local GetItemSubClassInfo = _G.C_Item.GetItemSubClassInfo
local SetCVar = _G.SetCVar

local BAG_TOP_WITH_SLOTS = 100
local BAG_TOP_WITHOUT_SLOTS = 64
local CATEGORY_HEADER_HEIGHT = 18
local CATEGORY_SPACING = 7
local ITEM_SIZE = 37
local HORIZONTAL_PADDING = 12
local FOOTER_PADDING = 12
local BACKPACK_ICON = 134400
local EMPTY_BAG_ICON = 133633

local inventoryConstants = _G.Constants.InventoryConstants
local REAGENT_BAG_ID = inventoryConstants.NumBagSlots + inventoryConstants.NumReagentBagSlots

local combinedFrame
local categoryButton
local initialized
local moduleEnabled
local refreshPending
local layoutScale = 1
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

    local _, _, _, _, _, classID, subclassID = _G.C_Item.GetItemInfoInstant(itemID)
    local itemClass = _G.Enum.ItemClass
    local key
    local label
    local order

    if classID == itemClass.Weapon or classID == itemClass.Armor then
        key = "equipment"
        label = _G.BAG_FILTER_EQUIPMENT or "Equipment"
        order = 10
    elseif classID == itemClass.Consumable then
        key = "consumables"
        label = _G.BAG_FILTER_CONSUMABLES or GetItemClassInfo(classID) or "Consumables"
        order = 20
    elseif classID == itemClass.Gem then
        key = "gems"
        label = GetItemClassInfo(classID) or _G.GEMS or "Gems"
        order = 30
    elseif classID == itemClass.Tradegoods
        or classID == itemClass.Reagent
        or classID == itemClass.ItemEnhancement
        or classID == itemClass.Profession then
        local className = GetItemClassInfo(classID) or "Reagents"
        local subclassName = GetItemSubClassInfo(classID, subclassID)
        label = subclassName and (className .. " - " .. subclassName) or className
        key = "profession:" .. (classID or -1) .. ":" .. (subclassID or -1)
        order = 40
    elseif classID == itemClass.Recipe then
        key = "recipes"
        label = GetItemClassInfo(classID) or "Recipes"
        order = 50
    elseif classID == itemClass.Questitem then
        key = "quest"
        label = _G.BAG_FILTER_QUEST_ITEMS or GetItemClassInfo(classID) or "Quest Items"
        order = 80
    else
        key = "class:" .. (classID or -1)
        label = (classID and GetItemClassInfo(classID)) or _G.MISCELLANEOUS or "Miscellaneous"
        order = 60
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

local function StyleItemButton(button)
    if button._BFIBagStyled then return end
    button._BFIBagStyled = true

    local icon = button.Icon or button.icon
    if icon then
        S.StyleIcon(icon)
    end

    S.CreateBackdrop(button, true, nil, -1)
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

local function BagButtonOnEnter(button)
    combinedFrame:SetItemsMatchingBagHighlighted(button.bagID, true)

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

local function LayoutControls(width)
    local searchBox = _G.BagItemSearchBox
    if searchBox and searchBox:GetParent() == combinedFrame then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", HORIZONTAL_PADDING, -31)
        searchBox:SetWidth(width - 94)
    end

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
        categoryButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -39, -29)
    end
    categoryButton:SetText(B.config.categories and "C+" or "C")
    categoryButton:SetTextColor(B.config.categories and "BFI" or "gray")
    categoryButton:Show()

    local tokenFrame = _G.BackpackTokenFrame
    if tokenFrame and tokenFrame:GetParent() == combinedFrame and tokenFrame.Border then
        tokenFrame.Border:SetAlpha(0)
    end
end

local function LayoutItems()
    if not IsEnabled() or not combinedFrame or not combinedFrame.Items then return end

    local columns = B.config.columns
    local spacing = B.config.spacing
    local top = B.config.showBagSlots and BAG_TOP_WITH_SLOTS or BAG_TOP_WITHOUT_SLOTS
    local groupCount

    ResetCategoryGroups()

    if B.config.categories then
        for _, itemButton in ipairs(combinedFrame.Items) do
            StyleItemButton(itemButton)
            local itemID = _G.C_Container.GetContainerItemID(itemButton:GetBagID(), itemButton:GetID())
            local key, label, order = GetCategory(itemID)
            local group = AcquireCategoryGroup(key, label, order)
            group.items[#group.items + 1] = itemButton
        end

        groupCount = #categoryGroups
        sort(categoryGroups, CompareCategoryGroups)
    else
        local group = AcquireCategoryGroup("all", "", 1)
        for _, itemButton in ipairs(combinedFrame.Items) do
            StyleItemButton(itemButton)
            group.items[#group.items + 1] = itemButton
        end
        groupCount = 1
    end

    local footerHeight = combinedFrame:CalculateExtraHeight() + FOOTER_PADDING
    local function CalculateHeight(columnCount)
        local height = top + footerHeight
        for groupIndex = 1, groupCount do
            local group = categoryGroups[groupIndex]
            if B.config.categories then
                height = height + CATEGORY_HEADER_HEIGHT
            end

            local rows = ceil(#group.items / columnCount)
            if rows > 0 then
                height = height + (rows * ITEM_SIZE) + ((rows - 1) * spacing)
            end
            if B.config.categories and groupIndex < groupCount then
                height = height + CATEGORY_SPACING
            end
        end
        return height
    end

    -- Category headers can make a narrow bag very tall. Treat the configured
    -- column count as a minimum and widen only as needed to stay on screen.
    local maxWidth = _G.UIParent:GetWidth() * 0.9
    local maxHeight = _G.UIParent:GetHeight() * 0.9
    local maxColumns = math.max(
        1,
        floor((maxWidth - (HORIZONTAL_PADDING * 2) + spacing) / (ITEM_SIZE + spacing))
    )
    columns = math.min(columns, maxColumns)
    while columns < maxColumns and CalculateHeight(columns) > maxHeight do
        columns = columns + 1
    end

    local width = (HORIZONTAL_PADDING * 2) + (columns * ITEM_SIZE) + ((columns - 1) * spacing)
    local height = CalculateHeight(columns)
    local cursorY = -top

    for groupIndex = 1, groupCount do
        local group = categoryGroups[groupIndex]
        if B.config.categories then
            local header = GetCategoryHeader(groupIndex)
            header:SetText(group.label)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", HORIZONTAL_PADDING, cursorY)
            header:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -HORIZONTAL_PADDING, cursorY)
            header:Show()
            cursorY = cursorY - CATEGORY_HEADER_HEIGHT
        end

        for itemIndex, itemButton in ipairs(group.items) do
            local row = floor((itemIndex - 1) / columns)
            local column = (itemIndex - 1) % columns
            AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
            itemButton:ClearAllPoints()
            itemButton:SetPoint(
                "TOPLEFT",
                combinedFrame,
                "TOPLEFT",
                HORIZONTAL_PADDING + (column * (ITEM_SIZE + spacing)),
                cursorY - (row * (ITEM_SIZE + spacing))
            )
        end

        local rows = ceil(#group.items / columns)
        if rows > 0 then
            cursorY = cursorY - (rows * ITEM_SIZE) - ((rows - 1) * spacing)
        end
        if B.config.categories and groupIndex < groupCount then
            cursorY = cursorY - CATEGORY_SPACING
        end
    end

    HideUnusedHeaders(B.config.categories and (groupCount + 1) or 1)
    LayoutBagButtons(spacing)

    combinedFrame:SetSize(width, -cursorY + footerHeight)
    -- The fixed cost of many category headers cannot be reduced by adding
    -- columns. Scale only as a last-resort overflow fallback, which also
    -- guarantees the configured width remains usable on narrow displays.
    layoutScale = math.min(1, maxWidth / width, maxHeight / height)
    combinedFrame:SetScale(layoutScale)
    LayoutControls(width)
    ApplyPosition()
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
    wipe(categoryCache)
    HideUnusedHeaders(1)

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

local function StyleCombinedFrame()
    S.StyleTitledFrame(combinedFrame)
    combinedFrame:SetClampedToScreen(true)

    if combinedFrame.PortraitButton then
        local menuButton = combinedFrame.PortraitButton
        menuButton:ClearAllPoints()
        menuButton:SetPoint("TOPLEFT", combinedFrame.BFIHeader, "TOPLEFT", 1, -1)
        AF.SetSize(menuButton, 20, 18)
        menuButton:Show()
        menuButton:EnableMouse(true)
        AF.SetFrameLevel(menuButton, 1, combinedFrame.BFIHeader)
        if menuButton.Highlight then
            menuButton.Highlight:SetAlpha(0)
        end
        S.CreateBackdrop(menuButton, true, nil, -1)
        menuButton.BFIMenuText = AF.CreateFontString(menuButton, "...", "BFI")
        menuButton.BFIMenuText:SetPoint("CENTER", 0, 3)
    end
    for _, child in ipairs({combinedFrame:GetChildren()}) do
        if child.routeToSibling == "PortraitButton" then
            child:EnableMouse(false)
        end
    end

    if combinedFrame.MoneyFrame and combinedFrame.MoneyFrame.Border then
        combinedFrame.MoneyFrame.Border:SetAlpha(0)
    end

    S.StyleEditBox(_G.BagItemSearchBox, -3, -2, 3, 2)
    S.CreateBackdrop(_G.BagItemAutoSortButton, true, -1)

    categoryButton = AF.CreateButton(combinedFrame, "C", nil, 24, 22)
    categoryButton:SetTooltip(L["Group Items by Category"])
    categoryButton:SetOnClick(function()
        B.config.categories = not B.config.categories
        LayoutItems()
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

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
    hooksecurefunc(combinedFrame, "UpdateItemLayout", LayoutItems)
    hooksecurefunc(combinedFrame, "UpdateItems", function()
        if IsEnabled() and B.config.categories then
            LayoutItems()
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
    layoutScale = 1
    combinedFrame:SetScale(1)

    categoryButton:Hide()
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

function B.Refresh()
    if IsEnabled() and combinedFrame and combinedFrame:IsShown() then
        LayoutItems()
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
