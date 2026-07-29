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

local renderer = readFile("Modules/DamageMeter/Renderer.lua")
local forbiddenRendererPatterns = {
    "hooksecurefunc",
    "issecret" .. "value",
    "F.isValueNonSecret",
    "GetCombatSessionSource",
    "table.sort",
    "AF.FormatNumber(",
    "tostring(source.",
    "type(session",
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

assertContains(
    renderer,
    "DM.Data.GetCurrentSession(meterType)",
    "renderer must use the public Damage Meter data adapter"
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
if not rendererAt or not lifecycleAt or rendererAt >= lifecycleAt then
    error("renderer must load before the Damage Meter lifecycle", 2)
end

print("damage_meter_renderer_policy_test.lua: ok")
