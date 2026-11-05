-- tests/addon_files.lua
-- The addon's Lua files in load order, read from SideQuest/SideQuest.toc so
-- the tests and the preview load exactly what the game loads.
--
-- The game runs Lua 5.1, but LuaJIT (which runs the tests and the preview)
-- also reads the 5.2+ string escapes \x.., \u{..} and \z. Lua 5.1 turns
-- those into plain letters, so text that looks right here shows up garbled
-- in game. Every file is refused if it holds one, comments included.

local function assertLua51Escapes(path)
    local f = assert(io.open(path, "r"))
    local lineNo = 0
    for line in f:lines() do
        lineNo = lineNo + 1
        -- a run of backslashes escapes the letter after it only when the
        -- run is odd ("\\x" is a backslash then x)
        for run, letter in line:gmatch("(\\+)([xuz])") do
            if #run % 2 == 1 then
                f:close()
                error(string.format("%s:%d: '\\%s' is not a Lua 5.1 escape; the game would print it as "
                    .. "the letter '%s'. Use decimal escapes (\"\\226\\128\\137\").", path, lineNo, letter, letter), 0)
            end
        end
    end
    f:close()
end

return function(root)
    local toc = assert(io.open(root .. "SideQuest/SideQuest.toc", "r"))
    local files = {}
    for line in toc:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local file = "SideQuest/" .. line:gsub("\\", "/")
            assertLua51Escapes(root .. file)
            table.insert(files, file)
        end
    end
    toc:close()
    return files
end
