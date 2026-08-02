---@type BFI
local BFI = select(2, ...)

-- Keep release notes as plain text. The in-game view and Markdown generator
-- are responsible for escaping or formatting the text for their output.
BFI.changelog = {
    {
        version = "r2-alpha",
        date = "2025-10-14 17:30 GMT+8",
        notes = {
            {
                enUS = "Added class accent color support",
                zhCN = "新增职业强调色的支持",
            },
            {
                enUS = "Added AF version check on load",
                zhCN = "新增加载时的 AF 版本检查",
            },
            {
                enUS = "Fixed Unit Frames preset issues",
                zhCN = "修复单位框体的预设问题",
            },
            {
                enUS = "Temporary font fixes",
                zhCN = "临时修复字体相关问题",
            },
            {
                enUS = "Updated Buffs & Debuffs options",
                zhCN = "更新增益与减益选项",
            },
            {
                enUS = "Updated font options",
                zhCN = "更新字体选项",
            },
            {
                enUS = "Used complement color for logo gradient",
                zhCN = "为徽标渐变使用互补色",
            },
        },
    },
    {
        version = "r1-alpha",
        date = "2025-10-06 01:36 GMT+8",
        notes = {
            {
                enUS = "Initial release",
                zhCN = "首次发布",
            },
        },
    },
}
