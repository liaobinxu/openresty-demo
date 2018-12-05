-- file myapp.lua: example "myapp" module
-- https://github.com/openresty/lua-resty-lrucache

local _M = {}

-- alternatively: local lrucache = require "resty.lrucache.pureffi"
local lrucache = require "resty.lrucache"

-- we need to initialize the cache on the lua module level so that
-- it can be shared by all the requests served by each nginx worker process:
local c, err = lrucache.new(200)  -- allow up to 200 items in the cache
if not c then
    return error("failed to create the cache: " .. (err or "unknown"))
end

function _M.go(key)
    ngx.say("key:", key)
    c:set("dog", 32)
    c:set("cat", 56)
    ngx.say("dog: ", c:get("dog"))
    ngx.say("cat: ", c:get("cat"))

    c:set("dog", { age = 10 }, 0.1)  -- expire in 0.1 sec
    c:delete("dog")

    c:flush_all()  -- flush all the cached data
end

function _M.get_from_cache(key)
    -- ngx.say("key:", key)
    local val = c:get(key)
    -- ngx.say("val:", val)
    return val, nil
end

function _M.set_to_cache(key, value, timeout)
    -- c:set(key, { age = 10 }, timeout)  -- expire in 0.1 sec
    -- c:set("dog", { age = 10 }, 0.1)  -- expire in 0.1 sec
    c:set(key, value, timeout)  -- expire in 0.1 sec
    -- ngx.say("set11 key:", key)
    -- ngx.say("set11 value:", value)
    -- ngx.say("set11 timeout:", timeout)
    return 1, nil
end

return _M
