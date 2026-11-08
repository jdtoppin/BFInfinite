local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local itemLink = "|Hitem:12345|h[Test Item]|h"
local itemInfoCalls = 0
local tooltipLines
local enhancements = {
    RegisterEvent = function() end,
}
local environment = {
    AbstractFramework = {
        IsBlank = function(value) return value == nil or value == "" end,
        RegisterAddonLoaded = function() end,
        RegisterCallback = function() end,
    },
    C_Container = {},
    C_Item = {
        GetItemInfo = function(link)
            assertEqual(link, itemLink, "item info link")
            itemInfoCalls = itemInfoCalls + 1
            return "Test Item", link, 4, 615
        end,
    },
    C_TooltipInfo = {
        GetHyperlink = function(link)
            assertEqual(link, itemLink, "tooltip link")
            return {lines = tooltipLines}
        end,
    },
    GetItemInfo = false, -- Removed global alias must never be called.
    ITEM_LEVEL = "Item Level %d",
}
setmetatable(environment, {__index = _G})
environment._G = environment

local BFI = {modules = {Enhancements = enhancements}}
local chunk = assert(loadfile("Modules/Enhancements/EquipmentInfo.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(enhancements.GetItemLevel(""), nil, "blank item link")
assertEqual(itemInfoCalls, 0, "blank item link avoids item API")

tooltipLines = {}
assertEqual(enhancements.GetItemLevel(itemLink), 615, "item info level fallback")

tooltipLines = {{}, {leftText = "Item Level 622"}}
assertEqual(enhancements.GetItemLevel(itemLink), 622, "tooltip level override")
assertEqual(itemInfoCalls, 2, "namespaced item API used for nonblank links")

print("equipment_info_item_level_test: passed")
