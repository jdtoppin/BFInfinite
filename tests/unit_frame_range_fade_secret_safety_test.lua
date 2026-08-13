local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local function stripComments(source)
    source = source:gsub("%-%-%[%[.-%]%]", "")
    return source:gsub("%-%-[^\n]*", "")
end

local function section(source, startPattern, endPattern)
    local startIndex = assert(source:find(startPattern))
    local endIndex = assert(source:find(endPattern, startIndex))
    return stripComments(source:sub(startIndex, endIndex - 1))
end

local function assertNoPattern(source, pattern, message)
    assertTrue(source:find(pattern) == nil, message or pattern)
end

local function assertCallOrder(source, patterns, message)
    local previous = 0
    for _, pattern in ipairs(patterns) do
        local index = assert(source:find(pattern, previous + 1), message)
        assertTrue(index > previous, message)
        previous = index
    end
end

local source = readFile("Modules/UnitFrames/UnitButton.lua")
local rangeUpdateCode = section(
    source,
    "local%s+function%s+UnitButton_UpdateInRange%s*%(",
    "\nlocal%s+function%s+UnitButton_UpdateRangeEventRegistration"
)
local rangeRegistrationCode = section(
    source,
    "local%s+function%s+UnitButton_UpdateRangeEventRegistration%s*%(",
    "\n%-%-%s*update all"
)
local registerCode = section(
    source,
    "local%s+function%s+UnitButton_RegisterEvents%s*%(",
    "\nlocal%s+function%s+UnitButton_UnregisterEvents"
)
local bindingCode = section(
    source,
    "local%s+function%s+UnitButton_RefreshUnitBinding%s*%(",
    "\nlocal%s+function%s+UnitButton_OnEvent"
)
local onEventCode = section(
    source,
    "local%s+function%s+UnitButton_OnEvent%s*%(",
    "\n%-%-%s*onUpdate"
)
local onTickCode = section(
    source,
    "local%s+function%s+UnitButton_OnTick%s*%(",
    "\nlocal%s+function%s+UnitButton_OnUpdate"
)
local onUpdateCode = section(
    source,
    "local%s+function%s+UnitButton_OnUpdate%s*%(",
    "\n%-%-%s*onShow/Hide"
)

-- Retail 12.1.0.68914 documents UnitInRange's two returns as secret.  They
-- must only compose into alpha through C_CurveUtil and Frame:SetAlpha.
for _, forbiddenPattern in ipairs({
    "disabled until the range path is made secret%-safe",
    "AF%.IsInRange",
    "FrameFadeIn",
    "FrameFadeOut",
    ":GetAlpha%s*%(",
    ":SetAlphaFromBoolean%s*%(",
    "states%.inRange",
    "states%.wasInRange",
    "F%.isValueNonSecret%s*%(",
}) do
    assertNoPattern(rangeUpdateCode, forbiddenPattern,
        "forbidden range implementation: " .. forbiddenPattern)
end

local rangeGateStart, rangeGateEnd, rangeGateCondition =
    rangeUpdateCode:find(
        "if%s+(.-)%s+then%s+UnitButton_ResetRangeFade%s*%(%s*self%s*%)"
        .. "%s+return%s+end"
    )
assertTrue(rangeGateStart ~= nil,
    "range must gate ordinary visibility and config mode")
assertTrue(
    rangeGateCondition:find("self:IsVisible%s*%(") ~= nil
        and rangeGateCondition:find("self%.inConfigMode") ~= nil,
    "range gate must include ordinary visibility and config mode"
)

local queryStart = assert(rangeUpdateCode:find(
    "local%s+inRange%s*,%s*checkedRange%s*=%s*UnitInRange%s*%(%s*self%.effectiveUnit%s*%)"
))
assertTrue(rangeGateEnd < queryStart,
    "range must gate before querying UnitInRange")

local nativeAlphaPattern =
    "C_CurveUtil%.EvaluateColorValueFromBoolean%s*%(%s*checkedRange%s*,%s*"
    .. "C_CurveUtil%.EvaluateColorValueFromBoolean%s*%(%s*inRange%s*,%s*1%s*,%s*"
    .. "self%.oorAlpha%s*%)%s*,%s*1%s*%)"
assertTrue(
    rangeUpdateCode:find(
        "self:SetAlpha%s*%(%s*" .. nativeAlphaPattern .. "%s*%)"
    ) ~= nil,
    "the native range alpha must reach the unit-button directly"
)
assertNoPattern(
    rangeUpdateCode,
    "local%s+[_%a][_%w]*%s*=%s*" .. nativeAlphaPattern,
    "the secret-composed alpha must not be stored in Lua"
)

local modelName = rangeUpdateCode:match(
    "local%s+([_%a][_%w]*)%s*=%s*self%._rangeFadeModel"
)
assertTrue(modelName ~= nil, "range fade model local")
assertTrue(
    rangeUpdateCode:find(
        "if%s+" .. modelName .. "%s+then%s+" .. modelName
        .. ":SetAlpha%s*%(%s*" .. nativeAlphaPattern .. "%s*%)%s+end"
    ) ~= nil,
    "the optional range-fade model must receive the direct native alpha"
)

for _, secretValue in ipairs({"inRange", "checkedRange"}) do
    for _, forbiddenPattern in ipairs({
        "%f[%a]if%f[^%a][^\n]*%f[%w]" .. secretValue .. "%f[^%w]",
        "%f[%a]not%f[^%a]%s*" .. secretValue,
        secretValue .. "%s*[~=]=",
        "[~=]=%s*" .. secretValue,
        secretValue .. "%s+and%f[^%a]",
        secretValue .. "%s+or%f[^%a]",
        "%f[^%a]and%s+" .. secretValue,
        "%f[^%a]or%s+" .. secretValue,
    }) do
        assertNoPattern(rangeUpdateCode, forbiddenPattern,
            "secret range result must not drive Lua logic")
    end
end

assertTrue(
    registerCode:find(
        "UnitButton_UpdateRangeEventRegistration%s*%(%s*self%s*%)"
    ) ~= nil,
    "ordinary event setup must update the range registration"
)
assertTrue(
    rangeRegistrationCode:find(
        "self:RegisterUnitEvent%s*%(%s*[\"']UNIT_IN_RANGE_UPDATE[\"']%s*,%s*"
        .. "self%.effectiveUnit%s*%)"
    ) ~= nil,
    "range updates must be C-filtered to the current effective unit"
)
assertTrue(
    rangeRegistrationCode:find(
        "self:UnregisterEvent%s*%(%s*[\"']UNIT_IN_RANGE_UPDATE[\"']%s*%)"
    ) ~= nil,
    "range registration must remove the prior filtered event first"
)
assertNoPattern(rangeRegistrationCode,
    "self:RegisterEvent%s*%(%s*[\"']UNIT_IN_RANGE_UPDATE[\"']",
    "range updates must not use an unfiltered event registration")

assertCallOrder(bindingCode, {
    "UnitButton_UnregisterEvents%s*%(%s*self%s*%)",
    "UnitButton_UpdateStates%s*%(%s*self%s*%)",
    "UnitButton_RegisterEvents%s*%(%s*self%s*%)",
    "UnitButton_UpdateInRange%s*%(%s*self%s*%)",
}, "unit rebind must unregister, update state, register, then seed range")

local rangeEventStart = assert(onEventCode:find(
    "if%s+event%s*==%s*[\"']UNIT_IN_RANGE_UPDATE[\"']%s+then"
))
local rangeEventEnd = assert(onEventCode:find("return%s+end", rangeEventStart))
local rangeEventCode = onEventCode:sub(rangeEventStart, rangeEventEnd)
assertTrue(
    rangeEventCode:find("UnitButton_UpdateInRange%s*%(%s*self%s*%)") ~= nil,
    "range event must re-query through the native range update"
)
assertNoPattern(rangeEventCode, "%.%.%.",
    "range event must not inspect its secret payload")

local onEventHeaderEnd = assert(onEventCode:find("\n"))
local firstPayloadUnpack = onEventCode:find("%.%.%.", onEventHeaderEnd + 1)
assertTrue(firstPayloadUnpack == nil or rangeEventStart < firstPayloadUnpack,
    "range event must be handled before payload unpacking")

assertNoPattern(onTickCode,
    "UnitButton_UpdateInRange%s*%(%s*self%s*%)",
    "the ordinary 0.25-second tick must not poll range")
assertTrue(
    onUpdateCode:find("self%.__updateElapsed%s*>=%s*0%.25") ~= nil,
    "the ordinary unit-button tick must retain its 0.25-second cadence"
)

local portraitCode = stripComments(
    readFile("Modules/UnitFrames/Indicators/Portrait.lua")
)
assertTrue(
    portraitCode:find(
        "portrait%.model:SetIgnoreParentAlpha%s*%(%s*true%s*%)"
    ) ~= nil,
    "the 3-D portrait model must ignore secret parent alpha"
)
assertTrue(
    portraitCode:find(
        "parent%._rangeFadeModel%s*=%s*portrait%.model"
    ) ~= nil,
    "the unit button must retain the dedicated 3-D range-fade model"
)
assertNoPattern(portraitCode, "SetModelAlpha%s*%(",
    "the 3-D portrait must not receive secret alpha through SetModelAlpha")
assertNoPattern(portraitCode, "GetAlpha%s*%(",
    "the 3-D portrait must not read potentially-secret parent alpha")

print("unit_frame_range_fade_secret_safety_test.lua: ok")
