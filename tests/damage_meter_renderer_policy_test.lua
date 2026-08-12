local function readFile(path)
    local file, openError = io.open(path, "r")
    if not file then
        error(openError or ("unable to open " .. path), 2)
    end

    local contents = file:read("*a")
    file:close()
    return contents
end

local function assertContains(contents, text, message)
    if not contents:find(text, 1, true) then
        error(message .. ": missing " .. text, 2)
    end
end

local function assertNotContains(contents, text, message)
    if contents:find(text, 1, true) then
        error(message .. ": found " .. text, 2)
    end
end

local function countPlain(contents, text)
    local count = 0
    local start = 1
    while true do
        local found = contents:find(text, start, true)
        if not found then return count end
        count = count + 1
        start = found + #text
    end
end

local function assertCount(contents, text, expected, message)
    local actual = countPlain(contents, text)
    if actual ~= expected then
        error(("%s: expected %d, got %d for %s"):format(
            message,
            expected,
            actual,
            text
        ), 2)
    end
end

local function assertBefore(contents, first, second, message)
    local firstAt = contents:find(first, 1, true)
    local secondAt = contents:find(second, 1, true)
    if not firstAt or not secondAt or firstAt >= secondAt then
        error(message, 2)
    end
end

local function extractSection(contents, first, second, message)
    local firstAt = contents:find(first, 1, true)
    local secondAt = firstAt
        and contents:find(second, firstAt + #first, true)
    if not firstAt or not secondAt then
        error(message, 2)
    end
    return contents:sub(firstAt, secondAt - 1)
end

local function removeSection(contents, first, second, message)
    local firstAt = contents:find(first, 1, true)
    local secondAt = firstAt
        and contents:find(second, firstAt + #first, true)
    if not firstAt or not secondAt then
        error(message, 2)
    end
    return contents:sub(1, firstAt - 1) .. contents:sub(secondAt)
end

local function stripLineComments(contents)
    local lines = {}
    for line in contents:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line:gsub("%-%-.*$", "")
    end
    return table.concat(lines, "\n")
end

local function assertOnlyInSections(
    contents,
    text,
    sections,
    message
)
    local approved = 0
    for _, section in ipairs(sections) do
        approved = approved + countPlain(section, text)
    end
    assertCount(contents, text, approved, message)
end

local function assertDataMethodAllowlist(contents, expected)
    local actual = {}
    for method in contents:gmatch("DM%.Data%.([%a_][%w_]*)") do
        actual[method] = (actual[method] or 0) + 1
    end

    for method, count in pairs(actual) do
        if expected[method] ~= count then
            error((
                "unapproved Damage Meter data getter (%dx): %s"
            ):format(count, method), 2)
        end
    end
    for method, count in pairs(expected) do
        if actual[method] ~= count then
            error((
                "Damage Meter data getter changed: expected %dx, got %dx: %s"
            ):format(count, actual[method] or 0, method), 2)
        end
    end
end

local function assertNoRetainedPayloadAssignments(contents)
    local payloads = {
        enemyDetail = true,
        enemySession = true,
        events = true,
        session = true,
        source = true,
        sourceDetail = true,
        spell = true,
        spells = true,
    }

    for rawLine in contents:gmatch("[^\r\n]+") do
        local line = rawLine:gsub("%-%-.*$", "")
        line = line:match("^%s*(.-)%s*$")
        local lhs, rhs = line:match("^(.-)%s*=%s*(.-)%s*,?$")
        local isLocal = lhs and lhs:match("^local%s+") ~= nil
        if lhs and not isLocal then
            local retained = rhs:match("^([%a_][%w_]*)$")
            if retained and payloads[retained] then
                error(
                    "renderer must not retain a source/session/spell payload: "
                        .. line,
                    2
                )
            end
            if rhs:find("^source%.sourceGUID%f[^%w_]")
                or rhs:find("^source%.sourceCreatureID%f[^%w_]")
                or rhs:find("^sourceDetail%.combatSpells%f[^%w_]")
                or rhs:find("^enemyDetail%.combatSpells%f[^%w_]")
            then
                error(
                    "renderer must not retain secret detail identifiers: "
                        .. line,
                    2
                )
            end
        end

        if line:find("%f[%w_]sourceGUID%f[^%w_]%s*=%s*[^=]")
            or line:find(
                "%f[%w_]sourceCreatureID%f[^%w_]%s*=%s*[^=]"
            )
            or line:find("%f[%w_]combatSpells%f[^%w_]%s*=%s*[^=]")
            or line:find(
                "%f[%w_]source%f[^%w_]%s*=%s*source%f[^%w_]"
            )
            or line:find(
                "%f[%w_]session%f[^%w_]%s*=%s*session%f[^%w_]"
            )
            or line:find(
                "%f[%w_]spell%f[^%w_]%s*=%s*spell%f[^%w_]"
            )
            or line:find(
                "%f[%w_]spells%f[^%w_]%s*=%s*spells%f[^%w_]"
            )
        then
            error(
                "renderer must not copy secret detail payloads into state: "
                    .. line,
                2
            )
        end
    end
end

local function assertIdentifierLineAllowlist(
    contents,
    identifier,
    expected,
    message
)
    local actual = {}
    for rawLine in contents:gmatch("[^\r\n]+") do
        local line = rawLine:gsub("%-%-.*$", "")
        line = line:match("^%s*(.-)%s*$")
        if line:find(
            "%f[%w_]" .. identifier .. "%f[^%w_]"
        ) then
            actual[line] = (actual[line] or 0) + 1
        end
    end

    for line, count in pairs(actual) do
        if expected[line] ~= count then
            error(("%s: unapproved use (%dx): %s"):format(
                message,
                count,
                line
            ), 2)
        end
    end
    for line, count in pairs(expected) do
        if actual[line] ~= count then
            error(("%s: expected %dx, got %dx: %s"):format(
                message,
                count,
                actual[line] or 0,
                line
            ), 2)
        end
    end
end

local renderer = readFile("Modules/DamageMeter/Renderer.lua")
local rendererCode = stripLineComments(renderer)
local aggregateRenderer = removeSection(
    rendererCode,
    "local function FormatDetailNumber(value)",
    "local function ToggleMinimized(window)",
    "unable to isolate the reviewed out-of-combat detail report"
)

local forbiddenEverywhere = {
    "hooksecurefunc",
    "issecret" .. "value",
    "F.isValueNonSecret",
    "_G.C_DamageMeter",
    "C_DamageMeter.",
    "GetCombatSessionSource",
    "DamageMeterSourceWindow",
    "ShowSourceWindow",
    "pcall(",
    "xpcall(",
}
for _, text in ipairs(forbiddenEverywhere) do
    assertNotContains(
        rendererCode,
        text,
        "renderer must use only the reviewed public data adapter"
    )
end

local forbiddenAggregatePatterns = {
    "sourceGUID",
    "sourceCreatureID",
    "deathTimeSeconds",
    "sourceDisplayType",
    "factionGroup",
    "combatSpells",
    "source[",
    "session[",
    "table.sort",
    "AF.FormatNumber(",
    "tostring(source.",
    "type(session)",
}
for _, text in ipairs(forbiddenAggregatePatterns) do
    assertNotContains(
        aggregateRenderer,
        text,
        "aggregate renderer must remain on its secret-safe field allowlist"
    )
end

assertDataMethodAllowlist(rendererCode, {
    GetAvailableSessions = 1,
    GetCurrentSession = 1,
    GetCurrentSource = 1,
    GetHistoricalSession = 1,
    GetHistoricalSource = 1,
    GetOverallSession = 1,
    GetOverallSource = 1,
    IsAvailable = 1,
})
assertNoRetainedPayloadAssignments(rendererCode)

local detailSourceData = extractSection(
    rendererCode,
    "local function GetDetailSourceData(",
    "local function BuildStandardDetailEntries(",
    "unable to isolate the detail source adapter"
)
local standardDetails = extractSection(
    rendererCode,
    "local function BuildStandardDetailEntries(",
    "local function GetDeathEventName(",
    "unable to isolate standard detail construction"
)
local deathDetails = extractSection(
    rendererCode,
    "local function BuildDeathDetailEntries(",
    "local function CreateDetailRow(",
    "unable to isolate death detail construction"
)
local detailRow = extractSection(
    rendererCode,
    "local function CreateDetailRow(",
    "local function CreateDetailPanel(",
    "unable to isolate detail-row tooltip handling"
)
local renderDetails = extractSection(
    rendererCode,
    "local function RenderDetailEntries(",
    "RefreshWindowDetails = function(window)",
    "unable to isolate detail report rendering"
)
local refreshDetails = extractSection(
    rendererCode,
    "RefreshWindowDetails = function(window)",
    "CloseWindowDetails = function(window",
    "unable to isolate detail report refresh"
)
local openDetails = extractSection(
    rendererCode,
    "OpenWindowDetails = function(window",
    "ScrollWindowDetails = function(window",
    "unable to isolate detail report opening"
)
local scrollDetails = extractSection(
    rendererCode,
    "ScrollWindowDetails = function(window",
    "local function ToggleMinimized(window)",
    "unable to isolate detail report scrolling"
)
local hoverCard = extractSection(
    rendererCode,
    "local function ConfigureRowHoverCard(row)",
    "local function CreateRow(parent, window)",
    "unable to isolate aggregate row hover details"
)

assertCount(
    detailSourceData,
    "sourceGUID",
    3,
    "detail source GUID use changed"
)
assertOnlyInSections(
    rendererCode,
    "sourceGUID",
    {detailSourceData},
    "source GUID is allowed only in the reviewed detail adapter"
)
assertCount(
    detailSourceData,
    "sourceCreatureID",
    3,
    "detail source creature ID use changed"
)
assertOnlyInSections(
    rendererCode,
    "sourceCreatureID",
    {detailSourceData},
    "source creature ID is allowed only in the reviewed detail adapter"
)
assertCount(
    standardDetails,
    "combatSpells",
    1,
    "standard spell traversal changed"
)
assertOnlyInSections(
    rendererCode,
    "combatSpells",
    {standardDetails},
    "combat spell tables are allowed only in reviewed detail builders"
)
assertNotContains(
    rendererCode,
    "BuildDamageTargetEntries(",
    "damage details must not join conditional-secret source names"
)
assertNotContains(
    rendererCode,
    "BuildEnemyPlayerEntries(",
    "enemy details must not group secret-capable player names"
)
assertNotContains(
    standardDetails,
    "combatSpellDetails",
    "spell details must not inspect secret-capable unit identities"
)
assertNotContains(
    rendererCode,
    ".unitName",
    "damage details must not inspect secret-capable unit names"
)

assertCount(
    rendererCode,
    "GetDetailSourceData(",
    2,
    "detail source adapter call graph changed"
)
assertCount(
    rendererCode,
    "BuildStandardDetailEntries(",
    2,
    "standard detail builder call graph changed"
)
assertCount(
    rendererCode,
    "BuildDeathDetailEntries(",
    2,
    "death detail builder call graph changed"
)
assertCount(
    rendererCode,
    "RenderDetailEntries(",
    2,
    "detail renderer call graph changed"
)
assertContains(
    renderDetails,
    'window.detailTitle:SetText(_G.Ambiguate(source.name, "short"))',
    "guarded detail titles must keep Blizzard's approved text pipeline"
)

assertContains(
    refreshDetails,
    'type(_G.InCombatLockdown) == "function"',
    "detail refresh must detect combat lockdown"
)
assertBefore(
    refreshDetails,
    "_G.InCombatLockdown()",
    "local config = GetConfig()",
    "detail refresh must leave combat before reading report data"
)
assertContains(
    openDetails,
    'type(_G.InCombatLockdown) == "function"',
    "detail report opening must detect combat lockdown"
)
assertBefore(
    openDetails,
    "_G.InCombatLockdown()",
    "window.detailOpen = true",
    "detail report must not open in combat"
)
assertContains(
    scrollDetails,
    'type(_G.InCombatLockdown) == "function"',
    "detail report scrolling must detect combat lockdown"
)
assertBefore(
    scrollDetails,
    "_G.InCombatLockdown()",
    "local offset = window.detailOffset or 0",
    "detail report must not read scroll state in combat"
)
assertBefore(
    detailRow,
    "_G.InCombatLockdown()",
    "tooltip:SetSpellByID(row.spellID)",
    "spell tooltips must be suppressed in combat"
)
assertContains(
    hoverCard,
    'type(_G.InCombatLockdown) == "function"',
    "aggregate hover cards must detect combat lockdown"
)
assertContains(
    hoverCard,
    "card.totalLabel:SetShown(not inCombat)",
    "aggregate hover cards must hide detail values in combat"
)
assertContains(
    hoverCard,
    'L["Detailed information is secret while in combat."]',
    "aggregate hover cards must explain their combat-safe fallback"
)

assertContains(
    deathDetails,
    "local api = _G.C_DeathRecap",
    "out-of-combat death details may use Blizzard's recap API"
)
assertContains(
    deathDetails,
    "api.GetRecapEvents(recapID)",
    "death reports must request recap events only in the guarded builder"
)

local eventHandling = extractSection(
    rendererCode,
    "local function EnsureEventFrame()",
    "local function RegisterEvents()",
    "unable to isolate Damage Meter event handling"
)
local combatEvent = extractSection(
    eventHandling,
    'elseif event == "PLAYER_REGEN_DISABLED" then',
    "else",
    "unable to isolate the combat-entry event"
)
assertBefore(
    combatEvent,
    "CloseAllWindowDetails()",
    "Renderer.Refresh()",
    "combat entry must close details before aggregate refresh"
)
assertContains(
    rendererCode,
    'eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")',
    "renderer must tear down detail reports on combat entry"
)

assertIdentifierLineAllowlist(aggregateRenderer, "source", {
    ["AF.FormatSecretNumber(source.amountPerSecond)"] = 3,
    ["AF.FormatSecretNumber(source.totalAmount)"] = 2,
    ["UpdateRow(row, source, sourceIndex, session, config)"] = 1,
    ["for index, source in ipairs(session.combatSources) do"] = 1,
    ["if alwaysShowLocalPlayer and source.isLocalPlayer then"] = 1,
    ["local function UpdateRow(row, source, index, session, config)"] = 1,
    ["local source = session.combatSources[sourceIndex]"] = 1,
    ["r, g, b = AF.GetClassColor(source.classFilename)"] = 1,
    ["UpdateSourceIcon(row, source.specIconID, source.classFilename)"] = 1,
    ["row.bar:SetValue(source.totalAmount)"] = 1,
    ["row.deathRecapID = source.deathRecapID"] = 1,
    ["row.hoverCard.playerBadge:SetShown(source.isLocalPlayer == true)"] = 1,
    ["row.hoverCard.shareBar:SetValue(source.totalAmount)"] = 1,
    ['row.hoverCard.title:SetText(_G.Ambiguate(source.name, "short"))'] = 1,
    ['row.name:SetText(_G.Ambiguate(source.name, "short"))'] = 1,
    ["row.total:SetText(AF.FormatSecretNumber(source.totalAmount))"] = 1,
}, "every whole combat-source use must stay on the reviewed safe path")

local sourceFieldCounts = {
    amountPerSecond = 3,
    classFilename = 2,
    deathRecapID = 1,
    isLocalPlayer = 2,
    name = 2,
    specIconID = 1,
    totalAmount = 5,
}
for field, count in pairs(sourceFieldCounts) do
    assertCount(
        aggregateRenderer,
        "source." .. field,
        count,
        "combat-source field allowlist changed"
    )
end

local sessionFieldCounts = {
    combatSources = 4,
    maxAmount = 1,
    totalAmount = 2,
}
for field, count in pairs(sessionFieldCounts) do
    assertCount(
        aggregateRenderer,
        "session." .. field,
        count,
        "combat-session field allowlist changed"
    )
end

assertContains(
    rendererCode,
    "DM.Data.GetCurrentSession(meterType)",
    "renderer must use the public Damage Meter data adapter"
)
assertContains(
    rendererCode,
    "DM.Data.GetOverallSession(meterType)",
    "renderer must expose Blizzard's overall session"
)
assertContains(
    rendererCode,
    "DM.Data.GetHistoricalSession(sessionID, meterType)",
    "renderer must expose historical sessions through the same safe path"
)
assertContains(
    rendererCode,
    "DM.Data.GetAvailableSessions()",
    "session picker must use Blizzard's non-secret session metadata"
)
assertContains(
    aggregateRenderer,
    "row.bar:SetMinMaxValues(0, session.maxAmount)",
    "session maximum must go directly to the approved StatusBar sink"
)
assertContains(
    aggregateRenderer,
    "row.bar:SetValue(source.totalAmount)",
    "source amount must go directly to the approved StatusBar sink"
)
assertContains(
    aggregateRenderer,
    'row.name:SetText(_G.Ambiguate(source.name, "short"))',
    "secret-capable names must use Blizzard's approved text pipeline"
)
assertContains(
    aggregateRenderer,
    "AF.FormatSecretNumber(source.totalAmount)",
    "secret-capable totals must use AF's canonical formatter"
)
assertContains(
    aggregateRenderer,
    "AF.FormatSecretNumber(source.amountPerSecond)",
    "secret-capable rates must use AF's canonical formatter"
)
assertContains(
    aggregateRenderer,
    "AF.GetClassColor(source.classFilename)",
    "addon-owned bars must support class colors"
)
assertContains(
    aggregateRenderer,
    "UpdateSourceIcon(row, source.specIconID, source.classFilename)",
    "addon-owned rows must support specialization and class icons"
)
assertContains(
    aggregateRenderer,
    "row.icon:SetAtlas(classAtlas, false, nil, true)",
    "followers without a specialization icon must use their class atlas"
)
assertContains(
    rendererCode,
    'F.OpenOptionsFrame("damageMeter")',
    "each BFI meter gear must open BFI Damage Meter settings"
)
assertContains(
    rendererCode,
    "local MAX_WINDOWS = 3",
    "focused renderer supports the requested three meters"
)
assertContains(
    rendererCode,
    "DM.Native.SetEnabled(false)",
    "BFI renderer hides the native meter through its sanctioned CVar"
)
assertContains(
    rendererCode,
    "_G.BFICVarBackup",
    "native restore bookkeeping must live outside shareable profiles"
)
assertNotContains(
    rendererCode,
    "config.nativeEnabledBeforeBFI",
    "renderer must never serialize native CVar state into a profile"
)

assertNotContains(
    rendererCode,
    "AF.CreateGradientTexture(",
    "Damage Meter title bars must keep the shared flat BFI styling"
)
assertNotContains(
    rendererCode,
    "accentHeader",
    "removed Damage Meter accent-header state must not return"
)
assertNotContains(
    rendererCode,
    "header.tex",
    "flat Damage Meter title bars must not retain a texture overlay"
)
assertContains(
    rendererCode,
    "local window = AF.CreateBorderedFrame(",
    "Damage Meter windows must use the shared bordered surface"
)
assertNotContains(
    rendererCode,
    "AF.ApplyDefaultBackdrop_NoBorder(header)",
    "Damage Meter headers must not cover the window border"
)
assertNotContains(
    rendererCode,
    "AF.ApplyDefaultBackdrop_NoBorder(body)",
    "Damage Meter bodies must not cover the window border"
)

local flatDropdown = extractSection(
    rendererCode,
    "local function ApplyFlatDropdownStyle(dropdown)",
    "local function CreateRowHoverCard(row)",
    "unable to isolate flat dropdown styling"
)
assertContains(
    flatDropdown,
    'dropdown:SetBackdropColor(AF.GetColorRGB("none"))',
    "flat dropdowns must remove their background"
)
assertContains(
    flatDropdown,
    'dropdown:SetBackdropBorderColor(AF.GetColorRGB("none"))',
    "flat dropdowns must remove their border"
)
assertContains(
    flatDropdown,
    "button.bg:Hide()",
    "flat dropdowns must hide the AF button fill"
)
assertCount(
    rendererCode,
    "ApplyFlatDropdownStyle(",
    3,
    "both title-bar dropdowns must use the flat style helper"
)

assertCount(
    rendererCode,
    'AF.GetIcon("Link")',
    2,
    "dock control must keep the AF Link icon"
)
assertContains(
    rendererCode,
    "Drag this window on top to another highlighted window and release to anchor it",
    "dock tooltip must explain the highlighted drop target"
)
assertNotContains(
    rendererCode,
    'AF.GetIcon("Menu3")',
    "dock control must not regress to the generic menu icon"
)

assertCount(
    rendererCode,
    'rank:SetJustifyH("LEFT")',
    2,
    "aggregate and detail ranks must use the left row cluster"
)
assertNotContains(
    rendererCode,
    'rank:SetJustifyH("RIGHT")',
    "row ranks must not regress to a detached right alignment"
)
assertCount(
    rendererCode,
    'row.iconHolder:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)',
    2,
    "aggregate and detail icons must follow their ranks"
)
assertContains(
    rendererCode,
    'row.name:SetPoint("LEFT", row.iconHolder, "RIGHT", 3, 0)',
    "aggregate names must follow visible icons"
)
assertContains(
    rendererCode,
    'row.name:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)',
    "aggregate names must follow ranks when icons are hidden"
)

local lockIcon = extractSection(
    rendererCode,
    "local function GetLockButtonIcon(locked)",
    "local function ApplyFlatDropdownStyle(dropdown)",
    "unable to isolate adaptive Damage Meter lock icons"
)
assertContains(
    lockIcon,
    "AF.hasLockIcons and AF.GetAdaptiveIcon",
    "lock icons must require the shared AF icon capability"
)
assertContains(
    lockIcon,
    'AF.GetAdaptiveIcon(locked and "Lock" or "Unlock")',
    "lock icons must use AF's adaptive raster-safe path"
)
assertNotContains(
    lockIcon,
    ".svg",
    "ordinary Texture lock controls must not receive SVG paths"
)
assertNotContains(
    lockIcon,
    "GetBuildInfo",
    "lock icon safety must not depend on a client-version guess"
)
assertNotContains(
    rendererCode,
    "SVG_INTERFACE_VERSION",
    "the removed Texture SVG version gate must not return"
)
assertContains(
    lockIcon,
    'locked and "Unavailable" or "Anchor_CENTER"',
    "Retail 12.0.7 must retain AF raster lock fallbacks"
)
assertCount(
    rendererCode,
    "GetLockButtonIcon(",
    3,
    "both lock-button states must use the versioned icon helper"
)
assertNotContains(
    rendererCode,
    'AF.GetIcon("SmallLock")',
    "Damage Meter lock control must not use an unavailable AF icon"
)

local options = readFile("Options/DamageMeter.lua")
assertNotContains(
    options,
    "accentHeader",
    "removed Damage Meter accent-header option must not return"
)
assertNotContains(
    options,
    "Accent Header",
    "removed Damage Meter accent-header label must not return"
)
local defaults = readFile("Modules/DamageMeter/Defaults.lua")
assertNotContains(
    defaults,
    "accentHeader",
    "removed Damage Meter accent-header default must not return"
)
assertContains(
    options,
    "AF.LSM_GetBarTextureDropdownItems()",
    "BFI appearance settings expose AF bar textures"
)
assertContains(
    options,
    "DM.config.padding = value",
    "BFI appearance settings expose live row padding"
)
assertContains(
    options,
    "DM.config.windowHeights[index] = value",
    "each BFI meter exposes a live independent height"
)
assertContains(
    rendererCode,
    'AF.Fire("BFI_RefreshOptions", "damageMeter")',
    "completed meter resizes must refresh open Damage Meter options"
)
assertContains(
    options,
    "DM.config.locked = checked",
    "BFI meter movement and resizing expose a shared live lock"
)
assertContains(
    options,
    'pane.tips:SetTipsPosition("BOTTOMRIGHT", 0, 0)',
    "right-edge help must expand inward inside the settings viewport"
)
assertContains(
    options,
    "pane:SetTips(title, body)",
    "settings help must provide a distinct title and body"
)
assertContains(
    options,
    "hasMessage and GENERAL_STATUS_HEIGHT or GENERAL_HEIGHT",
    "the first settings pane must reserve status space only when needed"
)

local forbiddenOptionsPatterns = {
    "Damage Meter Native Settings Read Only",
    "DM.Native.GetSetting",
    "DM.Native.SetSetting",
    "DM.Native.Configure",
    "InCombatLockdown",
    "ApplyCombatProtectionToWidget",
}

for _, text in ipairs(forbiddenOptionsPatterns) do
    assertNotContains(
        options,
        text,
        "BFI-owned meter settings must remain live and writable"
    )
end

local native = readFile("Modules/DamageMeter/Native.lua")
local forbiddenNativeWrites = {
    "function Native.SetSetting",
    "function Native.ConfigureWindows",
    "function Native.ConfigureWindowCount",
    "SetSessionWindowDamageMeterType",
    "ShowNewSecondarySessionWindow",
    "HideSessionWindow",
    "OnSystemSettingChange",
}

for _, text in ipairs(forbiddenNativeWrites) do
    assertNotContains(
        native,
        text,
        "native secret-bearing rows and Edit Mode state remain untouched"
    )
end

local loadOrder = readFile("Modules/DamageMeter/Load.xml")
local rendererAt = loadOrder:find(
    '<Script file="Renderer.lua"/>',
    1,
    true
)
local lifecycleAt = loadOrder:find(
    '<Script file="DamageMeter.lua"/>',
    1,
    true
)
local automationAt = loadOrder:find(
    '<Script file="Automation.lua"/>',
    1,
    true
)
if not rendererAt
    or not automationAt
    or not lifecycleAt
    or rendererAt >= automationAt
    or automationAt >= lifecycleAt
then
    error(
        "renderer and automation must load before the Damage Meter lifecycle",
        2
    )
end

print("damage_meter_renderer_policy_test.lua: ok")
