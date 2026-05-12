FROM --platform=linux/amd64 debian:trixie-slim

LABEL org.opencontainers.image.authors="RhavinX"
LABEL org.opencontainers.image.source="https://git.riyria.xyz/rhavin/windrose"
LABEL org.opencontainers.image.description="Windrose Dedicated Server"

ARG DEBIAN_FRONTEND=noninteractive

ADD --chmod=755 https://dl.winehq.org/wine-builds/winehq.key /etc/apt/keyrings/winehq-archive.key
ADD https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources /etc/apt/sources.list.d/winehq-trixie.sources

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get install -y --no-install-recommends \
        curl \
        unzip \
        xvfb \
        winbind \
        gosu \
        jq \
        tzdata \
        procps && \
    apt-get clean -y && apt-get autopurge -y && \
    rm -rf /var/lib/apt/lists/*

ARG DEPOT_DOWNLOADER_VERSION=3.4.0
RUN curl -sL \
    "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" \
    -o /tmp/dd.zip && \
    unzip /tmp/dd.zip -d /depotdownloader && \
    chmod +x /depotdownloader/DepotDownloader && \
    rm /tmp/dd.zip

RUN useradd -m -s /bin/bash steam

ENV SERVERHOME="/home/steam/windrose/server"
ENV GAMEDATA="/home/steam/windrose/data"

COPY start.sh /start.sh
COPY ServerDescription.json /ServerDescription.json

RUN mkdir -p ${SERVERHOME} ${GAMEDATA} && \
    chmod +x /start.sh && \
    chown -R steam:steam /home/steam/windrose

VOLUME ["/home/steam/windrose/server", "/home/steam/windrose/data"]

EXPOSE 7777/udp
EXPOSE 7777/tcp

ENTRYPOINT ["/start.sh"]
