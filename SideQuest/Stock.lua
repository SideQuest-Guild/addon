-- SideQuest/Stock.lua
-- This character's "stock" directory section: crafting materials in bags and bank. See docs/directory.md.

SideQuest = SideQuest or {}
SideQuest.Stock = SideQuest.Stock or {}
local Stock = SideQuest.Stock

local function now()
    return GetServerTime and GetServerTime() or 0
end

local TRADE_GOODS_CLASS_ID = 7
local REAGENT_CLASS_ID = 5

-- Backpack + four bags. [UNCONFIRMED] whether Forever adds a dedicated reagent bag slot like retail;
-- if it does its bag ID is not yet known, so that bag's materials are simply not counted yet.
local BAG_IDS = { 0, 1, 2, 3, 4 }
-- Main bank (-1) + bank bag slots 5-11 (classic-era bank bag count). [UNCONFIRMED] bank bag IDs on Forever.
local BANK_BAG_IDS = { -1, 5, 6, 7, 8, 9, 10, 11 }

local function sellItemIds()
    local set = {}
    local m = SideQuestDB.market
    if m then
        for _, row in ipairs(m.sell or {}) do
            set[row.item_id] = true
        end
    end
    return set
end

local function isTracked(itemId, sellIds)
    if sellIds[itemId] then
        return true
    end
    if not (C_Item and C_Item.GetItemInfoInstant) then
        return false
    end
    local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemId)
    if not ok then
        return false
    end
    return classID == TRADE_GOODS_CLASS_ID or classID == REAGENT_CLASS_ID
end

local function countBag(bagId, sellIds, counts)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return
    end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagId)
    if not ok or not slots then
        return
    end
    for slot = 1, slots do
        local ok2, info = pcall(C_Container.GetContainerItemInfo, bagId, slot)
        if ok2 and info and info.itemID and isTracked(info.itemID, sellIds) then
            counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
        end
    end
end

local function toRows(counts)
    local rows = {}
    for itemId, count in pairs(counts) do
        table.insert(rows, { itemId, count })
    end
    table.sort(rows, function(a, b)
        return a[1] < b[1]
    end)
    return rows
end

--- Pure: bag contents matching the tracked classes (or anything in market.sell), as `{ itemId, count }` rows.
function Stock.CollectBags()
    local sellIds = sellItemIds()
    local counts = {}
    for _, bagId in ipairs(BAG_IDS) do
        countBag(bagId, sellIds, counts)
    end
    return toRows(counts)
end

--- Pure: bank contents, same filter as CollectBags.
function Stock.CollectBank()
    local sellIds = sellItemIds()
    local counts = {}
    for _, bagId in ipairs(BANK_BAG_IDS) do
        countBag(bagId, sellIds, counts)
    end
    return toRows(counts)
end

--------------------------------------------------------------------------
-- Store: this character's own bags/bank, independent of settings.share.stock.
--------------------------------------------------------------------------

local function myStock()
    SideQuestDB.stock = SideQuestDB.stock or { bags = {}, bank = {}, bank_at = nil }
    return SideQuestDB.stock
end

local function publish()
    local st = myStock()
    SideQuest.Directory.SetMine("stock", { bags = st.bags, bank = st.bank, bank_at = st.bank_at })
end

function Stock.ScanBags()
    SideQuest.WhenOutOfCombat(function()
        local st = myStock()
        st.bags = Stock.CollectBags()
        publish()
    end)
end

function Stock.ScanBank()
    SideQuest.WhenOutOfCombat(function()
        local st = myStock()
        st.bank = Stock.CollectBank()
        st.bank_at = now()
        publish()
    end)
end

--------------------------------------------------------------------------
-- Triggers: bags debounced 5s, bank on open.
--------------------------------------------------------------------------

local bagScanPending = false

local function scheduleBagScan()
    if bagScanPending then
        return
    end
    bagScanPending = true
    local function run()
        bagScanPending = false
        Stock.ScanBags()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(5, run)
    else
        run()
    end
end

SideQuest.On("BAG_UPDATE_DELAYED", scheduleBagScan)
SideQuest.RegisterGameEvent("BAG_UPDATE_DELAYED")
SideQuest.On("BANKFRAME_OPENED", Stock.ScanBank)
SideQuest.RegisterGameEvent("BANKFRAME_OPENED")
SideQuest.On("PLAYER_ENTERING_WORLD", Stock.ScanBags)

return Stock
