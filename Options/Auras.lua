---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local A = BFI.modules.Auras
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local aurasPanel
local contentPane
local inputBox
local dialog
local colorPool
local LoadList

local floor, huge = math.floor, math.huge

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -huge
        and value < huge
end

local function IsPositiveInteger(value)
    return IsFiniteNumber(value)
        and value > 0
        and value == floor(value)
end

local function HasNativeAuraContainerBackend()
    return AF.isRetail
        and type(UF.HasNativeAuraContainerBackend) == "function"
        and UF.HasNativeAuraContainerBackend()
end

local function FireColorsChanged()
    AF.Fire("BFI_UpdateConfig", "auras", "colors")
end

local function GetDisplayColor(color)
    if type(color) == "table"
        and IsFiniteNumber(color[1])
        and IsFiniteNumber(color[2])
        and IsFiniteNumber(color[3])
        and IsFiniteNumber(color[4])
    then
        return color
    end
    return {0.5, 0.5, 0.5, 1}
end

local function HideInputBox()
    if inputBox then
        local activeInputBox = inputBox
        inputBox = nil
        activeInputBox:Hide()
    end
    AF.Tooltip2:Hide()
end

local function CreateAurasPanel()
    aurasPanel = AF.CreateFrame(
        BFIOptionsFrame_ContentPane,
        "BFIOptionsFrame_AurasPanel"
    )
    aurasPanel:SetAllPoints()

    local title = AF.CreateFontString(
        aurasPanel,
        AF.GetGradientText(
            L["Global Colors"],
            "BFI",
            "white"
        )
    )
    AF.SetPoint(title, "TOPLEFT", 15, -15)

    local description = AF.CreateFontString(aurasPanel)
    aurasPanel.description = description
    AF.SetPoint(
        description,
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )
    AF.SetPoint(description, "TOPRIGHT", -15, -38)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)
    description:SetColor("tip")

    if HasNativeAuraContainerBackend() then
        description:SetText(
            L["Assign colors to aura spell IDs. Block-style unit-frame auras use them where WoW supports safe matching; unlisted spells stay gray. Rows may hide when matching is unavailable. Changes may require a UI reload"]
        )
    else
        description:SetText(
            L["Assign colors by spell ID for WoW 12.1. Older aura rows stay gray"]
        )
    end

    aurasPanel:SetOnHide(function()
        HideInputBox()
        AF.CancelColorPicker()
    end)
end

local function ShowInputBox(owner)
    HideInputBox()

    local colors = A.config.colors
    inputBox = AF.GetEditBox(
        contentPane,
        L["Input Spell ID"],
        nil,
        nil,
        "number"
    )
    inputBox:SetAllPoints(
        owner.spell ~= nil
            and owner
            or contentPane.search
    )
    inputBox:SetBorderColor("BFI")

    inputBox:SetOnTextChanged(function(spell)
        if not IsPositiveInteger(spell) then
            AF.Tooltip2:Hide()
            return
        end
        AF.Tooltip2:SetOwner(inputBox, "ANCHOR_NONE")
        AF.Tooltip2:SetSpellByID(spell, true)
        AF.Tooltip2:SetPoint(
            "TOPRIGHT",
            inputBox,
            "TOPLEFT",
            -1,
            0
        )
        AF.Tooltip2:Show()
    end)

    inputBox:SetOnEnterPressed(function(spell)
        -- AF's transient edit box hides itself after this callback. Clear our
        -- reference first so the pooled widget cannot later be mistaken for
        -- an editor still owned by this panel.
        inputBox = nil
        AF.Tooltip2:Hide()

        if not IsPositiveInteger(spell)
            or not AF.SpellExists(spell)
        then
            return
        end

        local oldSpell = owner.spell
        if oldSpell ~= nil then
            if spell == oldSpell then
                HideInputBox()
                return
            end
            if colors[spell] ~= nil then return end

            local oldColor = colors[oldSpell]
            colors[oldSpell] = nil
            colors[spell] = oldColor
        else
            if colors[spell] ~= nil then return end
            colors[spell] = AF.GetColorTable("BFI")
        end

        LoadList()
        FireColorsChanged()
    end)
    inputBox:SetOnEscapePressed(function()
        inputBox = nil
        AF.Tooltip2:Hide()
    end)

    inputBox:SetText(
        owner.spell ~= nil
            and tostring(owner.spell)
            or ""
    )
end

local function CreateContentPane()
    contentPane = AF.CreateFrame(aurasPanel)
    aurasPanel.contentPane = contentPane
    AF.SetPoint(
        contentPane,
        "TOPLEFT",
        aurasPanel.description,
        "BOTTOMLEFT",
        0,
        -15
    )
    AF.SetPoint(contentPane, "BOTTOMRIGHT", -15, 15)

    local search = AF.CreateEditBox(
        contentPane,
        _G.SEARCH,
        nil,
        20,
        "trim"
    )
    contentPane.search = search
    search:SetOnTextChanged(function(_, userChanged)
        if userChanged then
            LoadList()
        end
    end)

    local reset = AF.CreateButton(
        contentPane,
        _G.RESET,
        "red_hover",
        107,
        20
    )
    contentPane.reset = reset
    reset:SetPoint("TOPRIGHT")

    local addButton = AF.CreateButton(
        contentPane,
        nil,
        "BFI_hover",
        35,
        20
    )
    contentPane.addButton = addButton
    addButton:SetTexture(AF.GetIcon("Plus"))
    addButton:EnablePushEffect(false)
    addButton:SetOnClick(ShowInputBox)

    AF.SetPoint(
        addButton,
        "TOPRIGHT",
        reset,
        "TOPLEFT",
        -7,
        0
    )
    AF.SetPoint(search, "TOPLEFT")
    AF.SetPoint(
        search,
        "TOPRIGHT",
        addButton,
        "TOPLEFT",
        -7,
        0
    )

    local scroll = AF.CreateScrollGrid(
        contentPane,
        nil,
        5,
        5,
        3,
        13,
        nil,
        20,
        5
    )
    contentPane.scroll = scroll
    AF.SetPoint(
        scroll,
        "TOPLEFT",
        search,
        "BOTTOMLEFT",
        0,
        -15
    )
    AF.SetPoint(
        scroll,
        "TOPRIGHT",
        reset,
        "BOTTOMRIGHT",
        0,
        -15
    )

    reset:SetOnClick(function()
        dialog = AF.GetDialog(
            scroll,
            AF.WrapTextInColor(
                L["Reset to default settings?"],
                "BFI"
            )
                .. "\n"
                .. L["Global Colors"]
        )
        AF.SetPoint(dialog, "TOP", 0, -30)
        dialog:SetOnConfirm(function()
            search:SetText("")
            wipe(A.config.colors)
            AF.Merge(
                A.config.colors,
                A.GetDefaults("colors")
            )
            LoadList()
            FireColorsChanged()
        end)
    end)

    local tip = AF.CreateFontString(
        contentPane,
        AF.GetIconString("MouseLeftClick")
            .. L["Edit"]
            .. "  "
            .. AF.GetIconString("MouseRightClick")
            .. L["Delete"]
    )
    AF.SetPoint(tip, "TOPLEFT", scroll, "BOTTOMLEFT", 0, -5)
    tip:SetColor("tip")

    colorPool = AF.CreateObjectPool(function()
        local button = AF.CreateButton(
            scroll,
            nil,
            "BFI_hover"
        )
        button:SetTexture(
            AF.GetIcon("QuestionMark"),
            nil,
            {"LEFT", 2, 0},
            nil,
            "black"
        )
        button:EnablePushEffect(false)
        button:RegisterForClicks(
            "LeftButtonUp",
            "RightButtonUp"
        )

        button.colorPicker = AF.CreateColorPicker(
            button,
            nil,
            true
        )
        button.colorPicker:SetPoint("RIGHT", -3, 0)
        button.colorPicker:HookOnEnter(button:GetOnEnter())
        button.colorPicker:HookOnLeave(button:GetOnLeave())
        button.colorPicker:SetOnConfirm(function(r, g, b, a)
            local spellID = button.spell
            if spellID == nil then return end

            local color = A.config.colors[spellID]
            if type(color) ~= "table" then
                color = {}
                A.config.colors[spellID] = color
            end
            color[1] = r
            color[2] = g
            color[3] = b
            color[4] = a
            FireColorsChanged()
        end)

        button.idText = AF.CreateFontString(button)
        AF.SetPoint(
            button.idText,
            "LEFT",
            button.texture,
            "RIGHT",
            5,
            0
        )
        button.idText:SetWidth(70)
        button.idText:SetJustifyH("LEFT")
        button.idText:SetWordWrap(false)

        button.nameText = AF.CreateFontString(button)
        AF.SetPoint(
            button.nameText,
            "LEFT",
            button.idText,
            "RIGHT",
            5,
            0
        )
        AF.SetPoint(
            button.nameText,
            "RIGHT",
            button.colorPicker,
            "LEFT",
            -3,
            0
        )
        button.nameText:SetJustifyH("LEFT")
        button.nameText:SetWordWrap(false)

        function button:Update()
            AF.TruncateFontStringByWidth(
                self.nameText,
                self.nameText:GetWidth(),
                "left",
                true,
                self.fullName
            )
        end

        button:SetOnClick(function(_, mouseButton)
            if mouseButton == "LeftButton" then
                ShowInputBox(button)
            elseif mouseButton == "RightButton" then
                A.config.colors[button.spell] = nil
                LoadList()
                FireColorsChanged()
            end
        end)

        button:HookOnEnter(function()
            if inputBox and inputBox:IsShown() then return end
            if not IsPositiveInteger(button.spell) then
                AF.Tooltip2:Hide()
                return
            end
            AF.Tooltip2:SetOwner(contentPane, "ANCHOR_NONE")
            AF.Tooltip2:SetSpellByID(button.spell, true)
            AF.Tooltip2:SetPoint(
                "TOPRIGHT",
                button,
                "TOPLEFT",
                -1,
                0
            )
            AF.Tooltip2:Show()
        end)

        button:HookOnLeave(function()
            if inputBox and inputBox:IsShown() then return end
            AF.Tooltip2:Hide()
        end)

        return button
    end, function(_, button)
        button:Hide()
        button.spell = nil
        button.sortKey = nil
        button.spellText = nil
        button.fullName = nil
    end)
end

LoadList = function()
    if dialog
        and AF.IsDialogActive(dialog)
        and dialog:GetParent() == contentPane.scroll
    then
        dialog:Hide()
        dialog = nil
    end

    -- A shared AF picker retains its owner until the session closes. End that
    -- session before pooled buttons can be rebound to different spell IDs.
    AF.CancelColorPicker()
    colorPool:ReleaseAll()
    local items = {}
    local search = contentPane.search:GetValue():lower()

    for spellID, color in next, A.config.colors do
        local validSpellID = IsPositiveInteger(spellID)
        local name, icon
        if validSpellID then
            name, icon = AF.GetSpellInfo(spellID, true)
        end
        local searchName = name and name:lower() or ""
        local spellText = tostring(spellID)
        if AF.IsBlank(search)
            or searchName:find(search, 1, true)
            or spellText:find(search, 1, true)
        then
            local button = colorPool:Acquire()
            items[#items + 1] = button
            button.spell = spellID
            button.sortKey = validSpellID and spellID or huge
            button.spellText = spellText
            button.colorPicker:SetColor(GetDisplayColor(color))
            button.idText:SetText(spellText)
            button.fullName = name or L["Unknown Spell"]
            button.nameText:SetText(button.fullName)
            button:SetTexture(
                icon or AF.GetIcon("QuestionMark"),
                nil,
                nil,
                nil,
                "black"
            )
        end
    end

    AF.Sort(
        items,
        "sortKey",
        "ascending",
        "spellText",
        "ascending"
    )
    contentPane.scroll:SetWidgets(items)
    for _, button in ipairs(items) do
        if button:IsShown() then
            button:Update()
        end
    end
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which == "auras" and aurasPanel then
        LoadList()
    end
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "auras" then
        if not aurasPanel then
            CreateAurasPanel()
            CreateContentPane()
            LoadList()
        end
        aurasPanel:Show()
    elseif aurasPanel then
        aurasPanel:Hide()
    end
end)
