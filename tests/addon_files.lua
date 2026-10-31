-- tests/addon_files.lua
-- The addon's Lua files in load order, read from SideQuest/SideQuest.toc so
-- the tests and the preview load exactly what the game loads.

return function(root)
    local toc = assert(io.open(root .. "SideQuest/SideQuest.toc", "r"))
    local files = {}
    for line in toc:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            table.insert(files, "SideQuest/" .. line:gsub("\\", "/"))
        end
    end
    toc:close()
    return files
end
