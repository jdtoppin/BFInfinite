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

local secret = {}
local state = {
    inRaid = true,
    name = "Public-Realm",
    class = "MAGE",
    guid = "Player-1",
    isPlayer = true,
    inVehicle = false,
    role = "HEALER",
    leader = true,
    assistant = false,
    phaseReason = 2,
}

GetUnitName = function()
    return state.name
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
            return value ~= secret
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

local snapshot = UF.GetPublicUnitIdentitySnapshot("target")
assertEqual(snapshot.name, state.name, "public snapshot name")
assertEqual(snapshot.class, state.class, "public snapshot class")
assertEqual(snapshot.guid, state.guid, "public snapshot guid")
assertEqual(snapshot.isPlayer, true, "public snapshot player")
assertEqual(snapshot.inVehicle, false, "public snapshot vehicle")

state.name = secret
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

local core = assert(io.open("Core.lua", "r"))
local coreSource = core:read("*a")
core:close()
assertTrue(
    coreSource:find("REQUIRED_AF_VERSION = 39", 1, true) ~= nil,
    "AF r39 dependency gate"
)

print("unit_frame_secret_identity_test.lua: ok")
