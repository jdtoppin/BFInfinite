local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertPoint(actual, expected, message)
    assertEqual(#actual, #expected, message .. " argument count")
    for index = 1, #expected do
        assertEqual(actual[index], expected[index],
            message .. " argument " .. index)
    end
end

local function installSecureHook(target, method, hook)
    local original = target[method]
    assertEqual(type(original), "function", method .. " hook target")
    target[method] = function(...)
        local results = {original(...)}
        hook(...)
        return unpack(results)
    end
end

local function makeHighlight()
    local highlight = {
        points = {},
    }

    function highlight:ClearAllPoints()
        self.clearCount = (self.clearCount or 0) + 1
        self.points = {}
    end

    function highlight:SetBlendMode(blendMode)
        self.blendMode = blendMode
    end

    function highlight:SetColorTexture(...)
        self.color = {...}
    end

    function highlight:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    return highlight
end

local function makeFrame(width, children, left)
    local frame = {
        children = children or {},
        effectiveScale = 1,
        highlight = makeHighlight(),
        includeInLayout = true,
        left = left or 0,
        width = width,
    }

    function frame:GetChildren()
        return unpack(self.children)
    end

    function frame:GetWidth()
        return self.width
    end

    function frame:GetLeft()
        self.getLeftCount = (self.getLeftCount or 0) + 1
        return self.left
    end

    function frame:GetEffectiveScale()
        return self.effectiveScale
    end

    function frame:GetRight()
        self.getRightCount = (self.getRightCount or 0) + 1
        return self.left + self.width
    end

    return frame
end

local function makeMenu(width, children, left)
    local menu = makeFrame(width, children, left or 100)
    menu.ScrollBox = {
        shown = false,
    }
    function menu.ScrollBox:IsShown()
        return self.shown
    end

    function menu:GetInset()
        return {
            bottom = 15,
            left = 8,
            right = 8,
            top = 8,
        }
    end

    function menu:Layout()
    end

    return menu
end

local startupCallback
local acquiredCallback
local currentMenu
local onePixel = 1
local secretValues = setmetatable({}, {__mode = "k"})
local secretCheckCounts = setmetatable({}, {__mode = "k"})

local function makeSecretValue()
    local value = {}
    secretValues[value] = true
    return value
end

local function assertSecretChecked(value, message)
    assertEqual((secretCheckCounts[value] or 0) > 0, true, message)
end

local AF = {}

function AF.ClearPoints(region)
    region.points = {}
end

function AF.GetButtonHoverColor(name)
    assertEqual(name, "BFI_transparent", "hover color name")
    return {0.1, 0.2, 0.3, 0.6}
end

function AF.GetColorRGB()
    return 0.1, 0.2, 0.3, 0.9
end

function AF.GetNearestPixelSize(size, scale)
    assertEqual(size, 1, "nearest pixel size")
    assertEqual(secretValues[scale], nil, "nearest pixel public scale")
    return onePixel
end

function AF.RegisterCallback(event, callback)
    assertEqual(event, "BFI_StyleBlizzard", "startup callback event")
    startupCallback = callback
end

function AF.SetPoint(region, ...)
    region.points[#region.points + 1] = {...}
end

function AF.SetSize()
end

function AF.UnpackColor(color)
    return unpack(color)
end

local S = {}

function S.CreateBackdrop(menu)
    menu.BFIBackdrop = {
        points = {},
    }
    function menu.BFIBackdrop:SetBackdropColor(...)
        self.color = {...}
    end
end

function S.RemoveTextures()
end

local manager = {}

function manager:GetOpenMenu()
    return currentMenu
end

function manager:OpenContextMenu()
end

function manager:OpenMenu()
end

local MenuVariants = {}

function MenuVariants.CreateCheckbox()
end

function MenuVariants.CreateHighlight(frame)
    return frame.highlight
end

local Menu = {}

function Menu.GetManager()
    return manager
end

local BFI = {
    funcs = {
        isValueNonSecret = function(value)
            if secretValues[value] then
                secretCheckCounts[value] = (secretCheckCounts[value] or 0) + 1
                return false
            end
            return true
        end,
    },
    modules = {
        Style = S,
    },
}

local environment = {
    AbstractFramework = AF,
    Menu = Menu,
    MenuVariants = MenuVariants,
    abs = math.abs,
    hooksecurefunc = installSecureHook,
    max = math.max,
    next = next,
    select = select,
    setmetatable = setmetatable,
    tostring = tostring,
    type = type,
    unpack = unpack,
}
environment._G = environment

local chunk, loadError = loadfile("Modules/Blizzard/Style/Menu.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(startupCallback), "function", "startup style callback")
startupCallback()

local description = {}
function description:AddMenuAcquiredCallback(callback)
    acquiredCallback = callback
end

-- The generic highlight hook keeps the AF color and ordinary alpha blend.
local row = makeFrame(80, nil, 108)
local widerRow = makeFrame(110, nil, 108)
MenuVariants.CreateHighlight(row)
MenuVariants.CreateHighlight(widerRow)
assertPoint(row.highlight.color, {0.1, 0.2, 0.3, 0.6},
    "highlight color")
assertEqual(row.highlight.blendMode, "BLEND", "highlight blend mode")

-- A content-sized radio row can end well before the 140px MenuStyle1 shell.
-- Its highlight should fill both actual gaps and stop one physical pixel
-- inside BFI's backdrop.
currentMenu = makeMenu(140, {row, widerRow})
manager:OpenMenu(nil, description)
assertEqual(row.highlight.clearCount, 1, "single-column highlight reset")
assertPoint(row.highlight.points[1],
    {"TOPLEFT", row, "TOPLEFT", -7, 0}, "single-column top-left")
assertPoint(row.highlight.points[2],
    {"BOTTOMRIGHT", row, "BOTTOMRIGHT", 51, 0},
    "single-column bottom-right")
assertPoint(widerRow.highlight.points[1],
    {"TOPLEFT", widerRow, "TOPLEFT", -7, 0},
    "wider single-column top-left")
assertPoint(widerRow.highlight.points[2],
    {"BOTTOMRIGHT", widerRow, "BOTTOMRIGHT", 21, 0},
    "wider single-column bottom-right")

-- Submenus are acquired before their children are laid out. The menu Layout
-- hook must apply the same geometry once the final row width is available.
local submenu = makeMenu(1, {})
acquiredCallback(submenu)
local submenuRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(submenuRow)
submenu.width = 140
submenu.children = {submenuRow}
submenu:Layout()
assertEqual(submenuRow.highlight.clearCount, 1,
    "submenu highlight reset after layout")
assertPoint(submenuRow.highlight.points[1],
    {"TOPLEFT", submenuRow, "TOPLEFT", -7, 0}, "submenu top-left")
assertPoint(submenuRow.highlight.points[2],
    {"BOTTOMRIGHT", submenuRow, "BOTTOMRIGHT", 51, 0},
    "submenu bottom-right")

-- Blizzard reuses pooled menu proxies. The original Layout hook must still
-- style a later acquisition even though the backdrop sentinel already exists.
submenu.width = 1
submenu.children = {}
acquiredCallback(submenu)
local reusedSubmenuRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(reusedSubmenuRow)
submenu.width = 140
submenu.children = {reusedSubmenuRow}
submenu:Layout()
assertEqual(reusedSubmenuRow.highlight.clearCount, 1,
    "reused submenu highlight reset after layout")

-- The border gap is based on a physical pixel rather than a fixed UI unit.
onePixel = 0.5
local scaledRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(scaledRow)
currentMenu = makeMenu(140, {scaledRow})
manager:OpenMenu(nil, description)
assertPoint(scaledRow.highlight.points[1],
    {"TOPLEFT", scaledRow, "TOPLEFT", -7.5, 0}, "scaled top-left")
assertPoint(scaledRow.highlight.points[2],
    {"BOTTOMRIGHT", scaledRow, "BOTTOMRIGHT", 51.5, 0},
    "scaled bottom-right")
onePixel = 1

-- Different row left edges identify grid columns. Active scroll layouts are
-- also left native to avoid overlap with adjacent cells and scrollbars.
local gridRow1 = makeFrame(54, nil, 108)
local gridRow2 = makeFrame(54, nil, 170)
MenuVariants.CreateHighlight(gridRow1)
currentMenu = makeMenu(140, {gridRow1, gridRow2})
manager:OpenMenu(nil, description)
assertEqual(gridRow1.highlight.clearCount, nil, "first grid highlight anchors")
assertEqual(gridRow2.highlight.clearCount, nil, "unstyled grid cell anchors")

local oversizedRow = makeFrame(144, nil, 98)
MenuVariants.CreateHighlight(oversizedRow)
currentMenu = makeMenu(140, {oversizedRow})
manager:OpenMenu(nil, description)
assertEqual(oversizedRow.highlight.clearCount, nil,
    "oversized highlight anchors")

local scrollRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(scrollRow)
currentMenu = makeMenu(140, {scrollRow})
currentMenu.ScrollBox.shown = true
manager:OpenMenu(nil, description)
assertEqual(scrollRow.highlight.clearCount, nil, "scroll highlight anchors")
assertEqual(currentMenu.getLeftCount, nil, "scroll menu left reads")
assertEqual(currentMenu.getRightCount, nil, "scroll menu right reads")

-- Secret-capable region values must be rejected before Lua inspects or uses
-- them. This keeps the global menu hook safe for protected 12.1 surfaces.
local secretShownRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretShownRow)
currentMenu = makeMenu(140, {secretShownRow})
local secretShown = makeSecretValue()
currentMenu.ScrollBox.shown = secretShown
manager:OpenMenu(nil, description)
assertEqual(secretShownRow.highlight.clearCount, nil,
    "secret scroll visibility anchors")
assertSecretChecked(secretShown, "secret scroll visibility check")
assertEqual(currentMenu.getLeftCount, nil, "secret scroll menu left reads")
assertEqual(currentMenu.getRightCount, nil, "secret scroll menu right reads")

local secretMenuLeftRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretMenuLeftRow)
currentMenu = makeMenu(140, {secretMenuLeftRow})
local secretMenuLeft = makeSecretValue()
function currentMenu:GetLeft()
    return secretMenuLeft
end
manager:OpenMenu(nil, description)
assertEqual(secretMenuLeftRow.highlight.clearCount, nil,
    "secret menu left anchors")
assertSecretChecked(secretMenuLeft, "secret menu left check")

local secretMenuRightRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretMenuRightRow)
currentMenu = makeMenu(140, {secretMenuRightRow})
local secretMenuRight = makeSecretValue()
function currentMenu:GetRight()
    return secretMenuRight
end
manager:OpenMenu(nil, description)
assertEqual(secretMenuRightRow.highlight.clearCount, nil,
    "secret menu right anchors")
assertSecretChecked(secretMenuRight, "secret menu right check")

local secretScaleRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretScaleRow)
currentMenu = makeMenu(140, {secretScaleRow})
local secretScale = makeSecretValue()
currentMenu.effectiveScale = secretScale
manager:OpenMenu(nil, description)
assertEqual(secretScaleRow.highlight.clearCount, nil,
    "secret menu scale anchors")
assertSecretChecked(secretScale, "secret menu scale check")

local secretRowLeft = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretRowLeft)
local secretLeft = makeSecretValue()
function secretRowLeft:GetLeft()
    return secretLeft
end
currentMenu = makeMenu(140, {secretRowLeft})
manager:OpenMenu(nil, description)
assertEqual(secretRowLeft.highlight.clearCount, nil,
    "secret row left anchors")
assertSecretChecked(secretLeft, "secret row left check")

local secretRowRight = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(secretRowRight)
local secretRight = makeSecretValue()
function secretRowRight:GetRight()
    return secretRight
end
currentMenu = makeMenu(140, {secretRowRight})
manager:OpenMenu(nil, description)
assertEqual(secretRowRight.highlight.clearCount, nil,
    "secret row right anchors")
assertSecretChecked(secretRight, "secret row right check")

-- Validate every eligible row before changing any texture anchors. If one
-- row exposes secret geometry, earlier rows in the menu stay native too.
local publicBeforeSecretRow = makeFrame(80, nil, 108)
local laterSecretRow = makeFrame(80, nil, 108)
MenuVariants.CreateHighlight(publicBeforeSecretRow)
MenuVariants.CreateHighlight(laterSecretRow)
local laterSecretRight = makeSecretValue()
function laterSecretRow:GetRight()
    return laterSecretRight
end
currentMenu = makeMenu(140, {publicBeforeSecretRow, laterSecretRow})
manager:OpenMenu(nil, description)
assertEqual(publicBeforeSecretRow.highlight.clearCount, nil,
    "row before secret geometry anchors")
assertEqual(laterSecretRow.highlight.clearCount, nil,
    "later secret geometry anchors")
assertSecretChecked(laterSecretRight, "later secret row right check")

print("menu highlight tests passed")
