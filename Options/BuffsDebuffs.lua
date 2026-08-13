---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local LoadOptions, UpdateStatus
local selected, currentConfig, currentTextConfig

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local SOURCE_DISCLOSURE = L[
    "WoW 12.1's PublicAndPrivate source list combines public and private authorized Buffs in this native row; the sources cannot be separated."
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
    return which == "buffs"
        and BD.GetAuraBackend(which) == BD.CUSTOM_AURA_CONTAINER_BACKEND
end

function BD.GetBuffsDebuffsOptionsPolicy(which)
    local backend = BD.GetAuraBackend(which)
    local custom = IsCustomBuffsBackend(which)
    local customBuffsAvailable = IsCustomBuffsBackend("buffs")
    return {
        available = backend ~= nil,
        backend = backend,
        custom = custom,
        label = which == "debuffs" and customBuffsAvailable
            and L["Debuffs (Blizzard controlled)"]
            or L[which == "buffs" and "Buffs" or "Debuffs"],
        separateOwnItems = {
            {text = L["Disabled"], value = 0},
            {text = L["Before"], value = 1, disabled = custom},
            {text = L["After"], value = -1, disabled = custom},
        },
        constructionOwnedStyle = custom,
        durationColorModes = true,
        sourceDisclosure = custom and SOURCE_DISCLOSURE or nil,
    }
end

function BD.GetBuffsDebuffsOptionsStatus(which)
    local policy = BD.GetBuffsDebuffsOptionsPolicy(which)
    if not policy.custom then return nil end

    local config = BD.config and BD.config[which]
    local state = type(BD.GetCustomAuraContainerState) == "function"
        and BD.GetCustomAuraContainerState(which)
        or nil
    local dispatcherPending =
        type(BD.IsBuffsDebuffsUpdatePending) == "function"
        and BD.IsBuffsDebuffsUpdatePending(which)
    local diagnostic = state and state.diagnostic
    if (config and config.separateOwn ~= 0)
        or diagnostic == "UNSUPPORTED_SEPARATE_OWN"
    then
        return {
            code = "UNSUPPORTED_SEPARATE_OWN",
            action = "RECOVER_SEPARATE_OWN",
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

    local arrangement = AF.CreateDropdown(iconsPane, 210)
    AF.SetPoint(arrangement, "TOPLEFT", iconsPane, "TOPLEFT", 10, -45)
    arrangement:SetLabel(L["Arrangement"])
    arrangement:SetItems(AF.GetDropdownItems_Arrangement_Complex())
    arrangement:SetOnSelect(function(value)
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

    local sourceDisclosure = AF.CreateFontString(
        iconsPane,
        SOURCE_DISCLOSURE,
        "gray"
    )
    normalPane.sourceDisclosure = sourceDisclosure
    AF.SetPoint(sourceDisclosure, "BOTTOMLEFT", 10, 28)
    AF.SetWidth(sourceDisclosure, 530)
    sourceDisclosure:SetWordWrap(true)
    sourceDisclosure:Hide()

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
        currentTextConfig.font[1] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local outline = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(outline, "TOPLEFT", font, "TOPRIGHT", 35, 0)
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetLabel(L["Outline"])
    outline:SetOnSelect(function(value)
        currentTextConfig.font[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local size = AF.CreateSlider(textsPane, L["Size"], 150, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -30)
    size:SetOnValueChanged(function(value)
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.font[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    size:SetAfterValueChanged(function(value)
        if not IsCustomBuffsBackend(selected) then return end
        currentTextConfig.font[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local shadow = AF.CreateCheckButton(textsPane, L["Shadow"])
    AF.SetPoint(shadow, "TOPLEFT", size, "TOPRIGHT", 35, 0)
    shadow:SetOnCheck(function(checked)
        currentTextConfig.font[4] = checked
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local anchorPoint = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(anchorPoint, "TOPLEFT", size, "BOTTOMLEFT", 0, -40)
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    anchorPoint:SetLabel(L["Anchor Point"])
    anchorPoint:SetOnSelect(function(value)
        currentTextConfig.position[1] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local relativePoint = AF.CreateDropdown(textsPane, 150)
    AF.SetPoint(relativePoint, "TOPLEFT", anchorPoint, "TOPRIGHT", 35, 0)
    relativePoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    relativePoint:SetLabel(L["Relative Point"])
    relativePoint:SetOnSelect(function(value)
        currentTextConfig.position[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local xOffset = AF.CreateSlider(textsPane, L["X Offset"], 150, -100, 100, 1, nil, true)
    AF.SetPoint(xOffset, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -30)
    xOffset:SetOnValueChanged(function(value)
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    xOffset:SetAfterValueChanged(function(value)
        if not IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local yOffset = AF.CreateSlider(textsPane, L["Y Offset"], 150, -100, 100, 1, nil, true)
    AF.SetPoint(yOffset, "TOPLEFT", xOffset, "TOPRIGHT", 35, 0)
    yOffset:SetOnValueChanged(function(value)
        if IsCustomBuffsBackend(selected) then return end
        currentTextConfig.position[4] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    yOffset:SetAfterValueChanged(function(value)
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
        if IsCustomBuffsBackend(selected) then return end
        local mode = GetDurationColorMode(currentTextConfig)
        local rule = currentTextConfig.color[mode]
        if type(rule) ~= "table" then return end
        rule.rgb[1], rule.rgb[2], rule.rgb[3] = r, g, b
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    lowTimeColor:SetOnConfirm(function(r, g, b)
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
        AF.SetEnabled(currentConfig.enabled, enabled)
        AF.SetEnabled(currentConfig.enabled and currentTextConfig.enabled, font, size, outline, shadow, anchorPoint, relativePoint, xOffset, yOffset, normalColor)
        textsPane.UpdateDurationWidgets()
    end

    function textsPane.UpdateDurationWidgets()
        local isDuration = textSwitch:GetSelectedValue() == "duration"
        local mode = isDuration and GetDurationColorMode(currentTextConfig)
            or "off"
        local enabledForDuration = isDuration
            and currentConfig.enabled
            and currentTextConfig.enabled

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
        textsPane.UpdateDurationWidgets()
    end

    function normalPane.Load()
        currentConfig = BD.config[selected]
        local policy = BD.GetBuffsDebuffsOptionsPolicy(selected)

        -- icons
        AF.SetEnabled(currentConfig.enabled, arrangement, sortMethod, sortDirection, width, height, spacingX, spacingY, maxWraps, wrapAfter)
        AF.SetEnabled(policy.custom or currentConfig.enabled, separateOwn)
        separateOwn:SetItems(policy.separateOwnItems)
        sourceDisclosure:SetShown(policy.sourceDisclosure ~= nil)
        arrangement:SetSelectedValue(currentConfig.orientation)
        sortMethod:SetSelectedValue(currentConfig.sortMethod)
        sortDirection:SetSelectedValue(currentConfig.sortDirection)
        separateOwn:SetSelectedValue(currentConfig.separateOwn)
        width:SetValue(currentConfig.width)
        height:SetValue(currentConfig.height)
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

UpdateStatus = function()
    if not normalPane then return end
    local status = BD.GetBuffsDebuffsOptionsStatus(selected)
    local statusText = normalPane.statusText
    local statusButton = normalPane.statusButton
    statusButton:SetOnClick(nil)

    if not status then
        statusText:Hide()
        statusButton:Hide()
        return
    end

    if status.code == "UNSUPPORTED_SEPARATE_OWN" then
        statusText:SetText(L[
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
        statusText:SetText(L[
            "Reload UI to apply Buffs styling. Blizzard Buffs remain active."
        ])
        statusButton:SetText(L["Reload UI"])
        statusButton:SetOnClick(_G.ReloadUI)
        statusButton:Show()
    elseif status.code == "PENDING_SAFE_UPDATE" then
        AF.SetWidth(statusText, 530)
        statusText:SetText(L[
            "Buffs update is waiting for combat to end."
        ])
        statusButton:Hide()
    else
        AF.SetWidth(statusText, 530)
        statusText:SetText(L[
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
    if not selected or not BD.HasAuraBackend(selected) then return end

    normalPane:Show()
    normalPane.Load()

    AF.ClearPoints(buffsDebuffsPanel.enabled)
    AF.SetPoint(buffsDebuffsPanel.enabled, "LEFT", buffsDebuffsPanel.switch:GetSelectedButton(), "LEFT", 3, 0)
    buffsDebuffsPanel.enabled:SetChecked(BD.config[selected].enabled)

    AF.ClearPoints(buffsDebuffsPanel.reset)
    AF.SetPoint(buffsDebuffsPanel.reset, "RIGHT", buffsDebuffsPanel.switch:GetSelectedButton(), "RIGHT", -3, 0)

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
            local firstAvailable = BD.HasAuraBackend("buffs") and "buffs"
                or (BD.HasAuraBackend("debuffs") and "debuffs")
            if firstAvailable then
                buffsDebuffsPanel.switch:SetSelectedValue(firstAvailable)
            end
        end
        buffsDebuffsPanel:Show()
    elseif buffsDebuffsPanel then
        buffsDebuffsPanel:Hide()
    end
end)
