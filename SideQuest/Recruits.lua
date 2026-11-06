-- SideQuest/Recruits.lua
-- Recruiting (contract v2 "recruits"/"member_notes"): applicants and
-- trials with a checklist and officer votes, plus member notes. Officer-
-- only; live edits share over the OFFICER addon channel.

SideQuest = SideQuest or {}
SideQuest.Recruits = {}
local Recruits = SideQuest.Recruits

local function now()
    return GetServerTime and GetServerTime() or 0
end

local function requireOfficer()
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can use the Recruits console.")
        return false
    end
    return true
end

function Recruits.List()
    return SideQuestDB.officerData.recruits
end

local function findRecruit(id)
    for _, r in ipairs(SideQuestDB.officerData.recruits) do
        if r.id == id then
            return r
        end
    end
    return nil
end

local function upsertRecruit(row)
    for i, existing in ipairs(SideQuestDB.officerData.recruits) do
        if existing.id == row.id then
            SideQuestDB.officerData.recruits[i] = row
            return
        end
    end
    table.insert(SideQuestDB.officerData.recruits, row)
end

--- Create or update a recruit; queues for export and shares with other
-- officers over OFFICER.
function Recruits.Save(recruit)
    if not requireOfficer() then
        return nil
    end
    recruit.id = recruit.id or SideQuest.NextId()
    recruit.at = recruit.at or now()
    recruit.checklist = recruit.checklist or {}
    recruit.votes = recruit.votes or {}
    upsertRecruit(recruit)

    local queue = SideQuestDB.pending.recruits
    local replaced = false
    for i, existing in ipairs(queue) do
        if existing.id == recruit.id then
            queue[i] = recruit
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(queue, recruit)
    end

    SideQuest.Comm.SendRecruit(recruit)
    SideQuest.Fire("SQ_RECRUIT_SAVED", recruit)
    return recruit
end

-- A character name must normalize to "Name-Realm" with no stray whitespace
-- or URL-breaking characters, matching the site's CHARACTER_SLUG_PATTERN.
local function validCharacter(character)
    return character ~= nil and character:match("^[^%s/?#]+%-[^%s/?#]+$") ~= nil
end

--- Add a new applicant from the in-game "Add recruit" form: validates and
-- normalizes the name, skips a duplicate (same character already
-- recruited), and defaults to status "applicant". Returns the recruit, or
-- nil plus a reason no row was added.
function Recruits.AddCandidate(rawCharacter, class, note)
    if not requireOfficer() then
        return nil, "Only officers can use the Recruits console."
    end
    if not rawCharacter or rawCharacter:gsub("%s+", "") == "" then
        return nil, "Enter a recruit's character name."
    end
    local trimmed = rawCharacter:gsub("^%s+", ""):gsub("%s+$", "")
    local character = SideQuest.NormalizeName(trimmed)
    if not validCharacter(character) then
        return nil, "That doesn't look like a character name."
    end
    for _, r in ipairs(SideQuestDB.officerData.recruits) do
        if r.character == character then
            return nil, character .. " is already a recruit."
        end
    end
    return Recruits.Save({
        character = character,
        class = class,
        status = "applicant",
        note = (note and note ~= "") and note or nil,
    })
end

function Recruits.Vote(recruitId, vote)
    if not requireOfficer() then
        return
    end
    local recruit = findRecruit(recruitId)
    if not recruit then
        SideQuest.Print("Unknown recruit " .. tostring(recruitId))
        return
    end
    local officer = SideQuest.NormalizeUnit("player")
    local entry = { officer = officer, vote = vote, at = now() }
    local replaced = false
    for i, v in ipairs(recruit.votes) do
        if v.officer == officer then
            recruit.votes[i] = entry
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(recruit.votes, entry)
    end
    SideQuest.Comm.SendVote({ recruit_id = recruitId, officer = officer, vote = vote, at = entry.at })
    Recruits.Save(recruit)
end

--- Move a recruit through the vetting pipeline (applicant/trial/accepted/
-- declined); saves and shares like any other edit.
function Recruits.SetStatus(recruitId, status)
    if not requireOfficer() then
        return nil
    end
    local recruit = findRecruit(recruitId)
    if not recruit then
        SideQuest.Print("Unknown recruit " .. tostring(recruitId))
        return nil
    end
    recruit.status = status
    return Recruits.Save(recruit)
end

--------------------------------------------------------------------------
-- Member notes
--------------------------------------------------------------------------

function Recruits.ListNotes(character)
    local out = {}
    for _, note in ipairs(SideQuestDB.officerData.member_notes) do
        if not note.voided and (not character or note.character == character) then
            table.insert(out, note)
        end
    end
    return out
end

function Recruits.AddNote(character, text)
    if not requireOfficer() then
        return nil
    end
    local note = {
        id = SideQuest.NextId(),
        character = character,
        note = text,
        officer = SideQuest.NormalizeUnit("player"),
        at = now(),
        voided = false,
    }
    table.insert(SideQuestDB.officerData.member_notes, note)
    table.insert(SideQuestDB.pending.member_notes, note)
    SideQuest.Comm.SendNote(note)
    SideQuest.Fire("SQ_NOTE_ADDED", note)
    return note
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if not SideQuest.IsOfficer() then
        return -- officer-channel data never processed on non-officer clients
    end
    if msgType == "RECRUIT" then
        local ok, recruit = pcall(SideQuestJSON.decode, payload)
        if ok then
            upsertRecruit(recruit)
            SideQuest.Fire("SQ_RECRUIT_SAVED", recruit)
        end
    elseif msgType == "VOTE" then
        local ok, v = pcall(SideQuestJSON.decode, payload)
        if ok then
            local recruit = findRecruit(v.recruit_id)
            if recruit then
                local replaced = false
                for i, existing in ipairs(recruit.votes) do
                    if existing.officer == v.officer then
                        recruit.votes[i] = { officer = v.officer, vote = v.vote, at = v.at }
                        replaced = true
                        break
                    end
                end
                if not replaced then
                    table.insert(recruit.votes, { officer = v.officer, vote = v.vote, at = v.at })
                end
            end
        end
    elseif msgType == "NOTE" then
        local ok, note = pcall(SideQuestJSON.decode, payload)
        if ok then
            local replaced = false
            for i, existing in ipairs(SideQuestDB.officerData.member_notes) do
                if existing.id == note.id then
                    SideQuestDB.officerData.member_notes[i] = note
                    replaced = true
                    break
                end
            end
            if not replaced then
                table.insert(SideQuestDB.officerData.member_notes, note)
            end
        end
    end
end)

return Recruits
