local B = GrimfallBags
B.Json = {}

local ESCAPES = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function EncodeString(s)
    local out = s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format('\\u%04x', c:byte())
    end)
    return '"'..out..'"'
end

local function IsArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n == #t
end

local Encode
local function EncodeValue(v)
    local t = type(v)
    if t == "string" then return EncodeString(v)
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "table" then return Encode(v)
    else return "null" end
end

Encode = function(t)
    if next(t) == nil then return "[]" end
    if IsArray(t) then
        local parts = {}
        for i = 1, #t do parts[i] = EncodeValue(t[i]) end
        return "["..table.concat(parts, ",").."]"
    end
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts+1] = EncodeString(tostring(k))..":"..EncodeValue(v)
    end
    return "{"..table.concat(parts, ",").."}"
end
B.Json.Encode = Encode

local function SkipWS(s, i)
    local _, e = s:find("^%s*", i)
    return e + 1
end

local function DecodeString(s, i)
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then error("unterminated string") end
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local n = s:sub(i + 1, i + 1)
            if n == "n" then out[#out+1] = "\n"
            elseif n == "r" then out[#out+1] = "\r"
            elseif n == "t" then out[#out+1] = "\t"
            elseif n == "u" then
                local hex = s:sub(i + 2, i + 5)
                out[#out+1] = string.char(tonumber(hex, 16) or 63)
                i = i + 4
            else
                out[#out+1] = n
            end
            i = i + 2
        else
            out[#out+1] = c
            i = i + 1
        end
    end
end

local Decode
Decode = function(s, i)
    i = SkipWS(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return DecodeString(s, i + 1)
    elseif c == "{" then
        local obj = {}
        i = SkipWS(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            i = SkipWS(s, i)
            if s:sub(i, i) ~= '"' then error("expected object key at "..i) end
            local key
            key, i = DecodeString(s, i + 1)
            i = SkipWS(s, i)
            if s:sub(i, i) ~= ":" then error("expected ':' at "..i) end
            local val
            val, i = Decode(s, i + 1)
            obj[key] = val
            i = SkipWS(s, i)
            local d = s:sub(i, i)
            if d == "," then i = i + 1
            elseif d == "}" then return obj, i + 1
            else error("bad object at "..i) end
        end
    elseif c == "[" then
        local arr = {}
        i = SkipWS(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local val
            val, i = Decode(s, i)
            arr[#arr+1] = val
            i = SkipWS(s, i)
            local d = s:sub(i, i)
            if d == "," then i = i + 1
            elseif d == "]" then return arr, i + 1
            else error("bad array at "..i) end
        end
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local numStr = s:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
        if not numStr or numStr == "" then
            error("bad value at "..i.." near '"..s:sub(i, i + 10).."'")
        end
        return tonumber(numStr), i + #numStr
    end
end

function B.Json.Decode(str)
    if not str or str == "" then return nil, "empty string" end
    local ok, result = pcall(Decode, str, 1)
    if not ok then return nil, result end
    return result
end
