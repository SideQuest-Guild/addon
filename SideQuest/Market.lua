-- SideQuest/Market.lua
-- This character's "market" directory section: what they sell, buy and request. See docs/directory.md.

SideQuest = SideQuest or {}
SideQuest.Market = SideQuest.Market or {}
local Market = SideQuest.Market

local function now()
    return GetServerTime and GetServerTime() or 0
end

--------------------------------------------------------------------------
-- Price parsing/formatting: "1g20s", "35s", "80c", or a plain decimal
-- number of gold ("1.5" = 1g 50s). Returns copper, or nil if unparseable.
--------------------------------------------------------------------------

function Market.ParsePrice(text)
    if not text then
        return nil
    end
    text = text:gsub("%s", "")
    if text == "" then
        return nil
    end
    if text:match("^%d+%.?%d*$") then
        local gold = tonumber(text)
        if not gold then
            return nil
        end
        return math.floor(gold * 10000 + 0.5)
    end
    local g = tonumber(text:match("(%d+)g")) or 0
    local s = tonumber(text:match("(%d+)s")) or 0
    local c = tonumber(text:match("(%d+)c")) or 0
    if g == 0 and s == 0 and c == 0 then
        return nil
    end
    return g * 10000 + s * 100 + c
end

function Market.FormatPrice(copper)
    if not copper then
        return "whisper me"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then
        table.insert(parts, g .. "g")
    end
    if s > 0 then
        table.insert(parts, s .. "s")
    end
    if c > 0 or #parts == 0 then
        table.insert(parts, c .. "c")
    end
    return table.concat(parts, " ")
end

--- The guild's lowest auction-house price for itemId from the last game
-- import ("Game import" contract: SideQuestDB.prices), or nil when none is
-- known. { p = unit_price copper, q = quantity, at = unix timestamp,
-- w = distinct wishers (contract SQI1 `wanted`, additive; 0 on an old import) }.
function Market.AuctionPrice(itemId)
    return SideQuestDB and SideQuestDB.prices and SideQuestDB.prices[itemId]
end

--- A price hint from an installed addon, in copper, or nil. Never required.
function Market.SuggestPrice(itemId)
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "SideQuest", itemId)
        if ok and price and price > 0 then
            return math.floor(price)
        end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemId)
        if ok and price and price > 0 then
            return math.floor(price)
        end
    end
    return nil
end

--------------------------------------------------------------------------
-- Store: this character's own sell/buy/requests, independent of whether
-- `settings.share.market` is on (that only governs what Directory publishes).
--------------------------------------------------------------------------

local function myMarket()
    SideQuestDB.market = SideQuestDB.market or { sell = {}, buy = {}, requests = {} }
    return SideQuestDB.market
end

local function publish()
    local m = myMarket()
    SideQuest.Directory.SetMine("market", { sell = m.sell, buy = m.buy, requests = m.requests })
end

--- An item ID from a number, an item link, or an item name the client has
-- cached ("Arcanite Bar"). Nil when it can't tell.
local function parseItemArg(token)
    if not token then
        return nil
    end
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then
        return nil
    end
    local id = tonumber(token)
    if id then
        return math.floor(id)
    end
    local linkId = token:match("item:(%d+)")
    if linkId then
        return tonumber(linkId)
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemId = pcall(C_Item.GetItemInfoInstant, token)
        if ok and type(itemId) == "number" then
            return itemId
        end
    end
    return nil
end
Market.ParseItemArg = parseItemArg

function Market.SetSell(itemId, price, qty, crafted)
    local m = myMarket()
    for i, row in ipairs(m.sell) do
        if row.item_id == itemId then
            table.remove(m.sell, i)
            break
        end
    end
    table.insert(m.sell, { item_id = itemId, price = price, qty = qty, crafted = crafted and true or false })
    publish()
end

function Market.RemoveSell(itemId)
    local m = myMarket()
    for i, row in ipairs(m.sell) do
        if row.item_id == itemId then
            table.remove(m.sell, i)
            break
        end
    end
    publish()
end

function Market.SetBuy(itemId, price)
    local m = myMarket()
    for i, row in ipairs(m.buy) do
        if row.item_id == itemId then
            table.remove(m.buy, i)
            break
        end
    end
    table.insert(m.buy, { item_id = itemId, price = price })
    publish()
end

function Market.RemoveBuy(itemId)
    local m = myMarket()
    for i, row in ipairs(m.buy) do
        if row.item_id == itemId then
            table.remove(m.buy, i)
            break
        end
    end
    publish()
end

function Market.AddRequest(itemId, qty, price, note)
    local m = myMarket()
    local character = SideQuest.NormalizeUnit("player") or "Unknown-Unknown"
    SideQuestDB.seq = (SideQuestDB.seq or 0) + 1
    local id = character .. "-" .. tostring(SideQuestDB.seq)
    table.insert(m.requests, { id = id, item_id = itemId, qty = qty, price = price, note = note, at = now() })
    publish()
    return id
end

function Market.RemoveRequest(id)
    local m = myMarket()
    for i, row in ipairs(m.requests) do
        if row.id == id then
            table.remove(m.requests, i)
            break
        end
    end
    publish()
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

--- Split the item off the front of a command: a shift-clicked link (which
-- has spaces in it), a "quoted name", or one word (an ID or a one-word name).
local function splitItem(rest)
    rest = rest or ""
    local link, after = rest:match("^%s*(|c%x+|H.-|h|r)%s*(.*)$")
    if not link then
        link, after = rest:match("^%s*(|H.-|h)%s*(.*)$")
    end
    if link then
        return link, after
    end
    local quoted, afterQuote = rest:match('^%s*"(.-)"%s*(.*)$')
    if quoted then
        return quoted, afterQuote
    end
    return rest:match("^%s*(%S*)%s*(.*)$")
end
Market.SplitItem = splitItem

SideQuest.RegisterSlash("sell", function(rest)
    local itemToken, after = splitItem(rest)
    local priceToken, qtyToken, craftedToken = after:match("^(%S*)%s*(%S*)%s*(%S*)")
    local itemId = parseItemArg(itemToken)
    if not itemId then
        SideQuest.Print('Usage: /sq sell <item link, ID or "name"> <price, e.g. 1g20s> [qty] [crafted]')
        return
    end
    local price = Market.ParsePrice(priceToken)
    local qty = tonumber(qtyToken)
    local crafted = craftedToken == "crafted"
    Market.SetSell(itemId, price, qty, crafted)
    SideQuest.Print("Selling " .. SideQuest.ItemName(itemId) .. " for " .. Market.FormatPrice(price)
        .. (qty and (" x" .. qty) or ""))
end, "sell <item> <price> [qty] [crafted] - add or replace a sell listing")

SideQuest.RegisterSlash("buy", function(rest)
    local itemToken, after = splitItem(rest)
    local priceToken = after:match("^(%S*)")
    local itemId = parseItemArg(itemToken)
    if not itemId then
        SideQuest.Print('Usage: /sq buy <item link, ID or "name"> <price, e.g. 1g20s>')
        return
    end
    local price = Market.ParsePrice(priceToken)
    Market.SetBuy(itemId, price)
    SideQuest.Print("Buying " .. SideQuest.ItemName(itemId) .. " for " .. Market.FormatPrice(price))
end, "buy <item> <price> - add or replace a standing buy offer")

SideQuest.RegisterSlash("request", function(rest)
    local itemToken, after = splitItem(rest)
    local qtyToken, remainder = after:match("^(%S*)%s*(.-)$")
    local itemId = parseItemArg(itemToken)
    local qty = tonumber(qtyToken)
    if not itemId or not qty then
        SideQuest.Print('Usage: /sq request <item link, ID or "name"> <qty> [price] [note]')
        return
    end
    local priceToken, note = remainder:match("^(%S*)%s*(.-)$")
    local price = Market.ParsePrice(priceToken)
    if not price then
        note = remainder
    end
    Market.AddRequest(itemId, qty, price, note ~= "" and note or nil)
    SideQuest.Print("Asked the guild for " .. qty .. "x " .. SideQuest.ItemName(itemId)
        .. ". /sq unrequest " .. itemId .. " takes it down.")
end, "request <item> <qty> [price] [note] - ask the guild for materials")

SideQuest.RegisterSlash("unrequest", function(rest)
    local token = splitItem(rest)
    local itemId = parseItemArg(token)
    local removedItem = nil
    for _, row in ipairs(myMarket().requests) do
        if row.id == token or (itemId and row.item_id == itemId) then
            removedItem = row.item_id
            Market.RemoveRequest(row.id)
            break
        end
    end
    if not removedItem then
        SideQuest.Print('Usage: /sq unrequest <item link, ID or "name">')
        return
    end
    SideQuest.Print("Took down your request for " .. SideQuest.ItemName(removedItem) .. ".")
end, "unrequest <item> - take down a material request")

return Market
