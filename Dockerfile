# syntax=docker/dockerfile:1
#
# PCSX2 Headless: a single-purpose PS2 streaming box.
# Xorg + Openbox + PulseAudio + Sunshine + PCSX2 (Big Picture). No desktop environment.
#
FROM debian:trixie-slim

# Pinned upstream releases (GitHub release tags). Bump them to update; "latest" also works.
# .github/workflows/check-upstream.yml opens an issue when a newer stable release is out.
ARG PCSX2_VERSION=v2.8.2
ARG SUNSHINE_VERSION=v2026.914.233613
ARG IMAGE_VERSION=dev

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    NVIDIA_DRIVER_CAPABILITIES=all \
    PUID=568 \
    PGID=568 \
    TZ=Etc/UTC \
    RESOLUTION=1920x1080 \
    REFRESH_RATE=60 \
    GPU_TYPE=auto \
    TEARFREE=true \
    ENABLE_UDEV=true \
    SUNSHINE_USER=admin \
    SUNSHINE_NAME=pcsx2-headless

# Runtime: Xorg (amdgpu, modesetting, dummy), Mesa (VAAPI + Vulkan), audio, input, Qt/xcb libs for the AppImage
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl jq crudini supervisor tini util-linux procps kmod pciutils \
        xserver-xorg-core xserver-xorg-video-amdgpu xserver-xorg-video-dummy \
        xserver-xorg-input-libinput x11-xserver-utils x11-utils xauth openbox \
        libgl1 libegl1 libgles2 libglx-mesa0 libgl1-mesa-dri libgbm1 \
        mesa-vulkan-drivers mesa-va-drivers intel-media-va-driver vainfo vulkan-tools \
        pulseaudio pulseaudio-utils udev \
        libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-xinput0 \
        libxcb-xkb1 libfontconfig1 libfreetype6 libdbus-1-3 libasound2t64 libpulse0 libudev1 \
        libgpg-error0 libx11-xcb1 libxi6 libxrandr2 libsm6 libice6 libusb-1.0-0 \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Newer Mesa (Vulkan, VAAPI, GL) from trixie-backports; everything else stays on trixie.
# -t trixie-backports lets apt take any library the newer Mesa needs from backports too.
RUN set -eu; \
    signed_by=$(sed -n 's/^Signed-By:[[:space:]]*//p' /etc/apt/sources.list.d/debian.sources | head -n1); \
    printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main\nSigned-By: %s\n' \
        "$signed_by" > /etc/apt/sources.list.d/backports.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends -t trixie-backports \
        libglx-mesa0 libegl-mesa0 libgl1-mesa-dri libgbm1 mesa-vulkan-drivers mesa-va-drivers; \
    dpkg-query -W -f '${Package} ${Version}\n' mesa-vulkan-drivers mesa-va-drivers libgl1-mesa-dri; \
    rm -rf /var/lib/apt/lists/*

# Sunshine: official LizardByte .deb for Debian trixie.
# An optional build secret "github_token" avoids GitHub API rate limits in CI.
# No "set -x" in these steps: it would print the token into the build log.
# Files are downloaded through the API asset URL (redirects straight to GitHub's file storage):
# the github.com/.../releases/download links have been returning 504 at times.
RUN --mount=type=secret,id=github_token \
    set -eu; \
    auth=(); [ -s /run/secrets/github_token ] && auth=(-H "Authorization: Bearer $(cat /run/secrets/github_token)"); \
    rel=latest; [ "$SUNSHINE_VERSION" != latest ] && rel="tags/$SUNSHINE_VERSION"; \
    release=$(curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors "${auth[@]}" "https://api.github.com/repos/LizardByte/Sunshine/releases/$rel"); \
    asset=$(jq -c '[.assets[] | select(.name | endswith("debiantrixie_amd64.deb"))][0] // empty' <<<"$release"); \
    if [ -z "$asset" ]; then echo "No Debian trixie package in Sunshine release $(jq -r .tag_name <<<"$release"). Assets:" >&2; jq -r '.assets[].name' <<<"$release" >&2; exit 1; fi; \
    url=$(jq -r .browser_download_url <<<"$asset"); echo "Sunshine: $url"; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors "${auth[@]}" -H "Accept: application/octet-stream" \
         -o /tmp/sunshine.deb "$(jq -r .url <<<"$asset")"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/sunshine.deb; \
    echo "$url" > /etc/sunshine-source; \
    rm -rf /tmp/sunshine.deb /var/lib/apt/lists/*

# PCSX2: official Qt AppImage, unpacked so it runs without FUSE or a Flatpak sandbox.
RUN --mount=type=secret,id=github_token \
    set -eu; \
    auth=(); [ -s /run/secrets/github_token ] && auth=(-H "Authorization: Bearer $(cat /run/secrets/github_token)"); \
    rel=latest; [ "$PCSX2_VERSION" != latest ] && rel="tags/$PCSX2_VERSION"; \
    release=$(curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors "${auth[@]}" "https://api.github.com/repos/PCSX2/pcsx2/releases/$rel"); \
    asset=$(jq -c '[.assets[] | select(.name | endswith("linux-appimage-x64-Qt.AppImage"))][0] // empty' <<<"$release"); \
    if [ -z "$asset" ]; then echo "No Linux AppImage in PCSX2 release $(jq -r .tag_name <<<"$release"). Assets:" >&2; jq -r '.assets[].name' <<<"$release" >&2; exit 1; fi; \
    url=$(jq -r .browser_download_url <<<"$asset"); echo "PCSX2: $url"; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors "${auth[@]}" -H "Accept: application/octet-stream" \
         -o /tmp/pcsx2.AppImage "$(jq -r .url <<<"$asset")"; \
    chmod +x /tmp/pcsx2.AppImage; \
    cd /opt; /tmp/pcsx2.AppImage --appimage-extract >/dev/null; \
    mv squashfs-root pcsx2; \
    echo "$url" > /opt/pcsx2/.source; \
    rm /tmp/pcsx2.AppImage; \
    # The AppImage leaves some libraries (e.g. libgpg-error) to the system. Fail the build,
    # listing them, instead of finding out at runtime ("error while loading shared libraries").
    libdirs=$(find /opt/pcsx2 -name '*.so*' -printf '%h\n' | sort -u | paste -sd:); \
    missing=$( { find /opt/pcsx2/usr/bin /opt/pcsx2/usr/lib /opt/pcsx2/usr/plugins/platforms \
                    -maxdepth 1 -type f -print0 2>/dev/null \
                 | xargs -0 -r env LD_LIBRARY_PATH="$libdirs" ldd 2>/dev/null || true; } \
               | awk '/=> not found/ {print $1}' | sort -u | paste -sd' '); \
    if [ -n "$missing" ]; then echo "PCSX2 needs libraries missing from the image: $missing" >&2; exit 1; fi

RUN groupadd -g 568 pcsx2 \
    && useradd -u 568 -g 568 -d /config -M -s /bin/bash pcsx2

COPY rootfs/ /
COPY LICENSE NOTICE /usr/share/doc/pcsx2-headless/
RUN chmod 0755 /usr/local/bin/* \
    && echo "$IMAGE_VERSION" > /etc/pcsx2-headless-version

VOLUME ["/config"]

# Sunshine / Moonlight. With host networking these are informational only.
EXPOSE 47984/tcp 47989/tcp 47990/tcp 48010/tcp 47998/udp 47999/udp 48000/udp

# Plain TCP check: the web UI answers 401 without a login, which curl -f treats as a failure
# (and it spams Sunshine's log with "not authorized").
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD bash -c '</dev/tcp/127.0.0.1/47990' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
