---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class Nameplates
local NP = BFI.modules.Nameplates
---@type AbstractFramework
local AF = _G.AbstractFramework

local max = math.max
local min = math.min
local HALF_PI = math.pi / 2

local PREVIEW_FILL = 0.68
local TILE_WIDTH = 160
local TILE_GAP = 10
local LEFT_X = 15
local RIGHT_X = LEFT_X + TILE_WIDTH + TILE_GAP

local function ColorWithAlpha(color, alphaMultiplier)
    color = color or {1, 1, 1, 1}
    return color[1] or 1,
        color[2] or 1,
        color[3] or 1,
        (color[4] == nil and 1 or color[4])
            * (alphaMultiplier or 1)
end

local function CreatePreviewNote(parent)
    local note = AF.CreateFontString(
        parent,
        L["Preview sizes are normalized."],
        "gray"
    )
    AF.SetPoint(note, "TOPLEFT", parent, 15, -30)
    AF.SetPoint(note, "TOPRIGHT", parent, -15, -30)
    AF.SetFont(note, "BFI", 10, "none", false)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(false)
    return note
end

local function CreateTile(
    parent,
    title,
    x,
    y,
    width,
    height
)
    local tile = AF.CreateBorderedFrame(
        parent,
        nil,
        width or TILE_WIDTH,
        height
    )
    AF.SetPoint(tile, "TOPLEFT", parent, x, y)
    tile:SetBackdropColor(0.06, 0.06, 0.06, 0.7)

    local titleText = AF.CreateFontString(
        tile,
        title,
        "white"
    )
    tile.titleText = titleText
    AF.SetPoint(titleText, "TOPLEFT", tile, 7, -6)
    AF.SetPoint(titleText, "TOPRIGHT", tile, -7, -6)
    AF.SetFont(titleText, "BFI", 10, "outline", false)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)

    local badge = AF.CreateFontString(tile, "", "gray")
    tile.badge = badge
    AF.SetPoint(badge, "TOPRIGHT", tile, -7, -20)
    AF.SetFont(badge, "BFI", 9, "outline", false)
    badge:SetJustifyH("RIGHT")
    badge:Hide()

    local content = CreateFrame("Frame", nil, tile)
    tile.content = content
    content:SetAllPoints()
    content:SetClipsChildren(true)
    content:EnableMouse(false)

    return tile
end

local function SetTileActive(tile, active, badge)
    tile.content:SetAlpha(active and 1 or 0.28)
    tile.badge:SetShown(not active)
    tile.badge:SetText(badge or L["Off"])
end

local function CreatePreviewBar(parent, topOffset)
    local bar = AF.CreateSimpleStatusBar(parent)
    AF.SetPoint(
        bar,
        "TOPLEFT",
        parent,
        7,
        topOffset or -36
    )
    AF.SetPoint(
        bar,
        "TOPRIGHT",
        parent,
        -7,
        topOffset or -36
    )
    AF.SetHeight(bar, 18)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(PREVIEW_FILL)
    bar:EnableMouse(false)

    local nameText = AF.CreateFontString(bar, "", "white")
    bar.nameText = nameText
    AF.SetPoint(nameText, "LEFT", bar, 3, 0)
    AF.SetPoint(nameText, "RIGHT", bar, -3, 0)
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)

    return bar
end

local function ApplyBaseBar(bar, config, fillColor)
    config = config or {}
    bar:LSM_SetTexture(config.texture or "AF")
    bar:SetValue(PREVIEW_FILL)

    fillColor = fillColor or AF.GetColorTable("white")
    bar:SetFillColor(
        ColorWithAlpha(
            fillColor,
            config.colorAlpha or 1
        )
    )

    local unfillColor = config.bgColor
    local unfillAlpha = 1
    local lossColor = config.lossColor or {}
    if lossColor.useDarkerForground then
        unfillColor = {
            (fillColor[1] or 1) * 0.42,
            (fillColor[2] or 1) * 0.42,
            (fillColor[3] or 1) * 0.42,
            fillColor[4],
        }
        unfillAlpha = lossColor.alpha or 1
    elseif lossColor.rgb then
        unfillColor = lossColor.rgb
        unfillAlpha = lossColor.alpha or 1
    end
    bar:SetUnfillColor(
        ColorWithAlpha(
            unfillColor or AF.GetColorTable("background"),
            unfillAlpha
        )
    )
    bar:SetBackgroundColor(
        ColorWithAlpha(
            config.bgColor or AF.GetColorTable("background")
        )
    )
    bar:SetBorderColor(
        ColorWithAlpha(
            config.borderColor or AF.GetColorTable("border")
        )
    )
end

local function CreateTileBar(
    parent,
    title,
    x,
    y,
    width,
    height,
    barOffset
)
    local tile = CreateTile(
        parent,
        title,
        x,
        y,
        width,
        height
    )
    tile.bar = CreatePreviewBar(
        tile.content,
        barOffset
    )
    return tile
end

---------------------------------------------------------------------
-- dungeon priority colors
---------------------------------------------------------------------
local SEMANTIC_STATES = {
    {key = "boss", label = "Boss"},
    {key = "lieutenant", label = "Lieutenant / Miniboss"},
    {key = "caster", label = "Caster"},
    {key = "default", label = "Default / Melee"},
}

function NP.CreateSemanticColorOptionsPreview(parent)
    CreatePreviewNote(parent)

    local preview = {
        parent = parent,
        tiles = {},
    }

    for index, info in ipairs(SEMANTIC_STATES) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local tile = CreateTileBar(
            parent,
            L[info.label],
            column == 0 and LEFT_X or RIGHT_X,
            -56 - row * 64,
            TILE_WIDTH,
            56,
            -31
        )
        tile.key = info.key
        preview.tiles[#preview.tiles + 1] = tile
    end

    function preview:Refresh(healthConfig)
        local semantic = healthConfig.semanticColor or {}
        for _, tile in ipairs(self.tiles) do
            local state = semantic[tile.key] or {}
            ApplyBaseBar(
                tile.bar,
                healthConfig,
                state.rgb or AF.GetColorTable("white")
            )
            SetTileActive(
                tile,
                healthConfig.enabled ~= false
                    and state.enabled ~= false
            )
        end
    end

    return preview
end

---------------------------------------------------------------------
-- casts
---------------------------------------------------------------------
local function CreateCastTile(
    parent,
    title,
    x,
    y
)
    local tile = CreateTileBar(
        parent,
        title,
        x,
        y,
        TILE_WIDTH,
        68,
        -37
    )

    local bar = tile.bar
    local spellIcon =
        bar:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.spellIcon = spellIcon
    AF.SetSize(spellIcon, 14, 14)
    AF.SetPoint(spellIcon, "LEFT", bar, 2, 0)
    spellIcon:SetTexture(
        [[Interface\Icons\Spell_Shadow_ShadowWordPain]]
    )
    spellIcon:Hide()

    local durationText = AF.CreateFontString(
        bar,
        "",
        "white"
    )
    tile.durationText = durationText
    AF.SetPoint(durationText, "RIGHT", bar, -3, 0)
    durationText:SetJustifyH("RIGHT")
    durationText:Hide()

    local overlay = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    tile.overlay = overlay
    AF.SetOnePixelInside(overlay, bar)
    overlay:SetBlendMode("ADD")
    overlay:Hide()

    local tick = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.tick = tick
    tick:SetPoint("TOP", bar, "TOP", 27, -1)
    tick:SetPoint("BOTTOM", bar, "BOTTOM", 27, 1)
    AF.SetWidth(tick, 2)
    tick:Hide()

    local reverseTick =
        bar:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.reverseTick = reverseTick
    reverseTick:SetPoint(
        "TOP",
        bar,
        "TOP",
        -22,
        -1
    )
    reverseTick:SetPoint(
        "BOTTOM",
        bar,
        "BOTTOM",
        -22,
        1
    )
    AF.SetWidth(reverseTick, 2)
    reverseTick:Hide()

    local icon = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    tile.icon = icon
    AF.SetSize(icon, 16, 16)
    AF.SetPoint(icon, "RIGHT", bar, -1, 0)
    icon:Hide()

    local targetText = AF.CreateFontString(
        bar,
        "",
        "white"
    )
    tile.targetText = targetText
    AF.SetPoint(targetText, "TOP", bar, "BOTTOM", 0, -1)
    targetText:Hide()

    tile.glow = AF.CreateGlow(bar, "gold", 3)
    tile.glow:SetBorderBlendMode("ADD")
    tile.glow:Hide()

    return tile
end

local function ApplyCastContent(
    tile,
    config,
    label,
    alertEnabled
)
    local spellIcon = config.icon or {}
    tile.spellIcon:SetShown(spellIcon.enabled == true)

    local duration = config.durationText or {}
    local durationFont =
        duration.font or {"BFI", 11, "none", true}
    tile.durationText:SetText("1.8")
    tile.durationText:SetShown(duration.enabled == true)
    tile.durationText:ClearAllPoints()
    AF.SetPoint(
        tile.durationText,
        "RIGHT",
        tile.bar,
        alertEnabled and -20 or -3,
        0
    )
    AF.SetFont(
        tile.durationText,
        durationFont[1],
        min(10, max(8, durationFont[2] or 10)),
        durationFont[3],
        durationFont[4]
    )
    tile.durationText:SetTextColor(
        ColorWithAlpha(
            duration.color or AF.GetColorTable("white")
        )
    )

    local name = config.nameText or {}
    local nameFont =
        name.font or {"BFI", 11, "none", true}
    tile.bar.nameText:SetText(label)
    tile.bar.nameText:SetShown(name.enabled == true)
    tile.bar.nameText:ClearAllPoints()
    AF.SetPoint(
        tile.bar.nameText,
        "LEFT",
        tile.bar,
        spellIcon.enabled == true and 18 or 3,
        0
    )
    local rightInset = 3
    if duration.enabled == true then
        rightInset = alertEnabled and 42 or 25
    elseif alertEnabled then
        rightInset = 20
    end
    AF.SetPoint(
        tile.bar.nameText,
        "RIGHT",
        tile.bar,
        -rightInset,
        0
    )
    AF.SetFont(
        tile.bar.nameText,
        nameFont[1],
        min(10, max(8, nameFont[2] or 10)),
        nameFont[3],
        nameFont[4]
    )
    tile.bar.nameText:SetTextColor(
        ColorWithAlpha(
            name.color or AF.GetColorTable("white")
        )
    )
    tile.bar.nameText:SetJustifyH("LEFT")
end

function NP.CreateCastOptionsPreview(parent)
    CreatePreviewNote(parent)

    local preview = {
        parent = parent,
        ready = CreateCastTile(
            parent,
            L["Kick Ready"],
            LEFT_X,
            -56
        ),
        cooling = CreateCastTile(
            parent,
            L["Cooling / No Kick"],
            RIGHT_X,
            -56
        ),
        protected = CreateCastTile(
            parent,
            L["Not Kickable"],
            LEFT_X,
            -128
        ),
        important = CreateCastTile(
            parent,
            L["Important Cast"],
            RIGHT_X,
            -128
        ),
        targeting = CreateCastTile(
            parent,
            L["Targeting You"],
            LEFT_X,
            -200
        ),
        channel = CreateCastTile(
            parent,
            L["Reverse Channel"],
            RIGHT_X,
            -200
        ),
    }

    local footer = AF.CreateFontString(
        parent,
        L["The X means a normal kick will not work; a stop may still work. If both alerts apply, the X replaces the exclamation mark while the important glow remains."],
        "sand"
    )
    AF.SetPoint(footer, "TOPLEFT", parent, 15, -278)
    AF.SetPoint(footer, "TOPRIGHT", parent, -15, -278)
    AF.SetFont(footer, "BFI", 10, "none", false)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(true)

    function preview:Refresh(config, enabled)
        local castEnabled = enabled
        if castEnabled == nil then
            castEnabled = config.enabled ~= false
        end
        local check = config.interruptibleCheck or {}
        local readyColor = check.enabled ~= false
            and config.interruptibleColor
            or config.color
        local coolingColor =
            check.enabled ~= false
                and check.requireUsable ~= true
                and config.interruptibleColor
            or config.color
        local protectedColor = check.enabled ~= false
            and config.uninterruptibleColor
            or config.color
        local tickConfig = config.interruptReadyTick or {}
        local protectedIcon =
            config.uninterruptibleIcon or {}
        local importantIcon = config.importantIcon or {}

        ApplyCastContent(
            self.ready,
            config,
            L["Cast"] .. " →",
            false
        )
        ApplyCastContent(
            self.cooling,
            config,
            L["Cast"] .. " →",
            false
        )
        ApplyCastContent(
            self.protected,
            config,
            L["Cast"] .. " →",
            protectedIcon.enabled == true
        )
        ApplyCastContent(
            self.important,
            config,
            L["Cast"] .. " →",
            importantIcon.enabled == true
        )
        ApplyCastContent(
            self.targeting,
            config,
            L["Cast"] .. " →",
            false
        )
        ApplyCastContent(
            self.channel,
            config,
            "← " .. L["Channel"],
            false
        )

        ApplyBaseBar(self.ready.bar, config, readyColor)
        SetTileActive(
            self.ready,
            castEnabled and check.enabled ~= false
        )

        ApplyBaseBar(
            self.cooling.bar,
            config,
            coolingColor
        )
        self.cooling.tick:SetColorTexture(
            ColorWithAlpha(
                tickConfig.color or {0, 1, 0, 1}
            )
        )
        self.cooling.tick:SetShown(
            tickConfig.enabled == true
        )
        SetTileActive(
            self.cooling,
            castEnabled
                and (
                    check.enabled ~= false
                        and check.requireUsable == true
                    or tickConfig.enabled == true
                )
        )

        ApplyBaseBar(
            self.protected.bar,
            config,
            protectedColor
        )
        self.protected.icon:SetTexture(
            AF.GetIcon("Fluent_Color_No")
        )
        local protectedSize = min(
            18,
            max(12, protectedIcon.size or 16)
        )
        AF.SetSize(
            self.protected.icon,
            protectedSize,
            protectedSize
        )
        self.protected.icon:SetShown(
            protectedIcon.enabled == true
        )
        SetTileActive(
            self.protected,
            castEnabled
                and (
                    check.enabled ~= false
                        or protectedIcon.enabled == true
                )
        )

        ApplyBaseBar(
            self.important.bar,
            config,
            config.color
        )
        self.important.icon:SetTexture(
            AF.GetIcon("Fluent_Notice")
        )
        local importantSize = min(
            18,
            max(12, importantIcon.size or 16)
        )
        AF.SetSize(
            self.important.icon,
            importantSize,
            importantSize
        )
        self.important.icon:SetShown(
            importantIcon.enabled == true
        )
        local importantGlow = config.importantGlow or {}
        self.important.glow:SetBackdropBorderColor(
            ColorWithAlpha(
                importantGlow.color
                    or AF.GetColorTable("gold")
            )
        )
        self.important.glow:SetShown(
            importantGlow.enabled == true
        )
        SetTileActive(
            self.important,
            castEnabled
                and (
                    importantIcon.enabled == true
                        or importantGlow.enabled == true
                )
        )

        ApplyBaseBar(
            self.targeting.bar,
            config,
            config.color
        )
        local targetHighlight =
            config.playerTargetHighlight or {}
        self.targeting.overlay:SetColorTexture(
            ColorWithAlpha(
                targetHighlight.color
                    or AF.GetColorTable("white", 0.2)
            )
        )
        self.targeting.overlay:SetShown(
            targetHighlight.enabled == true
        )
        self.targeting.targetText:SetText("→ " .. L["You"])
        local targetText = config.spellTargetText or {}
        local targetFont =
            targetText.font or {"BFI", 10, "outline", false}
        AF.SetFont(
            self.targeting.targetText,
            targetFont[1],
            min(10, max(8, targetFont[2] or 10)),
            targetFont[3],
            targetFont[4]
        )
        self.targeting.targetText:SetTextColor(
            ColorWithAlpha(
                targetText.color
                    or AF.GetColorTable("white")
            )
        )
        self.targeting.targetText:SetShown(
            targetText.enabled == true
        )
        SetTileActive(
            self.targeting,
            castEnabled
                and (
                    targetHighlight.enabled == true
                        or (
                            config.spellTargetText
                            and config.spellTargetText.enabled == true
                        )
                )
        )

        ApplyBaseBar(
            self.channel.bar,
            config,
            coolingColor
        )
        self.channel.bar:SetValue(0.58)
        self.channel.reverseTick:SetColorTexture(
            ColorWithAlpha(
                tickConfig.color or {0, 1, 0, 1}
            )
        )
        self.channel.reverseTick:SetShown(
            tickConfig.enabled == true
        )
        SetTileActive(self.channel, castEnabled)
    end

    return preview
end

---------------------------------------------------------------------
-- threat
---------------------------------------------------------------------
local THREAT_STATES = {
    {key = "safe", label = "Safe"},
    {key = "transition", label = "Transition"},
    {key = "warning", label = "Warning / Aggro"},
    {key = "offTank", label = "Off-Tank"},
}

local THREAT_MEANINGS = {
    tank = {
        safe = "You hold aggro",
        transition = "Aggro is changing",
        warning = "You lost aggro",
        offTank = "Another tank or group pet holds aggro",
    },
    damage = {
        safe = "You do not have aggro",
        transition = "Threat is rising",
        warning = "You have aggro",
        offTank = "Tank-only state",
    },
}

local function CreateThreatTile(
    parent,
    title,
    x,
    y,
    width,
    height
)
    local tile = CreateTileBar(
        parent,
        title,
        x,
        y,
        width,
        height,
        -47
    )

    local description = AF.CreateFontString(
        tile,
        "",
        "gray"
    )
    tile.description = description
    AF.SetPoint(description, "TOPLEFT", tile, 7, -23)
    AF.SetPoint(description, "TOPRIGHT", tile, -7, -23)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)
    AF.SetFont(description, "BFI", 9, "none", false)

    local swatch = tile:CreateTexture(nil, "OVERLAY")
    tile.swatch = swatch
    AF.SetSize(swatch, 9, 9)
    AF.SetPoint(swatch, "TOPRIGHT", tile, -7, -7)
    tile.titleText:ClearAllPoints()
    AF.SetPoint(tile.titleText, "TOPLEFT", tile, 7, -6)
    AF.SetPoint(tile.titleText, "TOPRIGHT", tile, -22, -6)
    tile.badge:ClearAllPoints()
    AF.SetPoint(tile.badge, "BOTTOMRIGHT", tile, -7, 4)

    local overlay =
        tile.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    tile.overlay = overlay
    overlay:SetAllPoints(tile.bar.fill)
    overlay:AddMaskTexture(tile.bar.fill.mask)
    overlay:Hide()

    tile.glow = AF.CreateGlow(tile.bar, "orange", 3)
    tile.glow:Hide()

    return tile
end

local function ApplyThreatTile(
    tile,
    healthConfig,
    threatConfig,
    color,
    active,
    badge
)
    local semantic = healthConfig.semanticColor or {}
    local baseState = semantic.default or {}
    ApplyBaseBar(
        tile.bar,
        healthConfig,
        baseState.rgb or AF.GetColorTable("orange")
    )
    tile.bar.nameText:SetText(tile.titleText:GetText())

    tile.swatch:SetColorTexture(ColorWithAlpha(color))
    tile.swatch:SetAlpha(active and 1 or 0.45)

    if active and threatConfig.border then
        tile.bar:SetBorderColor(
            ColorWithAlpha(
                color,
                threatConfig.borderAlpha or 1
            )
        )
    end

    tile.overlay:SetColorTexture(
        ColorWithAlpha(
            color,
            threatConfig.barAlpha or 1
        )
    )
    tile.overlay:SetShown(
        active and threatConfig.bar == true
    )

    if active and threatConfig.name then
        tile.bar.nameText:SetTextColor(
            ColorWithAlpha(
                color,
                threatConfig.nameAlpha or 1
            )
        )
    else
        tile.bar.nameText:SetTextColor(1, 1, 1, 1)
    end

    local glowSize = min(
        6,
        max(2, threatConfig.size or 3)
    )
    AF.SetBackdrop(
        tile.glow,
        {
            edgeFile = AF.GetTexture("StaticGlow"),
            edgeSize = glowSize,
        }
    )
    AF.SetOutside(
        tile.glow,
        tile.bar,
        min(5, max(0, threatConfig.outset or 0))
    )
    tile.glow:SetBackdropBorderColor(
        ColorWithAlpha(
            color,
            threatConfig.glowAlpha or 1
        )
    )
    tile.glow:SetShown(
        active and threatConfig.glow == true
    )

    SetTileActive(tile, active, badge)
end

function NP.CreateThreatOptionsPreview(parent)
    local preview = {
        parent = parent,
        perspective = "tank",
        tiles = {},
    }

    local perspective = AF.CreateSwitch(parent, 200, 20)
    preview.perspectiveSwitch = perspective
    perspective:SetLabel(L["Perspective"])
    AF.SetPoint(perspective, "TOPLEFT", parent, 15, -42)
    perspective:SetLabels({
        {text = L["Tank"], value = "tank"},
        {text = L["Damage / Healing"], value = "damage"},
    })

    local note = AF.CreateFontString(
        parent,
        L["Preview sizes are normalized."],
        "gray"
    )
    AF.SetPoint(note, "TOPRIGHT", parent, -15, -31)
    AF.SetFont(note, "BFI", 9, "none", false)

    for index, info in ipairs(THREAT_STATES) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local tile = CreateThreatTile(
            parent,
            L[info.label],
            column == 0 and LEFT_X or RIGHT_X,
            -82 - row * 76,
            TILE_WIDTH,
            68
        )
        tile.key = info.key
        preview.tiles[#preview.tiles + 1] = tile
    end

    preview.fallback = CreateThreatTile(
        parent,
        L["Native / Restricted Fallback"],
        LEFT_X,
        -234,
        TILE_WIDTH * 2 + TILE_GAP,
        55
    )
    preview.fallback.bar:ClearAllPoints()
    AF.SetPoint(
        preview.fallback.bar,
        "TOPLEFT",
        preview.fallback.content,
        178,
        -28
    )
    AF.SetPoint(
        preview.fallback.bar,
        "TOPRIGHT",
        preview.fallback.content,
        -7,
        -28
    )
    preview.fallback.description:ClearAllPoints()
    AF.SetPoint(
        preview.fallback.description,
        "TOPLEFT",
        preview.fallback,
        7,
        -23
    )
    AF.SetPoint(
        preview.fallback.description,
        "TOPRIGHT",
        preview.fallback,
        -170,
        -23
    )

    function preview:Refresh(
        healthConfig,
        nameTextEnabled
    )
        self.healthConfig = healthConfig
        self.nameTextEnabled = nameTextEnabled
        local threatConfig = healthConfig.threatGlow or {}
        local stateColors = threatConfig.stateColors or {}
        local meanings =
            THREAT_MEANINGS[self.perspective]
        local tankOnlyUnavailable =
            self.perspective == "damage"
                and threatConfig.tankOnly == true
        local presentationEnabled
        if threatConfig.border ~= nil
            or threatConfig.glow ~= nil
            or threatConfig.bar ~= nil
            or threatConfig.name ~= nil
        then
            presentationEnabled =
                threatConfig.border == true
                    or threatConfig.glow == true
                    or threatConfig.bar == true
                    or (
                        threatConfig.name == true
                        and nameTextEnabled ~= false
                    )
        else
            presentationEnabled =
                threatConfig.style == "border"
                    or threatConfig.style == "glow"
                    or threatConfig.style == "both"
        end
        local threatEnabled =
            healthConfig.enabled ~= false
                and threatConfig.enabled == true
                and presentationEnabled

        for _, tile in ipairs(self.tiles) do
            local state = stateColors[tile.key] or {}
            tile.description:SetText(
                L[meanings[tile.key]]
            )
            local active =
                threatEnabled
                and stateColors.enabled == true
                and state.enabled ~= false
            local badge
            if tankOnlyUnavailable
                or (
                    self.perspective == "damage"
                    and tile.key == "offTank"
                )
            then
                active = false
                badge = L["Tank Only"]
            end
            ApplyThreatTile(
                tile,
                healthConfig,
                threatConfig,
                state.rgb or AF.GetColorTable("white"),
                active,
                badge
            )
        end

        local fallbackColor
        if threatConfig.useCustomColor then
            fallbackColor = threatConfig.color
            self.fallback.description:SetText(
                L["Custom fallback color"]
            )
        else
            fallbackColor = AF.GetColorTable("orange")
            self.fallback.description:SetText(
                L["Blizzard native color varies"]
            )
        end
        ApplyThreatTile(
            self.fallback,
            healthConfig,
            threatConfig,
            fallbackColor,
            threatEnabled and not tankOnlyUnavailable,
            tankOnlyUnavailable and L["Tank Only"] or nil
        )
    end

    perspective:SetOnSelect(function(value)
        preview.perspective = value
        if preview.healthConfig then
            preview:Refresh(
                preview.healthConfig,
                preview.nameTextEnabled
            )
        end
    end)
    perspective:SetSelectedValue("tank")

    return preview
end

---------------------------------------------------------------------
-- target and focus
---------------------------------------------------------------------
local function CreateTargetTile(
    parent,
    title,
    x,
    y
)
    local tile = CreateTileBar(
        parent,
        title,
        x,
        y,
        TILE_WIDTH,
        70,
        -44
    )

    local topIcon =
        tile.content:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.topIcon = topIcon
    AF.SetPoint(topIcon, "BOTTOM", tile.bar, "TOP", 0, 0)
    topIcon:Hide()

    local leftIcon =
        tile.content:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.leftIcon = leftIcon
    leftIcon:SetRotation(HALF_PI)
    AF.SetPoint(leftIcon, "RIGHT", tile.bar, "LEFT", 0, 0)
    leftIcon:Hide()

    local rightIcon =
        tile.content:CreateTexture(nil, "OVERLAY", nil, 2)
    tile.rightIcon = rightIcon
    rightIcon:SetRotation(-HALF_PI)
    AF.SetPoint(rightIcon, "LEFT", tile.bar, "RIGHT", 0, 0)
    rightIcon:Hide()

    local highlight =
        tile.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    tile.highlight = highlight
    AF.SetOnePixelInside(highlight, tile.bar)
    highlight:SetBlendMode("ADD")
    highlight:Hide()

    return tile
end

local function ApplyTargetBase(
    tile,
    plateConfig,
    stateConfig
)
    local healthConfig = plateConfig.healthBar or {}
    local semantic = healthConfig.semanticColor or {}
    local defaultState = semantic.default or {}
    ApplyBaseBar(
        tile.bar,
        healthConfig,
        defaultState.rgb or AF.GetColorTable("orange")
    )
    tile.bar.nameText:SetText(L["Sample Unit"])

    local texture = AF.GetTexture(
        stateConfig.texture or "Arrow1_Green",
        BFI.name
    )
    local color = stateConfig.color or
        AF.GetColorTable("white")
    for _, icon in ipairs({
        tile.topIcon,
        tile.leftIcon,
        tile.rightIcon,
    }) do
        icon:SetTexture(texture)
        icon:SetVertexColor(ColorWithAlpha(color))
    end
end

function NP.CreateTargetOptionsPreview(parent)
    local preview = {
        parent = parent,
        top = CreateTargetTile(
            parent,
            L["Top Arrow"],
            LEFT_X,
            -58
        ),
        sides = CreateTargetTile(
            parent,
            L["Side Arrows"],
            RIGHT_X,
            -58
        ),
        highlight = CreateTargetTile(
            parent,
            L["Highlight Health Bar"],
            LEFT_X,
            -134
        ),
        emphasis = CreateTargetTile(
            parent,
            L["Emphasize Name Text"],
            RIGHT_X,
            -134
        ),
    }

    local context = AF.CreateFontString(
        parent,
        "",
        "gray"
    )
    preview.context = context
    AF.SetPoint(context, "TOPLEFT", parent, 15, -30)

    local note = AF.CreateFontString(
        parent,
        L["Preview sizes are normalized."],
        "gray"
    )
    AF.SetPoint(note, "TOPRIGHT", parent, -15, -30)
    AF.SetFont(note, "BFI", 9, "none", false)

    local footer = AF.CreateFontString(
        parent,
        L["Focus presentation wins when a unit is both your target and focus."],
        "sand"
    )
    AF.SetPoint(footer, "TOPLEFT", parent, 15, -210)
    AF.SetPoint(footer, "TOPRIGHT", parent, -15, -210)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(true)

    preview.sides.bar:ClearAllPoints()
    AF.SetPoint(
        preview.sides.bar,
        "TOPLEFT",
        preview.sides.content,
        28,
        -44
    )
    AF.SetPoint(
        preview.sides.bar,
        "TOPRIGHT",
        preview.sides.content,
        -28,
        -44
    )

    function preview:Refresh(
        plateConfig,
        stateConfig,
        scopeLabel,
        stateLabel,
        indicatorEnabled,
        healthBarEnabled,
        nameTextEnabled
    )
        self.context:SetText(
            scopeLabel .. " · " .. stateLabel
        )

        for _, tile in ipairs({
            self.top,
            self.sides,
            self.highlight,
            self.emphasis,
        }) do
            ApplyTargetBase(
                tile,
                plateConfig,
                stateConfig
            )
            tile.topIcon:Hide()
            tile.leftIcon:Hide()
            tile.rightIcon:Hide()
            tile.highlight:Hide()
        end

        local topSize = min(
            23,
            max(14, stateConfig.size or 18)
        )
        AF.SetSize(
            self.top.topIcon,
            topSize,
            topSize
        )
        self.top.topIcon:ClearAllPoints()
        AF.SetPoint(
            self.top.topIcon,
            "BOTTOM",
            self.top.bar,
            "TOP",
            0,
            min(5, max(0, stateConfig.topSpacing or 0))
        )
        self.top.topIcon:Show()
        SetTileActive(
            self.top,
            indicatorEnabled
                and stateConfig.layout == "top"
        )

        local sideSize = min(
            20,
            max(12, stateConfig.sideSize or 16)
        )
        local sideSpacing = min(
            5,
            max(0, stateConfig.sideSpacing or 0)
        )
        for _, icon in ipairs({
            self.sides.leftIcon,
            self.sides.rightIcon,
        }) do
            AF.SetSize(icon, sideSize, sideSize)
            icon:Show()
        end
        self.sides.leftIcon:ClearAllPoints()
        AF.SetPoint(
            self.sides.leftIcon,
            "RIGHT",
            self.sides.bar,
            "LEFT",
            -sideSpacing,
            0
        )
        self.sides.rightIcon:ClearAllPoints()
        AF.SetPoint(
            self.sides.rightIcon,
            "LEFT",
            self.sides.bar,
            "RIGHT",
            sideSpacing,
            0
        )
        SetTileActive(
            self.sides,
            indicatorEnabled
                and stateConfig.layout == "sides"
        )

        local healthHighlight =
            stateConfig.healthBarHighlight or {}
        self.highlight.highlight:SetColorTexture(
            ColorWithAlpha(
                healthHighlight.color
                    or AF.GetColorTable("white", 0.25)
            )
        )
        self.highlight.highlight:Show()
        SetTileActive(
            self.highlight,
            indicatorEnabled
                and healthBarEnabled
                and healthHighlight.enabled == true,
            healthBarEnabled
                and L["Off"]
                or L["Unavailable"]
        )

        local emphasis =
            stateConfig.nameTextEmphasis or {}
        local font = plateConfig.nameText
            and plateConfig.nameText.font
            or {"BFI", 12, "outline", true}
        local shadow = emphasis.shadow
        if shadow == nil then
            shadow = font[4]
        end
        AF.SetFont(
            self.emphasis.bar.nameText,
            font[1],
            min(
                15,
                max(
                    8,
                    (font[2] or 12)
                        + (emphasis.sizeDelta or 0)
                )
            ),
            emphasis.outline or font[3],
            shadow
        )
        SetTileActive(
            self.emphasis,
            indicatorEnabled
                and nameTextEnabled
                and emphasis.enabled == true,
            nameTextEnabled
                and L["Off"]
                or L["Unavailable"]
        )
    end

    return preview
end

---------------------------------------------------------------------
-- auras and name placement
---------------------------------------------------------------------
local COOLDOWN_STYLE_LABELS = {
    none = function() return _G.NONE end,
    vertical = function() return L["Vertical"] end,
    block_vertical = function() return L["Block Vertical"] end,
    clock = function() return L["Clock"] end,
    block_clock = function() return L["Block Clock"] end,
    clock_with_leading_edge = function()
        return L["Clock (With Leading Edge)"]
    end,
    block_clock_with_leading_edge = function()
        return L["Block Clock (With Leading Edge)"]
    end,
}

local function CreateAuraLayoutTile(
    parent,
    title,
    x,
    placement
)
    local tile = CreateTileBar(
        parent,
        title,
        x,
        -55,
        TILE_WIDTH,
        112,
        -83
    )
    tile.placement = placement

    tile.bar.nameText:ClearAllPoints()
    if placement == "inside" then
        AF.SetPoint(tile.bar.nameText, "CENTER", tile.bar)
    else
        AF.SetPoint(
            tile.bar.nameText,
            "BOTTOM",
            tile.bar,
            "TOP",
            0,
            2
        )
    end

    tile.auras = {}
    for index = 1, 2 do
        local aura = AF.CreateAura(tile.content, true)
        tile.auras[index] = aura
        aura:EnableMouse(false)
    end

    return tile
end

function NP.CreateAuraOptionsPreview(parent)
    CreatePreviewNote(parent)

    local preview = {
        parent = parent,
        outside = CreateAuraLayoutTile(
            parent,
            L["Outside Health Bar"],
            LEFT_X,
            "outside"
        ),
        inside = CreateAuraLayoutTile(
            parent,
            L["Inside Health Bar"],
            RIGHT_X,
            "inside"
        ),
    }

    local auraIcons = {
        [[Interface\Icons\Spell_Shadow_ShadowWordPain]],
        [[Interface\Icons\Spell_Nature_Rejuvenation]],
    }

    local styleText = AF.CreateFontString(
        parent,
        "",
        "gray"
    )
    preview.styleText = styleText
    AF.SetPoint(styleText, "TOPLEFT", parent, 15, -174)
    AF.SetPoint(styleText, "TOPRIGHT", parent, -15, -174)
    styleText:SetJustifyH("LEFT")

    local function ApplyAuraTile(
        tile,
        plateConfig,
        active,
        auraEnabled,
        durationEnabled
    )
        local healthConfig = plateConfig.healthBar or {}
        local semantic = healthConfig.semanticColor or {}
        local defaultState = semantic.default or {}
        ApplyBaseBar(
            tile.bar,
            healthConfig,
            defaultState.rgb or AF.GetColorTable("orange")
        )

        local nameConfig = plateConfig.nameText or {}
        tile.bar.nameText:SetText(L["Sample Unit"])
        AF.SetFont(
            tile.bar.nameText,
            nameConfig.font
                or {"BFI", 12, "outline", true}
        )

        local auraConfig = plateConfig.debuffs or {}
        local auraWidth = min(
            25,
            max(18, auraConfig.width or 25)
        )
        local auraHeight = min(
            25,
            max(16, auraConfig.height or 18)
        )

        for index, aura in ipairs(tile.auras) do
            AF.SetSize(aura, auraWidth, auraHeight)
            aura:ClearAllPoints()
            if tile.placement == "inside" then
                AF.SetPoint(
                    aura,
                    "BOTTOM",
                    tile.bar,
                    "TOP",
                    (index - 1) * (auraWidth + 3)
                        - (auraWidth + 3) / 2,
                    3
                )
            else
                AF.SetPoint(
                    aura,
                    "BOTTOM",
                    tile.bar,
                    "TOP",
                    (index - 1) * (auraWidth + 3)
                        - (auraWidth + 3) / 2,
                    18
                )
            end
            local durationText =
                auraConfig.durationText or {}
            local durationFont =
                durationText.font
                    or {"BFI", 10, "outline", false}
            local durationPosition =
                durationText.position
                    or {"RIGHT", "TOPRIGHT", 0, -2}
            aura:SetupDurationText(
                {
                    enabled = durationEnabled,
                    font = {
                        durationFont[1],
                        min(14, max(8, durationFont[2] or 10)),
                        durationFont[3],
                        durationFont[4],
                    },
                    position = {
                        durationPosition[1],
                        durationPosition[2],
                        min(
                            6,
                            max(-6, durationPosition[3] or 0)
                        ),
                        min(
                            6,
                            max(-6, durationPosition[4] or -2)
                        ),
                    },
                    color = durationText.color or {
                        normal = AF.GetColorTable("white"),
                    },
                }
            )
            local stackText = auraConfig.stackText or {}
            local stackFont =
                stackText.font
                    or {"BFI", 10, "outline", false}
            local stackPosition =
                stackText.position
                    or {"RIGHT", "BOTTOMRIGHT", 0, 2}
            aura:SetupStackText(
                {
                    enabled = stackText.enabled ~= false,
                    font = {
                        stackFont[1],
                        min(14, max(8, stackFont[2] or 10)),
                        stackFont[3],
                        stackFont[4],
                    },
                    position = {
                        stackPosition[1],
                        stackPosition[2],
                        min(
                            6,
                            max(-6, stackPosition[3] or 0)
                        ),
                        min(
                            6,
                            max(-6, stackPosition[4] or 2)
                        ),
                    },
                    color = stackText.color
                        or AF.GetColorTable("white"),
                }
            )
            aura:SetCooldown(
                GetTime() - 15,
                index == 1 and 60 or 90,
                index == 2 and 2 or "",
                auraIcons[index]
            )
            -- Bind the simulated timer before applying presentation. Native
            -- cooldown and duration-bar setters may refresh their child
            -- regions, so the selected style must be the final authority.
            aura:SetCooldownStyle(
                auraConfig.cooldownStyle or "none"
            )
        end

        if active and auraEnabled then
            tile:SetBackdropBorderColor(
                AF.GetColorRGB("BFI")
            )
        else
            tile:SetBackdropBorderColor(
                AF.GetColorRGB("border")
            )
        end
        if not auraEnabled then
            tile.badge:SetText(L["Off"])
            tile.badge:Show()
        elseif active then
            tile.badge:SetText(L["Current"])
            tile.badge:Show()
        else
            tile.badge:Hide()
        end
        tile.content:SetAlpha(auraEnabled and 1 or 0.35)
    end

    function preview:Refresh(
        plateConfig,
        enabled,
        durationEnabled
    )
        self.plateConfig = plateConfig
        self.auraEnabled = enabled
        if self.auraEnabled == nil then
            self.auraEnabled =
                (plateConfig.debuffs or {}).enabled ~= false
        end
        self.durationEnabled = durationEnabled
        if self.durationEnabled == nil then
            local durationText =
                (plateConfig.debuffs or {}).durationText
                    or {}
            self.durationEnabled =
                durationText.enabled ~= false
        end
        if not self.parent:IsVisible() then return end

        local placement = plateConfig.nameText
            and plateConfig.nameText.placement
            or "outside"
        ApplyAuraTile(
            self.outside,
            plateConfig,
            placement ~= "inside",
            self.auraEnabled,
            self.durationEnabled
        )
        ApplyAuraTile(
            self.inside,
            plateConfig,
            placement == "inside",
            self.auraEnabled,
            self.durationEnabled
        )

        local cooldownStyle = plateConfig.debuffs
            and plateConfig.debuffs.cooldownStyle
            or "none"
        local getLabel =
            COOLDOWN_STYLE_LABELS[cooldownStyle]
        self.styleText:SetText(
            L["Cooldown Style"]
                .. ": "
                .. (getLabel and getLabel() or cooldownStyle)
        )
    end

    function preview:Stop()
        for _, tile in ipairs({
            self.outside,
            self.inside,
        }) do
            for _, aura in ipairs(tile.auras) do
                aura:ClearAura()
            end
        end
    end

    local function RestartPreview()
        if preview.parent:IsVisible()
            and preview.plateConfig
        then
            preview:Refresh(
                preview.plateConfig,
                preview.auraEnabled,
                preview.durationEnabled
            )
        end
    end
    preview.outside.auras[1].cooldown:SetScript(
        "OnCooldownDone",
        RestartPreview
    )

    return preview
end
