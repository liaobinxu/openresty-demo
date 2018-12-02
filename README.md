
## 安装

```
sudo apt-get install libssl-dev
cd /data/install/
wget https://openresty.org/download/openresty-1.13.6.2.tar.gz
tar zxvf openresty-1.13.6.2.tar.gz
cd openresty-1.13.6.2
./configure --prefix=/data/software/openresty-1.13.6.2
make -j2 && make -j2 install
cd /data/software/
ln -s openresty-1.13.6.2/ openresty
```

## 配置环境变量
sudo vim /etc/profile
```
export PATH=$PATH:/data/software/openresty/bin
```
source /etc/profile

## 测试HelloWorld
```
resty -e 'print("hello, world!")'
// output: hello, world
```

## Prepare directory layout
准备工作目录
```
mkdir ~/work
cd ~/work
mkdir logs/ conf/
```


## Prepare the nginx.conf config file
Create a simple plain text file named conf/nginx.conf with the following contents in it:
```
worker_processes  1;
error_log logs/error.log;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            default_type text/html;
            content_by_lua '
                ngx.say("<p>hello, world</p>")
            ';
        }
    }
}
```

## Start the Nginx server

openresty是安装目录bin文件， 是安装目录nginx/sbin/nginx的软件

```
openresty -p `pwd`/ -c conf/nginx.conf
```

## Access our HelloWorld web service

```
curl http://localhost:8080/
```

## Test performance
```
cd /data/install/
git clone https://github.com/wg/wrk.git
cd wrk/
make
```
由于没有默认目录， 拷贝到bin

```
cp wrk ~/bin/
wrk -t10 -c400 -d5s http://127.0.0.1:8080/
```

测试输出
```
Running 5s test @ http://127.0.0.1:8080/
  10 threads and 400 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     8.22ms   15.89ms 205.98ms   88.90%
    Req/Sec    13.06k     2.73k   21.38k    70.36%
  657546 requests in 5.07s, 134.17MB read
Requests/sec: 129686.81
Transfer/sec:     26.46MB
```

## 添加lua package目录
在nginx.conf添加关键字 `lua_package_path`, 添加目录的lua文件才能被`require("myapp")`， `myapp`是目录下的`myapp.lua`.


```
http {
    lua_package_path "/home/jackson/workspace/github/openresty-demo/?.lua;;";
}
```

## 使用content_by_lua_file代替content_by_lua

```
        location / {
            default_type text/html;
            content_by_lua_file /home/jackson/workspace/github/openresty-demo/helloworld.lua;
            #content_by_lua '
            #    ngx.say("<p>hello, world1</p>")
            #    ngx.say("<p>hello, world1</p>")
            #';
        }
```

## 开发环境关闭lua cache减少-s reload
!!只能在开发环境中使用， 否则会影响线上环境性能

```
server {
    listen 8080;
    # lua_code_cache off;
}
```

## 安装redis
```
cd /data/install
wget http://download.redis.io/releases/redis-5.0.2.tar.gz
tar zvxf redis-5.0.2.tar.gz
cd redis-5.0.2
make
make PREFIX=/data/software/redis-5.0.2 install
cd /data/software
ln -s redis-5.0.2 redis
```

sudo vim /etc/profile
```
export PATH=$PATH:/data/software/redis/bin
```
source /etc/profile

## 访问 redis

启动redis
```
./bin/redis-server redis.conf &
```

参考文档 https://github.com/openresty/lua-resty-redis
```
local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(1000) -- 1 sec

-- or connect to a unix domain socket file listened
-- by a redis server:
--     local ok, err = red:connect("unix:/path/to/redis.sock")

local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.say("failed to connect: ", err)
    return
end

ok, err = red:set("dog", "an animal")
if not ok then
    ngx.say("failed to set dog: ", err)
    return
end

ngx.say("set result: ", ok)

local res, err = red:get("dog")
if not res then
    ngx.say("failed to get dog: ", err)
    return
end

-- put it into the connection pool of size 100,
-- with 10 seconds max idle time
-- local ok, err = red:set_keepalive(10000, 100)

local ok, err = red:close()
if not ok then
     ngx.say("failed to close: ", err)
     return
end
```

## 使用lrcache代替nginx共享内存
主要原因是前置是基于一个worker的 ，后者是基于所有worker的； 对后者写操作加锁会锁住所有worker

https://github.com/openresty/lua-resty-lrucache

## 缓存失效风暴
https://moonbingbing.gitbooks.io/openresty-best-practices/content/lock/cache-miss-storm.html
看下这个段伪代码：
```
local value = get_from_cache(key)
if not value then
    value = query_db(sql)
    set_to_cache(value， timeout ＝ 100)
end
return value
```
看上去没有问题，在单元测试情况下，也不会有异常。
但是，进行压力测试的时候，你会发现，每隔 100 秒，数据库的查询就会出现一次峰值。如果你的 cache 失效时间设置的比较长，那么这个问题被发现的机率就会降低。
为什么会出现峰值呢？想象一下，在 cache 失效的瞬间，如果并发请求有 1000 条同时到了 query_db(sql) 这个函数会怎样？没错，会有 1000 个请求打向数据库。这就是缓存失效瞬间引起的风暴。它有一个英文名，叫 "dog-pile effect"。
怎么解决？自然的想法是发现缓存失效后，加一把锁来控制数据库的请求。具体的细节，春哥在 lua-resty-lock 的文档里面做了详细的说明，我就不重复了，请看这里。多说一句，lua-resty-lock 库本身已经替你完成了 wait for lock 的过程，看代码的时候需要注意下这个细节。

解决办法就是加锁， 不过要注意double check的问题.


## 参考文档
[openresty最佳实践](https://www.gitbook.com/book/moonbingbing/openresty-best-practices)
[openresty最佳实践-连接池](https://moonbingbing.gitbooks.io/openresty-best-practices/web/conn_pool.html)
[Openresty+Lua+Redis灰度发布](https://www.cnblogs.com/Eivll0m/p/6774622.html)
[缓存失效风暴](https://moonbingbing.gitbooks.io/openresty-best-practices/content/lock/cache-miss-storm.html)
