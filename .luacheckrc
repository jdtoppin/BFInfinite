std = "lua51"
codes = true
max_line_length = false

-- WoW provides globals at runtime, and callback signatures commonly contain
-- intentionally unused parameters. Keep those environmental warnings out of
-- the baseline while retaining local control-flow and shadowing checks.
ignore = {
    "111",
    "112",
    "113",
    "212",
    "213",
    "631",
}

exclude_files = {
    ".unused/**",
    "Libs/**",
}
