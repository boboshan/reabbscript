assert(_VERSION == "Lua 5.4", "Run this suite with Lua 5.4.")
dofile("tests/test_actions.lua")
dofile("tests/test_split.lua")
print("All Reabbscript regression tests passed.")
