local function Fail(message)
    error(message, 0)
end

local source = debug.getinfo(1, "S").source
local scriptPath = source:match("^@(.+)$")
if not scriptPath then
    Fail("Could not locate scripts/generate-changelog.lua")
end

local repoRoot = scriptPath:match("^(.*)[/\\]scripts[/\\][^/\\]+$")
if not repoRoot and scriptPath:match("^scripts[/\\][^/\\]+$") then
    repoRoot = "."
end
if not repoRoot then
    Fail("Could not determine the repository root")
end

local function JoinPath(relative)
    return repoRoot .. "/" .. relative
end

local function ReadFile(path)
    local file, openError = io.open(path, "rb")
    if not file then
        return nil, openError
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function WriteFile(path, content)
    local file, openError = io.open(path, "wb")
    if not file then
        Fail("Could not write " .. path .. ": " .. tostring(openError))
    end
    file:write(content)
    file:close()
end

local function ParseArguments(arguments)
    local options = {
        check = false,
    }
    local index = 1
    while index <= #arguments do
        local argument = arguments[index]
        if argument == "--check" then
            options.check = true
        elseif argument == "--version" then
            index = index + 1
            options.version = arguments[index]
            if not options.version or options.version == "" then
                Fail("--version requires a value")
            end
        elseif argument == "--release-notes" then
            index = index + 1
            options.releaseNotes = arguments[index]
            if not options.releaseNotes or options.releaseNotes == "" then
                Fail("--release-notes requires a path")
            end
        elseif argument == "--help" then
            print("Usage: lua scripts/generate-changelog.lua [--check] [--version VERSION --release-notes PATH]")
            os.exit(0)
        else
            Fail("Unknown argument: " .. tostring(argument))
        end
        index = index + 1
    end

    if options.releaseNotes and not options.version then
        Fail("--release-notes requires --version")
    end
    return options
end

local function IsReleaseVersion(version)
    return version:match("^r[1-9]%d*$")
        or version:match("^r[1-9]%d*%-alpha$")
        or version:match("^r[1-9]%d*%-beta$")
end

local function ValidatePlainText(value, field)
    if type(value) ~= "string" or value == "" then
        Fail(field .. " must be a non-empty string")
    end
    if value:find("[\r\n]") then
        Fail(field .. " must be a single line")
    end
end

local function LoadReleases()
    local addon = {}
    local chunk, loadError = loadfile(JoinPath("Options/ChangelogData.lua"))
    if not chunk then
        Fail("Could not load changelog data: " .. tostring(loadError))
    end
    chunk("BFInfinite", addon)

    local releases = addon.changelog
    if type(releases) ~= "table" or #releases == 0 then
        Fail("Options/ChangelogData.lua must define at least one release")
    end

    local seen = {}
    local previousRevision
    for releaseIndex, release in ipairs(releases) do
        if type(release) ~= "table" then
            Fail(("release %d must be a table"):format(releaseIndex))
        end
        ValidatePlainText(release.version, ("release %d version"):format(releaseIndex))
        if not IsReleaseVersion(release.version) then
            Fail("Unsupported release version: " .. release.version)
        end
        if seen[release.version] then
            Fail("Duplicate release version: " .. release.version)
        end
        seen[release.version] = true

        local revision = tonumber(release.version:match("^r(%d+)"))
        if previousRevision and revision >= previousRevision then
            Fail("Releases must be ordered from newest to oldest")
        end
        previousRevision = revision

        ValidatePlainText(release.date, release.version .. " date")
        if type(release.notes) ~= "table" or #release.notes == 0 then
            Fail(release.version .. " must contain at least one note")
        end
        for noteIndex, note in ipairs(release.notes) do
            if type(note) ~= "table" then
                Fail(("%s note %d must be a table"):format(release.version, noteIndex))
            end
            ValidatePlainText(note.enUS, ("%s note %d enUS"):format(release.version, noteIndex))
            ValidatePlainText(note.zhCN, ("%s note %d zhCN"):format(release.version, noteIndex))
        end
    end
    return releases
end

local function EscapeMarkdown(value)
    local escaped = value:gsub("\\", "\\\\")
    for _, character in ipairs({"`", "*", "_", "{", "}", "[", "]", "<", ">", "#", "|"}) do
        local pattern = character:gsub("(%W)", "%%%1")
        escaped = escaped:gsub(pattern, "\\" .. character)
    end
    return escaped
end

local function AddLocalizedNotes(output, release)
    output[#output + 1] = "### English (enUS)"
    output[#output + 1] = ""
    for _, note in ipairs(release.notes) do
        output[#output + 1] = "- " .. EscapeMarkdown(note.enUS)
    end
    output[#output + 1] = ""
    output[#output + 1] = "### 简体中文 (zhCN)"
    output[#output + 1] = ""
    for _, note in ipairs(release.notes) do
        output[#output + 1] = "- " .. EscapeMarkdown(note.zhCN)
    end
end

local function RenderChangelog(releases)
    local output = {
        "<!-- Generated by scripts/generate-changelog.lua from Options/ChangelogData.lua. -->",
        "# BFInfinite changelog",
        "",
    }
    for releaseIndex, release in ipairs(releases) do
        output[#output + 1] = "## " .. release.version .. " — " .. release.date
        output[#output + 1] = ""
        AddLocalizedNotes(output, release)
        if releaseIndex < #releases then
            output[#output + 1] = ""
        end
    end
    output[#output + 1] = ""
    return table.concat(output, "\n")
end

local function RenderReleaseNotes(release)
    local output = {
        "<!-- Generated by scripts/generate-changelog.lua from Options/ChangelogData.lua. -->",
        "# BFInfinite " .. release.version,
        "",
        "Released: " .. release.date,
        "",
    }
    AddLocalizedNotes(output, release)
    output[#output + 1] = ""
    return table.concat(output, "\n")
end

local function FindRelease(releases, version)
    for _, release in ipairs(releases) do
        if release.version == version then
            return release
        end
    end
    Fail("No changelog entry found for release tag " .. version)
end

local function UpdateFile(path, content, check)
    if check then
        local current, readError = ReadFile(path)
        if not current then
            Fail("Could not read " .. path .. ": " .. tostring(readError))
        end
        if current ~= content then
            Fail(path .. " is out of date; run lua5.1 scripts/generate-changelog.lua")
        end
        return
    end
    WriteFile(path, content)
end

local function Main(arguments)
    local options = ParseArguments(arguments)
    local releases = LoadReleases()

    if options.version then
        local release = FindRelease(releases, options.version)
        local outputPath = options.releaseNotes or JoinPath("RELEASE_NOTES.md")
        UpdateFile(outputPath, RenderReleaseNotes(release), options.check)
    else
        UpdateFile(JoinPath("CHANGELOG.md"), RenderChangelog(releases), options.check)
        UpdateFile(JoinPath("RELEASE_NOTES.md"), RenderReleaseNotes(releases[1]), options.check)
    end
end

local ok, message = pcall(Main, arg or {})
if not ok then
    io.stderr:write("Changelog generation failed: " .. tostring(message) .. "\n")
    os.exit(1)
end
