FROM alpine:3.16

RUN addgroup -S -g 1000 redis && adduser -S -G redis -u 999 redis

# 改为中科大镜像源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# 调整时区
RUN apk add --no-cache --virtual .build-tzdata tzdata ; \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;\
    apk del .build-tzdata;



RUN apk add --no-cache \
                'su-exec>=0.2' \
                tzdata

ENV REDIS_VERSION 6.2.7
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-6.2.7.tar.gz
ENV REDIS_DOWNLOAD_SHA b7a79cc3b46d3c6eb52fa37dde34a4a60824079ebdfb3abfbbfa035947c55319

# 编译 Redis 相关镜像
RUN set -eux; \
        \
        # 使用 --virtual 将软件包虚拟安装到 .build-deps 空间下, 之后会被打包
        # 使用 --no-cache 不会留下缓存文件
        apk add --no-cache --virtual .build-deps \
                coreutils \
                dpkg-dev dpkg \
                gcc \
                linux-headers \
                make \
                musl-dev \
                openssl-dev \
                wget \
        ; \
        \
        wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
        echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
        mkdir -p /usr/src/redis; \
        tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
        rm redis.tar.gz; \
        \
        # 禁用 Redis 的保护模式
        grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' /usr/src/redis/src/config.c; \
        sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' /usr/src/redis/src/config.c; \
        grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' /usr/src/redis/src/config.c; \
        \
        # 获取CPU架构
        gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
        extraJemallocConfigureFlags="--build=$gnuArch"; \
        dpkgArch="$(dpkg --print-architecture)"; \
        case "${dpkgArch##*-}" in \
                amd64 | i386 | x32) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=12" ;; \
                *) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=16" ;; \
        esac; \
        extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-hugepage=21"; \
        # 根据架构调整 Makefile 文件
        grep -F 'cd jemalloc && ./configure ' /usr/src/redis/deps/Makefile; \
        sed -ri 's!cd jemalloc && ./configure !&'"$extraJemallocConfigureFlags"' !' /usr/src/redis/deps/Makefile; \
        grep -F "cd jemalloc && ./configure $extraJemallocConfigureFlags " /usr/src/redis/deps/Makefile; \
        \
        # 编译 Redis
        export BUILD_TLS=yes; \
        make -C /usr/src/redis -j "$(nproc)" all; \
        make -C /usr/src/redis install; \
        \
        # Redis
        serverMd5="$(md5sum /usr/local/bin/redis-server | cut -d' ' -f1)"; export serverMd5; \
        find /usr/local/bin/redis* -maxdepth 0 \
                -type f -not -name redis-server \
                -exec sh -eux -c ' \
                        md5="$(md5sum "$1" | cut -d" " -f1)"; \
                        test "$md5" = "$serverMd5"; \
                ' -- '{}' ';' \
                -exec ln -svfT 'redis-server' '{}' ';' \
        ; \
        \
        rm -r /usr/src/redis; \
        \
        runDeps="$( \
                scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
                        | tr ',' '\n' \
                        | sort -u \
                        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
        )"; \
        apk add --no-network --virtual .redis-rundeps $runDeps; \
        # 基于前面安装卸载 .build-deps 虚拟包
        apk del --no-network .build-deps; \
        \
        redis-cli --version; \
        redis-server --version

RUN mkdir /data && chown redis:redis /data
VOLUME /data
WORKDIR /data

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 6379
CMD ["redis-server"]