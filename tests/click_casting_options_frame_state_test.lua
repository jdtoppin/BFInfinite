local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message, 2) end
end

local function newWidget(kind, parent, name, width, height)
    local widget = {
        kind = kind,
        parent = parent,
        name = name,
        width = width,
        height = height,
        shown = true,
        enabled = true,
        points = {},
        textColorHistory = {},
    }

    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:GetName() return self.name end
    function widget:GetWidth() return self.width or 140 end
    function widget:Hide()
        self.shown = false
        if self.onHide then self.onHide() end
    end
    function widget:IsEnabled() return self.enabled end
    function widget:Raise() self.raised = true end
    function widget:SetAllPoints() self.allPoints = true end
    function widget:SetBackdropColor(...) self.backdropColor = {...} end
    function widget:SetClampRectInsets(...) self.clampInsets = {...} end
    function widget:SetClampedToScreen(value) self.clamped = value end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:SetFrameStrata(value) self.frameStrata = value end
    function widget:SetOnClick(callback) self.onClick = callback end
    function widget:SetOnHide(callback) self.onHide = callback end
    function widget:SetOnMouseWheel(callback) self.onMouseWheel = callback end
    function widget:SetOnShow(callback) self.onShow = callback end
    function widget:SetPoint(...) self.points[#self.points + 1] = {...} end
    function widget:SetTextColor(color)
        self.textColor = color
        self.textColorHistory[#self.textColorHistory + 1] = color
    end
    function widget:SetTextJustifyH(value) self.textJustifyH = value end
    function widget:SetTextPadding(value) self.textPadding = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:SetTooltip(...) self.tooltip = {...} end
    function widget:SetToplevel(value) self.toplevel = value end
    function widget:Show()
        self.shown = true
        if self.onShow then self.onShow() end
    end
    function widget:SilentClick()
        assertTrue(self.groupClick ~= nil, "button is missing its group callback")
        self.groupClick(self, self.id)
    end
    function widget:Toggle()
        if self.shown then self:Hide() else self:Show() end
    end

    return widget
end

local state = {
    buttons = {},
    callbacks = {},
    fires = {},
}
local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
local F = {
    GetModuleLocalizedName = function(name) return name end,
    PrepareEditModePositions = function() end,
    ToggleModuleResetFrame = function() end,
}
local CC = {
    activeConfig = {enabled = false},
}
local BFI = {
    L = L,
    funcs = F,
    modules = {
        ActionBars = {},
        BuffsDebuffs = {
            HasAuraBackend = function() return true end,
        },
        ClickCastings = CC,
    },
    name = "BFInfinite",
}
local AF = {
    isRetail = true,
    noop = function() end,
}

function AF.AnimatedResize(_, _, _, _, _, _, callback)
    if callback then callback() end
end

function AF.ApplyCombatProtectionToWidget() end

function AF.CreateBorderedFrame(parent, name, width, height)
    return newWidget("borderedFrame", parent, name, width, height)
end

function AF.CreateButton(parent, text, _, width, height)
    local button = newWidget("button", parent, nil, width, height)
    button.text = text
    state.buttons[#state.buttons + 1] = button
    return button
end

function AF.CreateButtonGroup(buttons, onClick)
    for _, button in ipairs(buttons) do
        button.groupClick = function(clicked, id)
            for _, other in ipairs(buttons) do
                other.isSelected = other == clicked
            end
            onClick(clicked, id)
        end
    end
end

function AF.CreateCloseButton(parent)
    return newWidget("closeButton", parent)
end

function AF.CreateFontString(parent, text)
    local fontString = newWidget("fontString", parent)
    fontString.text = text
    return fontString
end

function AF.CreateFrame(parent, name, width, height)
    return newWidget("frame", parent, name, width, height)
end

function AF.CreateGlow() end

function AF.CreateGradientTexture(parent)
    return newWidget("gradientTexture", parent)
end

function AF.CreateTexture(parent)
    return newWidget("texture", parent)
end

function AF.Fire(event, ...)
    state.fires[#state.fires + 1] = {event, ...}
    local callbacks = state.callbacks[event]
    if callbacks then
        for _, callback in ipairs(callbacks) do callback(event, ...) end
    end
end

function AF.GetColorRGB(color) return color end
function AF.GetColorTable(color) return color end
function AF.GetComplementColor() return 1, 1, 1 end
function AF.GetIcon(name) return name end
function AF.ReAnchorRegion() end

function AF.RegisterCallback(event, callback)
    state.callbacks[event] = state.callbacks[event] or {}
    state.callbacks[event][#state.callbacks[event] + 1] = callback
end

function AF.ResizeToFitText() end
function AF.SetDraggable() end
function AF.SetHeight(widget, height) widget.height = height end
function AF.SetPoint(widget, ...) widget:SetPoint(...) end
function AF.SetSize(widget, width, height)
    widget.width, widget.height = width, height
end
function AF.SetWidth(widget, width) widget.width = width end
function AF.ShowMovers() end
function AF.WrapTextInColor(text) return text end
function AF.WrapTextInColorRGB(text) return text end

local environment = {
    _G = false,
    AbstractFramework = AF,
    AFParent = newWidget("root"),
    BFIConfig = {
        general = {
            accentColor = {type = "default"},
        },
    },
    HUD_EDIT_MODE_MENU = "Edit Mode",
    LOCALE_zhCN = false,
    RELOADUI = "Reload UI",
    ReloadUI = function() end,
    UISpecialFrames = {},
    ipairs = ipairs,
    next = next,
    select = select,
    string = string,
    tinsert = table.insert,
    tostring = tostring,
    type = type,
}
environment._G = environment

local chunk, loadError = loadfile("Options/OptionsFrame.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local function findOptionButton(id)
    for _, button in ipairs(state.buttons) do
        if button.id == id then return button end
    end
end

-- Profile/module notifications may arrive before the lazy options window is
-- built; they must remain harmless.
AF.Fire("BFI_UpdateProfile")
AF.Fire("BFI_UpdateModule", "clickCastings")

F.ToggleOptionsFrame()
local clickCasting = findOptionButton("clickCastings")
assertTrue(clickCasting ~= nil, "Click Casting navigation button exists")
assertTrue(clickCasting:IsEnabled(),
    "disabled Click Casting remains navigable and editable")
assertEqual(clickCasting.textColor, "disabled",
    "initial disabled profile dims Click Casting navigation text")
assertTrue(F.OpenOptionsFrame("clickCastings"),
    "dimmed Click Casting navigation remains clickable")
assertEqual(state.fires[#state.fires][1], "BFI_ShowOptionsPanel",
    "dimmed Click Casting navigation opens its settings panel")
assertEqual(state.fires[#state.fires][2], "clickCastings",
    "dimmed navigation opens the Click Casting panel")

CC.activeConfig.enabled = true
AF.Fire("BFI_UpdateModule", "clickCastings")
assertEqual(clickCasting.textColor, "white",
    "live enable restores Click Casting navigation text")

CC.activeConfig.enabled = false
local colorWrites = #clickCasting.textColorHistory
AF.Fire("BFI_UpdateModule", "unitFrames")
assertEqual(#clickCasting.textColorHistory, colorWrites,
    "unrelated module updates do not rewrite Click Casting navigation")
assertEqual(clickCasting.textColor, "white",
    "unrelated module updates preserve Click Casting navigation state")

AF.Fire("BFI_UpdateModule", "clickCastings")
assertEqual(clickCasting.textColor, "disabled",
    "live disable dims Click Casting navigation text")

-- Reset publishes a module update after restoring the active class defaults.
CC.activeConfig.enabled = true
AF.Fire("BFI_UpdateModule", "clickCastings")
assertEqual(clickCasting.textColor, "white",
    "module reset restores enabled navigation text")

-- Profile updates replace activeConfig before low-priority option listeners.
CC.activeConfig = {enabled = false}
AF.Fire("BFI_UpdateProfile")
assertEqual(clickCasting.textColor, "disabled",
    "profile replacement refreshes disabled navigation text")

CC.activeConfig = nil
AF.Fire("BFI_UpdateProfile")
assertEqual(clickCasting.textColor, "white",
    "temporarily missing profile config keeps navigation available")

print("click_casting_options_frame_state_test: ok")
