FROM catthehacker/ubuntu:act-latest

# Lightweight runner image for local GitHub Actions via `act`.
# Includes Docker CLI/Compose from the base image and installs the latest `act`.
RUN set -euo pipefail \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh \
       | bash -s -- -b /usr/local/bin \
    && act --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /github/workspace
