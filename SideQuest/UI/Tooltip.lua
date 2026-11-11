-- SideQuest/UI/Tooltip.lua
-- Directory lines on item tooltips: who crafts, sells, buys or holds the item. See docs/directory.md.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
SideQuest.UI.Tooltip = SideQuest.UI.Tooltip or {}
local Tooltip = SideQuest.UI.Tooltip

-- Forever runs the Mainline 12.x API: TooltipDataProcessor.AddTooltipPostCall
-- with Enum.TooltipDataType.Item is how a modern client adds tooltip lines.
-- Degrade silently (no hook at all) when either is missing.
if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then
    return Tooltip
end

--- "Name-Realm" to "Name", to keep tooltip lines short.
local function shortName(character)
    return character and character:gsub("%-.+$", "") or "?"
end

--- Joins up to two entries formatted by `formatFn`, "+N more" past that --
-- keeps every line to one row regardless of guild size.
local function joinCapped(list, formatFn)
    local parts = {}
    for i, entry in ipairs(list) do
        if i > 2 then
            table.insert(parts, "+" .. (#list - 2) .. " more")
            break
        end
        table.insert(parts, formatFn(entry))
    end
    return table.concat(parts, ", ")
end

--- SideQuest.Market.FormatPrice once Market.lua has it; a plain copper
-- fallback otherwise so a missing collector never blanks the line.
local function moneyText(copper)
    if SideQuest.Market and SideQuest.Market.FormatPrice then
        return SideQuest.Market.FormatPrice(copper)
    end
    return tostring(copper or 0) .. "c"
end

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- "Xh ago" / "Xd ago" / "just now", for a server-time timestamp.
local function ago(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then
        return "unknown"
    end
    local hours = math.floor(math.max(0, now() - ts) / 3600)
    if hours < 1 then
        return "just now"
    elseif hours < 48 then
        return hours .. "h ago"
    end
    return math.floor(hours / 24) .. "d ago"
end

local function tipColor()
    local C = SideQuest.UI.Colors
    if C and C.mist then
        return C.mist[1], C.mist[2], C.mist[3]
    end
    return 0.77, 0.84, 0.96
end

local function onItemTooltip(tooltip, data)
    -- These are scans over the whole directory on every hover; skip rather
    -- than risk a hitch mid-fight (DESIGN.md: nothing costly runs in combat).
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local Directory = SideQuest.Directory
    local itemId = data and SideQuest.Unsecret(data.id)
    if not Directory or not itemId then
        return
    end

    local lines = {}

    -- Game import "prices" (contract "Game import"): the guild's lowest AH
    -- price for this item, if a sync has priced it.
    local priceEntry = SideQuest.Market and SideQuest.Market.AuctionPrice and SideQuest.Market.AuctionPrice(itemId)
    if priceEntry then
        table.insert(lines, "Auction house: " .. moneyText(priceEntry.p)
            .. " (" .. (priceEntry.q or 0) .. " listed, " .. ago(priceEntry.at) .. ")")
        -- Game import "prices" `wanted` (contract SQI1, additive): distinct
        -- guild members with this item on their wishlist; absent/0 on an
        -- old import or an unwished item, so this line just doesn't appear.
        if (priceEntry.w or 0) > 0 then
            table.insert(lines, "Wanted by " .. priceEntry.w .. (priceEntry.w == 1 and " guildie" or " guildies"))
        end
    end

    -- Crafters: WhoCrafts matches by recipe name substring, so this only
    -- works once the item's name is known, and only keeps hits whose
    -- recipe produces exactly this item (not every partial-name match).
    if Directory.WhoCrafts then
        local itemName = SideQuest.GetItemInfo(itemId)
        if itemName then
            local crafters, seen = {}, {}
            for _, hit in ipairs(Directory.WhoCrafts(itemName) or {}) do
                if hit.recipe_name == itemName and not seen[hit.character] then
                    seen[hit.character] = true
                    table.insert(crafters, hit)
                end
            end
            -- Offline/imported crafters (contract SQI1 on-demand "crafters" +
            -- "recipe_names", additive): a guildie who is offline or doesn't
            -- run the addon still shows up here. The import carries recipe
            -- ids, not item ids, so this matches by recipe name exactly the
            -- same way the live WhoCrafts hits above were filtered.
            local onDemand = SideQuestDB.onDemand
            for _, row in ipairs((onDemand and onDemand.crafters) or {}) do
                if not seen[row.character] then
                    for _, recipeId in ipairs(row.recipes or {}) do
                        local name = onDemand.recipe_names[tostring(recipeId)]
                        if name == itemName then
                            seen[row.character] = true
                            table.insert(crafters, { character = row.character })
                            break
                        end
                    end
                end
            end
            if #crafters > 0 then
                table.insert(lines, "Crafted by " .. joinCapped(crafters, function(c) return shortName(c.character) end))
            end
        end
    end

    if #lines < 3 and Directory.WhoSells then
        local sellers = Directory.WhoSells(itemId) or {}
        if #sellers > 0 then
            table.insert(lines, "Selling: " .. joinCapped(sellers, function(s)
                return shortName(s.character) .. " " .. moneyText(s.price)
            end))
        end
    end

    if #lines < 3 and Directory.WhoBuys then
        local buyers = Directory.WhoBuys(itemId) or {}
        if #buyers > 0 then
            table.insert(lines, "Buying: " .. joinCapped(buyers, function(b)
                return shortName(b.character) .. " " .. moneyText(b.price)
            end))
        end
    end

    if #lines < 3 and Directory.WhoHas then
        local holders = Directory.WhoHas(itemId) or {}
        if #holders > 0 then
            table.insert(lines, #holders .. (#holders == 1 and " guildie has this" or " guildies have this"))
        end
    end

    local shown = math.min(3, #lines)
    for i = 1, shown do
        tooltip:AddLine(lines[i], tipColor())
    end
    if shown > 0 and tooltip.Show then
        tooltip:Show()
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)

return Tooltip
