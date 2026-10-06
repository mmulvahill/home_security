# Home Security AI System

A local-first, GPU-accelerated home security camera system built on [Frigate](https://frigate.video).
Everything runs on your own hardware — no cloud, no subscriptions, no footage leaving your network.
Object detection, face recognition, and audio event detection all run locally on an NVIDIA GPU.

Built around **Reolink** cameras, but any camera that exposes an RTSP stream will work.

---

## What you get

- **Frigate NVR** — live view, 24/7 recording, motion/object review, a clean web UI.
- **GPU object detection** — YOLOv9-s on an NVIDIA GPU (person, car, dog, etc.).
- **Native face recognition** — Frigate's built-in face recognition (ArcFace). Enroll known
  faces in the UI; get named alerts for "known" vs "unknown" people.
- **Audio detection** — bark, glass breaking, scream, smoke/CO alarm, and more.
- **MQTT** — publishes every event, so you can wire it into Home Assistant or anything else.

Optional / experimental (off by default): Whisper speech-to-text and license-plate recognition — see
[Optional services](#optional-services).

## Architecture

```
                 Cameras (Reolink, RTSP)
                          │
                          ▼
   ┌───────────────────────────────────────────┐
   │        GPU Server  (Docker Compose)         │
   │                                             │
   │   ┌─────────────────┐     ┌─────────────┐   │
   │   │     Frigate     │────▶│    MQTT     │   │
   │   │  NVR + object   │     │ (Mosquitto) │   │
   │   │  detection +    │     └─────────────┘   │
   │   │  face recog +   │            │          │
   │   │  audio  (GPU)   │            │          │
   │   └────────┬────────┘            ▼          │
   │            │              Home Assistant,   │
   │            │              notifications,    │
   │            ▼              automations (opt)  │
   │   recordings / clips                        │
   └────────────┼────────────────────────────────┘
                ▼
        Storage (NAS over NFS, or a local disk)
```

That's the whole stack: **two containers**, `frigate` and `mqtt`. Face recognition is now native to
Frigate (it used to be a separate CompreFace + Double-Take stack; that was removed in favor of Frigate's
built-in recognition, which is simpler and runs in-process).

## Hardware

You need a Linux box with a single NVIDIA GPU. This is a light load — one GPU comfortably handles a
handful of cameras doing object detection and face recognition at the same time.

| Component | Recommended minimum | Notes |
|---|---|---|
| GPU | One NVIDIA GPU, ~2 GB free VRAM (GTX 1660 / RTX 3050 or newer) | Frigate uses CUDA here; one GPU is plenty |
| CPU | 4-core+ x86-64 | mostly ffmpeg video decode |
| RAM | 8–16 GB | |
| Storage | Room for your retention window (see [Storage](#storage--retention)) | a local disk is fine; a NAS is optional |
| Cameras | Any RTSP camera | the config is tuned for Reolink, which most people run |

**No NVIDIA GPU?** Frigate also supports a Google Coral accelerator or plain CPU detection — both are
fine for a few cameras — but this repo is wired for NVIDIA, so you'd adjust the detector in
`frigate/config/config.yml` to go another way.

**Multiple GPUs?** Frigate runs on GPU **0** by default. To put it on a different GPU, set
`FRIGATE_GPU_ID` in your `.env` (e.g. `FRIGATE_GPU_ID=1`). Single-GPU machines need nothing — `0` is
already correct.

## Prerequisites

- Linux host with Docker + Docker Compose v2
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  (so Docker can see the GPU)
- `nfs-common` **if** you store recordings on a NAS over NFS (see [Storage](#storage--retention))
- One or more RTSP cameras you can reach on your LAN

Quick GPU sanity check before you start:
```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```
If the second command prints your GPU, Docker can use it. If not, fix the NVIDIA Container Toolkit first.

## Setup

```bash
# 1. Clone
git clone <this-repo> home_security
cd home_security

# 2. Create your config from the template
cp .env.example .env
nano .env          # fill in camera password, camera IPs, host IP, storage path

# 3. (only if your GPU isn't index 0) set FRIGATE_GPU_ID in .env — see Hardware

# 4. Deploy (idempotent — safe to re-run)
make setup

# 5. Check status
make status
```

`make setup` checks prerequisites, mounts storage, pulls images, and starts `mqtt` + `frigate`. On the
first run Frigate downloads the detection + face models, so give it a couple of minutes before it
reports healthy.

Then open the Frigate UI at **http://<your-host-ip>:5000**.

> **Heads up:** `make setup` currently assumes a NAS/NFS target (it reads `SYNOLOGY_IP` /
> `SYNOLOGY_NFS_EXPORT` and mounts it). If you're storing recordings on a **local disk**, point
> `NFS_FRIGATE_PATH` at a local directory and skip/adapt the NFS step — see [Storage](#storage--retention).

## Cameras

Cameras are defined in `frigate/config/config.yml`. The repo ships with two Reolink cameras
(`front_door` doorbell + `backyard_floodlight`) wired to `.env` variables so no IPs or passwords live
in the config itself:

```yaml
- rtsp://admin:{FRIGATE_RTSP_PASSWORD}@{FRIGATE_DOORBELL_IP}:554/h264Preview_01_main
```

Each camera uses two streams: a low-res **sub** stream for detection (cheap on CPU/GPU) and the full-res
**main** stream for recording. That's the standard Frigate dual-stream pattern.

**Reolink stream paths:**
- Main (record): `/h264Preview_01_main`
- Sub (detect): `/h264Preview_01_sub`
- ⚠️ **Reolink doorbell quirk:** its sub stream is `/Preview_01_sub` (no `h264` prefix). If your
  doorbell's detect stream won't connect, that's almost always why.

**Test a camera before adding it:**
```bash
make test-camera IP=192.168.1.50 PASS=your_camera_password
```

**To add a camera:** add its IP to `.env`, copy one of the camera blocks in `config.yml`, point it at the
new streams, and `make restart-frigate`. You can also draw detection zones in the Frigate UI
(Settings → Mask & Zone Editor).

## Face recognition

Face recognition is built into Frigate and enabled in `config.yml` (`face_recognition: { enabled: true,
model_size: large }`). It runs on person detections, on the GPU.

To use it: open the Frigate UI → **Settings → Face Library**, and enroll known faces (upload photos or
assign faces from detection events). Once enrolled, events are tagged with the person's name, and you can
alert differently on known vs. unknown faces.

## Daily operations

```bash
make status          # service status + endpoints
make logs            # tail all logs
make logs-frigate    # tail one service
make health          # run the health check
make gpu             # watch GPU utilization
make restart         # restart the stack
make update          # pull latest images and redeploy
```

Run `make help` to see everything.

Endpoints:

| Service | URL | Purpose |
|---------|-----|---------|
| Frigate | http://<host-ip>:5000 | NVR, live view, config, face library |
| MQTT    | mqtt://<host-ip>:1883 | event bus (Home Assistant, etc.) |

## Storage & retention

Recordings and clips are stored under `NFS_FRIGATE_PATH` (default `/mnt/synology/frigate`). The default
is a Synology NAS exported over NFS, but it can be any path — set it to a local directory if you don't
have a NAS.

Retention (edit in `config.yml`):
- **14 days** of continuous (motion) recordings
- **60 days** of event clips (alerts + detections) and snapshots

For reference, two cameras at these settings use roughly ~1 TB.

## Optional services

Two extra services are defined in `docker-compose.yml` behind a `full` profile, so they **don't start**
normally. They're experimental and not required:

- **Whisper** — speech-to-text.
- **License plate recognition (PlateRecognizer)** — ALPR via the PlateRecognizer container. Needs a
  (free-tier) license key in `.env`. Note: this predates Frigate's own native LPR, which is now the
  simpler path if you want plates — so treat this container as legacy.

Start them with `docker compose --profile full up -d` if you want to experiment. See
[ROADMAP.md](ROADMAP.md) for where these are headed.

## Troubleshooting

**Frigate won't start / unhealthy**
```bash
docker logs frigate
# Common causes:
#  - GPU not visible to Docker  -> re-check the nvidia-smi test under Prerequisites
#  - wrong GPU id (single-GPU)   -> see the single-GPU note above
#  - bad RTSP creds/IP           -> verify values in .env
```

**Camera not connecting**
```bash
make test-camera IP=<camera-ip> PASS=<password>
ping <camera-ip>
nc -zv <camera-ip> 554          # RTSP port open?
# Reolink doorbell? remember the sub stream is /Preview_01_sub (no h264 prefix)
```

**NFS / storage mount issues**
```bash
mountpoint /mnt/synology/frigate
sudo mount /mnt/synology/frigate
# On the NAS: NFS service enabled, the share exported to your host's IP,
# and write permission for the host (Squash set to "No mapping" is simplest).
```

**GPU memory / utilization**
```bash
nvidia-smi
# Frigate typically uses ~1–2 GB for two cameras. If a GPU is unexpectedly full,
# something else is using it — Frigate isn't the culprit at that scale.
```

## Security notes

- Nothing here is meant to be exposed to the internet. Keep the stack on your LAN and reach it remotely
  via a VPN (e.g. [Tailscale](https://tailscale.com)) rather than port-forwarding.
- Camera credentials live only in `.env`, which is gitignored. Never commit `.env`.
- **Change the Frigate admin password** after first login (Settings → Users). The auto-generated one is
  fine to start, but set your own.
- MQTT runs anonymous by default for simplicity. If your network isn't fully trusted, enable a password
  file — see the commented instructions in `mosquitto/config/mosquitto.conf`.

## Repository layout

```
home_security/
├── docker-compose.yml      # the whole stack (mqtt + frigate; optional services behind `full`)
├── .env.example            # copy to .env and fill in
├── Makefile                # make setup / status / logs / health / ...
├── README.md               # this file
├── QUICK_START.md          # condensed getting-started
├── ROADMAP.md              # planned / unbuilt features (LPR, Whisper, Home Assistant)
├── frigate/
│   └── config/
│       └── config.yml      # cameras, detection, face recognition, recording
├── mosquitto/
│   └── config/
│       └── mosquitto.conf  # MQTT broker config
└── scripts/
    ├── setup.sh            # idempotent deploy
    ├── health-check.sh     # monitoring (cron-friendly)
    ├── test-camera.sh      # RTSP connectivity test
    └── test-*.sh           # pre/post-deploy checks
```

## License

MIT — see [LICENSE](LICENSE).
