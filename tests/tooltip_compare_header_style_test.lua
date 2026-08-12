local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local styleCallback
local hooks = {}

local function newTexture()
    return {
        alpha = 1,
        atlas = "tooltip-compare-label",
        shown = true,
        texture = "native",
        Hide = function(self)
            self.shown = false
        end,
        IsObjectType = function(_, objectType)
            return objectType == "Texture"
        end,
        SetAlpha = function(self, alpha)
            self.alpha = alpha
        end,
        SetAtlas = function(self, atlas)
            self.atlas = atlas
        end,
        SetTexture = function(self, texture)
            self.texture = texture
        end,
    }
end

local function newLabel(text)
    return {
        text = text,
        GetText = function(self)
            return self.text
        end,
        IsObjectType = function(_, objectType)
            return objectType == "FontString"
        end,
        SetText = function(self, value)
            self.text = value
        end,
    }
end

local function newCompareHeader(name)
    local texture = newTexture()
    local label = newLabel("Equipped")
    local header = {
        Label = label,
        height = 22,
        name = name,
        point = {"BOTTOMLEFT", "TOPLEFT", 0, -1},
        shown = true,
        width = 100,
        GetRegions = function(self)
            return unpack(self.regions)
        end,
        Hide = function(self)
            self.shown = false
        end,
        SetWidth = function(self, width)
            self.width = width
        end,
        Show = function(self)
            self.shown = true
        end,
    }
    header.regions = {texture, label}
    return header, texture, label
end

local function newTooltip(compareHeader)
    return {
        CompareHeader = compareHeader,
        Delimiter1 = newTexture(),
        Delimiter2 = newTexture(),
        NineSlice = {},
        IsForbidden = function()
            return false
        end,
    }
end

local headers = {}
local comparisonTooltips = {}
for _, name in ipairs({
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
}) do
    local header, texture, label = newCompareHeader(name .. "CompareHeader")
    headers[name] = {header = header, texture = texture, label = label}
    comparisonTooltips[name] = newTooltip(header)
end

local AF = {
    AddToPixelUpdater_Auto = function() end,
    AddToPixelUpdater_CustomGroup = function(group, frame)
        frame.pixelUpdaterCalls = (frame.pixelUpdaterCalls or 0) + 1
        frame.pixelUpdaterGroup = group
    end,
    ApplyDefaultBackdropWithColors = function(frame, color)
        frame.backdropCalls = (frame.backdropCalls or 0) + 1
        frame.backdropColor = color
    end,
    RegisterCallback = function(event, callback)
        assertEqual(event, "BFI_StyleBlizzard", "style callback event")
        styleCallback = callback
    end,
    SetOnePixelInside = function() end,
    SetPoint = function() end,
}

local S = {
    CreateBackdrop = function() end,
    RemoveTextures = function(region, hide)
        region.removeTextureCalls = (region.removeTextureCalls or 0) + 1
        for _, child in ipairs({region:GetRegions()}) do
            if child:IsObjectType("Texture") then
                child:SetTexture("empty")
                child:SetAtlas("")
                if hide then
                    child:SetAlpha(0)
                    child:Hide()
                end
            end
        end
    end,
    StyleIcon = function() end,
    StyleIconBorder = function() end,
    StyleStatusBar = function() end,
}

local genericTooltip = newTooltip()
local embeddedTooltip = newTooltip()
embeddedTooltip.ItemTooltip = {Icon = {}, IconBorder = {}}

local statusBar = {
    ClearAllPoints = function() end,
    SetStatusBarTexture = function() end,
}

local environment = {
    _G = false,
    AbstractFramework = AF,
    EmbeddedItemTooltip = embeddedTooltip,
    FriendsTooltip = genericTooltip,
    GameTooltip = genericTooltip,
    GameTooltipStatusBar = statusBar,
    ItemRefShoppingTooltip1 = comparisonTooltips.ItemRefShoppingTooltip1,
    ItemRefShoppingTooltip2 = comparisonTooltips.ItemRefShoppingTooltip2,
    ItemRefTooltip = genericTooltip,
    LibDBIconTooltip = genericTooltip,
    QuickKeybindTooltip = genericTooltip,
    QuestMapLog_GetCampaignTooltip = function()
        return genericTooltip
    end,
    ReputationParagonTooltip = genericTooltip,
    SettingsTooltip = genericTooltip,
    ShoppingTooltip1 = comparisonTooltips.ShoppingTooltip1,
    ShoppingTooltip2 = comparisonTooltips.ShoppingTooltip2,
    WorldMapTooltip = genericTooltip,
    hooksecurefunc = function(name, callback)
        hooks[name] = callback
    end,
    select = select,
    unpack = unpack,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local BFI = {
    media = {bar = "bar"},
    modules = {Style = S},
}

local chunk, loadError = loadfile("Modules/Blizzard/Style/Tooltip.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(styleCallback), "function", "style callback")
styleCallback()

for name, record in pairs(headers) do
    local header = record.header
    assertEqual(header._BFIStyled, true, name .. " style marker")
    assertEqual(header.backdropColor, "widget", name .. " AF background")
    assertEqual(header.backdropCalls, 1, name .. " backdrop count")
    assertEqual(header.pixelUpdaterGroup, "BFIStyled", name .. " pixel updater group")
    assertEqual(header.pixelUpdaterCalls, 1, name .. " pixel updater count")
    assertEqual(header.removeTextureCalls, 1, name .. " native artwork removal count")
    assertEqual(record.texture.texture, "empty", name .. " native texture")
    assertEqual(record.texture.atlas, "", name .. " native atlas")
    assertEqual(record.texture.alpha, 0, name .. " native texture alpha")
    assertEqual(record.texture.shown, false, name .. " native texture visibility")
    assertEqual(header.Label, record.label, name .. " native label ownership")
    assertEqual(record.label:GetText(), "Equipped", name .. " native label text")
    assertEqual(header.height, 22, name .. " native height")
    assertEqual(header.width, 100, name .. " native width")
    assertEqual(header.point[1], "BOTTOMLEFT", name .. " native anchor")

    record.label:SetText("If equipped together")
    header:SetWidth(170)
    header:Hide()
    header:Show()
    assertEqual(record.label:GetText(), "If equipped together", name .. " label lifecycle")
    assertEqual(header.width, 170, name .. " dynamic width lifecycle")
    assertEqual(header.shown, true, name .. " visibility lifecycle")
end

assertEqual(type(hooks.SharedTooltip_SetBackdropStyle), "function", "backdrop style hook")
hooks.SharedTooltip_SetBackdropStyle(comparisonTooltips.ShoppingTooltip1)
assertEqual(headers.ShoppingTooltip1.header.backdropCalls, 1, "idempotent backdrop")
assertEqual(headers.ShoppingTooltip1.header.removeTextureCalls, 1, "idempotent artwork removal")

print("tooltip_compare_header_style_test.lua: ok")
