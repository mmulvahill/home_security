#!/bin/bash
# Export a YOLOv9 detection model to ONNX for Frigate's GPU (onnx) detector.
#
# Frigate's stable-tensorrt image runs ONNX models on the NVIDIA GPU via the
# onnxruntime CUDA execution provider, but does NOT ship a YOLOv9 model — it
# must be generated. This builds a throwaway Docker image that clones YOLOv9,
# downloads the pretrained weights, and exports a simplified .onnx, then drops
# it into frigate/config/model_cache/ (gitignored build artifact).
#
# Idempotent: skips the export if the target .onnx already exists (use --force
# to regenerate). Referenced by frigate/config/config.yml (model.path).
#
# Usage:
#   scripts/export-yolo.sh                 # defaults: size=s, imgsz=320
#   MODEL_SIZE=m IMG_SIZE=640 scripts/export-yolo.sh
#   scripts/export-yolo.sh --force

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

# Model size: t|s|m|c|e  (s = good accuracy, trivial load on a 3090)
MODEL_SIZE="${MODEL_SIZE:-s}"
IMG_SIZE="${IMG_SIZE:-320}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

MODEL_CACHE="${PROJECT_DIR}/frigate/config/model_cache"
OUT_NAME="yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx"
OUT_PATH="${MODEL_CACHE}/${OUT_NAME}"

log_step "Exporting YOLOv9-${MODEL_SIZE} at ${IMG_SIZE}x${IMG_SIZE} -> ${OUT_NAME}"

if [[ -f "$OUT_PATH" && $FORCE -eq 0 ]]; then
    log_info "Model already exists: ${OUT_PATH} (use --force to regenerate). Skipping."
    exit 0
fi

CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT

# Dockerfile per Frigate docs (docs.frigate.video/configuration/object_detectors)
cat > "${CTX}/Dockerfile" <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y cmake libgl1 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /bin/
WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier==0.4.* onnxscript
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt
# torch.load() with weights_only=False unpickles arbitrary Python objects (RCE
# risk for untrusted files). Required here: YOLOv9 checkpoints are full pickled
# model objects, not pure-tensor state_dicts, so weights_only=True fails to load
# them. Safe in this context — the .pt is the official WongKinYiu/yolov9 v0.1
# release, fetched over HTTPS, loaded only inside this throwaway build container.
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
EOF

log_info "Building export image (clones YOLOv9, pulls torch + weights — a few minutes)..."
docker build "$CTX" \
    --build-arg "MODEL_SIZE=${MODEL_SIZE}" \
    --build-arg "IMG_SIZE=${IMG_SIZE}" \
    --output "$CTX" \
    -f "${CTX}/Dockerfile"

if [[ ! -f "${CTX}/${OUT_NAME}" ]]; then
    log_error "Export produced no ${OUT_NAME}. Check the build output above."
    exit 1
fi

# model_cache is root-owned (created by the Frigate container). Write through
# the running container if present, else fall back to a direct copy.
if docker ps --format '{{.Names}}' | grep -qx frigate; then
    docker cp "${CTX}/${OUT_NAME}" "frigate:/config/model_cache/${OUT_NAME}"
    log_info "Installed via 'docker cp' into the frigate container (bind-mounted to host)."
else
    mkdir -p "$MODEL_CACHE"
    cp "${CTX}/${OUT_NAME}" "$OUT_PATH"
    log_info "Copied to ${OUT_PATH}."
fi

log_info "Done. Ensure frigate/config/config.yml model.path points at:"
log_info "  /config/model_cache/${OUT_NAME}"
log_warn "Restart Frigate to load it: docker restart frigate (or 'make restart-frigate')"
