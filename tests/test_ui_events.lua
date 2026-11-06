-- tests/test_ui_events.lua
-- The Events tab for imported events: role counts only for raid/dungeon/world_boss, a going/maybe/can't
-- summary and no officer invite/place-groups buttons for the other five kinds.

return function(h)
    local function open()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.inCombat = false
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-EVT0001" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Raids")
        return SideQuest.UI.panels.Raids.chamber
    end

    h.test("events tab: a role-kind event shows Signed: Tank/Healer/DPS counts", function()
        local chamber = open()
        SideQuestDB.standings.generated_at = 1793500000
        SideQuestDB.events = {
            { id = "evt-raid", title = "Molten Core", kind = "raid", starts_at = WowStub.time + 3600, signups = {
                { character = "Demo2", class = "WARRIOR", role = "tank", status = "signed" },
                { character = "Demo3", class = "PRIEST", role = "healer", status = "signed" },
            } },
        }
        SideQuest.UI.RefreshRaids()
        local row = chamber.rows[1]
        h.assertTrue(row.roleCounts:GetText():find("Signed: Tank 1", 1, true) ~= nil, "role counts shown")
    end)

    h.test("events tab: a non-role event shows Going/Maybe/Can't counts, not role counts", function()
        local chamber = open()
        SideQuestDB.standings.generated_at = 1793500000
        SideQuestDB.events = {
            { id = "evt-other", title = "The Adventure Begins - Discord hang out", kind = "other",
                starts_at = WowStub.time + 3600, signups = {
                    { character = "Demo2", status = "signed" },
                    { character = "Demo3", status = "tentative" },
                    { character = "Demo4", status = "absent" },
                } },
        }
        SideQuest.UI.RefreshRaids()
        local row = chamber.rows[1]
        h.assertEq(row.roleCounts:GetText(), "Going 1  --  Maybe 1  --  Can't 1", "going/maybe/can't counts shown")
        h.assertTrue(row.roleCounts:GetText():find("Signed:", 1, true) == nil, "no role-count line")
    end)

    h.test("events tab: Going/Maybe/Can't answers work without a role, and officer actions stay raid-only", function()
        local chamber = open()
        WowStub.isOfficer = true
        SideQuestDB.standings.generated_at = 1793500000
        SideQuestDB.events = {
            { id = "evt-other", title = "Game Night", kind = "social", starts_at = WowStub.time + 3600, signups = {} },
        }
        SideQuest.UI.RefreshRaids()
        local row = chamber.rows[1]
        h.assertTrue(not row.inviteBtn:IsShown(), "invite button hidden for a non-role event")
        h.assertTrue(not row.placeBtn:IsShown(), "place-groups button hidden for a non-role event")

        row.answers.going:GetScript("OnClick")()
        local _, status = SideQuest.Signups.MyState("evt-other")
        h.assertEq(status, "signed", "Going answer sent without a role")
    end)

    h.test("events tab: a raid event still shows invite/place-groups buttons for officers", function()
        local chamber = open()
        WowStub.isOfficer = true
        SideQuestDB.standings.generated_at = 1793500000
        SideQuestDB.events = {
            { id = "evt-raid", title = "Molten Core", kind = "raid", starts_at = WowStub.time + 3600, signups = {} },
        }
        SideQuest.UI.RefreshRaids()
        local row = chamber.rows[1]
        h.assertTrue(row.inviteBtn:IsShown(), "invite button shown for a raid event")
        h.assertTrue(row.placeBtn:IsShown(), "place-groups button shown for a raid event")
    end)
end
