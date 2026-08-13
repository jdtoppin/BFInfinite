local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local secret = setmetatable({}, {
    __concat = function()
        error("secret identity value must not be concatenated", 2)
    end,
})
local state = {
    inRaid = true,
    name = "Public",
    server = "Realm",
    class = "MAGE",
    guid = "Player-1",
    isPlayer = true,
    inVehicle = false,
    role = "HEALER",
    leader = true,
    assistant = false,
    phaseReason = 2,
}

UnitName = function()
    return state.name, state.server
end
IsInRaid = function()
    return state.inRaid
end
UnitGUID = function()
    return state.guid
end
UnitGroupRolesAssigned = function()
    return state.role
end
UnitHasVehicleUI = function()
    return state.inVehicle
end
UnitIsGroupAssistant = function()
    return state.assistant
end
UnitIsGroupLeader = function()
    return state.leader
end
UnitIsPlayer = function()
    return state.isPlayer
end
UnitPhaseReason = function()
    return state.phaseReason
end

local UF = {}
local AF = {
    funcs = {},
    UnitClassBase = function()
        return state.class
    end,
}
local BFI = {
    funcs = {
        isValueNonSecret = function(value)
            return not rawequal(value, secret)
        end,
    },
    modules = {
        UnitFrames = UF,
    },
}
_G.AbstractFramework = AF

local identityChunk =
    assert(loadfile("Modules/UnitFrames/SecretIdentity.lua"))
identityChunk("BFInfinite", BFI)

local value, valuePublic = UF.GetPublicUnitIdentityValue("public")
assertEqual(value, "public", "ordinary identity value")
assertEqual(valuePublic, true, "ordinary identity access")
value, valuePublic = UF.GetPublicUnitIdentityValue(secret)
assertEqual(value, nil, "secret identity value")
assertEqual(valuePublic, false, "secret identity access")

local publicName, namePublic = UF.GetPublicUnitName("target")
assertEqual(publicName, "Public-Realm", "public full unit name")
assertEqual(namePublic, true, "public full unit name access")

state.server = ""
publicName, namePublic = UF.GetPublicUnitName("target")
assertEqual(publicName, "Public", "empty realm unit name")
assertEqual(namePublic, true, "empty realm unit name access")

state.name = secret
state.server = "Realm"
publicName, namePublic = UF.GetPublicUnitName("target")
assertEqual(publicName, nil, "secret name is rejected")
assertEqual(namePublic, false, "secret name access")

state.name = "Public"
state.server = secret
publicName, namePublic = UF.GetPublicUnitName("target")
assertEqual(publicName, nil, "secret realm is rejected")
assertEqual(namePublic, false, "secret realm access")

state.name = "Public"
state.server = "Realm"
local snapshot = UF.GetPublicUnitIdentitySnapshot("target")
assertEqual(snapshot.name, "Public-Realm", "public snapshot name")
assertEqual(snapshot.class, state.class, "public snapshot class")
assertEqual(snapshot.guid, state.guid, "public snapshot guid")
assertEqual(snapshot.isPlayer, true, "public snapshot player")
assertEqual(snapshot.inVehicle, false, "public snapshot vehicle")

state.name = secret
state.server = "Realm"
state.class = secret
state.guid = secret
state.isPlayer = secret
state.inVehicle = secret
snapshot = UF.GetPublicUnitIdentitySnapshot("target")
assertEqual(snapshot.name, nil, "secret snapshot name")
assertEqual(snapshot.class, nil, "secret snapshot class")
assertEqual(snapshot.guid, nil, "secret snapshot guid")
assertEqual(snapshot.isPlayer, nil, "secret snapshot player")
assertEqual(snapshot.inVehicle, nil, "secret snapshot vehicle")

state.role = "TANK"
local role, rolePublic = UF.GetPublicUnitGroupRole("target")
assertEqual(role, "TANK", "public role")
assertEqual(rolePublic, true, "public role access")
state.role = secret
role, rolePublic = UF.GetPublicUnitGroupRole("target")
assertEqual(role, nil, "secret role")
assertEqual(rolePublic, false, "secret role access")

state.leader = true
state.assistant = false
local leader, assistant, leadershipPublic =
    UF.GetPublicUnitLeadership("target")
assertEqual(leader, true, "public leader")
assertEqual(assistant, false, "public assistant")
assertEqual(leadershipPublic, true, "public leadership access")

state.leader = secret
leader, assistant, leadershipPublic =
    UF.GetPublicUnitLeadership("target")
assertEqual(leader, false, "secret leader fallback")
assertEqual(assistant, false, "secret assistant fallback")
assertEqual(leadershipPublic, false, "secret leader access")

state.leader = false
state.assistant = secret
leader, assistant, leadershipPublic =
    UF.GetPublicUnitLeadership("target")
assertEqual(leader, false, "public non-leader")
assertEqual(assistant, false, "secret assistant fallback")
assertEqual(leadershipPublic, false, "secret assistant access")

state.phaseReason = 3
local phaseReason, phasePublic =
    UF.GetPublicUnitPhaseReason("target")
assertEqual(phaseReason, 3, "public phase reason")
assertEqual(phasePublic, true, "public phase access")
state.phaseReason = secret
phaseReason, phasePublic =
    UF.GetPublicUnitPhaseReason("target")
assertEqual(phaseReason, nil, "secret phase reason")
assertEqual(phasePublic, false, "secret phase access")

local function newRegion()
    local region = {
        shown = false,
        text = "",
    }

    function region:CreateFontString()
        return newRegion()
    end

    function region:CreateTexture()
        return newRegion()
    end

    function region:Hide()
        self.shown = false
    end

    function region:Show()
        self.shown = true
    end

    function region:SetAtlas(atlas)
        self.atlas = atlas
    end

    function region:SetPoint()
    end

    function region:SetText(text)
        self.text = text
    end

    function region:SetTextColor(...)
        self.textColor = {...}
    end

    function region:SetVertexColor(...)
        self.vertexColor = {...}
    end

    function region:SetAllPoints()
    end

    function region:SetShown(shown)
        self.shown = shown
    end

    function region:RegisterEvent()
    end

    function region:UnregisterAllEvents()
    end

    return region
end

CreateFrame = function()
    return newRegion()
end

AF.AddEventHandler = function()
end
AF.ApplyDefaultTexCoord = function()
end
AF.GetClassColor = function()
    return 0.4, 0.4, 0.4
end
AF.GetReactionColor = function()
    return 0.5, 0.5, 0.5
end
AF.SetFrameLevel = function()
end
AF.SetFont = function()
end
AF.SetSize = function()
end
AF.UnitIsPlayer = function()
    return true
end
AF.UnpackColor = function(color)
    return unpack(color)
end
AF.noop = function()
end
AF.Glyphs = {
    Group = {
        assistant = {char = "A"},
        leader = {char = "L"},
    },
    Role = {
        DAMAGER = {char = "D"},
        HEALER = {char = "H"},
        TANK = {char = "T"},
    },
    SetFont = function()
    end,
    SetGlyph = function(region, glyph)
        region.glyph = glyph
        region:SetText(glyph and glyph.char or "")
    end,
}
UF.LoadIndicatorPosition = function()
end

C_IncomingSummon = {
    HasIncomingSummon = function()
        return false
    end,
    IncomingSummonStatus = function()
    end,
}
C_Timer = {
    After = function()
    end,
}
Enum = {
    SummonStatus = {
        Accepted = 2,
        Declined = 3,
        Pending = 1,
    },
}
UnitHasIncomingResurrection = function()
    return false
end
UnitInOtherParty = function()
    return false
end

local parent = newRegion()
parent.unit = "target"

assert(loadfile("Modules/UnitFrames/Indicators/RoleIcon.lua"))(
    "BFInfinite",
    BFI
)
local roleIcon = UF.CreateRoleIcon(parent, "Role")
roleIcon.hideDamager = false
state.role = "HEALER"
roleIcon:Update()
assertEqual(roleIcon.shown, true, "public role icon visibility")
assertEqual(roleIcon.text.text, "H", "public role glyph")
state.role = secret
roleIcon:Update()
assertEqual(roleIcon.shown, false, "secret role icon visibility")
assertEqual(roleIcon.text.text, "", "secret role glyph cleared")

assert(loadfile("Modules/UnitFrames/Indicators/LeaderIcon.lua"))(
    "BFInfinite",
    BFI
)
local leaderIcon = UF.CreateLeaderIcon(parent, "Leader")
state.leader = true
state.assistant = false
leaderIcon:Update()
assertEqual(leaderIcon.shown, true, "public leader icon visibility")
assertEqual(leaderIcon.text.text, "L", "public leader glyph")
state.leader = secret
leaderIcon:Update()
assertEqual(leaderIcon.shown, false, "secret leader icon visibility")
assertEqual(leaderIcon.text.text, "", "secret leader glyph cleared")

assert(loadfile("Modules/UnitFrames/Indicators/LeaderText.lua"))(
    "BFInfinite",
    BFI
)
local leaderText = UF.CreateLeaderText(parent, "LeaderText")
leaderText.color = {
    type = "custom_color",
    rgb = {1, 1, 1},
}
state.leader = true
leaderText:Update()
assertEqual(leaderText.text, "L", "public leader text")
state.leader = secret
leaderText:Update()
assertEqual(leaderText.text, "", "secret leader text cleared")

assert(loadfile("Modules/UnitFrames/Indicators/StatusIcon.lua"))(
    "BFInfinite",
    BFI
)
local statusIcon = UF.CreateStatusIcon(parent, "Status")
state.isPlayer = true
state.phaseReason = 2
statusIcon:Update()
assertEqual(statusIcon.shown, true, "public phase icon visibility")
assertEqual(statusIcon.icon.atlas,
    "RaidFrame-Icon-Phasing",
    "public phase icon atlas")
state.phaseReason = secret
statusIcon:Update()
assertEqual(statusIcon.shown, false, "secret phase icon visibility")
state.isPlayer = secret
state.phaseReason = 2
statusIcon:Update()
assertEqual(statusIcon.shown, false, "secret player identity visibility")

local loadXML = assert(io.open("Modules/UnitFrames/Load.xml", "r"))
local loadSource = loadXML:read("*a")
loadXML:close()
local identityIndex = assert(
    loadSource:find('Script file="SecretIdentity.lua"', 1, true)
)
local buttonIndex = assert(
    loadSource:find('Script file="UnitButton.lua"', 1, true)
)
assertTrue(identityIndex < buttonIndex,
    "secret identity helper must load before UnitButton")

local identityFile = assert(io.open(
    "Modules/UnitFrames/SecretIdentity.lua",
    "r"
))
local identitySource = identityFile:read("*a")
identityFile:close()

assertTrue(
    identitySource:find("GetUnitName(", 1, true) == nil,
    "identity boundary must call direct UnitName"
)
local nameSanitizerIndex = assert(identitySource:find(
    "UF.GetPublicUnitIdentityValue(name)",
    1,
    true
))
local serverSanitizerIndex = assert(identitySource:find(
    "UF.GetPublicUnitIdentityValue(server)",
    1,
    true
))
local serverTruthIndex = assert(identitySource:find(
    "if publicServer",
    1,
    true
))
local serverComparisonIndex = assert(identitySource:find(
    'publicServer ~= ""',
    1,
    true
))
local nameConcatIndex = assert(identitySource:find(
    'publicName .. "-" .. publicServer',
    1,
    true
))
assertTrue(nameSanitizerIndex < serverTruthIndex,
    "name must be sanitized before server truth testing")
assertTrue(serverSanitizerIndex < serverTruthIndex,
    "server must be sanitized before truth testing")
assertTrue(serverSanitizerIndex < serverComparisonIndex,
    "server must be sanitized before comparison")
assertTrue(nameSanitizerIndex < nameConcatIndex,
    "name must be sanitized before concatenation")
assertTrue(serverSanitizerIndex < nameConcatIndex,
    "server must be sanitized before concatenation")

print("unit_frame_secret_identity_test.lua: ok")
