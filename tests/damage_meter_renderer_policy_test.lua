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
local forbiddenRendererPatterns = {
    "hooksecurefunc",
    "issecret" .. "value",
    "F.isValueNonSecret",
    "GetCombatSessionSource",
    "DamageMeterSourceWindow",
    "ShowSourceWindow",
    "C_DeathRecap.GetRecapEvents",
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
    "pcall(",
    "xpcall(",
}

for _, text in ipairs(forbiddenRendererPatterns) do
    assertNotContains(
        renderer,
        text,
        "custom renderer must keep one secret-safe, native-row-free path"
    )
end

assertIdentifierLineAllowlist(renderer, "source", {
    ["AF.FormatSecretNumber(source.amountPerSecond)"] = 3,
    ["AF.FormatSecretNumber(source.totalAmount)"] = 2,
    ["UpdateRow(row, source, sourceIndex, session, config)"] = 1,
    ["for index, source in ipairs(session.combatSources) do"] = 1,
    ["if alwaysShowLocalPlayer and source.isLocalPlayer then"] = 1,
    ["local function UpdateRow(row, source, index, session, config)"] = 1,
    ["local source = session.combatSources[sourceIndex]"] = 1,
    ["r, g, b = AF.GetClassColor(source.classFilename)"] = 1,
    ["row.bar:SetValue(source.totalAmount)"] = 1,
    ["row.deathRecapID = source.deathRecapID"] = 1,
    ["row.hoverCard.playerBadge:SetShown(source.isLocalPlayer == true)"] = 1,
    ["row.hoverCard.shareBar:SetValue(source.totalAmount)"] = 1,
    ['row.hoverCard.title:SetText(_G.Ambiguate(source.name, "short"))'] = 1,
    ["row.icon:SetTexture(source.specIconID)"] = 1,
    ['row.name:SetText(_G.Ambiguate(source.name, "short"))'] = 1,
    ["row.total:SetText(AF.FormatSecretNumber(source.totalAmount))"] = 1,
}, "every whole combat-source use must stay on the reviewed safe path")

local sourceFieldCounts = {
    amountPerSecond = 3,
    classFilename = 1,
    deathRecapID = 1,
    isLocalPlayer = 2,
    name = 2,
    specIconID = 1,
    totalAmount = 5,
}
for field, count in pairs(sourceFieldCounts) do
    assertCount(
        renderer,
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
        renderer,
        "session." .. field,
        count,
        "combat-session field allowlist changed"
    )
end

assertContains(
    renderer,
    "DM.Data.GetCurrentSession(meterType)",
    "renderer must use the public Damage Meter data adapter"
)
assertContains(
    renderer,
    "DM.Data.GetOverallSession(meterType)",
    "renderer must expose Blizzard's overall session"
)
assertContains(
    renderer,
    "DM.Data.GetHistoricalSession(sessionID, meterType)",
    "renderer must expose historical sessions through the same safe path"
)
assertContains(
    renderer,
    "DM.Data.GetAvailableSessions()",
    "session picker must use Blizzard's non-secret session metadata"
)
assertContains(
    renderer,
    "row.bar:SetMinMaxValues(0, session.maxAmount)",
    "session maximum must go directly to the approved StatusBar sink"
)
assertContains(
    renderer,
    "row.bar:SetValue(source.totalAmount)",
    "source amount must go directly to the approved StatusBar sink"
)
assertContains(
    renderer,
    'row.name:SetText(_G.Ambiguate(source.name, "short"))',
    "secret-capable names must use Blizzard's approved text pipeline"
)
assertContains(
    renderer,
    "AF.FormatSecretNumber(source.totalAmount)",
    "secret-capable totals must use AF's canonical formatter"
)
assertContains(
    renderer,
    "AF.FormatSecretNumber(source.amountPerSecond)",
    "secret-capable rates must use AF's canonical formatter"
)
assertContains(
    renderer,
    "AF.GetClassColor(source.classFilename)",
    "addon-owned bars must support class colors"
)
assertContains(
    renderer,
    "row.icon:SetTexture(source.specIconID)",
    "addon-owned rows must support specialization icons"
)
assertContains(
    renderer,
    "_G.OpenDeathRecapUI(deathRecapID)",
    "death rows must delegate to Blizzard using the never-secret recap ID"
)
assertContains(
    renderer,
    'F.OpenOptionsFrame("damageMeter")',
    "each BFI meter gear must open BFI Damage Meter settings"
)
assertContains(
    renderer,
    "local MAX_WINDOWS = 3",
    "focused renderer supports the requested three meters"
)
assertContains(
    renderer,
    "DM.Native.SetEnabled(false)",
    "BFI renderer hides the native meter through its sanctioned CVar"
)
assertContains(
    renderer,
    "_G.BFICVarBackup",
    "native restore bookkeeping must live outside shareable profiles"
)
assertNotContains(
    renderer,
    "config.nativeEnabledBeforeBFI",
    "renderer must never serialize native CVar state into a profile"
)

local options = readFile("Options/DamageMeter.lua")
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
