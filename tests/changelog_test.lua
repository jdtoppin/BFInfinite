local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertContains(value, expected, message)
    if not value:find(expected, 1, true) then
        error(("%s: expected to find %q"):format(message, expected), 2)
    end
end

local function assertNotContains(value, unexpected, message)
    if value:find(unexpected, 1, true) then
        error(("%s: did not expect to find %q"):format(message, unexpected), 2)
    end
end

local AF = {}
local environment = {
    AbstractFramework = AF,
    LOCALE_zhCN = false,
}
environment._G = environment
setmetatable(environment, {__index = _G})

local BFI = {
    L = {},
    funcs = {},
}

local dataChunk = assert(loadfile("Options/ChangelogData.lua"))
setfenv(dataChunk, environment)
dataChunk("BFInfinite", BFI)

assertEqual(#BFI.changelog, 3, "known release count")
assertEqual(BFI.changelog[1].version, "r5-alpha", "latest release")
assertEqual(BFI.changelog[2].version, "r2-alpha", "middle preserved release")
assertEqual(BFI.changelog[3].version, "r1-alpha", "oldest preserved release")
assertEqual(#BFI.changelog[1].notes, 9, "all known r5 notes")
assertEqual(#BFI.changelog[2].notes, 7, "all known r2 notes")
for _, release in ipairs(BFI.changelog) do
    for noteIndex, note in ipairs(release.notes) do
        assertEqual(type(note.enUS), "string",
            release.version .. " note " .. noteIndex .. " enUS text")
        assertEqual(type(note.zhCN), "string",
            release.version .. " note " .. noteIndex .. " zhCN text")
    end
end

local frameChunk = assert(loadfile("Options/ChangelogsFrame.lua"))
setfenv(frameChunk, environment)
frameChunk("BFInfinite", BFI)

local buildHTML = BFI.funcs.BuildChangelogHTML
assertEqual(type(buildHTML), "function", "testable HTML renderer")

local english = buildHTML("enUS")
assertContains(english, "<h1>r2-alpha (2025-10-14 17:30 GMT+8)</h1>",
    "English release heading")
assertContains(english, "<p>- Updated Buffs &amp; Debuffs options</p>",
    "English HTML escaping")
assertNotContains(english, "Updated Buffs & Debuffs options",
    "unescaped ampersand")

local chinese = buildHTML("zhCN")
assertContains(chinese, "<p>- 新增职业强调色的支持</p>",
    "Chinese localized note")
assertContains(chinese, "<p>- 首次发布</p>",
    "Chinese initial release note")

table.insert(BFI.changelog, 1, {
    version = "<r&>",
    date = "'date' \"quoted\"",
    notes = {
        {
            enUS = "Fallback <unsafe> & \"quoted\" 'single'",
            zhCN = "",
        },
    },
})

local fallback = buildHTML("zhCN")
assertContains(fallback,
    [=[<h1>&lt;r&amp;&gt; (&#39;date&#39; &quot;quoted&quot;)</h1>]=],
    "release metadata HTML escaping")
assertContains(fallback,
    [=[<p>- Fallback &lt;unsafe&gt; &amp; &quot;quoted&quot; &#39;single&#39;</p>]=],
    "per-item English fallback and HTML escaping")
assertNotContains(fallback, "<unsafe>", "raw fallback markup")
assertNotContains(fallback, "quoted\"", "raw quote")

print("changelog_test.lua: ok")
