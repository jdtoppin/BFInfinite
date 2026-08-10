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
        offsetX = 10,
        offsetY = 20,
    },
    settings = {},
    isInDefaultPosition = false,
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

function manager:EnterEditMode()
    self.editModeActive = true
end

function manager:ExitEditMode()
    self.editModeActive = nil
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
    return 570
end

function frame:GetHeight()
    return 155
end

function frame:GetEffectiveScale()
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
end

function AF.CreateMover(owner, group, textLabel, save)
    owner.mover = {
        Hide = function(self)
            self.hideCalls = (self.hideCalls or 0) + 1
        end,
    }
    moverCalls[#moverCalls + 1] = {
        group = group,
        owner = owner,
        save = save,
        text = textLabel,
    }
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
    UIParent = UIParent,
    hooksecurefunc = function(target, method, hook)
        local original = target[method]
        target[method] = function(...)
            original(...)
            hook(...)
        end
    end,
    select = select,
    type = type,
}
environment._G = environment
environment.EditModeManagerFrame = manager
environment.HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL = "Talking Head"
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

systemInfo.isInDefaultPosition = true
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "managed default position remains Blizzard-only")
systemInfo.isInDefaultPosition = false

callbacks.BFI_PrepareEditModePositions()
assertTrue(proxy.enabled, "custom native layout enables the proxy mover")
assertEqual(proxy.width, 1710, "proxy width preserves screen size")
assertEqual(proxy.height, 465, "proxy height preserves screen size")
assertEqual(proxy.point[1], "BOTTOM", "native anchor point copied to proxy")
assertEqual(proxy.point[2], afUIParent, "proxy is anchored to AF parent")
assertEqual(proxy.point[3], "BOTTOM", "native relative point copied to proxy")
assertEqual(proxy.point[4], 20, "native x is converted to AF mover scale")
assertEqual(proxy.point[5], 40, "native y is converted to AF mover scale")

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
assertTrue(not systemInfo.isInDefaultPosition, "native layout marked custom")
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

systemInfo.anchorInfo.relativeTo = "OtherFrame"
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "non-UIParent native anchors remain Blizzard-only")
systemInfo.anchorInfo.relativeTo = "UIParent"

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Preset
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "preset layouts remain Blizzard-only")
moverCalls[1].save("CENTER", 1, 2)
assertEqual(frame.updateSystemCalls, 1, "preset layout is not mutated")
assertEqual(manager.saveCalls, 1, "preset layout is not persisted")

manager.activeLayoutInfo.layoutType = environment.Enum.EditModeLayoutType.Override
callbacks.BFI_PrepareEditModePositions()
assertTrue(not proxy.enabled, "override layouts remain Blizzard-only")
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
