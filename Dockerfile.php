# ./Dockerfile.php
FROM php:8.3-cli

# Base tooling + libraries for pdo_pgsql
RUN echo "memory_limit=1024M" > /usr/local/etc/php/conf.d/zz-memory-limit.ini
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libpq-dev \
 && docker-php-ext-install pdo_mysql pdo_pgsql \
 && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /work
