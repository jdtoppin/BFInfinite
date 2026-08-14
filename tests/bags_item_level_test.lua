local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do
        result[key] = copy(entry)
    end
    return result
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then return nil end
        if name == targetName then return value end
        index = index + 1
    end
end

local function setUpvalue(func, targetName, replacement)
    local index = 1
    while true do
        local name = debug.getupvalue(func, index)
        if not name then return false end
        if name == targetName then
            debug.setupvalue(func, index, replacement)
            return true
        end
        index = index + 1
    end
end

local function loadDefaults()
    local callbacks = {}
    local bags = {}
    local AF = {
        Copy = copy,
        Merge = function(target, source)
            for key, value in pairs(source) do
                target[key] = copy(value)
            end
        end,
        RegisterCallback = function(name, callback)
            callbacks[name] = callback
        end,
    }
    local environment = {
        AbstractFramework = AF,
        math = math,
        pairs = pairs,
        select = select,
        tonumber = tonumber,
        type = type,
    }
    setmetatable(environment, {__index = _G})
    environment._G = environment

    local BFI = {
        modules = {
            Bags = bags,
        },
    }
    local chunk, loadError = loadfile("Modules/Bags/Defaults.lua")
    assertEqual(type(chunk), "function", loadError or "defaults load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return bags, callbacks
end

local defaultsBags, defaultsCallbacks = loadDefaults()
assertEqual(defaultsBags.GetDefaults().showItemLevel, true,
    "item level default is enabled")
assertEqual(defaultsBags.GetDefaults().viewMode, "combined",
    "combined bag view is the default")
assertEqual(defaultsBags.GetDefaults().sidebarCollapsed, false,
    "sidebar labels are expanded by default")

local legacyCategoryProfile = {
    bags = {
        categories = true,
        position = {"BOTTOMRIGHT", -35, 110},
    },
}
defaultsCallbacks.BFI_UpdateProfile(nil, legacyCategoryProfile)
assertEqual(legacyCategoryProfile.bags.viewMode, "combined",
    "legacy category toggle migrates to persistent-sidebar Combined view")
assertEqual(legacyCategoryProfile.bags.categories, nil,
    "legacy category toggle is removed after migration")

local formerCategoryViewProfile = {
    bags = {
        viewMode = "categories",
        position = {"BOTTOMRIGHT", -35, 110},
    },
}
defaultsCallbacks.BFI_UpdateProfile(nil, formerCategoryViewProfile)
assertEqual(formerCategoryViewProfile.bags.viewMode, "combined",
    "former saved category mode migrates to Combined view")

local invalidViewProfile = {
    bags = {
        viewMode = "unknown",
        position = {"BOTTOMRIGHT", -35, 110},
    },
}
defaultsCallbacks.BFI_UpdateProfile(nil, invalidViewProfile)
assertEqual(invalidViewProfile.bags.viewMode, "combined",
    "invalid saved view normalizes to Combined view")

local individualProfile = {
    bags = {
        viewMode = "individual",
        position = {"BOTTOMRIGHT", -35, 110},
    },
}
defaultsCallbacks.BFI_UpdateProfile(nil, individualProfile)
assertEqual(individualProfile.bags.viewMode, "individual",
    "individual bag view is preserved")

local profile = {
    bags = {
        enabled = true,
        position = {"BOTTOMRIGHT", -35, 110},
    },
}
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.showItemLevel, true,
    "missing item level setting is normalized")
assertEqual(profile.bags.sidebarCollapsed, false,
    "missing sidebar collapsed setting is normalized")

profile.bags.sidebarCollapsed = "yes"
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.sidebarCollapsed, false,
    "invalid sidebar collapsed setting is normalized")

profile.bags.sidebarCollapsed = true
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.sidebarCollapsed, true,
    "valid collapsed sidebar setting is preserved")

profile.bags.sidebarCollapsed = false
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.sidebarCollapsed, false,
    "valid expanded sidebar setting is preserved")

profile.bags.sidebarCollapsed = nil
profile.bags.sidebarAutoHide = true
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.sidebarCollapsed, true,
    "legacy sidebarAutoHide true migrates to sidebarCollapsed true")
assertEqual(profile.bags.sidebarAutoHide, nil,
    "the legacy sidebarAutoHide key is consumed after migration")

profile.bags.showItemLevel = "yes"
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.showItemLevel, true,
    "invalid item level setting is normalized")

profile.bags.showItemLevel = false
defaultsCallbacks.BFI_UpdateProfile(nil, profile)
assertEqual(profile.bags.showItemLevel, false,
    "valid item level setting is preserved")

local createdTextCount = 0
local currentInfoBySlot = {}
local currentLevelBySlot = {}
local containerInfoCalls = 0
local equippableCalls = 0
local currentLevelCalls = 0

local function makeFontString()
    local text = {
        shown = false,
    }

    function text:Hide()
        self.shown = false
    end

    function text:SetJustifyH(justify)
        self.justify = justify
    end

    function text:SetPoint(...)
        self.point = {...}
    end

    function text:SetText(value)
        self.value = value
    end

    function text:SetTextColor(...)
        assertEqual(select("#", ...), 3, "item quality color component count")
        self.color = {...}
    end

    function text:Show()
        self.shown = true
    end

    return text
end

local AF = {
    CreateFontString = function(_, _, color, font, layer)
        assertEqual(color, nil, "item level inherits font color")
        assertEqual(font, "NumberFontNormal", "item level stack count font")
        assertEqual(layer, "ARTWORK", "item level stack count layer")
        createdTextCount = createdTextCount + 1
        return makeFontString()
    end,
    GetColorRGB = function(color)
        assertEqual(color, "white", "fallback color")
        return 1, 1, 1
    end,
    GetIcon = function(name)
        return name
    end,
    SetPoint = function(region, ...)
        region:SetPoint(...)
    end,
    RegisterCallback = function() end,
    player = {
        class = {1, 0.5, 0},
    },
}

local ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    return {
        bagID = bagID,
        slotID = slotID,
    }
end

local itemClass = {
    Consumable = 0,
    Gem = 1,
    Tradegoods = 2,
    Reagent = 3,
    ItemEnhancement = 4,
    Profession = 5,
    Recipe = 6,
    Questitem = 7,
}
local environment = {
    AbstractFramework = AF,
    C_Container = {
        GetContainerItemInfo = function(bagID, slotID)
            containerInfoCalls = containerInfoCalls + 1
            return currentInfoBySlot[bagID .. ":" .. slotID]
        end,
    },
    C_Item = {
        GetCurrentItemLevel = function(itemLocation)
            currentLevelCalls = currentLevelCalls + 1
            return currentLevelBySlot[
                itemLocation.bagID .. ":" .. itemLocation.slotID
            ]
        end,
        IsEquippableItem = function(itemLink)
            equippableCalls = equippableCalls + 1
            return itemLink:find("equipment", 1, true) ~= nil
        end,
    },
    Constants = {
        InventoryConstants = {
            NumBagSlots = 4,
            NumReagentBagSlots = 1,
        },
    },
    Enum = {
        BagIndex = {
            Backpack = 0,
        },
        GameRule = {
            BagsUIDisabled = 1,
        },
        ItemClass = itemClass,
    },
    GetCVarBool = function() end,
    GetInventoryItemTexture = function() end,
    HIGHLIGHT_FONT_COLOR = {
        GetRGB = function()
            return 1, 1, 1
        end,
    },
    ItemLocation = ItemLocation,
    SetCVar = function() end,
    bit = {
        band = function() return 0 end,
    },
    debug = debug,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    type = type,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local bags = {
    Cleanup = {},
    config = {
        enabled = true,
        showItemLevel = true,
    },
}
local BFI = {
    L = {},
    modules = {
        Bags = bags,
        Style = {},
    },
}
local chunk, loadError = loadfile("Modules/Bags/Bags.lua")
assertEqual(type(chunk), "function", loadError or "bags module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local refreshItemLevelTexts = findUpvalue(
    bags.Refresh,
    "RefreshItemLevelTexts"
)
assertEqual(type(refreshItemLevelTexts), "function",
    "item level refresh upvalue")
local updateItemLevelText = findUpvalue(
    refreshItemLevelTexts,
    "UpdateItemLevelText"
)
assertEqual(type(updateItemLevelText), "function",
    "item level update upvalue")

local button = {
    bagID = 0,
    slotID = 1,
    borderColorCalls = 0,
}
function button:GetBagID()
    return self.bagID
end
function button:GetID()
    return self.slotID
end
function button:SetBackdropBorderColor()
    self.borderColorCalls = self.borderColorCalls + 1
end

currentInfoBySlot["0:1"] = {
    hyperlink = "item:equipment:one",
    quality = 4,
}
currentLevelBySlot["0:1"] = 678

assertEqual(setUpvalue(refreshItemLevelTexts, "combinedFrame", {
    Items = {button},
}), true, "combined frame upvalue")
bags.config.showItemLevel = false
refreshItemLevelTexts()
assertEqual(createdTextCount, 0, "disabled display creates no text")
assertEqual(containerInfoCalls, 0, "disabled display skips container query")
assertEqual(equippableCalls, 0, "disabled display skips equipment query")
assertEqual(currentLevelCalls, 0, "disabled display skips item level query")

bags.config.showItemLevel = true
refreshItemLevelTexts()

assertEqual(createdTextCount, 1, "item level text creation")
assertEqual(button.BFIItemLevel.value, 678, "current item level text")
assertEqual(button.BFIItemLevel.shown, true, "equipment item level visibility")
assertEqual(button.BFIItemLevel.point[1], "BOTTOMLEFT", "item level anchor")
assertEqual(button.BFIItemLevel.point[2], 5, "item level x offset")
assertEqual(button.BFIItemLevel.point[3], 2, "item level y offset")
assertEqual(button.BFIItemLevel.justify, "LEFT", "item level justification")
assertEqual(button.BFIItemLevel.color[1], 1, "item level text red")
assertEqual(button.BFIItemLevel.color[2], 1, "item level text green")
assertEqual(button.BFIItemLevel.color[3], 1, "item level text blue")
assertEqual(button.BFIItemLevelOutline, nil, "item level has no custom outline")
assertEqual(button.borderColorCalls, 0, "item border remains unchanged")

local isEnabled = findUpvalue(bags.Refresh, "IsEnabled")
assertEqual(type(isEnabled), "function", "bags enabled upvalue")
assertEqual(setUpvalue(isEnabled, "moduleEnabled", true), true,
    "module enabled upvalue")
assertEqual(setUpvalue(
    bags.Refresh,
    "UpdateBlizzardBagBarVisibility",
    function() end
), true, "bag bar refresh upvalue")
assertEqual(setUpvalue(bags.Refresh, "combinedFrame", {
    IsShown = function() return false end,
    Items = {button},
}), true, "hidden combined frame upvalue")

bags.config.showItemLevel = false
bags.Refresh()
assertEqual(button.BFIItemLevel.value, "", "toggle off clears item level")
assertEqual(button.BFIItemLevel.shown, false, "toggle off hides item level")
local disabledContainerCalls = containerInfoCalls
local disabledEquippableCalls = equippableCalls
local disabledLevelCalls = currentLevelCalls
bags.Refresh()
assertEqual(containerInfoCalls, disabledContainerCalls,
    "closed disabled refresh skips container query")
assertEqual(equippableCalls, disabledEquippableCalls,
    "closed disabled refresh skips equipment query")
assertEqual(currentLevelCalls, disabledLevelCalls,
    "closed disabled refresh skips item level query")

bags.config.showItemLevel = true
currentLevelBySlot["0:1"] = 679
assertEqual(setUpvalue(refreshItemLevelTexts, "combinedFrame", {
    Items = {button},
}), true, "reopened combined frame upvalue")
refreshItemLevelTexts()
assertEqual(button.BFIItemLevel.value, 679,
    "same pooled slot refreshes current item level")
assertEqual(createdTextCount, 1, "same pooled slot reuses item level text")

local priorLevelCalls = currentLevelCalls
currentInfoBySlot["0:1"] = {
    hyperlink = "item:consumable:one",
    quality = 1,
}
updateItemLevelText(button)
assertEqual(currentLevelCalls, priorLevelCalls,
    "non-equipment skips item level query")
assertEqual(button.BFIItemLevel.value, "", "non-equipment clears item level")
assertEqual(button.BFIItemLevel.shown, false,
    "non-equipment hides item level")

currentInfoBySlot["0:1"] = {
    hyperlink = "item:equipment:two",
}
currentLevelBySlot["0:1"] = 701
updateItemLevelText(button)
assertEqual(createdTextCount, 1, "pooled button reuses item level text")
assertEqual(button.BFIItemLevel.value, 701, "reused button item level")
assertEqual(button.BFIItemLevel.color[1], 1, "reused item level text red")
assertEqual(button.BFIItemLevel.color[2], 1, "reused item level text green")
assertEqual(button.BFIItemLevel.color[3], 1, "reused item level text blue")

currentLevelBySlot["0:1"] = nil
updateItemLevelText(button)
assertEqual(button.BFIItemLevel.value, "", "nil item level clears text")
assertEqual(button.BFIItemLevel.shown, false, "nil item level hides text")

local emptyButton = {
    GetBagID = function() return 0 end,
    GetID = function() return 2 end,
}
updateItemLevelText(emptyButton)
assertEqual(emptyButton.BFIItemLevel, nil,
    "empty slot does not create item level text")

print("bags_item_level_test.lua: ok")
