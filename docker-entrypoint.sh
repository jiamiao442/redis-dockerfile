#!/bin/sh
set -e

# 当第一个参数使用 `-f` or `--some-option` 这样参数时
# 或以 `.conf` 结尾,
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
  # 将第一个参数设为 redis-server, 方便后面启动
        set -- redis-server "$@"
fi

# 当启动程序是 'redis-server' 且 uid = 0 时, 即 Root 启动
if [ "$1" = 'redis-server' -a "$(id -u)" = '0' ]; then
  # 1. 调整数据目录属主为 Redis
        find . \! -user redis -exec chown redis '{}' +
  # 2. 使用 exec su-exec 组合启动redis-server,  会将当前 PID 传递给 redis-server, 并切换用户为 redis
  #    注意: 使用 exec 后, 后面脚本将不会执行
        exec su-exec redis "$0" "$@"
fi

# 当用户使用其它用户启动, 或者非 redis-server 服务启动适时会执行如下代码

# 修改默认权限 为 700
um="$(umask)"
if [ "$um" = '0022' ]; then
        umask 0077
fi

# 启动服务
exec "$@"