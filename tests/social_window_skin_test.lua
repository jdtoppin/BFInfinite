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

local function assertPoint(region, message, ...)
    local expected = {...}
    local actual = region.point or {}
    assertEqual(#actual, #expected, message .. " argument count")
    for index = 1, #expected do
        assertEqual(actual[index], expected[index],
            message .. " argument " .. index)
    end
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then
            return nil
        elseif name == targetName then
            return value
        end
        index = index + 1
    end
end

local function makeAlphaRegion()
    local region = {}
    function region:SetAlpha(alpha)
        self.alpha = alpha
    end
    return region
end

local function makeFlatTexture()
    local texture = makeAlphaRegion()
    function texture:SetColorTexture(...)
        self.color = {...}
    end
    function texture:SetTexCoord(...)
        self.texCoord = {...}
    end
    function texture:SetBlendMode(blendMode)
        self.blendMode = blendMode
    end
    return texture
end

local function makeFontString(owner, name, layer)
    local fontString = {
        layer = layer,
        name = name,
        owner = owner,
    }
    function fontString:SetAlpha(alpha)
        self.alpha = alpha
    end
    function fontString:SetFontObject(fontObject)
        self.fontObject = fontObject
    end
    function fontString:SetText(text)
        self.text = text
    end
    return fontString
end

local function makeTab(name)
    local tab = {
        Icon = {},
        name = name,
        scripts = {},
    }

    function tab:SetChecked()
        self.nativeCheckedCalls = (self.nativeCheckedCalls or 0) + 1
    end

    function tab:RefreshIconAnchoring()
        self.Icon.point = {"NATIVE"}
    end

    function tab:HookScript(script, callback)
        self.scripts[script] = callback
    end

    function tab:IsEnabled()
        return true
    end

    return tab
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

local startupCallback
local addonCallbacks = {}
local textScaleRegistration
local titledFrameCalls = {}
local titleBarInfoButtonCalls = {}

local AF = {}

function AF.RegisterCallback(event, callback)
    assertEqual(event, "BFI_StyleBlizzard", "startup callback event")
    startupCallback = callback
end

function AF.RegisterAddonLoaded(addon, callback)
    addonCallbacks[addon] = callback
end

function AF.GetColorRGB(_, alpha)
    return 0.1, 0.2, 0.3, alpha or 1
end

function AF.SetSize(region, width, height)
    region.width = width
    region.height = height
end

function AF.ClearPoints(region)
    region.point = nil
end

function AF.SetPoint(region, ...)
    region.point = {...}
end

local S = {}

function S.StyleTitledFrame(frame, movableTarget)
    titledFrameCalls[frame] = movableTarget
    frame.BFIBg = frame.BFIBg or {}
    if not frame.BFIHeader then
        local header = {
            createdFontStrings = {},
        }
        function header:CreateFontString(name, layer)
            local fontString = makeFontString(self, name, layer)
            self.createdFontStrings[#self.createdFontStrings + 1] = fontString
            return fontString
        end
        frame.BFIHeader = header
    end
end

function S.StyleTitleBarInfoButton(frame, button)
    titleBarInfoButtonCalls[#titleBarInfoButtonCalls + 1] = {
        button = button,
        frame = frame,
    }
    AF.SetSize(button, 20, 20)
end

function S.StyleDropdownButton()
end

function S.StyleEditBox()
end

function S.StyleButton()
end

function S.StyleSideTab(tab, width, height)
    -- Mirror StyleSideTab's shared defaults so this mock exercises whether
    -- FriendsFrame requests the standard World Map-sized side-tab treatment.
    AF.SetSize(tab, width or 35, height or 50)
end

local eventRegistry = {}
function eventRegistry:RegisterCallback(event, callback, owner)
    textScaleRegistration = {
        callback = callback,
        event = event,
        owner = owner,
    }
end

local BFI = {
    modules = {
        Style = S,
    },
}

local environment = {
    AbstractFramework = AF,
    EventRegistry = eventRegistry,
    debug = debug,
    hooksecurefunc = installSecureHook,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    tostring = tostring,
    type = type,
    unpack = unpack,
}
environment._G = environment
environment.ADD_NEW_FRIEND = "Localized Add New Friend"

local chunk, loadError = loadfile("Modules/Blizzard/Style/FriendsFrame.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(startupCallback), "function", "startup style callback")
assertEqual(type(addonCallbacks.Blizzard_AddFriend), "function",
    "Add Friend addon callback")

local styleSocialUI = findUpvalue(startupCallback, "StyleSocialUI")
assertEqual(type(styleSocialUI), "function", "Social UI style upvalue")
local styleSocialContent = findUpvalue(styleSocialUI, "StyleSocialContent")
assertEqual(type(styleSocialContent), "function", "Social content style upvalue")

-- The filter starts with Blizzard's mismatched 30px/20px heights.
local dropdown = {
    height = 30,
}
function dropdown:GetHeight()
    return self.height
end
function dropdown:SetHeight(height)
    self.height = height
end

local searchBar = {
    height = 20,
}
function searchBar:GetHeight()
    return self.height
end

local filterBar = {
    SearchBar = searchBar,
    SearchFilterDropdown = dropdown,
}
styleSocialContent({FilterBar = filterBar})

assertEqual(dropdown:GetHeight(), searchBar:GetHeight(),
    "initial Social filter height")
assertEqual(textScaleRegistration.event,
    "TextSizeManager.OnTextScaleUpdated", "text-scale callback event")
assertEqual(textScaleRegistration.owner, filterBar,
    "text-scale callback owner")

-- Simulate TextSizeManager updating both controls in its own iteration order.
searchBar.height = 26
dropdown.height = 34
textScaleRegistration.callback(textScaleRegistration.owner)
assertEqual(dropdown:GetHeight(), searchBar:GetHeight(),
    "scaled Social filter height")

local firstTab = makeTab("Contacts")
local secondTab = makeTab("Quick Join")
local tabsByType = {
    contacts = firstTab,
    quickJoin = secondTab,
}
local socialFrame = {
    availableTabData = {
        {tabType = "contacts"},
        {tabType = "quickJoin"},
    },
    BattleNetBar = {
        Background = makeAlphaRegion(),
        ControlsContainer = {
            BattleNetBackground = makeFlatTexture(),
        },
    },
    BottomFade = makeAlphaRegion(),
    PortraitContainer = {
        CircleMask = makeAlphaRegion(),
        portrait = makeAlphaRegion(),
    },
    tabDefinitions = {},
    TopFade = makeAlphaRegion(),
}

function socialFrame:GetTabByType(tabType)
    return tabsByType[tabType]
end

function socialFrame:RefreshTabStates()
end

function socialFrame:RefreshTabs()
    for _, tab in pairs(tabsByType) do
        tab.width = 43
        tab.height = 55
        tab.point = {"NATIVE"}
        tab.Icon.width = 30
        tab.Icon.height = 30
        tab.Icon.point = {"NATIVE"}
    end
end

environment.SocialUIFrame = socialFrame
styleSocialUI()

local function assertSocialTabLayout(label)
    assertEqual(firstTab.width, 35, label .. " first-tab width")
    assertEqual(firstTab.height, 50, label .. " first-tab height")
    assertEqual(secondTab.width, 35, label .. " second-tab width")
    assertEqual(secondTab.height, 50, label .. " second-tab height")
    assertEqual(firstTab.Icon.width, 24, label .. " first icon width")
    assertEqual(firstTab.Icon.height, 24, label .. " first icon height")
    assertEqual(secondTab.Icon.width, 24, label .. " second icon width")
    assertEqual(secondTab.Icon.height, 24, label .. " second icon height")
    assertPoint(firstTab.Icon, label .. " first icon point", "CENTER", 0, 0)
    assertPoint(secondTab.Icon, label .. " second icon point", "CENTER", 0, 0)
    assertPoint(firstTab, label .. " first-tab point",
        "TOPLEFT", socialFrame, "TOPRIGHT", 4, -122)
    assertPoint(secondTab, label .. " second-tab point",
        "TOPLEFT", firstTab, "BOTTOMLEFT", 0, -1)
end

assertSocialTabLayout("initial")
assertTrue(socialFrame._BFISocialTabLayoutHooked,
    "Social RefreshTabs hook marker")

-- Native checked/counter/press updates must retain BFI's centered icon while
-- accepting Blizzard's method arguments and dynamic counter offset.
firstTab:SetChecked(true)
assertPoint(firstTab.Icon, "checked icon point", "CENTER", 0, 0)
firstTab.iconBaseYOffset = 5
firstTab:RefreshIconAnchoring()
assertPoint(firstTab.Icon, "counter icon point", "CENTER", 0, 5)
firstTab.scripts.OnMouseDown(firstTab, "LeftButton")
assertPoint(firstTab.Icon, "pressed icon point", "CENTER", 0, 4)
firstTab.scripts.OnMouseUp(firstTab, "LeftButton")
assertPoint(firstTab.Icon, "released icon point", "CENTER", 0, 5)
firstTab.iconBaseYOffset = 0

socialFrame:RefreshTabs()
assertSocialTabLayout("post-RefreshTabs")

local sourceFont = {}
local sourceTitle = {
    fontObject = sourceFont,
    text = "",
}
function sourceTitle:GetFontObject()
    return self.fontObject
end
function sourceTitle:GetText()
    return self.text
end
function sourceTitle:SetAlpha(alpha)
    self.alpha = alpha
end

local infoButton = {}
function infoButton:OnTextScaleUpdated()
    self.nativeTextScaleCalls = (self.nativeTextScaleCalls or 0) + 1
    self.width = 32
    self.height = 32
end

local addFriendFrame = {
    Border = makeAlphaRegion(),
    createdFontStrings = {},
    EntryFrame = {
        TitleContainer = {
            Title = sourceTitle,
        },
    },
}
function addFriendFrame:CreateFontString(name, layer)
    local fontString = makeFontString(self, name, layer)
    self.createdFontStrings[#self.createdFontStrings + 1] = fontString
    return fontString
end

environment.AddFriendFrame = addFriendFrame
environment.AddFriendEntryFrameInfoButton = infoButton
addonCallbacks.Blizzard_AddFriend()

assertTrue(addFriendFrame.BFIHeader, "Add Friend BFI header")
assertTrue(addFriendFrame.Title, "Add Friend root title placeholder")
assertEqual(addFriendFrame.Title.layer, "OVERLAY",
    "Add Friend root title placeholder layer")
assertEqual(addFriendFrame.Title.fontObject, sourceFont,
    "Add Friend root title placeholder font")
assertEqual(addFriendFrame.Title.text, environment.ADD_NEW_FRIEND,
    "Add Friend root title placeholder localized fallback")
assertEqual(addFriendFrame.Title.ignoreInLayout, true,
    "Add Friend root title placeholder excluded from layout")
assertEqual(addFriendFrame.Title.alpha, 0,
    "Add Friend root title placeholder hidden")
assertEqual(addFriendFrame.Title.owner, addFriendFrame,
    "Add Friend root title placeholder owner")

local visibleTitle = addFriendFrame.BFITitleText
assertTrue(visibleTitle, "Add Friend visible header title")
assertEqual(visibleTitle.owner, addFriendFrame.BFIHeader,
    "Add Friend visible title owner")
assertEqual(visibleTitle.layer, "OVERLAY",
    "Add Friend visible title layer")
assertEqual(visibleTitle.fontObject, sourceFont,
    "Add Friend visible title font")
assertEqual(visibleTitle.text, environment.ADD_NEW_FRIEND,
    "Add Friend visible title localized fallback")
assertEqual(visibleTitle.ignoreInLayout, true,
    "Add Friend visible title excluded from layout")
assertTrue(visibleTitle.alpha ~= 0, "Add Friend visible title shown")
assertPoint(visibleTitle, "Add Friend visible title point", "CENTER")
assertEqual(addFriendFrame.BFIBg.ignoreInLayout, true,
    "Add Friend background excluded from layout")
assertEqual(addFriendFrame.BFIHeader.ignoreInLayout, true,
    "Add Friend header excluded from layout")
assertEqual(sourceTitle.alpha, 0, "nested Add Friend title hidden")
assertEqual(sourceTitle.ignoreInLayout, true,
    "nested Add Friend title excluded from content layout")
assertEqual(addFriendFrame.Border.alpha, 0, "native Add Friend border hidden")
assertEqual(titledFrameCalls[addFriendFrame], false,
    "Add Friend retains native positioning")
assertEqual(#titleBarInfoButtonCalls, 1,
    "Add Friend title-bar info-button call count")
assertEqual(titleBarInfoButtonCalls[1].frame, addFriendFrame,
    "Add Friend title-bar info-button frame")
assertEqual(titleBarInfoButtonCalls[1].button,
    environment.AddFriendEntryFrameInfoButton,
    "Add Friend global info-button target")
assertEqual(infoButton.ignoreInLayout, true,
    "Add Friend info button excluded from layout")
assertEqual(infoButton.width, 20, "Add Friend info button initial width")
assertEqual(infoButton.height, 20, "Add Friend info button initial height")
assertEqual(infoButton._BFITitleBarScaleHooked, true,
    "Add Friend info-button text-scale hook marker")

infoButton:OnTextScaleUpdated()
assertEqual(infoButton.nativeTextScaleCalls, 1,
    "Add Friend native info-button text-scale update preserved")
assertEqual(infoButton.width, 20,
    "Add Friend info-button width restored after text scaling")
assertEqual(infoButton.height, 20,
    "Add Friend info-button height restored after text scaling")

print("social_window_skin_test.lua: ok")
