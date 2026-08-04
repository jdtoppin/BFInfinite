---@type BFI
local BFI = select(2, ...)

-- Keep release notes as plain text. The in-game view and Markdown generator
-- are responsible for escaping or formatting the text for their output.
BFI.changelog = {
    {
        version = "r5-alpha",
        date = "2026-08-04 00:00 GMT+8",
        notes = {
            {
                enUS = "Individual Bags view keeps full-size icons and grows from the Combined View baseline height",
                zhCN = "独立背包视图保留完整大小的图标，并以合并视图的基准高度为起点向上增长",
            },
            {
                enUS = "Sidebar category expansion now persists when the auto-hide sidebar collapses",
                zhCN = "自动隐藏侧栏收起时，侧栏分类的展开状态现在会保留",
            },
            {
                enUS = "Added distinct icons for consumable subclasses and equipment slots in the collapsed sidebar",
                zhCN = "为收起状态下的侧栏消耗品子类和装备部位新增了独立图标",
            },
        },
    },
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
