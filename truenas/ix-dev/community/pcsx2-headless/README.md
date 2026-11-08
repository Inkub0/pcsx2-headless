# PCSX2 Headless

[PCSX2 Headless](https://github.com/Inkub0/pcsx2-headless) streams PS2 games from your NAS.
It runs PCSX2 in Big Picture mode on a GPU-accelerated virtual screen and streams it with Sunshine,
so you play from any [Moonlight](https://moonlight-stream.org) client.

- Assign a GPU (AMD, Intel or NVIDIA) under Resources.
- The app takes over the GPU's display output, so only one display app (e.g. Steam Headless) can use a GPU at a time.
- Point **PS2 BIOS Storage** at a folder with your BIOS dump and **PS2 Games Storage** at your ISO/CHD files.
- Pair Moonlight at `https://<server-ip>:47990`, then start the **PCSX2** app from Moonlight.
  For PAL games, start **PCSX2 (PAL 50 Hz)** and set Moonlight's frame rate to 50.

No BIOS or games are included. You must dump them from hardware you own.
