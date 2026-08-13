---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local CreateFrame = CreateFrame
local type = type

local EMPTY_UNIT = "none"

local function IsCleanUnit(unit)
    return F.isValueNonSecret(unit)
        and type(unit) == "string"
        and unit ~= ""
end

local function ResolveUnit(runtime, unit)
    -- Never use `or`, equality, or type on a possibly secret token. If an
    -- explicit or preferred token is secret, fail closed rather than using
    -- fallback state that could preserve the previous unit's presentation.
    if not F.isValueNonSecret(unit) then
        return EMPTY_UNIT
    end
    if type(unit) == "string" then
        return unit ~= "" and unit or EMPTY_UNIT
    end

    unit = runtime.root.effectiveUnit
    if not F.isValueNonSecret(unit) then
        return EMPTY_UNIT
    end
    if type(unit) == "string" then
        return unit ~= "" and unit or EMPTY_UNIT
    end

    unit = runtime.root.unit
    return IsCleanUnit(unit) and unit or EMPTY_UNIT
end

local function SameConstructionKey(left, right)
    return left ~= nil
        and right ~= nil
        and left.appearance == right.appearance
        and left.alpha == right.alpha
        and left.blendMode == right.blendMode
        and left.anchorFrameLevel == right.anchorFrameLevel
end

local function SetPreviewStyle(runtime)
    local preview = runtime._preview
    local config = runtime._descriptor.config
    local texture = preview.texture

    if config.appearance == "bottom_gradient" then
        texture:SetTexture(AF.GetTexture("Gradient_Linear_Bottom"))
    elseif config.appearance == "full_gradient" then
        texture:SetTexture(AF.GetTexture(
            "Gradient_Linear_Vertical_CenterToEdges"
        ))
    else
        texture:SetColorTexture(1, 1, 1, 1)
    end

    local r, g, b = AF.GetColorRGB(
        UF.GetNativeDispelHighlightPreviewColor(config)
    )
    texture:SetVertexColor(r, g, b, 1)
    texture:SetAlpha(config.alpha)
    texture:SetBlendMode(config.blendMode)
end

local function EnsurePreview(runtime)
    if runtime._preview then return runtime._preview end

    local preview = CreateFrame(
        "Frame",
        runtime:GetName() .. "_ConfigPreview",
        runtime.root
    )
    preview:EnableMouse(false)
    preview:SetAllPoints(runtime._anchorTarget)
    AF.SetFrameLevel(preview, 0, runtime._anchorTarget)
    preview.texture = preview:CreateTexture(nil, "ARTWORK", nil, 0)
    preview.texture:SetAllPoints(preview)
    preview:Hide()
    runtime._preview = preview
    return preview
end

local function SyncPreview(runtime)
    local preview = EnsurePreview(runtime)
    if runtime._configMode
        and runtime.enabled
        and runtime._anchorTarget.enabled == true
        and runtime._descriptor
    then
        SetPreviewStyle(runtime)
        preview:Show()
    else
        preview:Hide()
    end
end

local function SyncNative(runtime, refresh, resolvedUnit)
    if not runtime._built then return end

    local unit = resolvedUnit or ResolveUnit(runtime)
    if unit ~= runtime._unit then
        runtime._controller:SetShown(false)
        runtime._unit = unit
        runtime._controller:SetUnit(unit)
    end

    local enabled = runtime._active == true
        and runtime.enabled == true
        and runtime._reloadRequired ~= true
        and unit ~= EMPTY_UNIT
        and runtime._anchorTarget.enabled == true
        and not runtime._configMode
        and not runtime.root.inConfigMode
    runtime._controller:SetEnabled(enabled)
    runtime._controller:SetShown(enabled)
    if enabled and refresh and runtime._controller:IsPresentationApplied() then
        runtime._controller:Refresh()
    end
end

local function Compile(runtime, config)
    return UF.CompileNativeDispelHighlightSpec(
        ResolveUnit(runtime),
        config,
        runtime._anchorTarget,
        runtime._anchorTarget._configuredFrameLevel
    )
end

local function DispelHighlight_LoadConfig(self, config)
    if self._destroyed then return end

    local descriptor = Compile(self, config)
    local wasReloadRequired = self._reloadRequired == true
    local reloadRequired = self._built
        and not SameConstructionKey(
            self._constructionKey,
            descriptor.constructionKey
        )

    self._sourceConfig = AF.Copy(config)
    self._descriptor = descriptor
    self._reloadRequired = reloadRequired or nil

    if reloadRequired then
        self._controller:SetShown(false)
        self._controller:SetEnabled(false)
        SyncPreview(self)
        -- Whole-frame paste/reset and preset application bypass the
        -- indicator-specific preflight in Options. Announce the transition
        -- here as well so a safely quiesced overlay never disappears without
        -- explaining how to apply the construction-owned change.
        if not wasReloadRequired then
            AF.Fire("BFI_NativeAuraReloadRequired")
        end
        return
    end

    if not self._built then
        self._controller:Rebuild(descriptor.completeSpec)
        self._constructionKey = AF.Copy(descriptor.constructionKey)
        self._built = true
    else
        self._controller:ApplyTuning(descriptor.tuning)
    end

    SyncNative(self)
    SyncPreview(self)
end

local function DispelHighlight_Enable(self)
    if self._destroyed then return end
    if self.root.inConfigMode then
        self:EnableConfigMode()
        return
    end

    self._configMode = nil
    self._active = true
    SyncPreview(self)
    SyncNative(self, true)
end

local function DispelHighlight_Disable(self)
    if self._destroyed then return end
    self._active = nil
    SyncNative(self)
    SyncPreview(self)
end

local function DispelHighlight_Update(self, force)
    if self._destroyed or self._configMode or self.root.inConfigMode then
        return
    end
    SyncNative(self, force == true)
end

local function DispelHighlight_SetUnit(self, unit)
    if self._destroyed then return end
    local resolved = ResolveUnit(self, unit)
    SyncNative(self, true, resolved)
end

local function DispelHighlight_EnableConfigMode(self)
    if self._destroyed then return end
    self._active = nil
    self._configMode = true
    SyncNative(self)
    SyncPreview(self)
end

local function DispelHighlight_DisableConfigMode(self)
    if self._destroyed then return end
    self._configMode = nil
    SyncPreview(self)
    SyncNative(self)
end

local function DispelHighlight_RequiresReloadForConfig(self, config)
    if self._destroyed or not self._built or type(config) ~= "table" then
        return false
    end
    return not SameConstructionKey(
        self._constructionKey,
        Compile(self, config).constructionKey
    )
end

local function DispelHighlight_GetState(self)
    return {
        active = self._active == true,
        built = self._built == true,
        configMode = self._configMode == true,
        reloadRequired = self._reloadRequired == true,
        unit = self._unit,
        constructionKey = self._constructionKey
            and AF.Copy(self._constructionKey)
            or nil,
    }
end

local function DispelHighlight_Destroy(self)
    if self._destroyed then return end
    self._destroyed = true
    self._active = nil
    self._configMode = nil
    if self._preview then
        self._preview:Hide()
    end
    self._controller:Destroy()
end

local function CreateUnavailableDispelHighlight(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame.root = parent
    frame:Hide()
    frame.LoadConfig = AF.noop
    frame.Enable = AF.noop
    frame.Disable = AF.noop
    frame.Update = AF.noop
    frame.SetUnit = AF.noop
    frame.EnableConfigMode = AF.noop
    frame.DisableConfigMode = AF.noop
    frame.RequiresReloadForConfig = function()
        return false
    end
    frame.GetNativeDispelState = function()
        return {
            available = false,
            built = false,
        }
    end
    return frame
end

function UF.CreateGroupNativeDispelHighlight(
    parent,
    name,
    containerKey
)
    if not UF.HasNativeAuraContainerBackend() then
        return CreateUnavailableDispelHighlight(parent, name)
    end

    local containers = parent._nativeAuraContainers
    local seedContainer = containers and containers[containerKey]
    assert(seedContainer,
        "native group dispel highlight seed is missing")
    local controller = UF.CreateNativeGroupAuraContainerController(
        parent,
        name,
        seedContainer
    )
    assert(controller,
        "native group dispel highlight controller is unavailable")

    local frame = controller:GetFrame()
    frame.root = parent
    frame._controller = controller
    frame._anchorTarget = parent.indicators.healthBar
    assert(frame._anchorTarget,
        "native group dispel highlight requires a health bar")
    frame.LoadConfig = DispelHighlight_LoadConfig
    frame.Enable = DispelHighlight_Enable
    frame.Disable = DispelHighlight_Disable
    frame.Update = DispelHighlight_Update
    frame.SetUnit = DispelHighlight_SetUnit
    frame.EnableConfigMode = DispelHighlight_EnableConfigMode
    frame.DisableConfigMode = DispelHighlight_DisableConfigMode
    frame.RequiresReloadForConfig =
        DispelHighlight_RequiresReloadForConfig
    frame.GetNativeDispelState = DispelHighlight_GetState
    frame.GetNativeAuraState = DispelHighlight_GetState
    frame.Destroy = DispelHighlight_Destroy
    return frame
end
