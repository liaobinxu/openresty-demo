-- https://github.com/openresty/lua-resty-redis
-- https://github.com/openresty/lua-resty-lrucache
-- https://github.com/openresty/lua-resty-lock
local myapp = require("myapp")
local resty_lock = require "resty.lock"

local key = "dog"
local val = myapp.get_from_cache(key)
if val == nil then
    -- step 1:
    local lock, err = resty_lock:new("my_locks")
    if not lock then
        ngx.say("failed to create lock: ", err)
    end
    local id = ngx.worker.id()

    -- cache miss!
    -- step 2:
    ngx.say("id: ", id, ", key：", key)
    local lockKey = "my_key_" .. id .. "_" .. key
    local elapsed, err = lock:lock(lockKey)
    ngx.say("lock: ", elapsed, ", lockKey:", lockKey)
    -- lock successfully acquired!

    -- step 3:
    -- someone might have already put the value into the cache
    -- so we check it here again:
    local val, err = myapp.get_from_cache(key)
    if val then
        local ok, err = lock:unlock()
        if not ok then
            return fail("failed to unlock: ", err)
        end

        ngx.say("result: ", val)
        return
    end

    --- step 4:
    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(1000) -- 1 sec

    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.say("failed to connect: ", err)
        lock:unlock()
        return
    end

    local val, err = red:get(key)
    if not val then
        local ok, err = lock:unlock()
        if not ok then
            return fail("failed to unlock: ", err)
        end
        -- FIXME: we should handle the backend miss more carefully
        -- here, like inserting a stub value into the cache.
        ngx.say("no value found")
        return
    end

    -- put it into the connection pool of size 100,
    -- with 10 seconds max idle time
    -- local ok, err = red:set_keepalive(10000, 100)

    -- or just close the connection right away:
    local ok, err = red:close()
    if not ok then
        lock:unlock()
        ngx.say("failed to close: ", err)
        return
    end

    -- update the shm cache with the newly fetched value
    -- local ok, err = cache:set(key, val, 1)
    local ok, err = myapp.set_to_cache(key, val, 10)
    if not ok then
        local ok, err = lock:unlock()
        if not ok then
            return fail("failed to unlock: ", err)
        end

        return fail("failed to update shm cache: ", err)
    end

    local ok, err = lock:unlock()
    if not ok then
        return fail("failed to unlock: ", err)
    end

    ngx.say("result: ", val)
else
    ngx.say("<p>get_from_cache:", val, "</p>")
end
