local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

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
        error((message or "missing source contract") .. ": " .. text, 2)
    end
end

local function loadInit(sharedFunction)
    local AF = {
        funcs = sharedFunction and {
            isValueNonSecret = sharedFunction,
        } or nil,
    }
    function AF.RegisterAddon()
    end
    function AF.AddEventHandler()
    end
    function AF.GetTexture()
        return "texture"
    end
    function AF.GetFont()
        return "font"
    end
    function AF.CreateFont()
    end

    local environment = {
        _G = false,
        AbstractFramework = AF,
        LibStub = function()
            return {}
        end,
    }
    environment._G = environment
    setmetatable(environment, {__index = _G})

    local BFI = {}
    local chunk = assert(loadfile("Init.lua"))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return BFI
end

local unsupported = loadInit()
assertEqual(unsupported.requiredAFVersion, 42,
    "global AbstractFramework requirement")
assertContains(readFile("Core.lua"), "local REQUIRED_AF_VERSION = 42",
    "runtime AbstractFramework requirement matches the bootstrap guard")
assertEqual(type(unsupported.funcs.isValueNonSecret), "function",
    "unsupported AF receives a conservative guard")
assertEqual(unsupported.funcs.isValueNonSecret("ordinary"), false,
    "conservative guard rejects values")

local shared = function(value)
    return value ~= "secret"
end
local supported = loadInit(shared)
assertEqual(supported.funcs.isValueNonSecret, shared,
    "supported AF helper is reused")
assertEqual(supported.funcs.isValueNonSecret("ordinary"), true,
    "supported AF helper remains functional")

print("abstract_framework_version_guard_test.lua: ok")
