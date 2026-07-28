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

local skin = readFile("Modules/DamageMeter/Skin.lua")
local forbiddenRowAccess = {
    "ScrollUtil.AddInitializedFrameCallback",
    "GetLocalPlayerEntry",
    "Skin.ApplyEntry",
    "_BFIDamageMeterBacking",
    "GetStatusBarTexture",
}

for _, text in ipairs(forbiddenRowAccess) do
    assertNotContains(
        skin,
        text,
        "native secret-bearing rows must remain Blizzard-owned"
    )
end

assertContains(
    skin,
    "local COMPACT_HEADER_HEIGHT = 26",
    "compact native header contract"
)

local options = readFile("Options/DamageMeter.lua")
assertNotContains(
    options,
    "AF.LSM_GetBarTextureDropdownItems()",
    "removed row texture control must not be exposed"
)
assertNotContains(
    options,
    "L[\"Bar Background Opacity\"]",
    "removed row background control must not be exposed"
)
assertNotContains(
    options,
    "DM.Native.SetSetting",
    "native Edit Mode writes must remain read-only"
)
assertNotContains(
    options,
    "DM.Native.Configure",
    "native session windows must remain Blizzard-controlled"
)

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
        "secret-bearing native state must remain read-only"
    )
end

print("damage_meter_skin_policy_test.lua: ok")
