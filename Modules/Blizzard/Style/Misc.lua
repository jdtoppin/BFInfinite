---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- IconIntroTracker
---------------------------------------------------------------------
local function StyleIconIntroTracker()
    -- crop the new spells being added to the actionbars
    _G.IconIntroTracker:HookScript("OnEvent", function(self)
        local l, r, t, b = 0.1, 0.9, 0.1, 0.9
        for _, iconIntro in ipairs(self.iconList) do
            if not iconIntro._BFIStyled then
                iconIntro.trail1.icon:SetTexCoord(l, r, t, b)
                iconIntro.trail1.bg:SetTexCoord(l, r, t, b)

                iconIntro.trail2.icon:SetTexCoord(l, r, t, b)
                iconIntro.trail2.bg:SetTexCoord(l, r, t, b)

                iconIntro.trail3.icon:SetTexCoord(l, r, t, b)
                iconIntro.trail3.bg:SetTexCoord(l, r, t, b)

                iconIntro.icon.icon:SetTexCoord(l, r, t, b)
                iconIntro.icon.bg:SetTexCoord(l, r, t, b)

                iconIntro._BFIStyled = true
            end
        end
    end)
end

---------------------------------------------------------------------
-- SetCheckButtonIsRadio
---------------------------------------------------------------------
local function HookSetCheckButtonIsRadio()
    hooksecurefunc("SetCheckButtonIsRadio", function(button, isRadio)
        if not button._BFIStyled then return end
        S.ReStyleCheckButtonTexture(button)
    end)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleIconIntroTracker()
    HookSetCheckButtonIsRadio()
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
