# PCSX2 Headless

Stream PS2 games from a headless server (TrueNAS SCALE or any Docker host) to any
[Moonlight](https://moonlight-stream.org) client.

One container, one job: **Xorg → Openbox → PCSX2 (Big Picture, fullscreen) → Sunshine**.
No desktop environment, no Steam, no Flatpak sandbox, no first-boot downloads (apart from
a one-time NVIDIA driver fetch on NVIDIA systems and optional covers).

> **Status:** working on TrueNAS SCALE 25.10 with an AMD RX 580 (picture, controller, VAAPI
> encoding). NVIDIA and Intel GPUs are supported by the scripts but not yet tested.

## What you get

- PCSX2 (official AppImage, latest stable at build time) in Big Picture mode, already set up:
  BIOS from `/bios`, games from `/games`, Vulkan renderer, 3× resolution, first controller mapped,
  Guide button opens the pause menu.
- Sunshine (latest LizardByte release) with two apps: **PCSX2** and **Restart PCSX2**.
- Hardware encoding: VAAPI on AMD and Intel, NVENC on NVIDIA (software only as a last resort).
- Optional cover download for your games (`PCSX2_COVERS`).
- Settings, memory cards, save states and pairing kept in your config folder (see [Your files](#your-files)).

## Before you start

> **One display per GPU.** Only one program at a time can drive a graphics card's display.
> PCSX2 Headless runs its own X server on the GPU you give it, so **stop anything else that uses
> that GPU's display first**, for example Steam Headless, another streaming container, or a
> desktop session. If you don't, Xorg fails with `device is not DRM master` / `no screens found`.
> Apps that only use the GPU for transcoding (Jellyfin, Plex) are fine alongside it.

You also need:

- **A supported GPU:** AMD or Intel (VAAPI), or NVIDIA **Turing or newer** (GTX 16xx, RTX 20xx and
  later). TrueNAS 25.10 dropped NVIDIA Pascal, Maxwell and Volta cards (GTX 10xx and older).
- **Host networking.** Moonlight needs it; the TrueNAS YAML already sets it.
- **A PS2 BIOS dump and your games** (ISO, CHD, CSO). None are included. Dump them from hardware you own.

## Install on TrueNAS (Custom App)

1. **Create three folders (datasets)** for config, BIOS and games, e.g.
   `/mnt/tank/apps/pcsx2-headless`, `/mnt/tank/games/ps2/bios`, `/mnt/tank/games/ps2/isos`.
   - The `apps` user (UID 568) needs **write** access to the config folder and **read** access to the other two.
   - **Paths are case-sensitive.** If a path in the YAML doesn't exist exactly as written, Docker
     silently creates an empty folder there. Check with `ls -la <path>` in the TrueNAS shell.
2. **Edit `truenas-custom-app.yaml`.** Change the lines marked `# <-`: the three volume paths,
   `SUNSHINE_PASS` and `TZ`. Pin the image to the newest `sha-...` tag from the
   [package page](https://github.com/users/Inkub0/packages/container/package/pcsx2-headless),
   e.g. `ghcr.io/inkub0/pcsx2-headless:sha-1a2b3c4` (see [Updating](#updating)). On NVIDIA, uncomment the `deploy:` block.
3. **Install:** Apps → Discover Apps → Custom App → **Install via YAML**, paste the file and save.
4. **Check the log** (Apps → Installed → pcsx2-headless → Logs). Within a minute you should see:
   - `GPU: amd (card0, renderD128)` (or `intel` / `nvidia`)
   - `Sunshine web UI accepts changes from: https://<server-ip>:47990`
   - `Found H.264 encoder: h264_vaapi` (or `h264_nvenc`)
   - all services in `RUNNING` state, and no `No BIOS found` / `No games found` warnings
5. **Pair Moonlight:** open `https://<server-ip>:47990`, log in with `SUNSHINE_USER` / `SUNSHINE_PASS`,
   go to the **PIN** tab and enter the PIN Moonlight shows.
6. **Play:** in Moonlight, start **PCSX2**. You get PCSX2's Big Picture game list.
   - **Quit a game:** press the controller's **Guide** button (Xbox / PS / Home) for the pause menu,
     then **Close Game**. If your Moonlight client keeps the Guide button for itself, start
     **Restart PCSX2** from Moonlight instead.
   - **Leave the stream:** Start + Select + L1 + R1 disconnects Moonlight; the game keeps running.

Building your own image instead: fork this repo; the included GitHub workflow publishes
`ghcr.io/<you>/pcsx2-headless`. Make the package public (GitHub profile → Packages → package
settings) so TrueNAS can pull it without logging in.

## Updating

Every push to `main` builds a new image tagged `latest` and `sha-<commit>`. TrueNAS keeps using
its cached copy of `latest`, so **pin the `sha-...` tag** in the YAML and change it to update
(Apps → pcsx2-headless → Edit). Changing the tag makes TrueNAS pull the new image.

## Your files

Everything that matters is in the config folder, so the app can be removed and reinstalled
without losing anything:

```
<config folder>/
  PCSX2/       inis/ (settings), memcards/, sstates/ (save states), covers/
  sunshine/    Sunshine settings and Moonlight pairing
```

Back up `PCSX2/memcards` and `PCSX2/sstates` to keep your saves. Deleting the config folder resets
everything, including pairing.

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

## Troubleshooting

Every line from this image's own scripts starts with `[pcsx2-headless]`.

| Symptom | Cause and fix |
|---|---|
| `device is not DRM master`, `no screens found` | Another program drives the GPU's display (e.g. Steam Headless). Stop it, then restart this app. See [Before you start](#before-you-start). |
| `No BIOS found` / `No games found`, or the game list is empty | The volume path doesn't exist exactly as written (case matters) and Docker created an empty folder, or the `apps` user can't read it. |
| `CSRF Protection Error` in the Sunshine web UI | You opened the UI by a hostname. Add it with `SUNSHINE_ALLOWED_ORIGINS`, e.g. `https://truenas.local:47990`, or use the IP address. |
| The log's first line shows an old commit after updating | TrueNAS reused its cached image. Pin the new `sha-...` tag (see [Updating](#updating)). |
| Black stream on AMD / Intel | The forced output isn't accepted by your card. An HDMI or DisplayPort dummy plug fixes it. |
| No covers | Set `PCSX2_COVERS: "true"`. Covers appear after PCSX2 restarts (Moonlight: **Restart PCSX2**). |
| The config folder looks empty over SMB | Older versions kept data in the hidden `.config` folder. Current versions move it to `PCSX2/` and `sunshine/` on start. |

**Safe to ignore** in the log: PulseAudio `Failed to connect to system bus`, udev `The line has no
effect`, Sunshine `Failed to gain CAP_SYS_ADMIN`, `av1_vaapi` / `HEVCMain10` not usable, and
`System tray` errors.

Useful commands in the TrueNAS shell:

```bash
sudo docker exec pcsx2-headless supervisorctl -c /etc/supervisor/pcsx2-headless.conf status
sudo docker exec pcsx2-headless cat /tmp/Xorg.0.log
sudo docker exec pcsx2-headless ls -la /bios /games
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
