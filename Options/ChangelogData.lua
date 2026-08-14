---@type BFI
local BFI = select(2, ...)

-- Keep release notes as plain text. The in-game view and Markdown generator
-- are responsible for escaping or formatting the text for their output.
BFI.changelog = {
    {
        version = "r6-alpha",
        date = "2026-08-14 00:00 GMT+8",
        notes = {
            {
                enUS = "Rebuilt Unit Frame Buffs and Debuffs for WoW 12.1 with native Aura Containers, and migrated the upper-right display and enemy Nameplate debuffs to native aura rows",
                zhCN = "使用《魔兽世界》12.1 原生光环容器重构了单位框体的增益与减益，并将右上角显示和敌方姓名板减益迁移到原生光环行",
            },
            {
                enUS = "Added configurable Party and Raid dispel highlights, supported aura filters, and global spell colors for Unit Frames",
                zhCN = "为单位框体新增可配置的小队和团队驱散高亮、受支持的光环筛选条件及全局法术颜色",
            },
            {
                enUS = "Added profile-aware Click Casting for BFI Unit Frames, supporting spells, macros, items, and target actions",
                zhCN = "为 BFI 单位框体新增按配置文件保存的点击施法，支持法术、宏、物品和目标动作",
            },
            {
                enUS = "Added Objective Tracker position and height controls, with an option to stack BFI Damage Meters beneath it",
                zhCN = "新增目标追踪器位置和高度设置，并可将 BFI 伤害统计堆叠在其下方",
            },
            {
                enUS = "Added optional quest acceptance and turn-in automation; hold Shift to keep a quest interaction manual",
                zhCN = "新增可选的自动接取和交还任务功能；按住 Shift 可保持任务交互为手动",
            },
            {
                enUS = "Updated Cooldown Manager lifecycle handling and tracked-bar presentation for WoW 12.1",
                zhCN = "更新冷却管理器的生命周期处理和追踪条外观，以适配《魔兽世界》12.1",
            },
        },
    },
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
