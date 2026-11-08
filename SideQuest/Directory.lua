-- SideQuest/Directory.lua
-- The guild directory: every member's shared record (professions, character, cooldowns, market, stock),
-- stored per character and section and kept in step over DIR_* addon messages. See docs/directory.md.

SideQuest = SideQuest or {}
SideQuest.Directory = SideQuest.Directory or {}
local Directory = SideQuest.Directory

local SECTIONS = { "prof", "char", "cd", "market", "stock" }
Directory.SECTIONS = SECTIONS

local ONLINE_WINDOW = 600 -- 10 minutes without a roster to go by
local PRUNE_AGE = 90 * 24 * 3600 -- 90 days

local function now()
    return GetServerTime and GetServerTime() or 0
end

--------------------------------------------------------------------------
-- Hash: deterministic canonical JSON (SideQuestJSON already sorts object
-- keys), then a plain djb2 over the bytes, folded into 8 hex digits. Pure
-- arithmetic (Lua 5.1 has no bitwise operators).
--------------------------------------------------------------------------

local function canonicalJSON(d)
    if d == nil then
        return "null"
    end
    return SideQuestJSON.encode(d)
end

local function djb2hex(str)
    local hash = 5381
    for i = 1, #str do
        hash = (hash * 33 + str:byte(i)) % 4294967296
    end
    return string.format("%08x", hash)
end

function Directory.Hash(d)
    return djb2hex(canonicalJSON(d))
end

--------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------

local function ensureEntry(character)
    SideQuestDB.directory[character] = SideQuestDB.directory[character] or {}
    return SideQuestDB.directory[character]
end

function Directory.Get(character)
    return SideQuestDB.directory[character]
end

function Directory.Section(character, section)
    local entry = SideQuestDB.directory[character]
    local sec = entry and entry[section]
    if not sec then
        return nil
    end
    return sec.d
end

function Directory.All()
    return pairs(SideQuestDB.directory)
end

--------------------------------------------------------------------------
-- Limits (docs/directory.md "Limits"): drop the excess, keep the newest.
--------------------------------------------------------------------------

local function capList(list, limit)
    if not list or #list <= limit then
        return list
    end
    local out = {}
    local start = #list - limit + 1
    for i = start, #list do
        table.insert(out, list[i])
    end
    return out
end

local function capByAt(list, limit)
    if not list or #list <= limit then
        return list
    end
    local copy = {}
    for i, v in ipairs(list) do
        copy[i] = v
    end
    table.sort(copy, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    local out = {}
    for i = 1, limit do
        out[i] = copy[i]
    end
    return out
end

local function applyLimits(section, d)
    if not d then
        return d
    end
    if section == "prof" then
        for _, p in ipairs(d.professions or {}) do
            if p.recipes then
                p.recipes = capList(p.recipes, 2000)
            end
        end
    elseif section == "char" then
        if d.reputations then
            d.reputations = capList(d.reputations, 30)
        end
    elseif section == "market" then
        if d.sell then
            d.sell = capList(d.sell, 100)
        end
        if d.buy then
            d.buy = capList(d.buy, 100)
        end
        if d.requests then
            d.requests = capByAt(d.requests, 30)
            for _, r in ipairs(d.requests) do
                if r.note then
                    r.note = SideQuest.Utf8Cut(r.note, 80)
                end
            end
        end
    elseif section == "stock" then
        if d.bags then
            d.bags = capList(d.bags, 300)
        end
        if d.bank then
            d.bank = capList(d.bank, 300)
        end
    end
    return d
end

--------------------------------------------------------------------------
-- Debounced DIR_V announce of this character's own section hashes.
--------------------------------------------------------------------------

local announcePending = false

local function sendMyDirV()
    announcePending = false
    local character = SideQuest.NormalizeUnit("player")
    if not character then
        return
    end
    local entry = SideQuestDB.directory[character]
    if not entry then
        return
    end
    local v = {}
    for _, section in ipairs(SECTIONS) do
        if entry[section] then
            v[section] = entry[section].v
        end
    end
    SideQuest.Comm.SendDirV({ c = character, v = v })
end
Directory.SendMyDirV = sendMyDirV

local function scheduleAnnounce()
    if announcePending then
        return
    end
    announcePending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(3, sendMyDirV)
    else
        sendMyDirV()
    end
end

--------------------------------------------------------------------------
-- SetMine: a collector publishes fresh data for one section of this
-- character's own record.
--------------------------------------------------------------------------

function Directory.SetMine(section, d)
    local character = SideQuest.NormalizeUnit("player")
    if not character then
        return nil
    end
    local share = SideQuestDB.settings.share[section]
    local data = share and applyLimits(section, d) or nil
    local hash = Directory.Hash(data)
    local entry = ensureEntry(character)
    local existing = entry[section]
    entry.seen_at = now()
    if existing and existing.v == hash then
        return existing
    end
    entry[section] = { v = hash, at = now(), d = data, relayed = false }
    SideQuest.Fire("SQ_DIRECTORY_UPDATED", character, section)
    scheduleAnnounce()
    return entry[section]
end

--------------------------------------------------------------------------
-- Online detection: the guild roster when known, else "heard recently".
--------------------------------------------------------------------------

local function rosterOnline(character)
    local roster = SideQuestDB.roster and SideQuestDB.roster.members
    if not roster or #roster == 0 then
        return nil
    end
    for _, m in ipairs(roster) do
        if m.character == character then
            return m.online and true or false
        end
    end
    return nil
end

function Directory.IsOnline(character)
    local known = rosterOnline(character)
    if known ~= nil then
        return known
    end
    local entry = SideQuestDB.directory[character]
    if entry and entry.seen_at and (now() - entry.seen_at) < ONLINE_WINDOW then
        return true
    end
    return false
end

--------------------------------------------------------------------------
-- Pruning: roster-known characters that left, or anything stale for 90d.
--------------------------------------------------------------------------

function Directory.Prune()
    local roster = SideQuestDB.roster and SideQuestDB.roster.members
    -- GetNumGuildMembers() returns (total, online); with "Show Offline"
    -- off in the guild panel, a sweep can only see the online members even
    -- though `total` still counts everyone -- a roster like that is a
    -- non-representative subset, and pruning against it would delete
    -- every offline member's directory record on every sweep. Only trust
    -- the roster to say who's gone when it covers the whole guild; when
    -- GetNumGuildMembers isn't available to check, don't prune by roster
    -- at all rather than guess.
    local total = GetNumGuildMembers and GetNumGuildMembers()
    local rosterKnown = roster ~= nil and #roster > 0 and total ~= nil and #roster >= total
    local inRoster = {}
    if rosterKnown then
        for _, m in ipairs(roster) do
            inRoster[m.character] = true
        end
    end
    local me = SideQuest.NormalizeUnit("player")
    local nowTs = now()
    local toRemove = {}
    for character, entry in pairs(SideQuestDB.directory) do
        if character ~= me then
            local tooOld = entry.seen_at and (nowTs - entry.seen_at) > PRUNE_AGE
            local notInRoster = rosterKnown and not inRoster[character]
            if tooOld or notInRoster then
                table.insert(toRemove, character)
            end
        end
    end
    for _, character in ipairs(toRemove) do
        SideQuestDB.directory[character] = nil
    end
    return toRemove
end

SideQuest.On("SQ_ROSTER_UPDATED", function()
    Directory.Prune()
end)

--------------------------------------------------------------------------
-- Receiving: newest `at` wins, hash must match, relayed flag is local-only.
--------------------------------------------------------------------------

local function normalizeSender(sender)
    return SideQuest.NormalizeName(sender)
end

local function storeReceived(character, section, v, at, d, relayed)
    if Directory.Hash(d) ~= v then
        return false -- hash mismatch; drop
    end
    local entry = ensureEntry(character)
    local existing = entry[section]
    if existing and existing.at and at and existing.at >= at then
        entry.seen_at = now()
        return false -- not newer
    end
    entry[section] = { v = v, at = at, d = d, relayed = relayed and true or false }
    entry.seen_at = now()
    SideQuest.Fire("SQ_DIRECTORY_UPDATED", character, section)
    return true
end

--------------------------------------------------------------------------
-- DIR_V / DIR_Q / DIR_R
--------------------------------------------------------------------------

local function handleDirV(req)
    local character = req.c
    if not character or type(req.v) ~= "table" then
        return
    end
    local entry = ensureEntry(character)
    entry.seen_at = now()
    local needed = {}
    for section, hash in pairs(req.v) do
        local have = entry[section]
        if not have or have.v ~= hash then
            table.insert(needed, section)
        end
    end
    if #needed == 0 then
        return
    end
    table.sort(needed)
    local key = "DIRQ:" .. character .. ":" .. table.concat(needed, ",")
    SideQuest.Comm.ScheduleAnswer(key, function()
        local toAsk = {}
        for _, section in ipairs(needed) do
            if SideQuest.Comm.RateLimit("DIRQSEND:" .. character .. ":" .. section, 30) then
                table.insert(toAsk, section)
            end
        end
        if #toAsk > 0 then
            SideQuest.Comm.SendDirQ({ c = character, s = toAsk })
        end
    end, 0, 3000)
end

local function handleDirQ(req)
    local character = req.c
    if not character or type(req.s) ~= "table" then
        return
    end
    local sorted = {}
    for i, s in ipairs(req.s) do
        sorted[i] = s
    end
    table.sort(sorted)
    SideQuest.Comm.SuppressAnswer("DIRQ:" .. character .. ":" .. table.concat(sorted, ","))

    local me = SideQuest.NormalizeUnit("player")
    local entry = SideQuestDB.directory[character]
    for _, section in ipairs(req.s) do
        local have = entry and entry[section]
        local answerKey = "DIRR:" .. character .. ":" .. section
        if character == me and have then
            SideQuest.Comm.SuppressAnswer(answerKey)
            if SideQuest.Comm.RateLimit(answerKey, 30) then
                SideQuest.Comm.SendDirR({ c = character, s = section, v = have.v, at = have.at, d = have.d })
            end
        elseif have then
            SideQuest.Comm.ScheduleAnswer(answerKey, function()
                if SideQuest.Comm.RateLimit(answerKey, 30) then
                    SideQuest.Comm.SendDirR({ c = character, s = section, v = have.v, at = have.at, d = have.d })
                end
            end, 2000, 5000)
        end
    end
end

local function handleDirR(ans, sender)
    if not ans.c or not ans.s then
        return
    end
    SideQuest.Comm.SuppressAnswer("DIRR:" .. ans.c .. ":" .. ans.s)
    local senderNorm = normalizeSender(sender)
    local relayed = senderNorm ~= nil and senderNorm ~= ans.c
    storeReceived(ans.c, ans.s, ans.v, ans.at, ans.d, relayed)
end

--------------------------------------------------------------------------
-- DIR_LQ / DIR_L: catch-up after login.
--------------------------------------------------------------------------

local catchup = { queue = nil, pending = 0, fired = true, advance = nil }

local function sendBatchQuery(batch)
    for _, item in ipairs(batch) do
        local toAsk = {}
        for _, section in ipairs(item.sections) do
            if SideQuest.Comm.RateLimit("DIRQSEND:" .. item.character .. ":" .. section, 30) then
                table.insert(toAsk, section)
            end
        end
        if #toAsk > 0 then
            SideQuest.Comm.SendDirQ({ c = item.character, s = toAsk })
        end
    end
end

local function runCatchupQueue()
    local queue = catchup.queue
    if not queue or #queue == 0 then
        catchup.queue = nil
        return
    end
    local batch = {}
    for _ = 1, math.min(10, #queue) do
        table.insert(batch, table.remove(queue, 1))
    end
    sendBatchQuery(batch)
    catchup.pending = 0
    for _, item in ipairs(batch) do
        catchup.pending = catchup.pending + #item.sections
    end
    catchup.fired = false
    local function advance()
        if catchup.fired then
            return
        end
        catchup.fired = true
        runCatchupQueue()
    end
    catchup.advance = advance
    if C_Timer and C_Timer.After then
        C_Timer.After(60, advance)
    else
        advance()
    end
end

SideQuest.On("SQ_DIRECTORY_UPDATED", function()
    if catchup.pending > 0 then
        catchup.pending = catchup.pending - 1
        if catchup.pending <= 0 and catchup.advance and not catchup.fired then
            catchup.advance()
        end
    end
end)

local function handleDirLQ(req)
    if not req.id then
        return
    end
    local key = "DIRLQ:" .. req.id
    SideQuest.Comm.ScheduleAnswer(key, function()
        local e = {}
        for character, entry in pairs(SideQuestDB.directory) do
            local hashes = {}
            local any = false
            for _, section in ipairs(SECTIONS) do
                if entry[section] then
                    hashes[section] = entry[section].v
                    any = true
                end
            end
            if any then
                e[character] = hashes
            end
        end
        SideQuest.Comm.SendDirL({ id = req.id, e = e })
    end, 0, 3000)
end

local function handleDirL(ans)
    if not ans.id then
        return
    end
    SideQuest.Comm.SuppressAnswer("DIRLQ:" .. ans.id)
    local needed = {}
    for character, hashes in pairs(ans.e or {}) do
        local entry = SideQuestDB.directory[character]
        local sections = {}
        for section, hash in pairs(hashes) do
            local have = entry and entry[section]
            if not have or have.v ~= hash then
                table.insert(sections, section)
            end
        end
        if #sections > 0 then
            table.sort(sections)
            table.insert(needed, { character = character, sections = sections })
        end
    end
    table.sort(needed, function(a, b)
        return a.character < b.character
    end)
    local wasEmpty = catchup.queue == nil or #catchup.queue == 0
    catchup.queue = catchup.queue or {}
    for _, item in ipairs(needed) do
        table.insert(catchup.queue, item)
    end
    if wasEmpty and #catchup.queue > 0 then
        runCatchupQueue()
    end
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "DIR_V" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if ok then
            handleDirV(req)
        end
    elseif msgType == "DIR_Q" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if ok then
            handleDirQ(req)
        end
    elseif msgType == "DIR_R" then
        local ok, ans = pcall(SideQuestJSON.decode, payload)
        if ok then
            handleDirR(ans, sender)
        end
    elseif msgType == "DIR_LQ" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if ok then
            handleDirLQ(req)
        end
    elseif msgType == "DIR_L" then
        local ok, ans = pcall(SideQuestJSON.decode, payload)
        if ok then
            handleDirL(ans)
        end
    end
end)

-- Once per session (a login or /reload), not on every loading screen.
local greeted = false
SideQuest.On("PLAYER_ENTERING_WORLD", function()
    if greeted or not (C_Timer and C_Timer.After) then
        return
    end
    greeted = true
    C_Timer.After(math.random(10, 25), sendMyDirV)
    C_Timer.After(math.random(30, 60), function()
        SideQuest.Comm.SendDirLQ({ id = SideQuest.NextId() })
    end)
end)

--- Test/reset helper: clear module-level debounce/catch-up state.
function Directory.ResetState()
    announcePending = false
    catchup.queue = nil
    catchup.pending = 0
    catchup.fired = true
    catchup.advance = nil
    greeted = false
end

--------------------------------------------------------------------------
-- Lookups shared by the UI and the tooltip.
--------------------------------------------------------------------------

local function textMatches(haystack, needle)
    if not haystack then
        return false
    end
    return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

local function recipeName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok then
            return name
        end
    end
    return nil
end

--- `{ { character, profession, skill, recipe_id, recipe_name, online } }`, matched by recipe name or
--- profession substring.
function Directory.WhoCrafts(query)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local prof = entry.prof and entry.prof.d
        if prof then
            for _, p in ipairs(prof.professions or {}) do
                local profMatch = textMatches(p.name, query)
                local any = false
                for _, recipeId in ipairs(p.recipes or {}) do
                    local name = recipeName(recipeId)
                    if profMatch or (name and textMatches(name, query)) then
                        any = true
                        table.insert(out, {
                            character = character, profession = p.name, skill = p.skill,
                            recipe_id = recipeId, recipe_name = name, online = Directory.IsOnline(character),
                        })
                    end
                end
                if profMatch and not any then
                    table.insert(out, {
                        character = character, profession = p.name, skill = p.skill,
                        recipe_id = nil, recipe_name = nil, online = Directory.IsOnline(character),
                    })
                end
            end
        end
    end
    return out
end

--- Members with profession `name`, best skill first; every member's every
-- profession when `name` is nil. Each entry names its `profession`.
function Directory.ByProfession(name)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local prof = entry.prof and entry.prof.d
        if prof then
            for _, p in ipairs(prof.professions or {}) do
                if name == nil or p.name == name then
                    table.insert(out, {
                        character = character, profession = p.name, skill = p.skill, max_skill = p.max_skill,
                        online = Directory.IsOnline(character),
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.skill or 0) > (b.skill or 0)
    end)
    return out
end

--- `{ { character, bags, bank, online } }` for members holding `itemId`.
function Directory.WhoHas(itemId)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local stock = entry.stock and entry.stock.d
        if stock then
            local bags, bank = 0, 0
            for _, row in ipairs(stock.bags or {}) do
                if row[1] == itemId then
                    bags = row[2]
                end
            end
            for _, row in ipairs(stock.bank or {}) do
                if row[1] == itemId then
                    bank = row[2]
                end
            end
            if bags > 0 or bank > 0 then
                table.insert(out, { character = character, bags = bags, bank = bank, online = Directory.IsOnline(character) })
            end
        end
    end
    return out
end

function Directory.WhoSells(itemId)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local market = entry.market and entry.market.d
        if market then
            for _, row in ipairs(market.sell or {}) do
                if row.item_id == itemId then
                    table.insert(out, {
                        character = character, price = row.price, qty = row.qty, crafted = row.crafted,
                        online = Directory.IsOnline(character),
                    })
                end
            end
        end
    end
    return out
end

function Directory.WhoBuys(itemId)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local market = entry.market and entry.market.d
        if market then
            for _, row in ipairs(market.buy or {}) do
                if row.item_id == itemId then
                    table.insert(out, { character = character, price = row.price, online = Directory.IsOnline(character) })
                end
            end
        end
    end
    return out
end

--- Every open request across the guild, newest first.
function Directory.Requests()
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local market = entry.market and entry.market.d
        if market then
            for _, row in ipairs(market.requests or {}) do
                table.insert(out, {
                    character = character, id = row.id, item_id = row.item_id, qty = row.qty,
                    price = row.price, note = row.note, at = row.at, online = Directory.IsOnline(character),
                })
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    return out
end

--- Who has cooldown `key`, soonest ready first.
function Directory.Cooldowns(key)
    local out = {}
    for character, entry in pairs(SideQuestDB.directory) do
        local cd = entry.cd and entry.cd.d
        if cd then
            for _, row in ipairs(cd.cooldowns or {}) do
                if row.key == key then
                    table.insert(out, { character = character, ready_at = row.ready_at, online = Directory.IsOnline(character) })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return (a.ready_at or 0) < (b.ready_at or 0)
    end)
    return out
end

return Directory
