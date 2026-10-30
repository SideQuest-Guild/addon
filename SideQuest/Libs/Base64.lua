-- SideQuest/Libs/Base64.lua
-- Standard (RFC 4648) base64 alphabet with '=' padding. Pure Lua 5.1, no bitwise ops.

SideQuestBase64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local ENCODE_LOOKUP = {}
local DECODE_LOOKUP = {}
for i = 1, #ALPHABET do
    local ch = ALPHABET:sub(i, i)
    ENCODE_LOOKUP[i - 1] = ch
    DECODE_LOOKUP[ch] = i - 1
end

function SideQuestBase64.encode(data)
    if data == nil or data == "" then
        return ""
    end
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local b1 = data:byte(i) or 0
        local b2 = data:byte(i + 1)
        local b3 = data:byte(i + 2)

        -- combine 3 bytes into a 24-bit value using arithmetic (no bitwise ops)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)

        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64

        out[#out + 1] = ENCODE_LOOKUP[c1]
        out[#out + 1] = ENCODE_LOOKUP[c2]
        out[#out + 1] = b2 and ENCODE_LOOKUP[c3] or "="
        out[#out + 1] = b3 and ENCODE_LOOKUP[c4] or "="

        i = i + 3
    end
    return table.concat(out)
end

function SideQuestBase64.decode(str)
    if str == nil or str == "" then
        return ""
    end
    -- strip any whitespace/newlines defensively
    str = str:gsub("%s", "")
    local len = #str
    if len % 4 ~= 0 then
        error("SideQuestBase64.decode: invalid length")
    end
    local out = {}
    local i = 1
    while i <= len do
        local c1 = str:sub(i, i)
        local c2 = str:sub(i + 1, i + 1)
        local c3 = str:sub(i + 2, i + 2)
        local c4 = str:sub(i + 3, i + 3)

        local v1 = DECODE_LOOKUP[c1]
        local v2 = DECODE_LOOKUP[c2]
        if v1 == nil or v2 == nil then
            error("SideQuestBase64.decode: invalid character")
        end

        local pad3 = (c3 == "=")
        local pad4 = (c4 == "=")
        local v3 = pad3 and 0 or DECODE_LOOKUP[c3]
        local v4 = pad4 and 0 or DECODE_LOOKUP[c4]
        if v3 == nil or v4 == nil then
            error("SideQuestBase64.decode: invalid character")
        end

        local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4

        local b1 = math.floor(n / 65536) % 256
        local b2 = math.floor(n / 256) % 256
        local b3 = n % 256

        out[#out + 1] = string.char(b1)
        if not pad3 then
            out[#out + 1] = string.char(b2)
        end
        if not pad4 then
            out[#out + 1] = string.char(b3)
        end

        i = i + 4
    end
    return table.concat(out)
end
