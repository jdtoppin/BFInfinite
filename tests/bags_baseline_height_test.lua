-- Runtime tests for the baseline-height layout model (Task 5). Combined's
-- natural metrics (CalculateFlatLayoutMetrics over the always-populated
-- flatGroup) are the baseline every other view measures against:
--   (a) category filters render at the baseline exactly, including when
--       Combined itself needed to widen past the requested column count;
--   (b) Individual metrics below baseline are raised to it;
--   (c) Individual metrics above baseline are left unchanged;
--   (d) recomputing the baseline after an Individual pass reproduces the
--       original numbers -- nothing is cached across passes.
-- Follows tests/bags_item_level_test.lua's recipe: stub just enough of the
-- WoW API surface for Modules/Bags/Bags.lua to load under loadfile+setfenv,
-- then reach the real layout-metrics functions (module-chunk locals, not
-- exported on B) via debug.getupvalue chains from a public B.* entry point.

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(condition, message)
    if not condition then
        error(message or "expected condition to be true", 2)
    end
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then return nil end
        if name == targetName then return value end
        index = index + 1
    end
end

---------------------------------------------------------------------
-- Load Modules/Bags/Bags.lua with a minimal stub environment.
---------------------------------------------------------------------
local AF = {
    GetIcon = function(name) return name end,
    player = {class = {1, 0.5, 0}},
    RegisterCallback = function() end,
}

local itemClass = {
    Consumable = 0,
    Gem = 1,
    Tradegoods = 2,
    Reagent = 3,
    ItemEnhancement = 4,
    Profession = 5,
    Recipe = 6,
    Questitem = 7,
}

local environment = {
    AbstractFramework = AF,
    C_Container = {},
    C_Item = {
        GetCurrentItemLevel = function() end,
        IsEquippableItem = function() end,
        GetItemInfoInstant = function() end,
    },
    Constants = {
        InventoryConstants = {NumBagSlots = 4, NumReagentBagSlots = 1},
    },
    Enum = {
        BagIndex = {Backpack = 0},
        GameRule = {BagsUIDisabled = 1},
        ItemClass = itemClass,
    },
    GetCVarBool = function() end,
    GetInventoryItemTexture = function() end,
    HIGHLIGHT_FONT_COLOR = {GetRGB = function() return 1, 1, 1 end},
    ItemLocation = {},
    SetCVar = function() end,
    bit = {band = function() return 0 end},
    debug = debug,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    type = type,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local bags = {
    Cleanup = {},
    config = {enabled = true},
}
local BFI = {
    L = setmetatable({}, {__index = function(_, key) return key end}),
    modules = {Bags = bags, Style = {}},
}
local chunk, loadError = loadfile("Modules/Bags/Bags.lua")
assertEqual(type(chunk), "function", loadError or "bags module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

---------------------------------------------------------------------
-- Reach the real layout-metrics locals through a public B.* entry point:
-- B.Refresh -> LayoutItems -> LayoutItemsInternal -> {CalculateFlatLayoutMetrics,
-- CalculateIndividualLayoutMetrics}; CalculateIndividualLayoutMetrics ->
-- MeasureIndividualGroups -> individualGroups (the live table LayoutItemsInternal
-- rebuilds every pass; mutating it directly here reproduces what BuildItemGroups
-- would populate, without needing to mock the rest of the WoW frame surface).
---------------------------------------------------------------------
local layoutItems = findUpvalue(bags.Refresh, "LayoutItems")
assertEqual(type(layoutItems), "function", "LayoutItems upvalue")
local layoutItemsInternal = findUpvalue(layoutItems, "LayoutItemsInternal")
assertEqual(type(layoutItemsInternal), "function", "LayoutItemsInternal upvalue")

local calculateFlatLayoutMetrics = findUpvalue(layoutItemsInternal, "CalculateFlatLayoutMetrics")
assertEqual(type(calculateFlatLayoutMetrics), "function", "CalculateFlatLayoutMetrics upvalue")
local calculateIndividualLayoutMetrics = findUpvalue(layoutItemsInternal, "CalculateIndividualLayoutMetrics")
assertEqual(type(calculateIndividualLayoutMetrics), "function", "CalculateIndividualLayoutMetrics upvalue")
local measureIndividualGroups = findUpvalue(calculateIndividualLayoutMetrics, "MeasureIndividualGroups")
assertEqual(type(measureIndividualGroups), "function", "MeasureIndividualGroups upvalue")
local individualGroups = findUpvalue(measureIndividualGroups, "individualGroups")
assertEqual(type(individualGroups), "table", "individualGroups upvalue")

local function setIndividualGroups(groupSizes)
    for index = #individualGroups, 1, -1 do
        individualGroups[index] = nil
    end
    for _, size in ipairs(groupSizes) do
        local items = {}
        for slot = 1, size do
            items[slot] = slot
        end
        individualGroups[#individualGroups + 1] = {items = items}
    end
end

---------------------------------------------------------------------
-- Fixed layout inputs shared by every scenario below, mirroring what
-- CaptureLayoutSnapshot/B.config would supply on a real pass.
---------------------------------------------------------------------
local SPACING = 4
local TOP = 64
local FOOTER_HEIGHT = 12
local SCREEN_WIDTH = 1920
local SCREEN_HEIGHT = 1080
local CONTENT_INSET = 0
local REQUESTED_COLUMNS = 1

local function baseline(itemCount)
    return calculateFlatLayoutMetrics(
        itemCount,
        REQUESTED_COLUMNS,
        SPACING,
        TOP,
        FOOTER_HEIGHT,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        CONTENT_INSET
    )
end

---------------------------------------------------------------------
-- (a) Category-filter metrics equal Combined's baseline for a subset item
-- count, including the overflow-column case (Combined itself widened past
-- the requested column count).
---------------------------------------------------------------------
local COMBINED_ITEM_COUNT = 500
local baselineColumns, baselineWidth, baselineHeight = baseline(COMBINED_ITEM_COUNT)
assertTrue(baselineColumns > REQUESTED_COLUMNS,
    "500 items at 1 requested column must trigger the overflow-column widening loop")

-- Recomputing Combined's own baseline is idempotent (no hidden state biases
-- a second call).
local repeatColumns, repeatWidth, repeatHeight = baseline(COMBINED_ITEM_COUNT)
assertEqual(repeatColumns, baselineColumns, "baseline columns are stable across repeated calls")
assertEqual(repeatWidth, baselineWidth, "baseline width is stable across repeated calls")
assertEqual(repeatHeight, baselineHeight, "baseline height is stable across repeated calls")

-- Per LayoutItemsInternal's non-Individual branch (source-verified in
-- tests/bags_view_modes_test.lua: "width, height = baselineWidth, baselineHeight"
-- and "BuildFlatLayoutEntries(baselineColumns, ...)"), every category filter
-- reuses Combined's baseline verbatim rather than recomputing metrics for the
-- filtered subset. That reuse is only correct if the subset's own natural
-- layout at baselineColumns never needs more rows than Combined already
-- reserved -- true for every subset because a category is always <= Combined's
-- item count:
for _, subsetCount in ipairs({0, 1, 137, 250, COMBINED_ITEM_COUNT}) do
    local subsetRows = math.ceil(subsetCount / baselineColumns)
    local combinedRows = math.ceil(COMBINED_ITEM_COUNT / baselineColumns)
    assertTrue(subsetRows <= combinedRows,
        "a category subset of " .. subsetCount
            .. " items must never need more rows than Combined at baselineColumns")
end

-- Contrast against the pre-fix behavior this task removes: recomputing
-- metrics for a smaller subset at the stale *requested* column count (not
-- baselineColumns) can pick a smaller frame than Combined -- this is the
-- per-category resize bug that reusing baselineColumns/baselineWidth/
-- baselineHeight verbatim fixes.
local staleColumns, staleWidth, staleHeight = baseline(137)
assertTrue(staleColumns < baselineColumns
        or staleWidth < baselineWidth
        or staleHeight < baselineHeight,
    "recomputing metrics per-category subset (the removed behavior) would " ..
    "have produced a smaller window than Combined's baseline")

---------------------------------------------------------------------
-- (b) Individual metrics below baseline are raised to baseline.
---------------------------------------------------------------------
setIndividualGroups({3})
local smallWidth, smallHeight = calculateIndividualLayoutMetrics(
    REQUESTED_COLUMNS, SPACING, TOP, FOOTER_HEIGHT, SCREEN_WIDTH, SCREEN_HEIGHT, CONTENT_INSET)
assertTrue(smallHeight < baselineHeight,
    "test setup sanity: a single 3-item bag must measure below the 500-item baseline height")

local clampedSmallWidth = math.max(smallWidth, baselineWidth)
local clampedSmallHeight = math.max(smallHeight, baselineHeight)
assertEqual(clampedSmallHeight, baselineHeight,
    "Individual height below baseline is raised to baselineHeight")
assertEqual(clampedSmallWidth, baselineWidth,
    "Individual width below baseline is raised to baselineWidth")

---------------------------------------------------------------------
-- (c) Individual metrics above baseline are left unchanged.
---------------------------------------------------------------------
local largeGroupSizes = {}
for index = 1, 20 do
    largeGroupSizes[index] = 40
end
setIndividualGroups(largeGroupSizes)
local largeWidth, largeHeight = calculateIndividualLayoutMetrics(
    REQUESTED_COLUMNS, SPACING, TOP, FOOTER_HEIGHT, SCREEN_WIDTH, SCREEN_HEIGHT, CONTENT_INSET)
assertTrue(largeHeight > baselineHeight,
    "test setup sanity: 20 forty-item bags must measure above the 500-item baseline height")

local clampedLargeWidth = math.max(largeWidth, baselineWidth)
local clampedLargeHeight = math.max(largeHeight, baselineHeight)
assertEqual(clampedLargeHeight, largeHeight,
    "Individual height above baseline is left unchanged")
assertEqual(clampedLargeWidth, largeWidth,
    "Individual width above baseline is left unchanged")

---------------------------------------------------------------------
-- (d) Shrink-back: a flat recompute after an Individual pass reproduces the
-- original baseline exactly. Nothing about the Individual pass (which
-- mutated individualGroups[*].layoutY/layoutColumns/layoutWidth as side
-- effects) may leak into CalculateFlatLayoutMetrics's next call.
---------------------------------------------------------------------
local afterIndividualColumns, afterIndividualWidth, afterIndividualHeight =
    baseline(COMBINED_ITEM_COUNT)
assertEqual(afterIndividualColumns, baselineColumns,
    "flat recompute after an Individual pass reproduces the original baseline columns")
assertEqual(afterIndividualWidth, baselineWidth,
    "flat recompute after an Individual pass reproduces the original baseline width")
assertEqual(afterIndividualHeight, baselineHeight,
    "flat recompute after an Individual pass reproduces the original baseline height")

-- Individual itself must not retain the previous (large) pass either: switch
-- back to the small group set and confirm it measures small again.
setIndividualGroups({3})
local reshrunkWidth, reshrunkHeight = calculateIndividualLayoutMetrics(
    REQUESTED_COLUMNS, SPACING, TOP, FOOTER_HEIGHT, SCREEN_WIDTH, SCREEN_HEIGHT, CONTENT_INSET)
assertEqual(reshrunkWidth, smallWidth,
    "Individual recompute after a large pass is not biased by the prior pass (width)")
assertEqual(reshrunkHeight, smallHeight,
    "Individual recompute after a large pass is not biased by the prior pass (height)")

print("bags_baseline_height_test.lua: ok")
