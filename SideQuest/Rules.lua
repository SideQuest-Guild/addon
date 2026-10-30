-- SideQuest/Rules.lua
-- EP/GP rule numbers. Defaults mirror the contract exactly; an import ("SQI1:")
-- replaces these at runtime so the site remains the source of truth.

SideQuest = SideQuest or {}
SideQuest.Rules = {}

local Rules = SideQuest.Rules

Rules.DEFAULTS = {
    ep = { boss_kill = 10, progress = 10, on_time = 5, full_night = 5, standby = nil }, -- standby mirrors the raid ep
    gp = {
        INVTYPE_HEAD = 100, INVTYPE_CHEST = 100, INVTYPE_ROBE = 100, INVTYPE_LEGS = 100,
        INVTYPE_SHOULDER = 75, INVTYPE_HAND = 75, INVTYPE_WAIST = 75, INVTYPE_FEET = 75,
        INVTYPE_NECK = 55, INVTYPE_WRIST = 55, INVTYPE_CLOAK = 55, INVTYPE_FINGER = 55,
        INVTYPE_HOLDABLE = 55, INVTYPE_SHIELD = 55,
        INVTYPE_TRINKET = 125,
        INVTYPE_WEAPON = 150, INVTYPE_WEAPONMAINHAND = 150, INVTYPE_WEAPONOFFHAND = 150,
        INVTYPE_2HWEAPON = 200,
        INVTYPE_RANGED = 50, INVTYPE_RANGEDRIGHT = 50, INVTYPE_THROWN = 50, INVTYPE_RELIC = 50,
    },
    chase_multiplier = 1.5,
    legendary_gp = 300,
    os_percent = 10,
    base_gp = 100,
    min_gp = 100,
    decay_percent = 15,
    trial_days = 14,
}

-- active rules table; starts as a deep-ish copy of defaults, replaced wholesale on import
local function cloneRules(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local inner = {}
            for ik, iv in pairs(v) do
                inner[ik] = iv
            end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

Rules.active = cloneRules(Rules.DEFAULTS)

function Rules.LoadFromImport(rulesTable)
    if type(rulesTable) ~= "table" then
        return
    end
    Rules.active = cloneRules(rulesTable)
    -- ensure nested ep/gp tables exist even if the import omitted a key
    Rules.active.ep = Rules.active.ep or cloneRules(Rules.DEFAULTS.ep)
    Rules.active.gp = Rules.active.gp or cloneRules(Rules.DEFAULTS.gp)
end

function Rules.Get()
    return Rules.active
end

-- round-half-up to nearest integer
local function roundHalfUp(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return -math.floor(-n + 0.5)
end

--- Compute GP cost for a loot item.
-- @param invType string e.g. "INVTYPE_CHEST" (nil/unknown -> 0)
-- @param response string one of ms|os|alt|council|de|bank
-- @param opts table optional: { isTierToken=bool, tierSlotInvType=string,
--   isChase=bool, isLegendary=bool, isMainCasterWeapon=bool }
function Rules.ComputeGP(invType, response, opts)
    opts = opts or {}
    local rules = Rules.active

    if response == "alt" or response == "de" or response == "bank" then
        return 0
    end

    local baseCost
    if opts.isLegendary then
        baseCost = rules.legendary_gp
    elseif opts.isTierToken then
        local slotType = opts.tierSlotInvType or invType
        baseCost = rules.gp[slotType] or 0
    elseif opts.isMainCasterWeapon and (invType == "INVTYPE_WEAPON" or invType == "INVTYPE_WEAPONMAINHAND") then
        baseCost = rules.gp.INVTYPE_2HWEAPON
    else
        baseCost = rules.gp[invType] or 0
    end

    if opts.isChase then
        baseCost = baseCost * rules.chase_multiplier
    end

    if response == "os" or response == "council" then
        -- council items are officer-decided but still cost GP; os pays a %, council pays full
        if response == "os" then
            return roundHalfUp(baseCost * (rules.os_percent / 100))
        end
        return roundHalfUp(baseCost)
    end

    -- ms
    return roundHalfUp(baseCost)
end

function Rules.EpFor(reason)
    local rules = Rules.active
    if reason == "standby" then
        return nil -- caller supplies the raid's own on_time/full_night amount
    end
    return rules.ep[reason]
end

return Rules
