---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class Funcs
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local changelogsFrame

local function EscapeHTML(value)
    if type(value) ~= "string" then
        return ""
    end

    return value
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#39;")
end

local function GetLocalizedNote(note, locale)
    if type(note) ~= "table" then
        return nil
    end

    local localized = type(locale) == "string" and note[locale]
    if type(localized) == "string" and localized ~= "" then
        return localized
    end

    if type(note.enUS) == "string" and note.enUS ~= "" then
        return note.enUS
    end
end

local function BuildChangelogHTML(locale)
    local output = {}
    local releases = BFI.changelog
    if type(releases) ~= "table" then
        return ""
    end

    for _, release in ipairs(releases) do
        if type(release) == "table"
            and type(release.version) == "string"
            and release.version ~= ""
        then
            local heading = EscapeHTML(release.version)
            if type(release.date) == "string" and release.date ~= "" then
                heading = heading .. " (" .. EscapeHTML(release.date) .. ")"
            end
            output[#output + 1] = "<h1>" .. heading .. "</h1>"

            if type(release.notes) == "table" then
                for _, note in ipairs(release.notes) do
                    local text = GetLocalizedNote(note, locale)
                    if text then
                        output[#output + 1] = "<p>- " .. EscapeHTML(text) .. "</p>"
                    end
                end
            end

            output[#output + 1] = "<br/>"
        end
    end

    if output[#output] == "<br/>" then
        output[#output] = nil
    end
    return table.concat(output, "\n")
end

-- Kept on the addon function table so the renderer can be covered without
-- constructing Blizzard UI objects in a standalone Lua test.
F.BuildChangelogHTML = BuildChangelogHTML

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateChangelogsFrame()
    changelogsFrame = AF.CreateHeaderedFrame(AF.UIParent, "BFIChangelogsFrame", "BFI " .. L["Changelogs"], 400, 500, "HIGH", 999, true)
    changelogsFrame:SetPoint("CENTER")
    changelogsFrame:SetBackdropColor(AF.GetColorRGB("background", 0.9))
    changelogsFrame:Hide()

    --------------------------------------------------
    -- scroll
    --------------------------------------------------
    local scroll = AF.CreateScrollFrame(changelogsFrame, nil, nil, nil, "none", "none")
    scroll:SetAllPoints(changelogsFrame)

    --------------------------------------------------
    -- fonts
    --------------------------------------------------
    local h1Font = CreateFont("BFI_Changelogs_H1")
    h1Font:CopyFontObject(AF_FONT_TITLE)
    h1Font:SetTextColor(AF.GetColorRGB("BFI"))
    AF.AddToFontSizeUpdater(h1Font)

    local h2Font = CreateFont("BFI_Changelogs_H2")
    h2Font:CopyFontObject(AF_FONT_NORMAL)
    h2Font:SetTextColor(AF.GetColorRGB("BFI"))
    AF.AddToFontSizeUpdater(h2Font)

    local pFont = CreateFont("BFI_Changelogs_P")
    pFont:CopyFontObject(AF_FONT_NORMAL)
    AF.AddToFontSizeUpdater(pFont)

    --------------------------------------------------
    -- html
    --------------------------------------------------
    local html = CreateFrame("SimpleHTML", nil, scroll.scrollContent)
    AF.SetPoint(html, "TOP", 0, -15)
    AF.SetWidth(html, 370)

    html:SetFontObject("h1", h1Font)
    html:SetFontObject("h2", h2Font)
    html:SetFontObject("p", pFont)

    html:SetSpacing("h1", 9)
    html:SetSpacing("h2", 7)
    html:SetSpacing("p", 5)

    --------------------------------------------------
    -- load
    --------------------------------------------------
    function changelogsFrame:Load()
        changelogsFrame:Show()
        local locale = LOCALE_zhCN and "zhCN" or "enUS"
        html:SetText("<html><body>" .. BuildChangelogHTML(locale) .. "</body></html>")
        RunNextFrame(function()
            html:SetHeight(html:GetContentHeight())
            scroll:SetContentHeight(html:GetHeight() + 30, true)
        end)
    end
end

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
function F.ToggleChangelogsFrame()
    if not changelogsFrame then
        CreateChangelogsFrame()
    end

    if changelogsFrame:IsShown() then
        changelogsFrame:Hide()
    else
        changelogsFrame:Load()
    end
end
