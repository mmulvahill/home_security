# Roadmap

Features that are planned or partially wired up but **not** active in the default stack. The core
system (Frigate NVR, GPU object detection, native face recognition, audio event detection, MQTT) is
done and documented in [README.md](README.md) — this file is just what's *next*.

**Status:** 🟡 scaffolded (defined in the repo, off by default) · 💡 idea (not built yet)

---

## 🟡 License plate recognition (ALPR)

A `platerecognizer` container is already defined in `docker-compose.yml` behind the `full` profile, so
it doesn't start normally. It uses [PlateRecognizer](https://platerecognizer.com)'s local ALPR image and
needs a license key in `.env` (`PLATE_RECOGNIZER_KEY`) — free tier is 2,500 lookups/month via their
cloud; a one-time purchase (~$50–100) unlocks fully-local inference.

It was intended for a dedicated LPR/zoom camera that hasn't been installed yet, so it's never been
switched on.

**Preferred path now:** Frigate 0.16+ ships *native* license plate recognition. When an LPR-capable
camera gets added, enabling Frigate's built-in LPR is simpler than running the separate PlateRecognizer
container — and it would likely replace that container entirely, the same way face recognition moved
in-house. Revisit this choice before building anything.

## 🟡 Speech-to-text on audio events (Whisper)

A `whisper` container (openai-whisper-asr-webservice, GPU, `ASR_MODEL=medium`, faster_whisper engine) is
defined behind the `full` profile. Not active.

Idea: pull audio from doorbell/camera events, transcribe it, and alert on keywords.

Note: Frigate **already** does native audio *event* detection (bark, glass breaking, scream, alarm,
speech, yell) — that's implemented and on. Whisper would add actual transcription on top of that.

## 💡 Home Assistant integration

Frigate publishes every event to MQTT already, so the plumbing exists — nothing is wired into Home
Assistant yet.

Next steps: install the Frigate integration in HA (via HACS), point it at the MQTT broker and the
Frigate URL, then build automations — e.g. notify on a person at the door, alert differently on an
unknown face vs. a known one, snapshot to a phone.

## 💡 Other ideas

- Package / delivery detection
- Presence-aware arming & disarming
- Additional cameras (garage, side yard)

---

To experiment with the scaffolded (🟡) services:

```bash
docker compose --profile full up -d
```
