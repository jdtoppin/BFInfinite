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
                enUS = "Sidebar category expansion now persists when the sidebar collapses",
                zhCN = "侧栏收起时，侧栏分类的展开状态现在会保留",
            },
            {
                enUS = "Sidebar category icons across every category (equipment, consumables, trade goods, recipes, reagents, quest items, and housing) now render as larger, full-color native in-game art on plated backgrounds",
                zhCN = "侧栏所有分类（装备、消耗品、贸易物品、配方、材料、任务物品和房屋）的图标现在都以更大尺寸的全彩游戏内原生素材呈现，并带有底板背景",
            },
            {
                enUS = "Sidebar toggle now collapses and expands the sidebar instantly, replacing the old auto-hide behavior",
                zhCN = "侧栏切换按钮现在可以立即收起或展开侧栏，取代了原有的自动隐藏方式",
            },
            {
                enUS = "The collapsed sidebar rail now shows expand/collapse chevrons next to each category icon",
                zhCN = "收起状态下的侧栏现在会在每个分类图标旁显示展开/收起箭头",
            },
            {
                enUS = "The sidebar rail now sits flush with the bag window's edge",
                zhCN = "侧栏现在与背包窗口边缘对齐",
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
