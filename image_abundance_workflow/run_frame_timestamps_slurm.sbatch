#!/usr/bin/env bash
#SBATCH --job-name=frame_timestamps
#SBATCH --cpus-per-task=12
#SBATCH --mem=64GB
#SBATCH --time=24:00:00
#SBATCH --partition=compute
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
##SBATCH --mail-type=ALL
##SBATCH --mail-user=your.email@example.edu

###############################################################################
# Build the media/frame timestamp CSV needed by abundance.
#
# This runner installs the Stingray image dependency set because
# `stingray images frame-timestamp` uses OpenCV to inspect media files.
###############################################################################

set -euo pipefail

###############################################################################
# Job configuration
###############################################################################

PYTHON_BIN="${PYTHON_BIN:-python3}"
STINGRAYTOOLS_GIT_REF="${STINGRAYTOOLS_GIT_REF:-main}"
INSTALL_ENV="0"  # 1 = reinstall environment from Git; 0 = create if missing, otherwise reuse

WORK_DIR="/proj/nes-lter/Stingray/data"
VENV_DIR="/proj/nes-lter/Stingray/data/envs/stingraytools-frame-timestamps"
CRUISE="CRUISE_ID"
MEDIA_DIR="CHANGEME_MEDIA_DIR"
OUT_DIR="/proj/nes-lter/Stingray/data/media_list/CAMERA_STREAM"
FPS="FPS_VALUE"
DETAILS="0"  # 1 = full per-frame timestamp extraction; 0 = fast frame count

# Optional filters. Leave FILE_LIMIT empty for full production runs.
FILE_LIMIT=""
SUFFIXES=(".avi" ".mp4" ".png" ".tiff")

###############################################################################
# End configuration
###############################################################################

require_value() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == CHANGEME* || "$value" == *"/CHANGEME"* ]]; then
        echo "[ERROR] Configure $name before running this workflow." >&2
        exit 2
    fi
}

require_dir() {
    local name="$1"
    local value="$2"
    require_value "$name" "$value"
    if [[ ! -d "$value" ]]; then
        echo "[ERROR] $name does not exist: $value" >&2
        exit 2
    fi
}

echo "[INFO] Run inputs:"
echo "  PYTHON_BIN=$PYTHON_BIN"
echo "  STINGRAYTOOLS_GIT_REF=$STINGRAYTOOLS_GIT_REF"
echo "  INSTALL_ENV=$INSTALL_ENV"
echo "  WORK_DIR=$WORK_DIR"
echo "  VENV_DIR=$VENV_DIR"
echo "  CRUISE=$CRUISE"
echo "  MEDIA_DIR=$MEDIA_DIR"
echo "  OUT_DIR=$OUT_DIR"
echo "  FPS=$FPS"
echo "  DETAILS=$DETAILS"
echo "  FILE_LIMIT=$FILE_LIMIT"
echo "  SUFFIXES=${SUFFIXES[*]}"

require_dir "WORK_DIR" "$WORK_DIR"
require_dir "MEDIA_DIR" "$MEDIA_DIR"
require_value "OUT_DIR" "$OUT_DIR"
require_value "CRUISE" "$CRUISE"
require_value "FPS" "$FPS"

JOB_TMP="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}"
MAX_WORKERS="${SLURM_CPUS_PER_TASK:-$(nproc)}"

mkdir -p slogs

echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $VENV_DIR"

if [[ ! -d "$VENV_DIR" || "$INSTALL_ENV" == "1" ]]; then
    echo "[INFO] Installing stingraytools[images] from Git ref: $STINGRAYTOOLS_GIT_REF"
    mkdir -p "$(dirname "$VENV_DIR")"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    python -m pip install --upgrade pip setuptools wheel
    python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git@$STINGRAYTOOLS_GIT_REF"
else
    echo "[INFO] Reusing existing environment: $VENV_DIR"
    source "$VENV_DIR/bin/activate"
fi

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

FRAME_ARGS=(
    --work-dir "$WORK_DIR"
    --cruise "$CRUISE"
    --media-dir "$MEDIA_DIR"
    --out-dir "$OUT_DIR"
    --fps "$FPS"
    --max-workers "$MAX_WORKERS"
    --suffix "${SUFFIXES[@]}"
    --no-file-log
)

if [[ -n "$FILE_LIMIT" ]]; then
    FRAME_ARGS+=(--file-limit "$FILE_LIMIT")
fi

if [[ "$DETAILS" == "1" ]]; then
    FRAME_ARGS+=(--details)
fi

stingray images frame-timestamp "${FRAME_ARGS[@]}"

echo "[DONE] Frame timestamp CSV written under: $OUT_DIR"
