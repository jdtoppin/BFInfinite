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

local function makeFontString()
    return {
        SetShadowColor = function() end,
        SetTextColor = function() end,
    }
end

local function makeRegion()
    return {
        textures = {},
    }
end

local inCombat = false
local callbacks = {}
local moverCalls = {}
local proxy
local secretValue = {}

local UIParent = {
    GetEffectiveScale = function()
        return 2
    end,
}

local afUIParent = {
    GetEffectiveScale = function()
        return 1
    end,
}

local systemInfo = {
    anchorInfo = {
        point = "BOTTOM",
        relativeTo = "UIParent",
        relativePoint = "BOTTOM",
        offsetX = 0,
        offsetY = 45,
    },
    settings = {},
    isInDefaultPosition = true,
}

local manager = {
    activeLayoutInfo = {
        layoutType = 1,
    },
    systemInfo = systemInfo,
}

function manager:IsInitialized()
    return true
end

function manager:GetActiveLayoutInfo()
    return self.activeLayoutInfo
end

function manager:IsShown()
    return self.shown
end

function manager:IsEditModeActive()
    return self.editModeActive
end

function manager:GetActiveLayoutSystemInfo(system, systemIndex)
    self.lastSystem = system
    self.lastSystemIndex = systemIndex
    return self.systemInfo
end

function manager:SaveLayouts()
    self.saveCalls = (self.saveCalls or 0) + 1
end

function manager:CanEnterEditMode()
    return self.canEnterEditMode ~= false
end

function manager:SelectSystem(selectedFrame)
    self.selectedSystem = selectedFrame
end

function manager:EnterEditMode()
    self.editModeActive = true
end

function manager:ExitEditMode()
    self.editModeActive = nil
    self.shown = nil
end

local name = makeFontString()
local text = makeFontString()
local mainFrame = makeRegion()
mainFrame.Model = makeRegion()
mainFrame.Overlay = makeRegion()
mainFrame.CloseButton = {}

local frame = {
    BackgroundFrame = makeRegion(),
    MainFrame = mainFrame,
    NameFrame = {Name = name},
    PortraitFrame = makeRegion(),
    TextFrame = {Text = text},
    system = 42,
}

function frame:GetWidth()
    if systemInfo.isInDefaultPosition then
        error("default preview must not read managed frame width")
    end
    return 570
end

function frame:GetHeight()
    if systemInfo.isInDefaultPosition then
        error("default preview must not read managed frame height")
    end
    return 155
end

function frame:GetEffectiveScale()
    if systemInfo.isInDefaultPosition then
        error("default preview must not read managed frame scale")
    end
    return 3
end

function frame:IsInitialized()
    return true
end

function frame:UpdateSystem(info)
    self.updateSystemCalls = (self.updateSystemCalls or 0) + 1
    self.updatedSystemInfo = info
end

function frame:ClearAllPoints()
    self.clearPointCalls = (self.clearPointCalls or 0) + 1
end

function frame:SetPoint()
    self.setPointCalls = (self.setPointCalls or 0) + 1
end

function frame:FadeinFrames()
end

function frame:FadeoutFrames()
end

function frame:PlayCurrent()
end

function frame:UpdateShownState()
end

local function CreateFrame()
    proxy = {}

    function proxy:Hide()
        self.hidden = true
    end

    function proxy:RegisterEvent(event)
        self.event = event
    end

    function proxy:SetScript(script, callback)
        self[script] = callback
    end

    function proxy:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function proxy:ClearAllPoints()
        self.clearPointCalls = (self.clearPointCalls or 0) + 1
        self.point = nil
    end

    function proxy:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = {point, relativeTo, relativePoint, x, y}
    end

    function proxy:GetPoint()
        if not self.point then return end
        return self.point[1], self.point[2], self.point[3], self.point[4], self.point[5]
    end

    return proxy
end

local AF = {
    UIParent = afUIParent,
}

function AF.ClearPoints(region)
    region:ClearAllPoints()
    region._points = {}
end

function AF.SetPoint(region, point, relativeTo, relativePoint, x, y)
    region:SetPoint(point, relativeTo, relativePoint, x, y)
    region._points = {
        [point] = {point, relativeTo, relativePoint, x, y},
    }
end

function AF.RoundToDecimal(num, decimalPlaces)
    local multiplier = 10 ^ decimalPlaces
    return math.floor(num * multiplier + 0.5) / multiplier
end

function AF.CreateMover(owner, group, textLabel, save)
    local mover = {
        owner = owner,
    }
    function mover:Hide()
        self.hideCalls = (self.hideCalls or 0) + 1
    end
    function mover:Show()
        if self.action then return end
        if not self._original then
            local point, _, _, x, y = self.owner:GetPoint()
            self._original = {
                point,
                AF.RoundToDecimal(x, 1),
                AF.RoundToDecimal(y, 1),
            }
        end
    end
    owner.mover = mover
    moverCalls[#moverCalls + 1] = {
        group = group,
        mover = mover,
        owner = owner,
        save = save,
        text = textLabel,
    }
end

function AF.SetMoverAction(owner, action, actionText)
    owner.mover.action = action
    owner.mover.actionText = actionText
    owner.mover._original = nil
end

function AF.HideMovers()
    AF.hideMoversCalls = (AF.hideMoversCalls or 0) + 1
end

function AF.CreateFadeInOutAnimation()
end

function AF.GetColorRGB()
    return 1, 1, 1, 1
end

function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end

function AF.SetFontShadow()
end

local S = {}

function S.CreateBackdrop(region)
    region.BFIBackdrop = {}
end

function S.RemoveTextures()
end

function S.StyleCloseButton()
end

local BFI = {
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secretValue
        end,
    },
    modules = {
        Style = S,
    },
}

local environment = {
    AbstractFramework = AF,
    CreateFrame = CreateFrame,
    Enum = {
        EditModeLayoutType = {
            Account = 1,
            Character = 2,
            Override = 3,
            Preset = 4,
        },
        EditModeSystem = {
            TalkingHeadFrame = 42,
        },
    },
    InCombatLockdown = function()
        return inCombat
    end,
    ShowUIPanel = function(target)
        target.showUIPanelCalls = (target.showUIPanelCalls or 0) + 1
        target.shown = true
        target:EnterEditMode()
    end,
    UIParent = UIParent,
    hooksecurefunc = function(target, method, hook)
        local original = target[method]
        target[method] = function(...)
            original(...)
            hook(...)
        end
    end,
    math = math,
    select = select,
    type = type,
}
environment._G = environment
environment.EditModeManagerFrame = manager
environment.HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL = "Talking Head"
environment.HUD_EDIT_MODE_MENU = "HUD Edit Mode"
environment.OTHER = "Other"
environment.TalkingHeadFrame = frame

local chunk, loadError = loadfile("Modules/Blizzard/Style/TalkingHeadFrame.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

callbacks.BFI_StyleBlizzard()
assertEqual(#moverCalls, 1, "BFI proxy mover registered")
assertEqual(moverCalls[1].owner, proxy, "native frame is not the mover owner")
assertEqual(moverCalls[1].group, "BFI: Other", "mover group")
assertEqual(moverCalls[1].text, "Talking Head", "mover label")
assertEqual(proxy.event, "EDIT_MODE_LAYOUTS_UPDATED", "native layout resync event")
assertEqual(proxy.width, 1, "proxy has an inert fallback width")
assertEqual(proxy.height, 1, "proxy has an inert fallback height")
assertEqual(proxy.point[1], "CENTER", "proxy is anchored before mover registration")
assertEqual(proxy.point[2], afUIParent, "fallback uses AF parent")
assertEqual(proxy.point[3], "CENTER", "fallback uses matching relative point")
assertEqual(proxy.point[4], 0, "fallback x")
assertEqual(proxy.point[5], 0, "fallback y")
moverCalls[1].mover:Show()
assertEqual(moverCalls[1].mover._original[1], "CENTER", "generic mover can capture fallback point")
assertEqual(moverCalls[1].mover._original[2], 0, "generic mover can capture fallback x")
assertEqual(moverCalls[1].mover._original[3], 0, "generic mover can capture fallback y")
moverCalls[1].mover._original = nil

callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "managed default position has a BFI action entry")
assertEqual(proxy.width, 300, "default action has a compact width")
assertEqual(proxy.height, 40, "default action has a compact height")
assertEqual(proxy.point[1], "BOTTOM", "default action is anchored at the screen bottom")
assertEqual(proxy.point[2], afUIParent, "default action is anchored to AF parent")
assertEqual(proxy.point[3], "BOTTOM", "default action uses matching relative point")
assertEqual(proxy.point[4], 0, "default action is centered")
assertEqual(proxy.point[5], 180, "default action sits above the action bar")
assertEqual(type(proxy.mover.action), "function", "default action opens Blizzard HUD Edit Mode")
assertEqual(proxy.mover.actionText, "Talking Head — HUD Edit Mode", "default action has a clear handoff label")
moverCalls[1].mover:Show()
assertEqual(moverCalls[1].mover._original, nil, "action entry does not create an undo snapshot")

proxy.mover.action(proxy)
assertEqual(AF.hideMoversCalls, 1, "handoff closes BFI Edit Mode")
assertEqual(manager.showUIPanelCalls, 1, "handoff opens Blizzard HUD Edit Mode")
assertEqual(manager.selectedSystem, frame, "handoff selects Blizzard's Talking Head system")
assertTrue(manager.editModeActive, "handoff enters native Edit Mode")
assertTrue(not proxy.enabled, "native Edit Mode hides the BFI action entry")
assertEqual(frame.updateSystemCalls, nil, "handoff does not update the native frame")
assertEqual(manager.saveCalls, nil, "handoff does not save a native layout")
manager:ExitEditMode()
assertTrue(proxy.enabled, "exiting native Edit Mode restores the BFI action entry")

manager.canEnterEditMode = false
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "unavailable native Edit Mode hides the action entry")
assertEqual(proxy.mover.action, nil, "unavailable native Edit Mode clears the action callback")
manager.canEnterEditMode = nil

callbacks.BFI_PrepareEditModePositions()
manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Preset
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "preset layouts show the native handoff action")
assertEqual(type(proxy.mover.action), "function", "preset layouts remain native-owned")
local presetUpdateCalls = frame.updateSystemCalls
local presetSaveCalls = manager.saveCalls
proxy.mover.action(proxy)
assertEqual(frame.updateSystemCalls, presetUpdateCalls, "preset handoff does not update the native frame")
assertEqual(manager.saveCalls, presetSaveCalls, "preset handoff does not save a native layout")
manager:ExitEditMode()

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Override
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "override layouts show the native handoff action")
assertEqual(type(proxy.mover.action), "function", "override layouts remain native-owned")

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Account
systemInfo.isInDefaultPosition = false
systemInfo.anchorInfo.offsetX = 10
systemInfo.anchorInfo.offsetY = 20
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "custom native layout enables the proxy mover")
assertEqual(proxy.mover.action, nil, "custom native layout restores normal mover behavior")
assertEqual(proxy.width, 1710, "proxy width preserves screen size")
assertEqual(proxy.height, 465, "proxy height preserves screen size")
assertEqual(proxy.point[1], "BOTTOM", "native anchor point copied to proxy")
assertEqual(proxy.point[2], afUIParent, "proxy is anchored to AF parent")
assertEqual(proxy.point[3], "BOTTOM", "native relative point copied to proxy")
assertEqual(proxy.point[4], 20, "native x is converted to AF mover scale")
assertEqual(proxy.point[5], 40, "native y is converted to AF mover scale")
moverCalls[1].mover:Show()
assertEqual(moverCalls[1].mover._original[1], "BOTTOM", "generic mover captures the native point after sync")
assertEqual(moverCalls[1].mover._original[2], 20, "generic mover captures the native x after sync")
assertEqual(moverCalls[1].mover._original[3], 40, "generic mover captures the native y after sync")

local hideCalls = proxy.mover.hideCalls or 0
manager:EnterEditMode()
assertTrue(not proxy.enabled, "native Edit Mode disables the proxy mover")
assertEqual(proxy.mover.hideCalls, hideCalls + 1, "native Edit Mode hides an open proxy overlay")
manager:ExitEditMode()
assertTrue(proxy.enabled, "exiting native Edit Mode resyncs the proxy mover")

moverCalls[1].save("TOP", 30, -40)
assertEqual(systemInfo.anchorInfo.point, "TOP", "native point saved")
assertEqual(systemInfo.anchorInfo.relativeTo, "UIParent", "native parent preserved")
assertEqual(systemInfo.anchorInfo.relativePoint, "TOP", "native relative point saved")
assertEqual(systemInfo.anchorInfo.offsetX, 15, "AF x converted back to native scale")
assertEqual(systemInfo.anchorInfo.offsetY, -20, "AF y converted back to native scale")
assertTrue(not systemInfo.isInDefaultPosition, "native layout remains custom")
assertEqual(frame.updateSystemCalls, 1, "Blizzard applies its own anchor")
assertEqual(manager.saveCalls, 1, "Blizzard layout is persisted")
assertEqual(frame.clearPointCalls, nil, "bridge never clears the native frame")
assertEqual(frame.setPointCalls, nil, "bridge never anchors the native frame directly")
assertEqual(proxy.point[4], 30, "proxy resyncs after native save")
assertEqual(proxy.point[5], -40, "proxy y resyncs after native save")

systemInfo.anchorInfo.offsetX = -25
systemInfo.anchorInfo.offsetY = 30
proxy.OnEvent(proxy, "EDIT_MODE_LAYOUTS_UPDATED")
assertEqual(proxy.point[4], -50, "layout event refreshes native x")
assertEqual(proxy.point[5], 60, "layout event refreshes native y")

local previousPoint = proxy.point
local clearPointCalls = proxy.clearPointCalls
systemInfo.anchorInfo.offsetX = nil
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "incomplete native anchors fall back to the native handoff action")
assertEqual(type(proxy.mover.action), "function", "incomplete native anchors do not become draggable")
assertTrue(proxy.clearPointCalls > clearPointCalls, "handoff action replaces the stale custom proxy point")
assertTrue(proxy.point ~= previousPoint, "handoff action uses its own stable position")
systemInfo.anchorInfo.offsetX = -25

systemInfo.anchorInfo.offsetY = secretValue
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "secret native anchors fall back to the native handoff action")
assertEqual(type(proxy.mover.action), "function", "secret native anchors do not become draggable")
systemInfo.anchorInfo.offsetY = 30
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "ordinary native anchors restore the proxy")
assertEqual(proxy.mover.action, nil, "ordinary native anchors restore normal mover behavior")

local updateCalls = frame.updateSystemCalls
local saveCalls = manager.saveCalls
moverCalls[1].save("TOP", math.huge, 0)
assertEqual(frame.updateSystemCalls, updateCalls, "invalid mover geometry is not applied")
assertEqual(manager.saveCalls, saveCalls, "invalid mover geometry is not persisted")

systemInfo.anchorInfo.relativeTo = "OtherFrame"
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "non-UIParent native anchors fall back to the native handoff action")
assertEqual(type(proxy.mover.action), "function", "non-UIParent native anchors do not become draggable")
systemInfo.anchorInfo.relativeTo = "UIParent"

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Preset
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "preset layouts remain Blizzard-owned through the handoff action")
moverCalls[1].save("CENTER", 1, 2)
assertEqual(frame.updateSystemCalls, 1, "preset layout is not mutated")
assertEqual(manager.saveCalls, 1, "preset layout is not persisted")

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Override
callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "override layouts remain Blizzard-owned through the handoff action")
moverCalls[1].save("CENTER", 1, 2)
assertEqual(frame.updateSystemCalls, 1, "override layout is not mutated")
assertEqual(manager.saveCalls, 1, "override layout is not persisted")

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Account
frame.isInEditMode = true
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "native Edit Mode owns its active session")

frame.isInEditMode = nil
manager.editModeActive = true
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "locked native Edit Mode owns its active session")

manager.editModeActive = nil
inCombat = true
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "bridge is disabled in combat")

print("talking_head_frame_edit_mode_bridge_test.lua: ok")
