---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local LoadOptions, UpdateStatus
local selected, currentConfig, currentTextConfig, currentTextKind, currentPolicy
local InCombatLockdown = InCombatLockdown
local min = math.min

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local SOURCE_DISCLOSURE = L[
    "WoW 12.1's PublicAndPrivate source list combines public and private authorized Buffs in this native row; the sources cannot be separated."
]
local HARMFUL_SOURCE_DISCLOSURE = L[
    "This opt-in replaces Blizzard's ordinary and private Debuffs with one PublicAndPrivate native row. Its finite icon cap is shared; at the cap, either source can displace auras from the other. Deadly Debuffs remain Blizzard controlled."
]

local function GetDurationColorMode(config)
    if type(BD.GetDurationColorMode) == "function" then
        return BD.GetDurationColorMode(config)
    end
    local color = type(config) == "table" and config.color or nil
    if type(color) == "table" then
        if type(color.seconds) == "table"
            and color.seconds.enabled == true
        then
            return "seconds"
        elseif type(color.percent) == "table"
            and color.percent.enabled == true
        then
            return "percent"
        end
    end
    return "off"
end

local function SetDurationColorMode(config, mode)
    if type(BD.SetDurationColorMode) == "function" then
        return BD.SetDurationColorMode(config, mode)
    end
    if type(config) ~= "table"
        or type(config.color) ~= "table"
        or type(config.color.seconds) ~= "table"
        or type(config.color.percent) ~= "table"
    then
        return false
    end
    config.color.seconds.enabled = mode == "seconds"
    config.color.percent.enabled = mode == "percent"
    return true
end

local function IsCustomBuffsBackend(which)
    if which == selected and currentPolicy then
        return currentPolicy.custom == true
    end
    return which == "buffs"
        and BD.GetAuraBackend(which) == BD.CUSTOM_AURA_CONTAINER_BACKEND
end

local function IsBlizzardOwnedDurationControl()
    return currentTextKind == "duration"
        and currentPolicy
        and currentPolicy.blizzardDebuffStyle == true
end

local function GetSharedAuraMoverState()
    local config = BD.config and BD.config.buffs
    if not config
        or config.enabled ~= true
        or type(BD.GetCustomAuraContainerState) ~= "function"
    then
        return nil
    end
    return BD.GetCustomAuraContainerState("buffs")
end

local function IsSharedAuraMoverActive()
    local state = GetSharedAuraMoverState()
    return state ~= nil
        and state.active == true
        and state.nativeFollowerActive == true
end

function BD.GetBuffsDebuffsOptionsPolicy(which)
    local backend = BD.GetAuraBackend(which)
    local custom = backend == BD.CUSTOM_AURA_CONTAINER_BACKEND
    local blizzardDebuffStyle = which == "debuffs"
        and backend == BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    local customBuffsAvailable = false
    if which == "debuffs" and not blizzardDebuffStyle then
        customBuffsAvailable =
            BD.GetAuraBackend("buffs") == BD.CUSTOM_AURA_CONTAINER_BACKEND
    end
    local harmfulOptInAvailable = which == "debuffs"
        and type(BD.HasCustomHarmfulAuraDescriptorCapability) == "function"
        and BD.HasCustomHarmfulAuraDescriptorCapability() == true
        and type(BD.GetCustomAuraContainerState) == "function"
        and BD.GetCustomAuraContainerState("debuffs") ~= nil
    local harmfulOptInRequested = which == "debuffs"
        and type(BD.config) == "table"
        and type(BD.config.debuffs) == "table"
        and BD.config.debuffs.customHarmfulEnabled == true
    return {
        available = backend ~= nil or harmfulOptInAvailable,
        backend = backend,
        blizzardDebuffStyle = blizzardDebuffStyle,
        custom = custom,
        harmfulOptInAvailable = harmfulOptInAvailable,
        harmfulOptInRequested = harmfulOptInRequested,
        label = blizzardDebuffStyle
            and L["Debuffs (appearance only)"]
            or custom and L[which == "buffs"
                and "Buffs (Public + Private)"
                or "Debuffs (Public + Private)"]
            or (which == "debuffs" and customBuffsAvailable
                and L["Debuffs (Blizzard controlled)"]
                or L[which == "buffs" and "Buffs" or "Debuffs"]),
        separateOwnItems = {
            {text = L["Disabled"], value = 0},
            {
                text = L["Before"],
                value = 1,
                disabled = custom or blizzardDebuffStyle,
            },
            {
                text = L["After"],
                value = -1,
                disabled = custom or blizzardDebuffStyle,
            },
        },
        arrangementControls = not blizzardDebuffStyle and not custom,
        constructionOwnedStyle = custom,
        durationColorModes = true,
        durationAppearanceControls = not blizzardDebuffStyle,
        durationEnabledControl = true,
        iconSizeControls = true,
        layoutControls = not blizzardDebuffStyle,
        fixedArrangement = custom and (which == "buffs"
            and "right_to_left_then_up"
            or "right_to_left_then_down") or nil,
        maximumIconSize = blizzardDebuffStyle and 30 or 100,
        separateOwnControl = not blizzardDebuffStyle,
        stackAppearanceControls = true,
        sourceDisclosure = custom and (which == "debuffs"
            and HARMFUL_SOURCE_DISCLOSURE
            or SOURCE_DISCLOSURE) or nil,
    }
end

function BD.GetBuffsDebuffsOptionsStatus(which)
    local policy = which == selected and currentPolicy
        or BD.GetBuffsDebuffsOptionsPolicy(which)
    local dispatcherPending =
        type(BD.IsBuffsDebuffsUpdatePending) == "function"
        and BD.IsBuffsDebuffsUpdatePending(which)
    if policy.harmfulOptInRequested
        and policy.custom ~= true
        and not dispatcherPending
    then
        return {code = "HARMFUL_NATIVE_FALLBACK"}
    end
    if policy.blizzardDebuffStyle then
        local moverState = GetSharedAuraMoverState()
        if dispatcherPending
            or (moverState and moverState.operationPending)
            or (
                moverState
                and moverState.pending
                and moverState.diagnostic
                    ~= "NATIVE_FOLLOWER_REFRESH_FAILED"
            )
        then
            return {code = "PENDING_SAFE_UPDATE"}
        end
        if moverState
            and moverState.diagnostic == "NATIVE_FOLLOWER_REFRESH_FAILED"
        then
            return {code = "NATIVE_FOLLOWER_REFRESH_FAILED"}
        end
        return {
            code = IsSharedAuraMoverActive()
                and "BFI_SHARED_AURA_MOVER"
                or "BLIZZARD_DEBUFF_STYLE",
        }
    end
    if not policy.custom then return nil end

    local config = BD.config and BD.config[which]
    local state = type(BD.GetCustomAuraContainerState) == "function"
        and BD.GetCustomAuraContainerState(which)
        or nil
    local diagnostic = state and state.diagnostic
    local operationPending = dispatcherPending
        or (state and state.operationPending)
    if (config and config.separateOwn ~= 0)
        or diagnostic == "UNSUPPORTED_SEPARATE_OWN"
    then
        return {
            code = "UNSUPPORTED_SEPARATE_OWN",
            action = "RECOVER_SEPARATE_OWN",
        }
    elseif diagnostic == "NATIVE_FOLLOWER_REFRESH_FAILED"
        and operationPending
    then
        return {
            code = "PENDING_SAFE_UPDATE",
        }
    elseif diagnostic == "NATIVE_FOLLOWER_REFRESH_FAILED" then
        return {
            code = "NATIVE_FOLLOWER_REFRESH_FAILED",
        }
    elseif which == "debuffs"
        and state
        and state.active == true
        and diagnostic
        and diagnostic ~= "CONSTRUCTION_CHANGE_REQUIRES_RELOAD"
    then
        return {
            code = "HARMFUL_ACTIVE_RECOVERY_FAILED",
        }
    elseif diagnostic
        and diagnostic ~= "CONSTRUCTION_CHANGE_REQUIRES_RELOAD"
    then
        return {
            code = "NATIVE_FALLBACK",
        }
    elseif state and state.reloadRequired then
        return {
            code = "RELOAD_REQUIRED",
            action = "RELOAD_UI",
        }
    elseif dispatcherPending or (state and state.pending) then
        return {
            code = "PENDING_SAFE_UPDATE",
        }
    elseif IsSharedAuraMoverActive() then
        return {
            code = "BFI_SHARED_AURA_MOVER",
        }
    end
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local buffsDebuffsPanel

local function CreateBuffsDebuffsPanel()
    buffsDebuffsPanel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_BuffsDebuffsPanel")
    buffsDebuffsPanel:SetAllPoints()
    AF.ApplyCombatProtectionToFrame(buffsDebuffsPanel)

    local switch = AF.CreateSwitch(buffsDebuffsPanel, nil, 20)
    buffsDebuffsPanel.switch = switch
    AF.SetPoint(switch, "TOPLEFT", 15, -15)
    AF.SetPoint(switch, "TOPRIGHT", -15, -15)
    local buffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("buffs")
    local debuffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    buffsDebuffsPanel.initialAvailable = buffsPolicy.available and "buffs"
        or (debuffsPolicy.available and "debuffs")
    switch:SetLabels({
        {
            text = buffsPolicy.label,
            value = "buffs",
            disabled = not buffsPolicy.available,
        },
        {
            text = debuffsPolicy.label,
            value = "debuffs",
            disabled = not debuffsPolicy.available,
        },
    })
    if buffsPolicy.sourceDisclosure then
        switch.buttons[1]:SetTooltip(buffsPolicy.sourceDisclosure)
    end
    if debuffsPolicy.sourceDisclosure then
        switch.buttons[2]:SetTooltip(debuffsPolicy.sourceDisclosure)
    end
    switch:SetOnSelect(LoadOptions)

    local enabled = AF.CreateCheckButton(switch)
    buffsDebuffsPanel.enabled = enabled
    AF.SetFrameLevel(enabled, 5)
    enabled.accentColor = "softlime"
    enabled.checkedTexture:SetColorTexture(AF.GetColorRGB(enabled.accentColor, 0.7))
    enabled.highlightTexture:SetColorTexture(AF.GetColorRGB(enabled.accentColor, 0.1))
    enabled:SetOnCheck(function(checked)
        BD.config[selected].enabled = checked
        LoadOptions()
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local reset = AF.CreateIconButton(switch, AF.GetIcon("Erase"), 15, 15, nil, "gray", "white")
    buffsDebuffsPanel.reset = reset
    AF.SetFrameLevel(reset, 5)
    reset:SetOnClick(function()
        local dialog = AF.GetDialog(buffsDebuffsPanel,
            AF.WrapTextInColor(L["Reset to default settings?"], "BFI") .. "\n"
            .. switch:GetSelectedButton():GetText()
        )
        AF.SetPoint(dialog, "TOP", 0, -55)
        dialog:SetOnConfirm(function()
            BD.ResetToDefaults(selected)
            LoadOptions()
            AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
        end)
    end)
end

---------------------------------------------------------------------
-- normal
---------------------------------------------------------------------
local normalPane

local function CreateNormalPane()
    normalPane = AF.CreateFrame(buffsDebuffsPanel)
    AF.SetPoint(normalPane, "TOPLEFT", buffsDebuffsPanel.switch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(normalPane, "BOTTOMRIGHT", -15, 15)

    --------------------------------------------------
    -- iconsPane
    --------------------------------------------------
    local iconsPane = AF.CreateTitledPane(normalPane, L["Icons"], nil, 260)
    AF.SetPoint(iconsPane, "TOPLEFT", 0, -5)
    AF.SetPoint(iconsPane, "TOPRIGHT", 0, -5)

    local harmfulOptIn = AF.CreateCheckButton(
        iconsPane,
        L["Use combined native Debuffs row"]
    )
    normalPane.harmfulOptIn = harmfulOptIn
    AF.SetPoint(harmfulOptIn, "TOPRIGHT", -10, -42)
    harmfulOptIn:SetTooltip(HARMFUL_SOURCE_DISCLOSURE)
    harmfulOptIn:SetOnCheck(function(checked)
        if selected ~= "debuffs"
            or not currentPolicy
            or currentPolicy.harmfulOptInAvailable ~= true
        then
            return
        end
        BD.config.debuffs.customHarmfulEnabled = checked == true
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", "debuffs")
        LoadOptions()
    end)

    local arrangement = AF.CreateDropdown(iconsPane, 210)
    AF.SetPoint(arrangement, "TOPLEFT", iconsPane, "TOPLEFT", 10, -45)
    arrangement:SetLabel(L["Arrangement"])
    arrangement:SetItems(AF.GetDropdownItems_Arrangement_Complex())
    arrangement:SetOnSelect(function(value)
        if currentPolicy
            and currentPolicy.arrangementControls ~= true
        then
            return
        end
        currentConfig.orientation = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local sortMethod = AF.CreateDropdown(iconsPane, 150)
    AF.SetPoint(sortMethod, "TOPLEFT", arrangement, "BOTTOMLEFT", 0, -30)
    sortMethod:SetLabel(L["Sort Method"])
    sortMethod:SetItems({
        {text = L["Aura Order"], value = "INDEX"},
        {text = L["Name"], value = "NAME"},
        {text = L["Expiration Time"], value = "TIME"},
    })
    sortMethod:SetOnSelect(function(value)
        currentConfig.sortMethod = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local sortDirection = AF.CreateDropdown(iconsPane, 150)
    AF.SetPoint(sortDirection, "TOPLEFT", sortMethod, "TOPRIGHT", 35, 0)
    sortDirection:SetLabel(L["Sort Direction"])
    sortDirection:SetItems({
        {text = L["Ascending"], value = "+"},
        {text = L["Descending"], value = "-"},
    })
    sortDirection:SetOnSelect(function(value)
        currentConfig.sortDirection = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local separateOwn = AF.CreateDropdown(iconsPane, 150)
    AF.SetPoint(separateOwn, "TOPLEFT", sortDirection, "TOPRIGHT", 35, 0)
    separateOwn:SetLabel(L["Separate Own"])
    separateOwn:SetOnSelect(function(value)
        currentConfig.separateOwn = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local width = AF.CreateSlider(iconsPane, L["Width"], 150, 10, 100, nil, nil, true)
    AF.SetPoint(width, "TOPLEFT", sortMethod, "BOTTOMLEFT", 0, -30)
    width:SetOnValueChanged(function(value)
        if IsCustomBuffsBackend(selected) then return end
        currentConfig.width = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    width:SetAfterValueChanged(function(value)
        if not IsCustomBuffsBackend(selected) then return end
        currentConfig.width = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local height = AF.CreateSlider(iconsPane, L["Height"], 150, 10, 100, nil, nil, true)
    AF.SetPoint(height, "TOPLEFT", width, "BOTTOMLEFT", 0, -45)
    height:SetOnValueChanged(function(value)
        if IsCustomBuffsBackend(selected) then return end
        currentConfig.height = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    height:SetAfterValueChanged(function(value)
        if not IsCustomBuffsBackend(selected) then return end
        currentConfig.height = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local spacingX = AF.CreateSlider(iconsPane, L["X Spacing"], 150, -1, 50, 1, nil, true)
    AF.SetPoint(spacingX, "TOPLEFT", width, "TOPRIGHT", 35, 0)
    spacingX:SetOnValueChanged(function(value)
        currentConfig.spacingX = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local spacingY = AF.CreateSlider(iconsPane, L["Y Spacing"], 150, -1, 50, 1, nil, true)
    AF.SetPoint(spacingY, "TOPLEFT", height, "TOPRIGHT", 35, 0)
    spacingY:SetOnValueChanged(function(value)
        currentConfig.spacingY = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local maxWraps = AF.CreateSlider(iconsPane, L["Aura Lines"], 150, 1, 50, 1, nil, true)
    AF.SetPoint(maxWraps, "TOPLEFT", spacingX, "TOPRIGHT", 35, 0)
    maxWraps:SetOnValueChanged(function(value)
        currentConfig.maxWraps = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local wrapAfter = AF.CreateSlider(iconsPane, L["Icons Per Line"], 150, 1, 50, 1, nil, true)
    AF.SetPoint(wrapAfter, "TOPLEFT", spacingY, "TOPRIGHT", 35, 0)
    wrapAfter:SetOnValueChanged(function(value)
        currentConfig.wrapAfter = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    local enchantmentCapHelp = L[
        "Temporary Main-Hand and Off-Hand enchants share this layout and may add up to two icons beyond the aura cap."
    ]
    maxWraps:SetTooltip(enchantmentCapHelp)
    wrapAfter:SetTooltip(enchantmentCapHelp)

    local statusText = AF.CreateFontString(
        iconsPane,
        nil,
        "firebrick",
        "AF_FONT_SMALL"
    )
    normalPane.statusText = statusText
    AF.SetPoint(statusText, "BOTTOMLEFT", 10, 7)
    AF.SetWidth(statusText, 350)
    statusText:SetWordWrap(false)
    statusText:Hide()

    local statusButton = AF.CreateButton(
        iconsPane,
        nil,
        "BFI_hover",
        165,
        20
    )
    normalPane.statusButton = statusButton
    AF.SetPoint(statusButton, "BOTTOMRIGHT", -10, 5)
    statusButton:Hide()

    --------------------------------------------------
    -- textsPane
    --------------------------------------------------
    local textsPane = AF.CreateTitledPane(normalPane, L["Texts"], nil, 235)
    AF.SetPoint(textsPane, "TOPLEFT", iconsPane, "BOTTOMLEFT", 0, -5)
    AF.SetPoint(textsPane, "TOPRIGHT", iconsPane, "BOTTOMRIGHT", 0, -5)

    local textSwitch = AF.CreateSwitch(textsPane, 210, 20)
    AF.SetPoint(textSwitch, "BOTTOMRIGHT", textsPane.line, "BOTTOMRIGHT", 0, -1)
    textSwitch:SetLabels({
        {text = L["Stack Text"], value = "stack"},
        {text = L["Duration Text"], value = "duration"},
    })
    textSwitch:SetOnSelect(function()
        textsPane.Load(textSwitch:GetSelectedValue())
    end)

    local font = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(font, "TOPLEFT", 10, -45)
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetLabel(L["Font"])
    font:SetOnSelect(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        currentTextConfig.font[1] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local outline = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(outline, "TOPLEFT", font, "TOPRIGHT", 35, 0)
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetLabel(L["Outline"])
    outline:SetOnSelect(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        currentTextConfig.font[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local size = AF.CreateSlider(textsPane, L["Size"], 150, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -30)
    size:SetOnValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.font[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    size:SetAfterValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if not IsCustomBuffsBackend(selected) then return end
        currentTextConfig.font[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local shadow = AF.CreateCheckButton(textsPane, L["Shadow"])
    AF.SetPoint(shadow, "TOPLEFT", size, "TOPRIGHT", 35, 0)
    shadow:SetOnCheck(function(checked)
        if IsBlizzardOwnedDurationControl() then return end
        currentTextConfig.font[4] = checked
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local anchorPoint = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(anchorPoint, "TOPLEFT", size, "BOTTOMLEFT", 0, -40)
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    anchorPoint:SetLabel(L["Anchor Point"])
    anchorPoint:SetOnSelect(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        currentTextConfig.position[1] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local relativePoint = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(relativePoint, "TOPLEFT", anchorPoint, "TOPRIGHT", 35, 0)
    relativePoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    relativePoint:SetLabel(L["Relative Point"])
    relativePoint:SetOnSelect(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        currentTextConfig.position[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local xOffset = AF.CreateSlider(textsPane, L["X Offset"], 150, -100, 100, 1, nil, true)
    AF.SetPoint(xOffset, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -30)
    xOffset:SetOnValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    xOffset:SetAfterValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if not IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local yOffset = AF.CreateSlider(textsPane, L["Y Offset"], 150, -100, 100, 1, nil, true)
    AF.SetPoint(yOffset, "TOPLEFT", xOffset, "TOPRIGHT", 35, 0)
    yOffset:SetOnValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[4] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    yOffset:SetAfterValueChanged(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if not IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[4] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local enabled = AF.CreateCheckButton(textsPane, L["Enabled"])
    AF.SetPoint(enabled, "TOPLEFT", outline, "TOPRIGHT", 35, 0)
    enabled:SetOnCheck(function(checked)
        currentTextConfig.enabled = checked
        textsPane.UpdateWidgets()
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local normalColor = AF.CreateColorPicker(textsPane, L["Normal"])
    AF.SetPoint(normalColor, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -15)
    normalColor:SetOnChange(function(r, g, b)
        if IsBlizzardOwnedDurationControl() then return end
        if IsCustomBuffsBackend(selected) then return end
        if textSwitch:GetSelectedValue() == "stack" then
            currentTextConfig.color[1] = r
            currentTextConfig.color[2] = g
            currentTextConfig.color[3] = b
        else
            currentTextConfig.color.normal[1] = r
            currentTextConfig.color.normal[2] = g
            currentTextConfig.color.normal[3] = b
        end
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    normalColor:SetOnConfirm(function(r, g, b)
        if IsBlizzardOwnedDurationControl() then return end
        if not IsCustomBuffsBackend(selected) then return end
        if textSwitch:GetSelectedValue() == "stack" then
            currentTextConfig.color[1] = r
            currentTextConfig.color[2] = g
            currentTextConfig.color[3] = b
        else
            currentTextConfig.color.normal[1] = r
            currentTextConfig.color.normal[2] = g
            currentTextConfig.color.normal[3] = b
        end
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local durationMode = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(durationMode, "TOPLEFT", normalColor, "BOTTOMLEFT", 0, -30)
    durationMode:SetLabel(L["Low-Time Text Color"])
    durationMode:SetItems({
        {text = L["Seconds"], value = "seconds"},
        {text = L["Percent"], value = "percent"},
        {text = L["Off"], value = "off"},
    })
    durationMode:SetOnSelect(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        if not SetDurationColorMode(currentTextConfig, value) then return end
        textsPane.UpdateDurationWidgets()
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local secondsValue = AF.CreateEditBox(
        textsPane,
        L["Seconds"],
        150,
        20,
        "decimal"
    )
    AF.SetPoint(secondsValue, "TOPLEFT", durationMode, "BOTTOMLEFT", 0, -30)
    secondsValue:SetLabelAlt(L["Seconds"])
    secondsValue:SetMaxLetters(12)
    secondsValue:SetConfirmButton(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        value = tonumber(value)
        if not IsFiniteNumber(value) or value <= 0 then
            secondsValue:SetText(currentTextConfig.color.seconds.value)
            return
        end
        currentTextConfig.color.seconds.value = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end, nil, "RIGHT_OUTSIDE")
    secondsValue:SetOnEditFocusLost(function(self)
        self:SetText(currentTextConfig.color.seconds.value)
    end)

    local percentValue = AF.CreateEditBox(
        textsPane,
        L["Percent"],
        150,
        20,
        "decimal"
    )
    AF.SetPoint(percentValue, "TOPLEFT", durationMode, "BOTTOMLEFT", 0, -30)
    percentValue:SetLabelAlt(L["Percent"])
    percentValue:SetMaxLetters(12)
    percentValue:SetConfirmButton(function(value)
        if IsBlizzardOwnedDurationControl() then return end
        value = tonumber(value)
        if not IsFiniteNumber(value) or value <= 0 or value >= 100 then
            percentValue:SetText(currentTextConfig.color.percent.value * 100)
            return
        end
        currentTextConfig.color.percent.value = value / 100
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end, nil, "RIGHT_OUTSIDE")
    percentValue:SetOnEditFocusLost(function(self)
        self:SetText(currentTextConfig.color.percent.value * 100)
    end)

    local lowTimeColor = AF.CreateColorPicker(textsPane, L["Low-Time Color"])
    AF.SetPoint(lowTimeColor, "TOPLEFT", secondsValue, "BOTTOMLEFT", 0, -15)
    lowTimeColor:SetOnChange(function(r, g, b)
        if IsBlizzardOwnedDurationControl() then return end
        if IsCustomBuffsBackend(selected) then return end
        local mode = GetDurationColorMode(currentTextConfig)
        local rule = currentTextConfig.color[mode]
        if type(rule) ~= "table" then return end
        rule.rgb[1], rule.rgb[2], rule.rgb[3] = r, g, b
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    lowTimeColor:SetOnConfirm(function(r, g, b)
        if IsBlizzardOwnedDurationControl() then return end
        if not IsCustomBuffsBackend(selected) then return end
        local mode = GetDurationColorMode(currentTextConfig)
        local rule = currentTextConfig.color[mode]
        if type(rule) ~= "table" then return end
        rule.rgb[1], rule.rgb[2], rule.rgb[3] = r, g, b
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    durationMode:SetTooltip(L[
        "Durations abbreviate automatically to seconds, minutes, hours, and days."
    ])

    --------------------------------------------------
    -- load
    --------------------------------------------------
    function textsPane.UpdateWidgets()
        local appearanceControls = currentConfig.enabled
            and currentTextConfig.enabled
            and (
                currentTextKind ~= "duration"
                or currentPolicy.durationAppearanceControls
            )
        AF.SetEnabled(currentConfig.enabled, enabled)
        AF.SetEnabled(
            appearanceControls,
            font,
            size,
            outline,
            shadow,
            anchorPoint,
            relativePoint,
            xOffset,
            yOffset,
            normalColor
        )
        textsPane.UpdateDurationWidgets()
    end

    function textsPane.UpdateDurationWidgets()
        local isDuration = textSwitch:GetSelectedValue() == "duration"
        local mode = isDuration and GetDurationColorMode(currentTextConfig)
            or "off"
        local enabledForDuration = isDuration
            and currentConfig.enabled
            and currentTextConfig.enabled
            and currentPolicy.durationAppearanceControls

        durationMode:SetShown(isDuration)
        secondsValue:SetShown(isDuration and mode == "seconds")
        percentValue:SetShown(isDuration and mode == "percent")
        lowTimeColor:SetShown(isDuration and mode ~= "off")
        if mode == "seconds" or mode == "percent" then
            lowTimeColor:SetColor(currentTextConfig.color[mode].rgb)
        else
            lowTimeColor:SetColor(1, 1, 1, 1)
        end
        AF.SetEnabled(enabledForDuration, durationMode)
        AF.SetEnabled(
            enabledForDuration and mode == "seconds",
            secondsValue
        )
        AF.SetEnabled(
            enabledForDuration and mode == "percent",
            percentValue
        )
        AF.SetEnabled(enabledForDuration and mode ~= "off", lowTimeColor)
    end

    function textsPane.Load(which)
        currentTextKind = which
        currentTextConfig = BD.config[selected][which]

        textsPane.UpdateWidgets()
        enabled:SetChecked(currentTextConfig.enabled)

        font:SetSelectedValue(currentTextConfig.font[1])
        size:SetValue(currentTextConfig.font[2])
        outline:SetSelectedValue(currentTextConfig.font[3])
        shadow:SetChecked(currentTextConfig.font[4])
        anchorPoint:SetSelectedValue(currentTextConfig.position[1])
        relativePoint:SetSelectedValue(currentTextConfig.position[2])
        xOffset:SetValue(currentTextConfig.position[3])
        yOffset:SetValue(currentTextConfig.position[4])

        if which == "stack" then
            normalColor:SetColor(currentTextConfig.color)
            durationMode:SetSelectedValue("off")
            secondsValue:SetText(5)
            percentValue:SetText(50)
            lowTimeColor:SetColor(1, 1, 1, 1)
        else
            normalColor:SetColor(currentTextConfig.color.normal)
            local mode = GetDurationColorMode(currentTextConfig)
            durationMode:SetSelectedValue(mode)
            secondsValue:SetText(currentTextConfig.color.seconds.value)
            percentValue:SetText(
                currentTextConfig.color.percent.value * 100
            )
            if mode == "seconds" or mode == "percent" then
                lowTimeColor:SetColor(currentTextConfig.color[mode].rgb)
            else
                lowTimeColor:SetColor(1, 1, 1, 1)
            end
        end
        durationMode:SetTooltip(
            currentPolicy.blizzardDebuffStyle
                and L[
                    "Blizzard supplies and abbreviates Debuff durations. BFInfinite can only show or hide this text."
                ]
                or L[
                    "Durations abbreviate automatically to seconds, minutes, hours, and days."
                ]
        )
        textsPane.UpdateDurationWidgets()
    end

    function normalPane.Load()
        currentConfig = BD.config[selected]
        local policy = currentPolicy

        harmfulOptIn:SetShown(
            selected == "debuffs" and policy.harmfulOptInAvailable == true
        )
        harmfulOptIn:SetChecked(
            selected == "debuffs"
                and currentConfig.customHarmfulEnabled == true
        )
        AF.SetEnabled(policy.harmfulOptInAvailable == true, harmfulOptIn)

        -- icons
        local layoutEnabled = currentConfig.enabled
            and policy.layoutControls
        AF.SetEnabled(
            currentConfig.enabled and policy.arrangementControls,
            arrangement
        )
        AF.SetEnabled(
            layoutEnabled,
            sortMethod,
            sortDirection,
            spacingX,
            spacingY,
            maxWraps,
            wrapAfter
        )
        AF.SetEnabled(
            currentConfig.enabled and policy.iconSizeControls,
            width,
            height
        )
        AF.SetEnabled(
            currentConfig.enabled and policy.separateOwnControl,
            separateOwn
        )
        width:SetMinMaxValues(10, policy.maximumIconSize)
        height:SetMinMaxValues(10, policy.maximumIconSize)
        separateOwn:SetItems(policy.separateOwnItems)
        arrangement:SetSelectedValue(
            policy.fixedArrangement or currentConfig.orientation
        )
        sortMethod:SetSelectedValue(currentConfig.sortMethod)
        sortDirection:SetSelectedValue(currentConfig.sortDirection)
        separateOwn:SetSelectedValue(currentConfig.separateOwn)
        -- Imported values above the fixed Blizzard cell remain saved. Clamp
        -- only the presentation until the user commits a supported value.
        width:SetValue(min(currentConfig.width, policy.maximumIconSize))
        height:SetValue(min(currentConfig.height, policy.maximumIconSize))
        spacingX:SetValue(currentConfig.spacingX)
        spacingY:SetValue(currentConfig.spacingY)
        maxWraps:SetValue(currentConfig.maxWraps)
        wrapAfter:SetValue(currentConfig.wrapAfter)

        -- texts
        if not textSwitch:GetSelectedValue() then
            textSwitch:SetSelectedValue("stack")
        end
        textsPane.Load(textSwitch:GetSelectedValue())
        UpdateStatus()
    end
end

local function OpenBFIEditMode()
    if InCombatLockdown() then return end
    local optionsFrame = _G.BFIOptionsFrame
    if optionsFrame then optionsFrame:Hide() end
    BFI.funcs.PrepareEditModePositions()
    AF.ShowMovers()
end

UpdateStatus = function()
    if not normalPane then return end
    local status = BD.GetBuffsDebuffsOptionsStatus(selected)
    local statusText = normalPane.statusText
    local statusButton = normalPane.statusButton
    statusButton:SetOnClick(nil)
    statusText:SetWordWrap(false)

    if not status then
        statusText:Hide()
        statusButton:Hide()
        return
    end

    if status.code == "UNSUPPORTED_SEPARATE_OWN" then
        statusText:SetText(selected == "debuffs"
            and L[
                "Separate Own is unavailable in 12.1. Blizzard Debuffs remain active."
            ]
            or L[
                "Separate Own is unavailable in 12.1. Blizzard Buffs remain active."
            ])
        statusButton:SetText(L["Use supported sorting"])
        statusButton:SetOnClick(function()
            local config = BD.config and BD.config[selected]
            if not config then return end
            config.separateOwn = 0
            AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
            LoadOptions()
        end)
        statusButton:Show()
    elseif status.code == "RELOAD_REQUIRED" then
        statusText:SetText(selected == "debuffs"
            and L[
                "Reload UI to apply Debuffs styling. Blizzard Debuffs remain active."
            ]
            or L[
                "Reload UI to apply Buffs styling. Blizzard Buffs remain active."
            ])
        statusButton:SetText(L["Reload UI"])
        statusButton:SetOnClick(_G.ReloadUI)
        statusButton:Show()
    elseif status.code == "PENDING_SAFE_UPDATE" then
        AF.SetWidth(statusText, 530)
        statusText:SetText(
            selected == "debuffs"
                and L["Debuffs styling is waiting for combat to end."]
                or L["Buffs update is waiting for combat to end."]
        )
        statusButton:Hide()
    elseif status.code == "NATIVE_FOLLOWER_REFRESH_FAILED" then
        AF.SetWidth(statusText, 530)
        statusText:SetWordWrap(true)
        statusText:SetText(L[
            "The shared DebuffFrame attachment could not be refreshed. The current safe layout remains in place while native frame access recovers."
        ])
        statusButton:Hide()
    elseif status.code == "BFI_SHARED_AURA_MOVER" then
        AF.SetWidth(statusText, 350)
        statusText:SetWordWrap(true)
        statusText:SetText(L[
            "The BFI Buff Frame mover positions the combined Buffs row and Blizzard's DebuffFrame root together. Movement is unavailable in combat."
        ])
        statusButton:SetText(L["Open BFI Edit Mode"])
        statusButton:SetOnClick(OpenBFIEditMode)
        statusButton:Show()
    elseif status.code == "BLIZZARD_DEBUFF_STYLE" then
        AF.SetWidth(statusText, 530)
        statusText:SetWordWrap(true)
        statusText:SetText(L[
            "BFInfinite styles ordinary Debuffs only. Blizzard controls their layout and duration text; private and deadly debuffs are unchanged."
        ])
        statusButton:Hide()
    elseif status.code == "HARMFUL_NATIVE_FALLBACK" then
        AF.SetWidth(statusText, 530)
        statusText:SetWordWrap(true)
        statusText:SetText(L[
            "The combined Debuffs row is opted in, but its native private-aura boundary is not currently available. Blizzard Debuffs remain active."
        ])
        statusButton:Hide()
    elseif status.code == "HARMFUL_ACTIVE_RECOVERY_FAILED" then
        AF.SetWidth(statusText, 530)
        statusText:SetWordWrap(true)
        statusText:SetText(L[
            "The combined Debuffs row remains active while native suppression recovery is pending."
        ])
        statusButton:Hide()
    else
        AF.SetWidth(statusText, 530)
        statusText:SetText(selected == "debuffs"
            and L[
                "Blizzard Debuffs remain active because the combined native replacement could not be applied."
            ]
            or L[
                "Blizzard Buffs remain active because the native replacement could not be applied."
            ])
        statusButton:Hide()
    end
    if statusButton:IsShown() then
        AF.SetWidth(statusText, 350)
    end
    statusText:Show()
end

---------------------------------------------------------------------
-- load
---------------------------------------------------------------------
LoadOptions = function()
    selected = buffsDebuffsPanel.switch:GetSelectedValue()
    if not selected then return end
    currentPolicy = BD.GetBuffsDebuffsOptionsPolicy(selected)
    if not currentPolicy.available then return end
    local selectedButton = buffsDebuffsPanel.switch:GetSelectedButton()
    if currentPolicy.sourceDisclosure then
        selectedButton:SetTooltip(currentPolicy.sourceDisclosure)
    end

    normalPane:Show()
    normalPane.Load()

    AF.ClearPoints(buffsDebuffsPanel.enabled)
    AF.SetPoint(buffsDebuffsPanel.enabled, "LEFT", selectedButton, "LEFT", 3, 0)
    buffsDebuffsPanel.enabled:SetChecked(BD.config[selected].enabled)

    AF.ClearPoints(buffsDebuffsPanel.reset)
    AF.SetPoint(buffsDebuffsPanel.reset, "RIGHT", selectedButton, "RIGHT", -3, 0)

    for _, b in next, buffsDebuffsPanel.switch.buttons do
        if b:IsEnabled() then
            if BD.config[b.value].enabled then
                b.text:SetTextColor(1, 1, 1)
            else
                b.text:SetTextColor(AF.GetColorRGB("firebrick"))
            end
        end
    end
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "buffsDebuffs" or not buffsDebuffsPanel then return end
    LoadOptions()
end)

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "buffsDebuffs" then
        if not buffsDebuffsPanel then
            CreateBuffsDebuffsPanel()
            CreateNormalPane()
            local firstAvailable = buffsDebuffsPanel.initialAvailable
            if firstAvailable then
                buffsDebuffsPanel.switch:SetSelectedValue(firstAvailable)
            end
        end
        buffsDebuffsPanel:Show()
    elseif buffsDebuffsPanel then
        buffsDebuffsPanel:Hide()
    end
end)
