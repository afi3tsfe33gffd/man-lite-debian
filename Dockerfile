FROM debian:12-slim

ARG XRAY_VERSION=26.9.30
ARG SNI_VERSION=1.0.2
ARG AETHER_VERSION=2.4.0

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Tehran

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl gettext-base jq musl nginx nano procps socat sqlite3 tar tzdata unzip \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && mkdir -p /etc/xray /var/log/xray /usr/share/xray /usr/local/bin/pt /root/x \
    && rm -rf /var/lib/apt/lists/*

# Xray is installed from its official Linux AMD64 release, not from an Alpine image.
RUN set -eux; \
    curl -fL "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -o /tmp/xray.zip; \
    mkdir -p /tmp/xray /usr/local/share/xray; \
    unzip -o /tmp/xray.zip -d /tmp/xray; \
    install -m 755 /tmp/xray/xray /usr/bin/xray; \
    [ ! -f /tmp/xray/geoip.dat ] || install -m 644 /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat; \
    [ ! -f /tmp/xray/geosite.dat ] || install -m 644 /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat; \
    rm -rf /tmp/xray /tmp/xray.zip; \
    /usr/bin/xray version

# SNI Spoof (musl build is self-contained and can run on Debian).
RUN set -eux; \
    curl -fL "https://github.com/therealaleph/sni-spoofing-rust/releases/download/v${SNI_VERSION}/sni-spoof-rs-linux-amd64-musl" -o /usr/local/bin/sni-spoof-rs; \
    chmod 755 /usr/local/bin/sni-spoof-rs

# Keep the original project assets, fetched from the source repository.
RUN set -eux; \
    curl -fL https://raw.githubusercontent.com/afi3tsfe33gffd/man-lite/main/x/x.zip -o /tmp/x.zip; \
    curl -fL https://raw.githubusercontent.com/afi3tsfe33gffd/man-lite/main/x/am.zip -o /tmp/am.zip; \
    unzip -o /tmp/x.zip -d /root/x; \
    unzip -o /tmp/am.zip -d /root/x; \
    test -f /root/x/arman; \
    chmod 755 /root/x/arman /root/x/x; \
    rm -f /tmp/x.zip /tmp/am.zip

RUN set -eux; \
    curl -fL https://raw.githubusercontent.com/afi3tsfe33gffd/man-lite/main/cotten/CottenDns_Client_Linux-Legacy_AMD64_v2026.10.24.183015-7db7b73 -o /usr/local/bin/cotten; \
    curl -fL https://raw.githubusercontent.com/afi3tsfe33gffd/man-lite/main/cotten/slipnet-linux-amd64 -o /usr/local/bin/slipnet; \
    chmod 755 /usr/local/bin/cotten /usr/local/bin/slipnet

RUN set -eux; \
    curl -fL "https://github.com/CluvexStudio/Aether/releases/download/v${AETHER_VERSION}/aether-linux-x86_64-musl.tar.gz" -o /tmp/aether.tar.gz; \
    tar -xzf /tmp/aether.tar.gz -C /tmp; \
    install -m 755 /tmp/aether /usr/local/bin/aether; \
    install -m 755 /tmp/pt/lyrebird /usr/local/bin/pt/lyrebird; \
    install -m 755 /tmp/pt/psiphon-tunnel-core /usr/local/bin/pt/psiphon-tunnel-core; \
    rm -rf /tmp/aether.tar.gz /tmp/aether /tmp/pt

# Default valid config. Mount your own /etc/xray directory to provide production config.
RUN printf '%s\\n' '{"inbounds":[],"outbounds":[{"protocol":"freedom","settings":{}}]}' > /etc/xray/config.json \
    && printf '%s\\n' '{"listeners":[]}' > /etc/xray/pconfig.json

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh

RUN chmod 755 /start.sh

EXPOSE 3000
CMD ["/start.sh"]
