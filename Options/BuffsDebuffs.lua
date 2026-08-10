---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework
local InCombatLockdown = InCombatLockdown
local type = type

local LoadOptions, UpdateStatus
local selected, currentConfig, currentTextConfig, currentTextKind

local function IsCustomAuraBackend(which)
    return BD.GetAuraBackend(which) == BD.CUSTOM_AURA_CONTAINER_BACKEND
end

local function IsBlizzardDebuffStyleBackend(which)
    return which == "debuffs"
        and BD.BLIZZARD_DEBUFF_STYLE_BACKEND ~= nil
        and BD.GetAuraBackend(which)
            == BD.BLIZZARD_DEBUFF_STYLE_BACKEND
end

local function IsSharedAuraMoverActive()
    if not IsCustomAuraBackend("buffs")
        or not BD.config
        or not BD.config.buffs
        or BD.config.buffs.enabled ~= true
        or type(BD.GetCustomAuraContainerState) ~= "function"
    then
        return false
    end

    local state = BD.GetCustomAuraContainerState("buffs")
    return state
        and state.active == true
        and state.nativeFollowerActive == true
end

function BD.GetBuffsDebuffsOptionsPolicy(which)
    local backend = BD.GetAuraBackend(which)
    local custom = IsCustomAuraBackend(which)
    local blizzardDebuffStyle = IsBlizzardDebuffStyleBackend(which)
    local positionOwnedByBFI = custom
    return {
        available = backend ~= nil,
        backend = backend,
        custom = custom,
        blizzardDebuffStyle = blizzardDebuffStyle,
        label = blizzardDebuffStyle
            and L["Debuffs (appearance only)"]
            or L[which == "buffs" and "Buffs" or "Debuffs"],
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
        constructionOwnedStyle = custom,
        fixedArrangement = custom
            and (
                which == "buffs"
                    and "right_to_left_then_up"
                    or "right_to_left_then_down"
            )
            or nil,
        arrangementControls = not blizzardDebuffStyle
            and not positionOwnedByBFI,
        positionOwnedByBFI = positionOwnedByBFI,
        layoutControls = not blizzardDebuffStyle,
        iconSizeControls = true,
        maximumIconSize = blizzardDebuffStyle and 30 or 100,
        durationAppearanceControls = not blizzardDebuffStyle,
        retiredDurationControls = true,
    }
end

function BD.GetBuffsDebuffsOptionsStatus(which)
    local policy = BD.GetBuffsDebuffsOptionsPolicy(which)
    local config = BD.config and BD.config[which]
    local dispatcherPending =
        type(BD.IsBuffsDebuffsUpdatePending) == "function"
        and BD.IsBuffsDebuffsUpdatePending(which)
    if policy.blizzardDebuffStyle then
        if dispatcherPending then
            return {
                code = "PENDING_SAFE_UPDATE",
            }
        end
        return {
            code = IsSharedAuraMoverActive()
                and "BFI_SHARED_AURA_MOVER"
                or "BLIZZARD_DEBUFF_STYLE",
        }
    elseif not policy.custom then
        return nil
    end

    local state = type(BD.GetCustomAuraContainerState) == "function"
        and BD.GetCustomAuraContainerState(which)
        or nil
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
    elseif policy.positionOwnedByBFI
        and config
        and config.enabled == true
        and state
        and state.active == true
    then
        if IsSharedAuraMoverActive() then
            return {
                code = "BFI_SHARED_AURA_MOVER",
            }
        elseif which == "debuffs" then
            return {
                code = "BLIZZARD_DEBUFF_POSITION",
            }
        end
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
        if IsCustomAuraBackend(selected) then return end
        currentConfig.width = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    width:SetAfterValueChanged(function(value)
        if not IsCustomAuraBackend(selected) then return end
        currentConfig.width = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local height = AF.CreateSlider(iconsPane, L["Height"], 150, 10, 100, nil, nil, true)
    AF.SetPoint(height, "TOPLEFT", width, "BOTTOMLEFT", 0, -45)
    height:SetOnValueChanged(function(value)
        if IsCustomAuraBackend(selected) then return end
        currentConfig.height = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    height:SetAfterValueChanged(function(value)
        if not IsCustomAuraBackend(selected) then return end
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
    local combinedDebuffCapHelp = L[
        "Ordinary and private Debuffs share this native row and icon limit."
    ]

    local statusText = AF.CreateFontString(
        iconsPane,
        nil,
        "firebrick",
        "AF_FONT_SMALL"
    )
    normalPane.statusText = statusText
    AF.SetPoint(statusText, "BOTTOMLEFT", 10, 7)
    AF.SetWidth(statusText, 350)
    statusText:SetWordWrap(true)
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
    AF.ApplyCombatProtectionToWidget(statusButton)
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
        if IsCustomAuraBackend(selected) then return end
        currentTextConfig.font[2] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    size:SetAfterValueChanged(function(value)
        if not IsCustomAuraBackend(selected) then return end
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
        if IsCustomAuraBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    xOffset:SetAfterValueChanged(function(value)
        if not IsCustomAuraBackend(selected) then return end
        currentTextConfig.position[3] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)

    local yOffset = AF.CreateSlider(textsPane, L["Y Offset"], 150, -100, 100, 1, nil, true)
    AF.SetPoint(yOffset, "TOPLEFT", xOffset, "TOPRIGHT", 35, 0)
    yOffset:SetOnValueChanged(function(value)
        if IsCustomAuraBackend(selected) then return end
        currentTextConfig.position[4] = value
        AF.Fire("BFI_UpdateModule", "buffsDebuffs", selected)
    end)
    yOffset:SetAfterValueChanged(function(value)
        if not IsCustomAuraBackend(selected) then return end
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
        if IsCustomAuraBackend(selected) then return end
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
        if not IsCustomAuraBackend(selected) then return end
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

    local durationHint = AF.CreateFontString(
        textsPane,
        L[
            "Durations abbreviate automatically to seconds, minutes, hours, and days."
        ],
        "gray"
    )
    AF.SetPoint(durationHint, "TOPLEFT", normalColor, "BOTTOMLEFT", 0, -15)
    AF.SetWidth(durationHint, 160)
    durationHint:SetWordWrap(true)
    durationHint:Hide()

    --------------------------------------------------
    -- load
    --------------------------------------------------
    function textsPane.UpdateWidgets()
        local policy = BD.GetBuffsDebuffsOptionsPolicy(selected)
        local appearanceControls = currentConfig.enabled
            and currentTextConfig.enabled
            and (
                currentTextKind ~= "duration"
                or policy.durationAppearanceControls
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
    end

    function textsPane.Load(which)
        currentTextKind = which
        currentTextConfig = BD.config[selected][which]
        local policy = BD.GetBuffsDebuffsOptionsPolicy(selected)

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
        else
            normalColor:SetColor(currentTextConfig.color.normal)
        end
        durationHint:SetText(
            policy.blizzardDebuffStyle
                and L[
                    "Blizzard supplies and abbreviates Debuff durations. BFInfinite can only show or hide this text."
                ]
                or L[
                    "Durations abbreviate automatically to seconds, minutes, hours, and days."
                ]
        )
        durationHint:SetShown(which == "duration"
            and (
                policy.blizzardDebuffStyle
                or (tonumber(AF.versionNum) or 0) >= 33
            ))
    end

    function normalPane.Load()
        currentConfig = BD.config[selected]
        local policy = BD.GetBuffsDebuffsOptionsPolicy(selected)

        -- icons
        local layoutEnabled = currentConfig.enabled
            and policy.layoutControls
        AF.SetEnabled(
            layoutEnabled and policy.arrangementControls,
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
            not policy.blizzardDebuffStyle
                and (policy.custom or currentConfig.enabled),
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
        width:SetValue(currentConfig.width)
        height:SetValue(currentConfig.height)
        spacingX:SetValue(currentConfig.spacingX)
        spacingY:SetValue(currentConfig.spacingY)
        maxWraps:SetValue(currentConfig.maxWraps)
        wrapAfter:SetValue(currentConfig.wrapAfter)
        local capHelp
        if selected == "debuffs" and policy.custom then
            capHelp = combinedDebuffCapHelp
        elseif selected == "buffs" then
            capHelp = enchantmentCapHelp
        end
        maxWraps:SetTooltip(capHelp)
        wrapAfter:SetTooltip(capHelp)

        -- texts
        if not textSwitch:GetSelectedValue() then
            textSwitch:SetSelectedValue("stack")
        end
        textsPane.Load(textSwitch:GetSelectedValue())
        UpdateStatus()
    end
end

local function OpenBFIEditMode()
    if InCombatLockdown() then
        -- AF owns the localized combat warning and guarantees that no mover
        -- remains interactive when this entry point is blocked.
        AF.ShowMovers()
        return
    end
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
    statusText:SetTextColor(AF.GetColorRGB("firebrick"))

    if not status then
        statusText:Hide()
        statusButton:Hide()
        return
    end

    if status.code == "UNSUPPORTED_SEPARATE_OWN" then
        statusText:SetText(
            selected == "debuffs"
                and L[
                    "Separate Own is unavailable in 12.1. Blizzard Debuffs remain active."
                ]
                or L[
                    "Separate Own is unavailable in 12.1. Blizzard Buffs remain active."
                ]
        )
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
        statusText:SetText(
            selected == "debuffs"
                and L[
                    "Reload UI to apply Debuffs styling. Blizzard Debuffs remain active."
                ]
                or L[
                    "Reload UI to apply Buffs styling. Blizzard Buffs remain active."
                ]
        )
        statusButton:SetText(L["Reload UI"])
        statusButton:SetOnClick(_G.ReloadUI)
        statusButton:Show()
    elseif status.code == "PENDING_SAFE_UPDATE" then
        AF.SetWidth(statusText, 530)
        statusText:SetText(
            selected == "debuffs"
                and L[
                    "Debuffs update will apply when it is safe."
                ]
                or L[
                    "Buffs update is waiting for combat to end."
                ]
        )
        statusButton:Hide()
    elseif status.code == "BFI_SHARED_AURA_MOVER" then
        AF.SetWidth(statusText, 350)
        statusText:SetTextColor(AF.GetColorRGB("gray"))
        statusText:SetText(
            selected == "debuffs" and IsCustomAuraBackend("debuffs")
                and L[
                    "Both rows share the BFI mover. Ordinary and private Debuffs share one native icon limit. Movement is unavailable in combat."
                ]
                or L[
                    "Both rows move together with the BFI Buff Frame mover. Movement is unavailable in combat."
                ]
        )
        statusButton:SetText(L["Open BFI Edit Mode"])
        statusButton:SetOnClick(OpenBFIEditMode)
        statusButton:Show()
    elseif status.code == "BLIZZARD_DEBUFF_POSITION" then
        AF.SetWidth(statusText, 530)
        statusText:SetTextColor(AF.GetColorRGB("gray"))
        statusText:SetText(L[
            "Debuffs follow Blizzard's position until Buffs are enabled. Ordinary and private Debuffs share one native icon limit."
        ])
        statusButton:Hide()
    elseif status.code == "BLIZZARD_DEBUFF_STYLE" then
        AF.SetWidth(statusText, 530)
        statusText:SetTextColor(AF.GetColorRGB("gray"))
        statusText:SetText(L[
            "Enable Buffs to move both ordinary rows together. Private auras remain Blizzard-managed; critical warnings stay separate."
        ])
        statusButton:Hide()
    else
        AF.SetWidth(statusText, 530)
        statusText:SetText(
            selected == "debuffs"
                and L[
                    "Blizzard Debuffs remain active because the native replacement could not be applied."
                ]
                or L[
                    "Blizzard Buffs remain active because the native replacement could not be applied."
                ]
        )
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
