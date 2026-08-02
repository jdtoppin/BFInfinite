local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertContains(source, pattern, message)
    if not source:match(pattern) then
        error(message or ("missing source pattern: " .. pattern), 2)
    end
end

local function assertNotContains(source, text, message)
    if source:find(text, 1, true) then
        error(message or ("unexpected source text: " .. text), 2)
    end
end

local function assertColor(texture, r, g, b, a, message)
    local color = texture.vertexColor or {}
    assertEqual(color[1], r, (message or "color") .. " red")
    assertEqual(color[2], g, (message or "color") .. " green")
    assertEqual(color[3], b, (message or "color") .. " blue")
    assertEqual(color[4], a, (message or "color") .. " alpha")
end

local frameCreations = 0
local function makeFrame()
    frameCreations = frameCreations + 1
    local frame = {
        scripts = {},
        shown = true,
    }

    function frame:Hide()
        self.shown = false
    end

    function frame:SetScript(scriptName, script)
        self.scripts[scriptName] = script
    end

    function frame:Show()
        self.shown = true
    end

    return frame
end

local AF = {
    Libs = {
        LCG = {},
    },
}

function AF.ApplyDefaultBackdrop()
    error("action buttons must not create a BackdropTemplate backdrop")
end

function AF.ApplyDefaultBackdropColors()
    error("action buttons must not color a BackdropTemplate backdrop")
end

function AF.CreateTexture()
    error("lightweight backdrop regions must be native textures")
end

function AF.DefaultUpdatePixels(region)
    region.defaultPixelUpdates = (region.defaultPixelUpdates or 0) + 1
end

function AF.GetColorRGB(name)
    if name == "background" then
        return 0.11, 0.12, 0.13, 0.14
    elseif name == "border" then
        return 0.21, 0.22, 0.23, 0.24
    end
    error("unexpected color: " .. tostring(name))
end

function AF.RePoint(region)
    region.pixelRepoints = (region.pixelRepoints or 0) + 1
end

function AF.ReSize(region)
    region.pixelResizes = (region.pixelResizes or 0) + 1
end

function AF.SetHeight(region, height)
    region:SetHeight(height)
end

function AF.SetOnePixelInside(region, relativeTo)
    region.onePixelInside = relativeTo
end

function AF.SetPoint(region, ...)
    region:SetPoint(...)
end

function AF.SetWidth(region, width)
    region:SetWidth(width)
end

local BFI = {
    funcs = {
        Hide = function()
        end,
    },
    libs = {
        LAB = {},
    },
    modules = {
        ActionBars = {},
    },
}

local environment = {
    _G = false,
    AbstractFramework = AF,
    ATTACK_BUTTON_FLASH_TIME = 0.4,
    BackdropTemplateMixin = {},
    CreateFrame = makeFrame,
    GetBindingKey = function()
    end,
    Mixin = function()
        error("action buttons must not mix in BackdropTemplateMixin")
    end,
    RANGE_INDICATOR = "RANGE",
}
setmetatable(environment, {__index = _G})
environment._G = environment

local commonPath = "Modules/ActionBars/Common.lua"
local chunk, loadError = loadfile(commonPath)
assertEqual(type(chunk), "function", loadError or "Common.lua load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)
assertEqual(frameCreations, 1, "only the shared pet flash controller is created")

local function makeTexture(layer, subLevel)
    local texture = {
        layer = layer,
        points = {},
        subLevel = subLevel,
    }

    function texture:SetColorTexture(r, g, b, a)
        self.colorTexture = {r, g, b, a}
    end

    function texture:SetVertexColor(r, g, b, a)
        self.vertexColor = {r, g, b, a}
        self.vertexColorWrites = (self.vertexColorWrites or 0) + 1
    end

    function texture:SetHeight(height)
        self.height = height
    end

    function texture:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function texture:SetWidth(width)
        self.width = width
    end

    return texture
end

local textures = {}
local legacyBackdropColor = function()
    error("legacy backdrop color setter must be replaced")
end
local legacyBackdropBorderColor = function()
    error("legacy backdrop border setter must be replaced")
end
local button = {
    icon = {},
    scripts = {},
    SetBackdropColor = legacyBackdropColor,
    SetBackdropBorderColor = legacyBackdropBorderColor,
}

function button.icon:SetDrawLayer(layer, subLevel)
    self.layer = layer
    self.subLevel = subLevel
end

function button.icon:SetTexCoord(...)
    self.texCoord = {...}
end

function button:ClearBackdrop()
    self.clearBackdropCalls = (self.clearBackdropCalls or 0) + 1
end

function button:CreateTexture(_, layer, _, subLevel)
    local texture = makeTexture(layer, subLevel)
    textures[#textures + 1] = texture
    return texture
end

function button:GetName()
    return "BFI_TestActionButton"
end

function button:GetNormalTexture()
    return nil
end

function button:SetScript(scriptName, script)
    self.scripts[scriptName] = script
end

local AB = BFI.modules.ActionBars
AB.StylizeButton(button)

assertEqual(#textures, 5, "one fill and four border textures")
assertEqual(frameCreations, 1, "styling creates no per-button frame")
assertEqual(button.clearBackdropCalls, 1, "legacy backdrop is cleared once")
assertEqual(button.scripts.OnUpdate, nil, "lightweight backdrop has no idle updater")

local background = textures[1]
local top, bottom, left, right = textures[2], textures[3], textures[4], textures[5]
local borders = {top, bottom, left, right}

assertEqual(button.BFIBackdropBackground, background, "private fill reference")
assertEqual(#button.BFIBackdropBorders, 4, "private border reference count")
assertEqual(background.layer, "BACKGROUND", "fill draw layer")
assertEqual(background.subLevel, 0, "fill draw sublevel")
assertEqual(background.onePixelInside, button, "fill sits inside the border")
assertEqual(background.colorTexture[1], 1, "fill uses a solid white texture")
assertColor(background, 0.11, 0.12, 0.13, 0.14, "default fill")

for index, border in ipairs(borders) do
    assertEqual(button.BFIBackdropBorders[index], border,
        "private border " .. index .. " reference")
    assertEqual(border.layer, "BORDER", "border " .. index .. " draw layer")
    assertEqual(border.subLevel, 0, "border " .. index .. " draw sublevel")
    assertEqual(border.colorTexture[1], 1,
        "border " .. index .. " uses a solid white texture")
    assertColor(border, 0.21, 0.22, 0.23, 0.24, "default border " .. index)
end
assertEqual(top.height, 1, "top border is one pixel high")
assertEqual(bottom.height, 1, "bottom border is one pixel high")
assertEqual(left.width, 1, "left border is one pixel wide")
assertEqual(right.width, 1, "right border is one pixel wide")
assertEqual(#top.points, 2, "top border has two edge anchors")
assertEqual(#bottom.points, 2, "bottom border has two edge anchors")
assertEqual(#left.points, 2, "left border has two edge anchors")
assertEqual(#right.points, 2, "right border has two edge anchors")

assertEqual(type(button.SetBackdropBorderColor), "function",
    "LibActionButton border-color compatibility")
button:SetBackdropBorderColor(0.31, 0.32, 0.33)
for index, border in ipairs(borders) do
    assertColor(border, 0.31, 0.32, 0.33, 1,
        "three-component border " .. index)
end
assertColor(background, 0.11, 0.12, 0.13, 0.14,
    "border color does not alter the fill")

button:SetBackdropBorderColor(0.41, 0.42, 0.43, 0.44)
for index, border in ipairs(borders) do
    assertColor(border, 0.41, 0.42, 0.43, 0.44,
        "four-component border " .. index)
end
button:SetBackdropColor(0.51, 0.52, 0.53, 0.54)
assertColor(background, 0.51, 0.52, 0.53, 0.54, "explicit fill")

local setBackdropColor = button.SetBackdropColor
local setBackdropBorderColor = button.SetBackdropBorderColor
AB.StylizeButton(button)
assertEqual(#textures, 5, "restyling does not duplicate backdrop textures")
assertEqual(frameCreations, 1, "restyling creates no frame")
assertEqual(button.clearBackdropCalls, 1, "restyling does not clear again")
assertEqual(button.SetBackdropColor, setBackdropColor,
    "fill setter is stable across restyling")
assertEqual(button.SetBackdropBorderColor, setBackdropBorderColor,
    "border setter is stable across restyling")
for index, border in ipairs(borders) do
    assertColor(border, 0.41, 0.42, 0.43, 0.44,
        "restyling preserves dynamic border " .. index)
end

button:UpdatePixels()
assertEqual(button.defaultPixelUpdates, 1, "ordinary button pixel update is preserved")
assertEqual(#textures, 5, "pixel resnap creates no textures")
assertEqual(background.pixelRepoints, 1, "fill pixel reanchor")
for index, border in ipairs(borders) do
    assertEqual(border.pixelResizes, 1, "border " .. index .. " pixel resize")
    assertEqual(border.pixelRepoints, 1, "border " .. index .. " pixel reanchor")
end

local commonFile = assert(io.open(commonPath, "r"))
local commonSource = commonFile:read("*a")
commonFile:close()
local stylizeStart = assert(commonSource:find("-- stylize button", 1, true))
local stylizeEnd = assert(commonSource:find("-- update text", stylizeStart, true))
local stylizeSource = commonSource:sub(stylizeStart, stylizeEnd - 1)
assertNotContains(stylizeSource, "BackdropTemplateMixin",
    "action-button styling avoids BackdropTemplateMixin")
assertNotContains(stylizeSource, "AF.ApplyDefaultBackdrop",
    "action-button styling avoids BackdropTemplate NineSlice")
assertNotContains(stylizeSource, ':SetBackdrop(',
    "action-button styling avoids native backdrops")
assertNotContains(stylizeSource, 'SetScript("OnUpdate"',
    "lightweight backdrop has no OnUpdate")
assertNotContains(stylizeSource, "C_Timer.NewTicker",
    "lightweight backdrop has no ticker")

local libraryPath = "Libs/LibActionButton-1.0/LibActionButton-1.0.lua"
local libraryFile = assert(io.open(libraryPath, "r"))
local librarySource = libraryFile:read("*a")
libraryFile:close()
assertContains(librarySource, "if self%.SetBackdropBorderColor then",
    "LibActionButton keeps optional border-color dispatch")
assertContains(librarySource, "self:SetBackdropBorderColor%(unpack%(self%.config%.colors%.equippedBorder%)%)",
    "equipped border still uses the compatibility setter")
assertContains(librarySource, "self:SetBackdropBorderColor%(unpack%(self%.config%.colors%.macroBorder%)%)",
    "macro border still uses the compatibility setter")
assertContains(librarySource, "self:SetBackdropBorderColor%(0, 0, 0, 1%)",
    "default border still uses the compatibility setter")

print("action_bar_lightweight_backdrop_test.lua: ok")
