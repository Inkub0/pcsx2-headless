# PCSX2 Headless

Stream PS2 games from a headless server (TrueNAS SCALE or any Docker host) to any
[Moonlight](https://moonlight-stream.org) client.

One container, one job: **Xorg → Openbox → PCSX2 (Big Picture, fullscreen) → Sunshine**.
No desktop environment, no Steam, no Flatpak sandbox, no first-boot downloads (apart from
a one-time NVIDIA driver fetch on NVIDIA systems).

> **Status: first version, not yet tested on real hardware.** Expect a round or two of fixes,
> especially around input and NVIDIA. See [Testing checklist](#testing-checklist).

## What you get

- PCSX2 (official AppImage, latest stable at build time) starts in Big Picture mode, already set up:
  BIOS folder `/bios`, game folder `/games`, Vulkan renderer, 3× resolution, VSync, first controller mapped.
- Sunshine (latest LizardByte release) with two apps: **PCSX2** and **Restart PCSX2**.
- AMD and Intel via VAAPI, NVIDIA via NVENC, or software-only as a last resort.
- Tear-free output: `TearFree` on AMD, `ForceFullCompositionPipeline` on NVIDIA.
- Settings, memory cards, save states and Sunshine pairing persist in `/config`, in visible folders:
  `PCSX2/` (settings in `inis/`, `memcards/`, `sstates/`, `covers/`) and `sunshine/` (settings, pairing).
  Older installs that kept them in the hidden `.config` folder are moved there automatically.

No BIOS or games are included. Dump them from hardware you own.

## Quick start on TrueNAS (Custom App)

1. Publish the image. Push this repo to GitHub; the included workflow builds
   `ghcr.io/<you>/pcsx2-headless` (make the package public under your GitHub profile → Packages).
2. Create datasets for config, BIOS and ISOs. The `apps` user (UID 568) needs write access to the
   config dataset and read access to the other two.
3. Apps → Discover Apps → Custom App → **Install via YAML**. Paste `truenas-custom-app.yaml`
   after editing the lines marked `# <-`. On NVIDIA, uncomment the `deploy:` block.
4. Open `https://<server-ip>:47990`, log in, and pair Moonlight using the PIN tab.
5. In Moonlight, start **PCSX2**.

## Settings (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `SUNSHINE_USER` / `SUNSHINE_PASS` | `admin` / empty | Sunshine web UI login. Avoid quotes, `$` and `\`. |
| `SUNSHINE_ALLOWED_ORIGINS` | empty | Extra web UI addresses Sunshine accepts changes from, e.g. `https://truenas.local:47990`. The server's own IPs are added automatically |
| `RESOLUTION` | `1920x1080` | `1280x720`, `1920x1080`, `2560x1440` or `3840x2160` |
| `REFRESH_RATE` | `60` | Other rates need `cvt`, which isn't installed by default |
| `GPU_TYPE` | `auto` | `auto`, `amd`, `intel`, `nvidia`, `dummy` (software only) |
| `TEARFREE` | `true` | Removes tearing at the cost of a little latency |
| `PUID` / `PGID` | `568` | User that runs PCSX2 and Sunshine and owns `/config` |
| `DRI_CARD` | auto | Pick a GPU when there are several, e.g. `card1` |
| `XORG_OUTPUT` | auto | Force a specific output, using the Xorg driver's name (e.g. `DisplayPort-0`) |
| `NVIDIA_CONNECTED_MONITOR` | `DFP-0` | Fake monitor the NVIDIA driver drives |
| `PCSX2_RENDERER` | `14` | `14` Vulkan, `12` OpenGL, `13` software. Applied on every start when set |
| `PCSX2_UPSCALE` | `3` | Internal resolution multiplier. Applied on every start when set |
| `PCSX2_ARGS` | empty | Extra PCSX2 command-line arguments |
| `PCSX2_COVERS` | `false` | `true` downloads missing covers for your games on start (from [xlenore/ps2-covers](https://github.com/xlenore/ps2-covers)); they show after PCSX2 restarts |
| `PCSX2_COVERS_STYLE` | `default` | `default` (flat) or `3d` box art |
| `PCSX2_COVERS_URL` | empty | Your own cover source; must contain `${serial}` |
| `SUNSHINE_ENCODER` | auto | Override Sunshine's encoder (`vaapi`, `nvenc`, `software`) |
| `ENABLE_UDEV` | `true` | Needed for Moonlight keyboard/mouse. Controllers work without it |
| `INPUT_GID` | auto | Host gid of `/dev/input` nodes, if auto-detection guesses wrong |

## Headless displays

- **AMD / Intel:** the image uses a real GPU output. With nothing plugged in, it forces the first
  output on. Most cards accept that. If yours shows a black stream, a cheap HDMI or DisplayPort
  dummy plug fixes it for good.
- **NVIDIA:** the driver is told a monitor is connected (`ConnectedMonitor`), so no plug is needed.
  On first start the container downloads the NVIDIA driver package that matches the host
  (cached in `/config/.cache`) to get the Xorg driver, which the container toolkit doesn't provide.

## Testing checklist

Check the app logs after each step. Every line from this image starts with `[pcsx2-headless]`.

1. **Starts:** `GPU: amd (card0, renderD128)` or similar, then `Wrote /etc/X11/xorg.conf`.
2. **Display:** no Xorg restarts in the log. Details are in `/tmp/Xorg.0.log` inside the container.
3. **Sunshine:** the web UI opens; its log shows an encoder found (`h264_vaapi` or `h264_nvenc`).
4. **Picture:** Moonlight shows PCSX2's Big Picture game list.
5. **Controller:** the Moonlight controller moves through the menus and works in game.
6. **Keyboard/mouse:** the mouse moves in the stream (needs udev).
7. **Audio:** game sound comes through Moonlight.
8. **Persistence:** restart the app; settings and pairing are still there.

Useful commands in the container shell:

```bash
supervisorctl -c /etc/supervisor/pcsx2-headless.conf status
cat /etc/X11/xorg.conf
tail -n 50 /tmp/Xorg.0.log
ls -l /dev/input /dev/uinput /dev/dri
```

## Submitting to the TrueNAS catalog

The app definition lives in `truenas/ix-dev/community/pcsx2-headless/`, modelled on the
official Steam Headless app and checked against TrueNAS app library 2.3.18.

1. Fill in the `YOUR_...` placeholders in `app.yaml` and `ix_values.yaml`, and pin `ix_values.yaml`
   to a released image tag.
2. Open an issue on [truenas/apps](https://github.com/truenas/apps) proposing the app and naming
   yourself as maintainer. Wait for approval.
3. Fork truenas/apps, copy the folder into `ix-dev/community/`, and render it:
   `./.github/scripts/ci.py --app pcsx2-headless --train community --test-file basic-values.yaml --render-only=true`
4. Open the PR. TrueNAS hosts the icon; they'll tell you how to supply it.

## Repository layout

```
Dockerfile                      image build
rootfs/usr/local/bin/           entrypoint and service start scripts
rootfs/usr/local/share/...      first-run PCSX2 and Sunshine settings
rootfs/etc/supervisor/          service definitions
truenas-custom-app.yaml         TrueNAS "Install via YAML" file
truenas/ix-dev/community/...    TrueNAS catalog app (for the PR)
.github/workflows/build.yml     builds and publishes the image (weekly rebuild for new releases)
```

## Licence

PCSX2 is GPL-3.0 and Sunshine is GPL-3.0. Publishing this repository under GPL-3.0 keeps things simple.
PCSX2 Headless is a community project, not affiliated with the PCSX2 or LizardByte teams.
