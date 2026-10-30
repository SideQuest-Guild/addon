-- SideQuest/Libs/Json.lua
-- Minimal pure Lua 5.1 JSON encoder/decoder. No external dependencies.
-- Supports: object, array, string, number, boolean, null, nested structures.
-- Lua tables have no distinct "array" type; an empty table encodes as `{}` and
-- SideQuestJSON.EMPTY_ARRAY may be used to force `[]` when needed.

SideQuestJSON = {}

SideQuestJSON.EMPTY_ARRAY = setmetatable({}, { __jsonarray = true })

local ESCAPES = {
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function escapeString(s)
    local out = s:gsub("[%z\1-\31\\\"]", function(c)
        if ESCAPES[c] then
            return ESCAPES[c]
        end
        return string.format("\\u%04x", string.byte(c))
    end)
    return out
end

local encodeValue

local function isArray(t)
    if t == SideQuestJSON.EMPTY_ARRAY then
        return true
    end
    local meta = getmetatable(t)
    if meta and meta.__jsonarray then
        return true
    end
    local count = 0
    local maxIndex = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
        if k > maxIndex then
            maxIndex = k
        end
    end
    if count == 0 then
        return false -- ambiguous empty table defaults to object unless marked
    end
    return maxIndex == count
end

local function encodeArray(t, buf)
    buf[#buf + 1] = "["
    local n = #t
    for i = 1, n do
        if i > 1 then
            buf[#buf + 1] = ","
        end
        encodeValue(t[i], buf)
    end
    buf[#buf + 1] = "]"
end

local function encodeObject(t, buf)
    buf[#buf + 1] = "{"
    local first = true
    -- deterministic key order for stable output / easier testing
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        if not first then
            buf[#buf + 1] = ","
        end
        first = false
        buf[#buf + 1] = "\"" .. escapeString(tostring(k)) .. "\":"
        encodeValue(t[k], buf)
    end
    buf[#buf + 1] = "}"
end

encodeValue = function(v, buf)
    local tv = type(v)
    if v == nil then
        buf[#buf + 1] = "null"
    elseif tv == "boolean" then
        buf[#buf + 1] = v and "true" or "false"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            buf[#buf + 1] = "null"
        elseif math.floor(v) == v and math.abs(v) < 1e15 then
            buf[#buf + 1] = string.format("%d", v)
        else
            buf[#buf + 1] = string.format("%.17g", v)
        end
    elseif tv == "string" then
        buf[#buf + 1] = "\"" .. escapeString(v) .. "\""
    elseif tv == "table" then
        if next(v) == nil then
            if v == SideQuestJSON.EMPTY_ARRAY then
                buf[#buf + 1] = "[]"
            else
                buf[#buf + 1] = "{}"
            end
        elseif isArray(v) then
            encodeArray(v, buf)
        else
            encodeObject(v, buf)
        end
    else
        error("SideQuestJSON.encode: cannot encode type " .. tv)
    end
end

function SideQuestJSON.encode(value)
    local buf = {}
    encodeValue(value, buf)
    return table.concat(buf)
end

-- Decoder: a small recursive-descent parser.
local function newParser(str)
    return { s = str, i = 1, n = #str }
end

local function peek(p)
    return p.s:sub(p.i, p.i)
end

local function skipWhitespace(p)
    while p.i <= p.n do
        local c = peek(p)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            p.i = p.i + 1
        else
            break
        end
    end
end

local parseValue

local function parseError(p, msg)
    error("SideQuestJSON.decode: " .. msg .. " at position " .. p.i)
end

local function parseLiteral(p, literal, value)
    if p.s:sub(p.i, p.i + #literal - 1) == literal then
        p.i = p.i + #literal
        return value
    end
    parseError(p, "expected '" .. literal .. "'")
end

local function parseString(p)
    if peek(p) ~= "\"" then
        parseError(p, "expected string")
    end
    p.i = p.i + 1
    local parts = {}
    while true do
        if p.i > p.n then
            parseError(p, "unterminated string")
        end
        local c = peek(p)
        if c == "\"" then
            p.i = p.i + 1
            break
        elseif c == "\\" then
            p.i = p.i + 1
            local esc = peek(p)
            if esc == "\"" then
                parts[#parts + 1] = "\""
            elseif esc == "\\" then
                parts[#parts + 1] = "\\"
            elseif esc == "/" then
                parts[#parts + 1] = "/"
            elseif esc == "b" then
                parts[#parts + 1] = "\b"
            elseif esc == "f" then
                parts[#parts + 1] = "\f"
            elseif esc == "n" then
                parts[#parts + 1] = "\n"
            elseif esc == "r" then
                parts[#parts + 1] = "\r"
            elseif esc == "t" then
                parts[#parts + 1] = "\t"
            elseif esc == "u" then
                local hex = p.s:sub(p.i + 1, p.i + 4)
                local code = tonumber(hex, 16) or 0
                p.i = p.i + 4
                if code < 0x80 then
                    parts[#parts + 1] = string.char(code)
                elseif code < 0x800 then
                    parts[#parts + 1] = string.char(
                        0xC0 + math.floor(code / 0x40),
                        0x80 + (code % 0x40)
                    )
                else
                    parts[#parts + 1] = string.char(
                        0xE0 + math.floor(code / 0x1000),
                        0x80 + (math.floor(code / 0x40) % 0x40),
                        0x80 + (code % 0x40)
                    )
                end
            else
                parseError(p, "invalid escape")
            end
            p.i = p.i + 1
        else
            parts[#parts + 1] = c
            p.i = p.i + 1
        end
    end
    return table.concat(parts)
end

local function parseNumber(p)
    local start = p.i
    if peek(p) == "-" then
        p.i = p.i + 1
    end
    while peek(p):match("%d") do
        p.i = p.i + 1
    end
    if peek(p) == "." then
        p.i = p.i + 1
        while peek(p):match("%d") do
            p.i = p.i + 1
        end
    end
    if peek(p) == "e" or peek(p) == "E" then
        p.i = p.i + 1
        if peek(p) == "+" or peek(p) == "-" then
            p.i = p.i + 1
        end
        while peek(p):match("%d") do
            p.i = p.i + 1
        end
    end
    local numStr = p.s:sub(start, p.i - 1)
    local num = tonumber(numStr)
    if not num then
        parseError(p, "invalid number")
    end
    return num
end

local function parseArray(p)
    p.i = p.i + 1 -- consume [
    local arr = setmetatable({}, { __jsonarray = true })
    skipWhitespace(p)
    if peek(p) == "]" then
        p.i = p.i + 1
        return arr
    end
    local idx = 0
    while true do
        skipWhitespace(p)
        idx = idx + 1
        arr[idx] = parseValue(p)
        skipWhitespace(p)
        local c = peek(p)
        if c == "," then
            p.i = p.i + 1
        elseif c == "]" then
            p.i = p.i + 1
            break
        else
            parseError(p, "expected ',' or ']'")
        end
    end
    return arr
end

local function parseObject(p)
    p.i = p.i + 1 -- consume {
    local obj = {}
    skipWhitespace(p)
    if peek(p) == "}" then
        p.i = p.i + 1
        return obj
    end
    while true do
        skipWhitespace(p)
        local key = parseString(p)
        skipWhitespace(p)
        if peek(p) ~= ":" then
            parseError(p, "expected ':'")
        end
        p.i = p.i + 1
        skipWhitespace(p)
        obj[key] = parseValue(p)
        skipWhitespace(p)
        local c = peek(p)
        if c == "," then
            p.i = p.i + 1
        elseif c == "}" then
            p.i = p.i + 1
            break
        else
            parseError(p, "expected ',' or '}'")
        end
    end
    return obj
end

parseValue = function(p)
    skipWhitespace(p)
    local c = peek(p)
    if c == "{" then
        return parseObject(p)
    elseif c == "[" then
        return parseArray(p)
    elseif c == "\"" then
        return parseString(p)
    elseif c == "t" then
        return parseLiteral(p, "true", true)
    elseif c == "f" then
        return parseLiteral(p, "false", false)
    elseif c == "n" then
        return parseLiteral(p, "null", nil)
    elseif c == "-" or c:match("%d") then
        return parseNumber(p)
    else
        parseError(p, "unexpected character '" .. c .. "'")
    end
end

function SideQuestJSON.decode(str)
    if type(str) ~= "string" then
        error("SideQuestJSON.decode: expected string")
    end
    local p = newParser(str)
    skipWhitespace(p)
    local value = parseValue(p)
    skipWhitespace(p)
    if p.i <= p.n then
        parseError(p, "trailing data")
    end
    return value
end
