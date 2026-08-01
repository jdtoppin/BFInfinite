local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function assertContains(contents, needle, message)
    assertTrue(contents:find(needle, 1, true), message or needle)
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local function copy(value)
    if type(value) ~= "table" then return value end

    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function wipeTable(value)
    for key in pairs(value) do
        value[key] = nil
    end
end

local function makeRuntime(addonIsLoaded)
    local secretValue = {}
    local callbacks = {}
    local addonCallbacks = {}
    local secureHooks = {}
    local trace = {}
    local counts = {}
    local state = {}

    local function resetCounts()
        wipeTable(counts)
        counts.canUse = 0
        counts.clearCursor = 0
        counts.cursorHasItem = 0
        counts.getCursorInfo = 0
        counts.getItemID = 0
        counts.hasSlotted = 0
        counts.inCombat = 0
        counts.isKeystone = 0
        counts.iterate = 0
        counts.pickup = 0
        counts.slot = 0
        counts.visited = 0
    end

    local config = {
        mythicPlus = {
            enabled = true,
            autoInsertKeystone = {
                enabled = false,
            },
            teleportButtons = {
                enabled = false,
            },
        },
    }

    local frame = {
        nativeShowCalls = 0,
    }

    function frame:ShowKeystoneFrame(marker)
        self.nativeShowCalls = self.nativeShowCalls + 1
        trace[#trace + 1] = "native-show"
        return "native-result", marker
    end

    local function forbiddenMutation(name)
        return function()
            error(name .. " must remain Blizzard-owned", 2)
        end
    end

    frame.HookScript = forbiddenMutation("ChallengesKeystoneFrame:HookScript")
    frame.SetScript = forbiddenMutation("ChallengesKeystoneFrame:SetScript")
    frame.Hide = forbiddenMutation("ChallengesKeystoneFrame:Hide")
    frame.Reset = forbiddenMutation("ChallengesKeystoneFrame:Reset")
    frame.Show = forbiddenMutation("ChallengesKeystoneFrame:Show")

    local function installSecureHook(target, method, hook)
        assertEqual(target, frame, "secure-hook target")
        assertEqual(method, "ShowKeystoneFrame", "secure-hook method")
        assertEqual(type(hook), "function", "secure-hook callback")

        secureHooks[#secureHooks + 1] = {
            hook = hook,
            method = method,
            target = target,
        }

        local original = target[method]
        target[method] = function(...)
            local results = {original(...)}
            hook(...)
            return unpack(results)
        end
    end

    local AF = {}

    function AF.RegisterCallback(event, callback)
        callbacks[event] = callback
    end

    function AF.RegisterAddonLoaded(addonName, callback)
        addonCallbacks[addonName] = addonCallbacks[addonName] or {}
        addonCallbacks[addonName][#addonCallbacks[addonName] + 1] = callback
    end

    function AF.UnregisterAddonLoaded(addonName, callback)
        local registered = addonCallbacks[addonName]
        if not registered then return end

        for index = #registered, 1, -1 do
            if registered[index] == callback then
                table.remove(registered, index)
            end
        end
    end

    function AF.Hide()
    end

    function AF.DelayedInvoke(_, callback)
        callback()
    end

    function AF.RegisterCallbackOnce()
    end

    local E = {
        config = config,
    }
    local BFI = {
        funcs = {
            isValueNonSecret = function(value)
                return value ~= secretValue
            end,
        },
        modules = {
            Enhancements = E,
        },
    }

    local C_Item = setmetatable({}, {
        __index = function(_, key)
            error("unexpected C_Item API: " .. tostring(key), 2)
        end,
    })

    function C_Item.GetItemID(itemLocation)
        counts.getItemID = counts.getItemID + 1
        if state.getItemIDResult ~= nil then
            return state.getItemIDResult
        end
        return itemLocation.itemID
    end

    function C_Item.IsItemKeystoneByID(itemID)
        counts.isKeystone = counts.isKeystone + 1
        if state.isKeystoneResult ~= nil then
            return state.isKeystoneResult
        end
        return state.keystoneItemIDs[itemID] == true
    end

    local C_ChallengeMode = setmetatable({}, {
        __index = function(_, key)
            error("unexpected C_ChallengeMode API: " .. tostring(key), 2)
        end,
    })

    function C_ChallengeMode.CanUseKeystoneInCurrentMap(itemLocation)
        counts.canUse = counts.canUse + 1
        if state.canUseResult ~= nil then
            return state.canUseResult
        end
        return itemLocation.compatible == true
    end

    function C_ChallengeMode.HasSlottedKeystone()
        counts.hasSlotted = counts.hasSlotted + 1
        return state.hasSlotted
    end

    function C_ChallengeMode.SlotKeystone()
        counts.slot = counts.slot + 1
        trace[#trace + 1] = "slot"

        if state.slotSucceeds then
            state.hasSlotted = true
            if state.slotConsumesCursor ~= false then
                state.cursorType = nil
                state.cursorItemID = nil
            end
        else
            if state.afterSlotCursorType ~= nil then
                state.cursorType = state.afterSlotCursorType
            end
            if state.afterSlotCursorItemID ~= nil then
                state.cursorItemID = state.afterSlotCursorItemID
            end
        end

        if state.hasSlottedAfterSlot ~= nil then
            state.hasSlotted = state.hasSlottedAfterSlot
        end
    end

    local ItemUtil = {}

    function ItemUtil.IteratePlayerInventory(callback)
        counts.iterate = counts.iterate + 1
        for _, itemLocation in ipairs(state.inventory) do
            counts.visited = counts.visited + 1
            trace[#trace + 1] = "visit:" .. itemLocation.name
            if callback(itemLocation) then
                return true
            end
        end
        return false
    end

    function ItemUtil.PickupBagItem(itemLocation)
        counts.pickup = counts.pickup + 1
        state.pickedLocation = itemLocation
        trace[#trace + 1] = "pickup:" .. itemLocation.name
        if state.pickupSucceeds then
            state.cursorType = state.pickupCursorType or "item"
            state.cursorItemID = state.pickupCursorItemID
                or itemLocation.itemID
        end
    end

    local environment = {
        AbstractFramework = AF,
        BFI = BFI,
        C_AddOns = {
            IsAddOnLoaded = function(addonName)
                assertEqual(addonName, "Blizzard_ChallengesUI",
                    "load-state query")
                return addonIsLoaded
            end,
        },
        C_ChallengeMode = C_ChallengeMode,
        C_Item = C_Item,
        C_Spell = {
            GetSpellCooldown = function()
            end,
            GetSpellName = function()
            end,
        },
        C_SpellBook = {
            IsSpellKnownOrInSpellBook = function()
                return false
            end,
        },
        ChallengesKeystoneFrame = addonIsLoaded and frame or nil,
        ClearCursor = function()
            counts.clearCursor = counts.clearCursor + 1
            trace[#trace + 1] = "clear-cursor"
            state.cursorType = nil
            state.cursorItemID = nil
        end,
        CreateFrame = forbiddenMutation("CreateFrame"),
        CursorHasItem = function()
            counts.cursorHasItem = counts.cursorHasItem + 1
            if counts.slot > 0 and state.cursorHasItemAfterSlot ~= nil then
                return state.cursorHasItemAfterSlot
            end
            if state.cursorHasItem ~= nil then
                return state.cursorHasItem
            end
            return state.cursorType == "item"
        end,
        GetCursorInfo = function()
            counts.getCursorInfo = counts.getCursorInfo + 1
            return state.cursorType, state.cursorItemID, state.cursorItemLink
        end,
        InCombatLockdown = function()
            counts.inCombat = counts.inCombat + 1
            return state.inCombat
        end,
        ItemUtil = ItemUtil,
        hooksecurefunc = installSecureHook,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        table = table,
        tostring = tostring,
        type = type,
        unpack = unpack,
    }
    environment._G = environment

    local function reset(overrides)
        resetCounts()
        wipeTable(trace)

        state.inventory = {}
        state.keystoneItemIDs = {}
        state.hasSlotted = false
        state.hasSlottedAfterSlot = nil
        state.inCombat = false
        state.getItemIDResult = nil
        state.isKeystoneResult = nil
        state.canUseResult = nil
        state.pickupSucceeds = true
        state.pickupCursorType = nil
        state.pickupCursorItemID = nil
        state.slotConsumesCursor = true
        state.slotSucceeds = true
        state.cursorHasItem = nil
        state.cursorHasItemAfterSlot = nil
        state.cursorItemID = nil
        state.cursorItemLink = nil
        state.cursorType = nil
        state.afterSlotCursorItemID = nil
        state.afterSlotCursorType = nil
        state.pickedLocation = nil

        config.mythicPlus.enabled = true
        config.mythicPlus.autoInsertKeystone.enabled = true

        if overrides then
            for key, value in pairs(overrides) do
                state[key] = value
            end
        end
    end

    reset()

    local chunk, loadError =
        loadfile("Modules/Enhancements/MythicPlus.lua")
    assertEqual(type(chunk), "function", loadError or "runtime module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local runtime = {
        addonCallbacks = addonCallbacks,
        callbacks = callbacks,
        config = config,
        counts = counts,
        environment = environment,
        frame = frame,
        reset = reset,
        secretValue = secretValue,
        secureHooks = secureHooks,
        state = state,
        trace = trace,
    }

    function runtime:loadChallengesUI()
        self.environment.ChallengesKeystoneFrame = self.frame
        local registered = self.addonCallbacks.Blizzard_ChallengesUI or {}
        for _, callback in ipairs(registered) do
            callback("Blizzard_ChallengesUI")
        end
    end

    function runtime:show(marker)
        return self.frame:ShowKeystoneFrame(marker)
    end

    return runtime
end

local function assertNoInventoryMutation(runtime, message)
    assertEqual(runtime.counts.iterate, 0, message .. " inventory scan")
    assertEqual(runtime.counts.pickup, 0, message .. " pickup")
    assertEqual(runtime.counts.slot, 0, message .. " slot")
    assertEqual(runtime.counts.clearCursor, 0, message .. " cursor cleanup")
end

-- The already-loaded path installs one post-hook immediately and preserves
-- Blizzard's native method result and ordering.
local runtime = makeRuntime(true)
assertEqual(#runtime.secureHooks, 0,
    "disabled setting installs no already-loaded hook")
runtime.config.mythicPlus.autoInsertKeystone.enabled = true
runtime.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
assertEqual(#runtime.secureHooks, 1, "already-loaded hook count")
runtime.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
assertEqual(#runtime.secureHooks, 1,
    "already-loaded config update keeps one hook")
assertEqual(runtime.secureHooks[1].method, "ShowKeystoneFrame",
    "already-loaded hook method")
assertEqual(#(runtime.addonCallbacks.Blizzard_ChallengesUI or {}), 0,
    "already-loaded path needs no LoD callback")

runtime.reset()
runtime.config.mythicPlus.autoInsertKeystone.enabled = false
local nativeResult, marker = runtime:show("disabled")
assertEqual(nativeResult, "native-result", "native show return value")
assertEqual(marker, "disabled", "native show secondary return")
assertEqual(runtime.trace[1], "native-show", "native show precedes BFI")
assertNoInventoryMutation(runtime, "disabled setting")
assertEqual(runtime.counts.inCombat, 0,
    "disabled setting is inert before combat query")
assertEqual(runtime.counts.getCursorInfo, 0,
    "disabled setting is inert before cursor query")
assertEqual(runtime.counts.hasSlotted, 0,
    "disabled setting is inert before slot query")

runtime.reset()
runtime.config.mythicPlus.enabled = false
runtime:show("master-disabled")
assertNoInventoryMutation(runtime, "disabled Mythic+ enhancement")
assertEqual(runtime.counts.inCombat, 0,
    "master-disabled setting is inert")

-- The toggle is read for each opening; enabling it needs no reload or
-- additional hook.
runtime.reset()
runtime.config.mythicPlus.autoInsertKeystone.enabled = false
runtime:show("toggle-off")
runtime.config.mythicPlus.autoInsertKeystone.enabled = true
runtime.state.inventory = {
    {name = "toggle-key", itemID = 180653, compatible = true},
}
runtime.state.keystoneItemIDs[180653] = true
runtime:show("toggle-on")
assertEqual(runtime.counts.pickup, 1, "live toggle pickup")
assertEqual(runtime.counts.slot, 1, "live toggle slot")
assertEqual(#runtime.secureHooks, 1, "live toggle keeps one hook")

runtime.reset({inCombat = true})
runtime:show("combat")
assertNoInventoryMutation(runtime, "combat guard")

runtime.reset({cursorType = "spell", cursorItemID = 12345})
runtime:show("occupied-cursor")
assertNoInventoryMutation(runtime, "occupied cursor guard")
assertEqual(runtime.state.cursorType, "spell",
    "occupied cursor type remains untouched")
assertEqual(runtime.state.cursorItemID, 12345,
    "occupied cursor payload remains untouched")

runtime.reset({hasSlotted = true})
runtime:show("already-slotted")
assertNoInventoryMutation(runtime, "already-slotted guard")
assertEqual(runtime.state.hasSlotted, true,
    "existing slotted keystone remains owned by Blizzard")

runtime.reset({inCombat = runtime.secretValue})
runtime:show("secret-combat-state")
assertNoInventoryMutation(runtime, "secret combat state")

runtime.reset({hasSlotted = runtime.secretValue})
runtime:show("secret-initial-slot-state")
assertNoInventoryMutation(runtime, "secret initial slot state")

runtime.reset({cursorType = runtime.secretValue})
runtime:show("secret-initial-cursor")
assertNoInventoryMutation(runtime, "secret initial cursor")

-- Match only Blizzard's two-part key predicate and stop after the first
-- compatible held key.
local nonKey = {name = "ordinary-item", itemID = 100, compatible = true}
local wrongKey = {name = "wrong-dungeon-key", itemID = 200,
    compatible = false}
local matchingKey = {name = "matching-key", itemID = 300,
    compatible = true}
local laterKey = {name = "later-key", itemID = 400, compatible = true}

runtime.reset({
    getItemIDResult = runtime.secretValue,
    inventory = {matchingKey},
})
runtime:show("secret-item-id")
assertEqual(runtime.counts.pickup, 0,
    "secret item ID fails closed before pickup")
assertEqual(runtime.counts.isKeystone, 0,
    "secret item ID is never passed to the keystone predicate")

runtime.reset({
    inventory = {matchingKey},
    isKeystoneResult = runtime.secretValue,
})
runtime:show("secret-is-keystone")
assertEqual(runtime.counts.pickup, 0,
    "secret keystone result fails closed before pickup")
assertEqual(runtime.counts.canUse, 0,
    "secret keystone result is never passed to map compatibility")

runtime.reset({
    canUseResult = runtime.secretValue,
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
})
runtime:show("secret-map-compatibility")
assertEqual(runtime.counts.pickup, 0,
    "secret map compatibility fails closed before pickup")

runtime.reset({
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    pickupCursorItemID = runtime.secretValue,
})
runtime:show("secret-picked-item-id")
assertEqual(runtime.counts.pickup, 1, "secret picked item attempt")
assertEqual(runtime.counts.slot, 0,
    "secret picked item ID is never slotted")
assertEqual(runtime.counts.clearCursor, 0,
    "secret picked item ID is never cleared")

runtime.reset({
    cursorHasItem = runtime.secretValue,
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
})
runtime:show("secret-cursor-item-state")
assertEqual(runtime.counts.pickup, 1, "secret cursor item pickup")
assertEqual(runtime.counts.slot, 0,
    "secret cursor item state is never slotted")
assertEqual(runtime.counts.clearCursor, 0,
    "secret cursor item state is never cleared")

runtime.reset({
    inventory = {nonKey, wrongKey, matchingKey, laterKey},
    keystoneItemIDs = {
        [200] = true,
        [300] = true,
        [400] = true,
    },
})
runtime:show("matching-key")
assertEqual(runtime.counts.visited, 3,
    "inventory scan stops at first compatible key")
assertEqual(runtime.counts.canUse, 2,
    "map compatibility is queried only for keystones")
assertEqual(runtime.counts.pickup, 1, "compatible key pickup")
assertEqual(runtime.state.pickedLocation, matchingKey,
    "compatible key location")
assertEqual(runtime.counts.slot, 1, "compatible key slot call")
assertEqual(runtime.counts.clearCursor, 0,
    "successful insertion needs no cursor cleanup")
assertEqual(runtime.state.hasSlotted, true,
    "successful insertion remains native state")
assertEqual(runtime.trace[1], "native-show",
    "native popup opens before inventory scan")

runtime.reset({
    inventory = {nonKey, wrongKey},
    keystoneItemIDs = {
        [200] = true,
    },
})
runtime:show("no-match")
assertEqual(runtime.counts.visited, 2, "no-match full scan")
assertEqual(runtime.counts.pickup, 0, "no-match pickup")
assertEqual(runtime.counts.slot, 0, "no-match slot")
assertEqual(runtime.counts.clearCursor, 0, "no-match cleanup")

runtime.reset({
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    pickupSucceeds = false,
})
runtime:show("failed-pickup")
assertEqual(runtime.counts.pickup, 1, "failed pickup attempt")
assertEqual(runtime.counts.slot, 0,
    "slot is not called without a cursor item")
assertEqual(runtime.counts.clearCursor, 0,
    "failed pickup has no BFI-owned cursor to clear")

runtime.reset({
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    pickupCursorItemID = 999,
})
runtime:show("pickup-identity-changed")
assertEqual(runtime.counts.pickup, 1, "changed pickup attempt")
assertEqual(runtime.counts.slot, 0,
    "a different picked cursor item is never slotted")
assertEqual(runtime.counts.clearCursor, 0,
    "a cursor item BFI cannot verify is never cleared")
assertEqual(runtime.state.cursorItemID, 999,
    "unverified picked cursor item remains untouched")

-- A rejected slot is cleaned up only while the cursor still carries the
-- exact item BFI picked up and no keystone became slotted.
runtime.reset({
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    slotSucceeds = false,
})
runtime:show("failed-slot")
assertEqual(runtime.counts.slot, 1, "failed slot attempt")
assertEqual(runtime.counts.clearCursor, 1,
    "verified BFI pickup is cleared after rejected slot")
assertEqual(runtime.state.cursorType, nil,
    "failed-slot cleanup restores an empty cursor")

runtime.reset({
    afterSlotCursorItemID = 999,
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    slotSucceeds = false,
})
runtime:show("changed-cursor")
assertEqual(runtime.counts.slot, 1, "changed-cursor slot attempt")
assertEqual(runtime.counts.clearCursor, 0,
    "a different cursor item is never cleared")
assertEqual(runtime.state.cursorItemID, 999,
    "different cursor item remains untouched")

runtime.reset({
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    slotConsumesCursor = false,
    slotSucceeds = true,
})
runtime:show("slotted-with-cursor")
assertEqual(runtime.counts.slot, 1, "successful slot attempt")
assertEqual(runtime.counts.clearCursor, 0,
    "slotted state prevents cursor cleanup")
assertEqual(runtime.state.hasSlotted, true,
    "successful native slot state")

-- If a safety-relevant post-slot result is not ordinary, cleanup must fail
-- closed instead of comparing or clearing the cursor.
runtime.reset({
    hasSlottedAfterSlot = runtime.secretValue,
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    slotSucceeds = false,
})
runtime:show("secret-slot-state")
assertEqual(runtime.counts.slot, 1,
    "secret post-slot state follows a slot attempt")
assertEqual(runtime.counts.clearCursor, 0,
    "secret slot state fails closed")

runtime.reset({
    cursorHasItemAfterSlot = runtime.secretValue,
    inventory = {matchingKey},
    keystoneItemIDs = {[300] = true},
    slotSucceeds = false,
})
runtime:show("secret-post-slot-cursor-state")
assertEqual(runtime.counts.slot, 1,
    "secret post-slot cursor state follows a slot attempt")
assertEqual(runtime.counts.clearCursor, 0,
    "secret post-slot cursor state fails closed")

-- The LoD callback must install the hook before the popup's first native
-- ShowKeystoneFrame call, and repeated callbacks must remain idempotent.
local deferred = makeRuntime(false)
assertEqual(#deferred.secureHooks, 0, "deferred initial hook count")
deferred.config.mythicPlus.autoInsertKeystone.enabled = true
deferred.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
deferred.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
assertTrue(#(deferred.addonCallbacks.Blizzard_ChallengesUI or {}) >= 1,
    "deferred Challenges UI callback")
deferred:loadChallengesUI()
assertEqual(#deferred.secureHooks, 1, "deferred hook count")
deferred:loadChallengesUI()
assertEqual(#deferred.secureHooks, 1, "deferred hook idempotence")

deferred.reset({
    inventory = {
        {name = "first-open-key", itemID = 500, compatible = true},
    },
    keystoneItemIDs = {[500] = true},
})
deferred:show("first-opening")
assertEqual(deferred.trace[1], "native-show",
    "first LoD opening remains native-first")
assertEqual(deferred.counts.slot, 1,
    "first LoD opening inserts the compatible key")

-- Disabling either setting before the LoD addon arrives cancels the pending
-- initialization callback, so no dormant behavior appears on first open.
local cancelledToggle = makeRuntime(false)
cancelledToggle.config.mythicPlus.autoInsertKeystone.enabled = true
cancelledToggle.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
cancelledToggle.config.mythicPlus.autoInsertKeystone.enabled = false
cancelledToggle.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
assertEqual(
    #(cancelledToggle.addonCallbacks.Blizzard_ChallengesUI or {}),
    0,
    "disabled toggle cancels pending LoD initialization"
)
cancelledToggle:loadChallengesUI()
assertEqual(#cancelledToggle.secureHooks, 0,
    "disabled toggle installs no delayed hook")

local cancelledMaster = makeRuntime(false)
cancelledMaster.config.mythicPlus.autoInsertKeystone.enabled = true
cancelledMaster.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
cancelledMaster.config.mythicPlus.enabled = false
cancelledMaster.callbacks.BFI_UpdateConfig(nil, "enhancements", "mythicPlus")
assertEqual(
    #(cancelledMaster.addonCallbacks.Blizzard_ChallengesUI or {}),
    0,
    "disabled master cancels pending LoD initialization"
)
cancelledMaster:loadChallengesUI()
assertEqual(#cancelledMaster.secureHooks, 0,
    "disabled master installs no delayed hook")

-- Default hydration is opt-in false and the Mythic+ Enhancements option
-- writes the live nested setting.
local defaultCallbacks = {}
local defaultAF = {}

function defaultAF.Copy(value)
    return copy(value)
end

function defaultAF.GetColorTable(name)
    return {name = name}
end

function defaultAF.Merge(target, source)
    for key, value in pairs(source) do
        target[key] = copy(value)
    end
end

function defaultAF.RegisterCallback(event, callback)
    defaultCallbacks[event] = callback
end

local defaultE = {}
local defaultBFI = {
    modules = {
        Enhancements = defaultE,
    },
}
local defaultEnvironment = {
    AbstractFramework = defaultAF,
    BFIConfig = {},
    next = next,
    pairs = pairs,
    select = select,
    type = type,
    wipe = wipeTable,
}
defaultEnvironment._G = defaultEnvironment

local defaultsChunk, defaultsLoadError =
    loadfile("Modules/Enhancements/Defaults.lua")
assertEqual(type(defaultsChunk), "function",
    defaultsLoadError or "Enhancements defaults load")
setfenv(defaultsChunk, defaultEnvironment)
defaultsChunk("BFInfinite", defaultBFI)

local defaults = defaultE.GetDefaults()
assertEqual(defaults.mythicPlus.autoInsertKeystone.enabled, false,
    "auto-insert default")
assertEqual(type(defaultCallbacks.BFI_UpdateConfig), "function",
    "Enhancements config callback")
defaultCallbacks.BFI_UpdateConfig(nil, nil)
assertEqual(
    defaultEnvironment.BFIConfig.enhancements.mythicPlus
        .autoInsertKeystone.enabled,
    false,
    "fresh common-config hydration"
)

local optionCheckButtons = {}
local optionFires = {}
local optionAF = {
    noop = function()
    end,
}

function optionAF.ClearPoints()
end

function optionAF.CreateBorderedFrame(_, name, _, height)
    local pane = {
        _height = height,
        name = name,
    }
    function pane:Hide()
        self.shown = false
    end
    function pane:Show()
        self.shown = true
    end
    return pane
end

function optionAF.CreateButton(_, label)
    local button = {labelText = label}
    function button:SetOnClick(callback)
        self.onClick = callback
    end
    return button
end

function optionAF.CreateCheckButton(_, label)
    local checkButton = {
        label = {
            SetTextColor = function()
            end,
        },
        labelText = label,
    }
    function checkButton:SetChecked(value)
        self.checked = value
    end
    function checkButton:SetOnCheck(callback)
        self.onCheck = callback
    end
    function checkButton:SetTooltip(...)
        self.tooltip = {...}
    end
    optionCheckButtons[#optionCheckButtons + 1] = checkButton
    return checkButton
end

function optionAF.Fire(...)
    optionFires[#optionFires + 1] = {...}
end

function optionAF.GetColorRGB()
    return 1, 1, 1
end

function optionAF.GetDialog()
    return {
        SetOnConfirm = function()
        end,
        SetPoint = function()
        end,
    }
end

function optionAF.SetPoint()
end

function optionAF.WrapTextInColor(text)
    return text
end

local optionL = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local optionE = {
    ResetToDefaults = function()
    end,
}
local optionF = {}
local optionBFI = {
    funcs = optionF,
    L = optionL,
    modules = {
        Enhancements = optionE,
    },
}
local optionEnvironment = {
    AbstractFramework = optionAF,
    BFIOptionsFrame_EnhancementsPanel = {},
    RESET = "Reset",
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    tinsert = table.insert,
    type = type,
    wipe = wipeTable,
}
optionEnvironment._G = optionEnvironment

local optionsChunk, optionsLoadError =
    loadfile("Options/Enhancements_Options.lua")
assertEqual(type(optionsChunk), "function",
    optionsLoadError or "Enhancements options load")
setfenv(optionsChunk, optionEnvironment)
optionsChunk("BFInfinite", optionBFI)

local optionInfo = {
    cfg = {
        enabled = true,
        autoInsertKeystone = {
            enabled = false,
        },
        teleportButtons = {
            enabled = true,
        },
    },
    id = "mythicPlus",
    ownerName = "Mythic+",
    SetTextColor = function()
    end,
}
local optionPanes = optionF.GetEnhancementOptions({}, optionInfo)
for _, pane in ipairs(optionPanes) do
    pane.Load(optionInfo)
end

local autoInsertControl
for _, checkButton in ipairs(optionCheckButtons) do
    if checkButton.labelText == "Auto Insert Matching Keystone" then
        autoInsertControl = checkButton
        break
    end
end
assertTrue(autoInsertControl, "auto-insert option control")
assertEqual(autoInsertControl.checked, false,
    "auto-insert option loads disabled")
assertEqual(autoInsertControl.tooltip[1], "Auto Insert Matching Keystone",
    "auto-insert tooltip title")
assertEqual(
    autoInsertControl.tooltip[2],
    "Automatically inserts your usable Mythic Keystone when the dungeon pedestal opens. It never starts the key.",
    "auto-insert tooltip body"
)
autoInsertControl.onCheck(true)
assertEqual(optionInfo.cfg.autoInsertKeystone.enabled, true,
    "auto-insert option stores enabled state")
assertEqual(optionFires[#optionFires][1], "BFI_UpdateConfig",
    "auto-insert option update event")
assertEqual(optionFires[#optionFires][2], "enhancements",
    "auto-insert option update module")
assertEqual(optionFires[#optionFires][3], "mythicPlus",
    "auto-insert option update section")

local enhancementsLoad = readFile("Modules/Enhancements/Load.xml")
assertContains(enhancementsLoad, '<Script file="MythicPlus.lua"/>',
    "Mythic+ Enhancements runtime load entry")

local englishLocale = readFile("Locales/enUS.lua")
assertContains(
    englishLocale,
    '["Auto Insert Matching Keystone"] = "Auto Insert Matching Keystone"',
    "English auto-insert locale"
)
local simplifiedChineseLocale = readFile("Locales/zhCN.lua")
assertContains(
    simplifiedChineseLocale,
    'L["Auto Insert Matching Keystone"] = ',
    "Simplified Chinese auto-insert locale"
)

print("mythic_plus_auto_insert_test.lua: ok")
