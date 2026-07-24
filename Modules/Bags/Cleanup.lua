---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags

local C_Container = _G.C_Container
local C_Item = _G.C_Item
local ClearCursor = _G.ClearCursor
local GetCursorInfo = _G.GetCursorInfo
local GetTime = _G.GetTime
local InCombatLockdown = _G.InCombatLockdown

local REAGENT_BAG_ID = _G.Enum.BagIndex.ReagentBag
local BACKPACK_ID = _G.Enum.BagIndex.Backpack
local NUM_BAG_SLOTS = _G.Constants.InventoryConstants.NumBagSlots
local DISABLE_AUTO_SORT = _G.Enum.BagSlotFlags.DisableAutoSort

local PHASE_SORTING = 1
local PHASE_MOVING = 2
local PHASE_ITEM_DATA = 3
local PHASE_RETURNING_CURSOR = 4

local WATCHDOG_INTERVAL = 0.25
local SORT_FALLBACK_DELAY = 0.5
local ITEM_DATA_RETRY_INTERVAL = 0.5
local OPERATION_TIMEOUT = 5

local Cleanup = {}
B.Cleanup = Cleanup

-- Retail 12.0.7 API evidence, Gethe/wow-ui-source commit
-- 4383ced30106d51b27e3e86d1987f1552f0d259d:
-- ContainerDocumentation.lua (SortBags, PickupContainerItem,
-- SplitContainerItem), ItemDocumentation.lua (GetItemInfo's reagent flag and
-- MayReturnNothing contract), and ContainerFrame.xml (native cleanup click).
local state = {
    reagentByLink = {},
    maxStackByLink = {},
    requestedItemIDs = {},
}

local ContinueCleanup

local function CancelWatchdog()
    if state.watchdog then
        state.watchdog:Cancel()
        state.watchdog = nil
    end
end

local function ArmWatchdog()
    CancelWatchdog()
    state.watchdog = _G.C_Timer.NewTimer(WATCHDOG_INTERVAL, function()
        state.watchdog = nil
        ContinueCleanup(false)
    end)
end

local function RestoreButtonEnabledState()
    if state.button and state.buttonWasEnabled ~= nil then
        state.button:SetEnabled(state.buttonWasEnabled)
    end
    state.buttonWasEnabled = nil
end

local function ClearCursorOwnership()
    state.ownsCursor = nil
    state.ownedCursorItemID = nil
    state.ownedCursorItemLink = nil
end

local function StopCleanup(refresh)
    if not state.active then return end

    state.active = nil
    state.phase = nil
    state.waiting = nil
    state.lastSourceBag = nil
    state.lastSourceSlot = nil
    state.lastTargetSlot = nil
    state.scanBag = nil
    state.scanSlot = nil
    state.sortFallbackAt = nil
    state.waitDeadline = nil
    state.dataRetryAt = nil
    state.itemDataDeadline = nil
    state.sawUncachedItem = nil
    state.retrySourceBag = nil
    state.retrySourceSlot = nil
    state.cancelRequested = nil
    state.cancelRefresh = nil
    ClearCursorOwnership()
    CancelWatchdog()
    B:UnregisterEvent("BAG_UPDATE_DELAYED", B.BAG_UPDATE_DELAYED)
    B:UnregisterEvent("ITEM_DATA_LOAD_RESULT", B.ITEM_DATA_LOAD_RESULT)
    RestoreButtonEnabledState()
    wipe(state.reagentByLink)
    wipe(state.maxStackByLink)
    wipe(state.requestedItemIDs)

    if refresh and B.Refresh then
        B.Refresh()
    end
end

local function CallOriginalCleanup(button, mouseButton, down)
    local onClick = state.originalOnClick
    if onClick then
        onClick(button, mouseButton, down)
    else
        _G.PlaySound(_G.SOUNDKIT.UI_BAG_SORTING_01)
        C_Container.SortBags()
    end
end

local function CursorMatchesOwnedItem()
    local cursorType, itemID, itemLink = GetCursorInfo()
    if cursorType == nil then return nil end
    if cursorType ~= "item" then return false end
    if state.ownedCursorItemID and itemID and state.ownedCursorItemID ~= itemID then
        return false
    end
    if state.ownedCursorItemLink and itemLink
        and state.ownedCursorItemLink ~= itemLink then
        return false
    end
    return true
end

local function CaptureCursorOwnership(itemID, itemLink)
    local cursorType, cursorItemID, cursorItemLink = GetCursorInfo()
    if cursorType ~= "item" then return false end

    state.ownsCursor = true
    state.ownedCursorItemID = cursorItemID or itemID
    state.ownedCursorItemLink = cursorItemLink or itemLink
    return true
end

local function ReturnOwnedCursor()
    if not state.ownsCursor then return true end

    local matches = CursorMatchesOwnedItem()
    if matches == nil then
        ClearCursorOwnership()
        return true
    elseif not matches then
        -- The player has acquired a different cursor payload. Never clear it.
        ClearCursorOwnership()
        return true
    end

    ClearCursor()
    matches = CursorMatchesOwnedItem()
    if matches == nil or matches == false then
        ClearCursorOwnership()
        return true
    end
    return false
end

local function RequestCancel(refresh)
    if not state.active then return end

    state.cancelRequested = true
    state.cancelRefresh = state.cancelRefresh or refresh
    if state.ownsCursor and not ReturnOwnedCursor() then
        state.phase = PHASE_RETURNING_CURSOR
        state.waitDeadline = state.waitDeadline
            or GetTime() + OPERATION_TIMEOUT
        ArmWatchdog()
        return
    end
    StopCleanup(refresh)
end

local function FinishCleanup()
    StopCleanup(true)
end

local function AbortCleanup()
    RequestCancel(true)
end

local function IsSourceBagIgnored(bagID)
    if bagID == BACKPACK_ID then
        return C_Container.GetBackpackAutosortDisabled()
    end
    return C_Container.GetBagSlotFlag(bagID, DISABLE_AUTO_SORT)
end

local function BagHasLockedItem(bagID)
    local slotCount = C_Container.GetContainerNumSlots(bagID)
    for slotID = 1, slotCount do
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info and info.isLocked then
            return true
        end
    end
    return false
end

local function AnySortItemLocked()
    for bagID = BACKPACK_ID, NUM_BAG_SLOTS do
        if not IsSourceBagIgnored(bagID) and BagHasLockedItem(bagID) then
            return true
        end
    end
    return BagHasLockedItem(REAGENT_BAG_ID)
end

local function AnyMovedItemLocked()
    if state.lastSourceBag then
        local info = C_Container.GetContainerItemInfo(
            state.lastSourceBag,
            state.lastSourceSlot
        )
        if info and info.isLocked then
            return true
        end
    end

    if state.lastTargetSlot then
        local info = C_Container.GetContainerItemInfo(
            REAGENT_BAG_ID,
            state.lastTargetSlot
        )
        if info and info.isLocked then
            return true
        end
    end
    return false
end

local function GetReagentInfo(itemID, itemLink)
    local isCraftingReagent = state.reagentByLink[itemLink]
    if isCraftingReagent ~= nil then
        return isCraftingReagent, state.maxStackByLink[itemLink]
    end

    local itemName, _, _, _, _, _, _, maxStack, _, _, _, _, _, _, _, _, reagent =
        C_Item.GetItemInfo(itemLink)
    if not itemName then
        state.sawUncachedItem = true
        if C_Item.RequestLoadItemDataByID and not state.requestedItemIDs[itemID] then
            state.requestedItemIDs[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end

    isCraftingReagent = reagent == true
    state.reagentByLink[itemLink] = isCraftingReagent
    state.maxStackByLink[itemLink] = maxStack or 1
    return isCraftingReagent, maxStack or 1
end

local function FindTargetSlot(itemID, itemLink, maxStack)
    local emptySlot
    local slotCount = C_Container.GetContainerNumSlots(REAGENT_BAG_ID)

    for slotID = 1, slotCount do
        local info = C_Container.GetContainerItemInfo(REAGENT_BAG_ID, slotID)
        if not info then
            emptySlot = emptySlot or slotID
        elseif not info.isLocked
            and info.itemID == itemID
            and info.hyperlink == itemLink
            and info.stackCount < maxStack then
            return slotID, maxStack - info.stackCount
        end
    end

    if emptySlot then
        return emptySlot, maxStack
    end
end

local function FindNextMove()
    while state.scanBag <= NUM_BAG_SLOTS do
        local bagID = state.scanBag
        local slotCount = C_Container.GetContainerNumSlots(bagID)

        if IsSourceBagIgnored(bagID) then
            state.scanBag = bagID + 1
            state.scanSlot = 1
        elseif state.scanSlot > slotCount then
            state.scanBag = bagID + 1
            state.scanSlot = 1
        else
            local slotID = state.scanSlot
            state.scanSlot = slotID + 1

            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and not info.isLocked and info.itemID and info.hyperlink then
                local isCraftingReagent, maxStack =
                    GetReagentInfo(info.itemID, info.hyperlink)
                if isCraftingReagent then
                    local targetSlot, targetCapacity =
                        FindTargetSlot(info.itemID, info.hyperlink, maxStack)
                    if targetSlot then
                        return bagID, slotID, targetSlot, targetCapacity
                    end
                end
            end
        end
    end
end

local function StartMoveWait(sourceBag, sourceSlot, targetSlot)
    state.phase = PHASE_MOVING
    state.lastSourceBag = sourceBag
    state.lastSourceSlot = sourceSlot
    state.lastTargetSlot = targetSlot
    state.waiting = true
    state.waitDeadline = GetTime() + OPERATION_TIMEOUT
    ArmWatchdog()
end

local function PlanRejectedMoveRetry(sourceBag, sourceSlot)
    if state.retrySourceBag == sourceBag
        and state.retrySourceSlot == sourceSlot then
        state.retrySourceBag = nil
        state.retrySourceSlot = nil
        state.scanBag = sourceBag
        state.scanSlot = sourceSlot + 1
    else
        state.retrySourceBag = sourceBag
        state.retrySourceSlot = sourceSlot
        state.scanBag = sourceBag
        state.scanSlot = sourceSlot
    end
end

local function MoveSourceToTarget(sourceBag, sourceSlot, targetSlot, targetCapacity)
    local sourceInfo = C_Container.GetContainerItemInfo(sourceBag, sourceSlot)
    if not sourceInfo or sourceInfo.isLocked or not sourceInfo.itemID then
        return false
    end

    local moveCount = math.min(sourceInfo.stackCount, targetCapacity)
    local sourceHasRemainder = moveCount < sourceInfo.stackCount
    if sourceHasRemainder then
        C_Container.SplitContainerItem(sourceBag, sourceSlot, moveCount)
    else
        C_Container.PickupContainerItem(sourceBag, sourceSlot)
    end

    if not CaptureCursorOwnership(sourceInfo.itemID, sourceInfo.hyperlink) then
        if GetCursorInfo() ~= nil then
            AbortCleanup()
            return true
        end
        return false
    end

    if sourceHasRemainder then
        -- Revisit the remainder in case another partial target can accept it.
        state.scanBag = sourceBag
        state.scanSlot = sourceSlot
    end

    local targetInfo = C_Container.GetContainerItemInfo(
        REAGENT_BAG_ID,
        targetSlot
    )
    local maxStack = state.maxStackByLink[sourceInfo.hyperlink]
        or sourceInfo.stackCount
    local targetIsValid = not targetInfo
        or (
            not targetInfo.isLocked
            and targetInfo.itemID == sourceInfo.itemID
            and targetInfo.hyperlink == sourceInfo.hyperlink
            and targetInfo.stackCount + moveCount <= maxStack
        )
    if not targetIsValid then
        PlanRejectedMoveRetry(sourceBag, sourceSlot)
        if not ReturnOwnedCursor() then
            state.phase = PHASE_RETURNING_CURSOR
            state.lastSourceBag = sourceBag
            state.lastSourceSlot = sourceSlot
            state.lastTargetSlot = targetSlot
            state.waitDeadline = GetTime() + OPERATION_TIMEOUT
            ArmWatchdog()
        else
            StartMoveWait(sourceBag, sourceSlot, targetSlot)
        end
        return true
    end

    C_Container.PickupContainerItem(REAGENT_BAG_ID, targetSlot)
    local cursorMatch = CursorMatchesOwnedItem()
    if cursorMatch == nil then
        state.retrySourceBag = nil
        state.retrySourceSlot = nil
        ClearCursorOwnership()
        StartMoveWait(sourceBag, sourceSlot, targetSlot)
        return true
    elseif cursorMatch == false then
        -- No script can interleave here, so a swapped payload is also ours.
        if not CaptureCursorOwnership() then
            AbortCleanup()
            return true
        end
    end

    -- A remaining cursor means the target rejected at least part of the move.
    PlanRejectedMoveRetry(sourceBag, sourceSlot)
    if not ReturnOwnedCursor() then
        state.phase = PHASE_RETURNING_CURSOR
        state.lastSourceBag = sourceBag
        state.lastSourceSlot = sourceSlot
        state.lastTargetSlot = targetSlot
        state.waitDeadline = GetTime() + OPERATION_TIMEOUT
        ArmWatchdog()
        return true
    end

    StartMoveWait(sourceBag, sourceSlot, targetSlot)
    return true
end

local function ResetScan()
    state.scanBag = BACKPACK_ID
    state.scanSlot = 1
end

ContinueCleanup = function(fromBagUpdate)
    if not state.active then return end
    CancelWatchdog()

    if state.ownsCursor then
        if not ReturnOwnedCursor() then
            if state.waitDeadline and GetTime() >= state.waitDeadline then
                -- The cursor remains visible and player-controlled; stop polling.
                ClearCursorOwnership()
                StopCleanup(true)
                return
            end
            state.phase = PHASE_RETURNING_CURSOR
            ArmWatchdog()
            return
        elseif state.cancelRequested then
            StopCleanup(state.cancelRefresh)
            return
        else
            StartMoveWait(
                state.lastSourceBag,
                state.lastSourceSlot,
                state.lastTargetSlot
            )
            return
        end
    end

    if state.cancelRequested then
        StopCleanup(state.cancelRefresh)
        return
    end

    if not B.config
        or not B.config.enabled
        or GetCursorInfo() ~= nil
        or C_Container.GetContainerNumSlots(REAGENT_BAG_ID) == 0
        or C_Container.GetBagSlotFlag(REAGENT_BAG_ID, DISABLE_AUTO_SORT) then
        AbortCleanup()
        return
    end

    if InCombatLockdown() then
        AbortCleanup()
        return
    end

    if state.phase == PHASE_SORTING then
        if AnySortItemLocked() then
            if GetTime() >= state.waitDeadline then
                AbortCleanup()
            else
                ArmWatchdog()
            end
            return
        end
        if not fromBagUpdate and GetTime() < state.sortFallbackAt then
            ArmWatchdog()
            return
        end

        state.phase = PHASE_MOVING
        state.waitDeadline = nil
        ResetScan()
    elseif state.phase == PHASE_ITEM_DATA then
        if GetTime() < state.dataRetryAt then
            ArmWatchdog()
            return
        end
        state.phase = PHASE_MOVING
        state.dataRetryAt = nil
    elseif state.phase == PHASE_RETURNING_CURSOR then
        -- Cursor ownership was cleared externally between callbacks.
        StartMoveWait(
            state.lastSourceBag,
            state.lastSourceSlot,
            state.lastTargetSlot
        )
        return
    end

    if state.waiting then
        if AnyMovedItemLocked() then
            if GetTime() >= state.waitDeadline then
                AbortCleanup()
            else
                ArmWatchdog()
            end
            return
        end
        state.waiting = nil
        state.lastSourceBag = nil
        state.lastSourceSlot = nil
        state.lastTargetSlot = nil
        state.waitDeadline = nil
    end

    while state.active do
        local sourceBag, sourceSlot, targetSlot, targetCapacity = FindNextMove()
        if not sourceBag then
            if state.sawUncachedItem
                and (
                    not state.itemDataDeadline
                    or GetTime() < state.itemDataDeadline
                ) then
                state.sawUncachedItem = nil
                state.itemDataDeadline = state.itemDataDeadline
                    or GetTime() + OPERATION_TIMEOUT
                state.phase = PHASE_ITEM_DATA
                state.dataRetryAt = GetTime() + ITEM_DATA_RETRY_INTERVAL
                ResetScan()
                ArmWatchdog()
            else
                FinishCleanup()
            end
            return
        end

        if MoveSourceToTarget(
            sourceBag,
            sourceSlot,
            targetSlot,
            targetCapacity
        ) then
            return
        end
    end
end

local function CleanupButtonOnClick(button, mouseButton, down)
    if state.active then return end

    local canPrioritizeReagents = B.config
        and B.config.enabled
        and C_Container.PickupContainerItem
        and C_Container.SplitContainerItem
        and GetCursorInfo() == nil
        and not InCombatLockdown()
        and C_Container.GetContainerNumSlots(REAGENT_BAG_ID) > 0
        and not C_Container.GetBagSlotFlag(REAGENT_BAG_ID, DISABLE_AUTO_SORT)

    if not canPrioritizeReagents then
        CallOriginalCleanup(button, mouseButton, down)
        return
    end

    state.active = true
    state.phase = PHASE_SORTING
    state.buttonWasEnabled = button:IsEnabled()
    state.sortFallbackAt = GetTime() + SORT_FALLBACK_DELAY
    state.waitDeadline = GetTime() + OPERATION_TIMEOUT
    wipe(state.reagentByLink)
    wipe(state.maxStackByLink)
    wipe(state.requestedItemIDs)

    button:Disable()
    _G.AbstractFramework.HideTooltip()
    B:RegisterEvent("BAG_UPDATE_DELAYED", B.BAG_UPDATE_DELAYED)
    B:RegisterEvent("ITEM_DATA_LOAD_RESULT", B.ITEM_DATA_LOAD_RESULT)
    ArmWatchdog()

    -- Blizzard sorts first; BFI's reagent placement is the terminal pass.
    CallOriginalCleanup(button, mouseButton, down)
end

function Cleanup:Install(button)
    if not button then return end

    if state.button and state.button ~= button then
        self:Restore()
    end

    state.button = button
    local currentOnClick = button:GetScript("OnClick")
    if currentOnClick == CleanupButtonOnClick then return end

    state.originalOnClick = currentOnClick
    button:SetScript("OnClick", CleanupButtonOnClick)
end

function Cleanup:Cancel(refresh)
    RequestCancel(refresh)
end

function Cleanup:Restore()
    RequestCancel(false)

    local button = state.button
    if button and button:GetScript("OnClick") == CleanupButtonOnClick then
        button:SetScript("OnClick", state.originalOnClick)
    end
    state.originalOnClick = nil
end

function Cleanup:IsActive()
    return state.active == true
end

function B:BAG_UPDATE_DELAYED()
    ContinueCleanup(true)
end

function B:ITEM_DATA_LOAD_RESULT(_, itemID)
    if not state.active
        or state.phase ~= PHASE_ITEM_DATA
        or not state.requestedItemIDs[itemID] then
        return
    end
    state.dataRetryAt = GetTime()
    ContinueCleanup(false)
end
