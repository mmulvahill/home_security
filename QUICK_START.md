# Quick Start

The condensed version. For the full story (hardware, architecture, troubleshooting), see
[README.md](README.md).

## 1. Prerequisites (5 min)

- Linux host with Docker + Docker Compose v2
- NVIDIA GPU visible to Docker — verify:
  ```bash
  docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
  ```
- `nfs-common` if you're storing recordings on a NAS
- An RTSP camera on your LAN (Reolink works out of the box)

## 2. Configure (2 min)

```bash
git clone <this-repo> home_security
cd home_security
cp .env.example .env
nano .env      # camera password, camera IP(s), host IP, storage path
```

**GPU not at index 0?** Set `FRIGATE_GPU_ID` in `.env`. The default is `0`, which is correct for a
single-GPU machine, so most people don't need to touch it. See the README's
[Hardware](README.md#hardware) section.

## 3. Test your camera (2 min)

```bash
make test-camera IP=<camera-ip> PASS=<camera-password>
```
Expect all checks to pass and a test frame to be captured.

> Reolink doorbell? Its detect (sub) stream is `/Preview_01_sub` — no `h264` prefix. Everything else
> Reolink uses `/h264Preview_01_sub`.

## 4. Deploy (first run: a few min)

```bash
make setup      # idempotent — safe to re-run
make status
```
First run downloads the detection + face models, so give Frigate a minute or two to go healthy.

## 5. Open the UI

```
http://<your-host-ip>:5000
```
You should see your camera's live stream within ~30 seconds. Click **Debug** on a camera to watch
detection run.

## 6. Enroll faces (optional)

In the Frigate UI: **Settings → Face Library**. Upload photos or assign faces from detection events.
After enrolling, events get tagged with the person's name.

## Common commands

```bash
make status          # what's running + endpoints
make logs-frigate    # tail Frigate logs
make health          # health check
make restart-frigate # restart just Frigate
make update          # pull latest images + redeploy
make help            # everything
```

## Something broken?

```bash
docker logs frigate            # first place to look
make test-camera IP=.. PASS=.. # camera reachable?
nvidia-smi                     # GPU visible?
```

Most first-run failures are: GPU id wrong (single-GPU setups), bad camera credentials in `.env`, or the
Reolink doorbell sub-stream path. See [README.md](README.md#troubleshooting) for the full list.
