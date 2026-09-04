#!/usr/bin/env bash
#SBATCH --job-name=yolo_abundance
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=compute
#SBATCH --output=slogs/%A.%x.out
#SBATCH --error=slogs/%A.%x.err
##SBATCH --mail-type=ALL
##SBATCH --mail-user=your.email@example.edu

###############################################################################
# Run post-inference YOLO abundance processing in one Slurm job.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MERGE_SCRIPT="${MERGE_SCRIPT:-$SCRIPT_DIR/merge_yolo_labels.sh}"

###############################################################################
# Job configuration
#
# Edit this block for each run.
###############################################################################

PYTHON_BIN="${PYTHON_BIN:-python3}"
STINGRAYTOOLS_GIT_REF="${STINGRAYTOOLS_GIT_REF:-main}"
INSTALL_ENV="0"  # 1 = reinstall environment from Git; 0 = create if missing, otherwise reuse

CRUISE="EN706"

# Some hosts mount this shared storage tree under /srv/vast instead of /proj.
WORK_DIR="/proj/nes-lter/Stingray/data"
VENV_DIR="/proj/nes-lter/Stingray/data/envs/stingraytools-yolo-abundance"
DATA_YAML="CHANGEME_TRAINING_DATA/data.yaml"
SENSOR_CSV="/proj/nes-lter/Stingray/data/dashboard_data/data/stingray_NESLTER/YYYYMMDD_EN706.csv"
MEDIA_CSV="/proj/nes-lter/Stingray/data/media_list/ISIIS1/YYYYMMDD_EN706_fast.csv"
YOLO_CSV="/proj/nes-lter/Stingray/data/yolo_abundance_work/YYYYMMDD_EN706_yolo_labels.csv"
ABUNDANCE_OUT_CSV="/proj/nes-lter/Stingray/data/dashboard_data/data/shadowgraph/YYYYMMDD_EN706.csv"

BUILD_MEDIA_CSV="0"  # 1 = build media CSV before abundance; 0 = use existing MEDIA_CSV
MEDIA_DIR="CHANGEME_MEDIA_DIR"
MEDIA_OUT_DIR="/proj/nes-lter/Stingray/data/media_list/ISIIS1"
FPS="15"
DETAILS="0"          # 1 = full per-frame timestamp extraction; 0 = fast frame count
FILE_LIMIT=""
SUFFIXES=(".avi" ".mp4" ".png" ".tiff")

SCORE_THRESH="0.7"
BIN_WIDTH="5"
IMAGE_WIDTH="2330"
IMAGE_HEIGHT="1750"
UM_PER_PIXEL="40"
VOLUME_PER_FRAME="0.00225"
ADD_CI="0"           # 1 = add Poisson confidence intervals; 0 = abundance only

LABEL_DIRS=(
    # "/proj/omics/sosik/yolozone/yolo-run-1/gpu0/labels"
    # "/proj/omics/sosik/yolozone/yolo-run-1/gpu1/labels"
    # "/proj/omics/sosik/yolozone/yolo-run-1/gpu2/labels"
)

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

require_file() {
    local name="$1"
    local value="$2"
    require_value "$name" "$value"
    if [[ ! -f "$value" ]]; then
        echo "[ERROR] $name does not exist: $value" >&2
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
echo "  CRUISE=$CRUISE"
echo "  WORK_DIR=$WORK_DIR"
echo "  VENV_DIR=$VENV_DIR"
echo "  DATA_YAML=$DATA_YAML"
echo "  SENSOR_CSV=$SENSOR_CSV"
echo "  MEDIA_CSV=$MEDIA_CSV"
echo "  YOLO_CSV=$YOLO_CSV"
echo "  ABUNDANCE_OUT_CSV=$ABUNDANCE_OUT_CSV"
echo "  BUILD_MEDIA_CSV=$BUILD_MEDIA_CSV"
echo "  MEDIA_DIR=$MEDIA_DIR"
echo "  MEDIA_OUT_DIR=$MEDIA_OUT_DIR"
echo "  FPS=$FPS"
echo "  DETAILS=$DETAILS"
echo "  FILE_LIMIT=$FILE_LIMIT"
echo "  SUFFIXES=${SUFFIXES[*]}"
echo "  SCORE_THRESH=$SCORE_THRESH"
echo "  BIN_WIDTH=$BIN_WIDTH"
echo "  IMAGE_WIDTH=$IMAGE_WIDTH"
echo "  IMAGE_HEIGHT=$IMAGE_HEIGHT"
echo "  UM_PER_PIXEL=$UM_PER_PIXEL"
echo "  VOLUME_PER_FRAME=$VOLUME_PER_FRAME"
echo "  ADD_CI=$ADD_CI"
echo "  LABEL_DIRS=${LABEL_DIRS[*]}"

require_dir "WORK_DIR" "$WORK_DIR"
require_file "DATA_YAML" "$DATA_YAML"
require_file "SENSOR_CSV" "$SENSOR_CSV"
require_file "MERGE_SCRIPT" "$MERGE_SCRIPT"
require_value "MEDIA_CSV" "$MEDIA_CSV"
require_value "YOLO_CSV" "$YOLO_CSV"
require_value "ABUNDANCE_OUT_CSV" "$ABUNDANCE_OUT_CSV"

if [[ "$BUILD_MEDIA_CSV" == "1" ]]; then
    require_dir "MEDIA_DIR" "$MEDIA_DIR"
    require_value "MEDIA_OUT_DIR" "$MEDIA_OUT_DIR"
    require_value "CRUISE" "$CRUISE"
    require_value "FPS" "$FPS"
else
    require_file "MEDIA_CSV" "$MEDIA_CSV"
fi

if [[ ${#LABEL_DIRS[@]} -eq 0 ]]; then
    echo "[ERROR] Add at least one label directory to LABEL_DIRS." >&2
    exit 2
fi

for label_dir in "${LABEL_DIRS[@]}"; do
    require_dir "LABEL_DIR" "$label_dir"
done

JOB_TMP="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}"
JOBS="${SLURM_CPUS_PER_TASK:-$(nproc)}"

mkdir -p slogs

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Merge script: $MERGE_SCRIPT"
echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $VENV_DIR"

if [[ ! -d "$VENV_DIR" || "$INSTALL_ENV" == "1" ]]; then
    echo "[INFO] Installing stingraytools[pipeline] from Git ref: $STINGRAYTOOLS_GIT_REF"
    mkdir -p "$(dirname "$VENV_DIR")"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    python -m pip install --upgrade pip setuptools wheel
    python -m pip install --upgrade "stingraytools[pipeline] @ git+https://github.com/anhph95/stingraytools.git@$STINGRAYTOOLS_GIT_REF"
else
    echo "[INFO] Reusing existing environment: $VENV_DIR"
    source "$VENV_DIR/bin/activate"
fi

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

mkdir -p "$(dirname "$YOLO_CSV")" "$(dirname "$ABUNDANCE_OUT_CSV")"

if [[ "$BUILD_MEDIA_CSV" == "1" ]]; then
    mkdir -p "$MEDIA_OUT_DIR"
    echo "[INFO] Building media CSV."
    FRAME_ARGS=(
        --work-dir "$WORK_DIR"
        --cruise "$CRUISE"
        --media-dir "$MEDIA_DIR"
        --out-dir "$MEDIA_OUT_DIR"
        --fps "$FPS"
        --max-workers "$JOBS"
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
fi

require_file "MEDIA_CSV" "$MEDIA_CSV"

echo "[INFO] Merging YOLO labels."
bash "$MERGE_SCRIPT" \
    --output-csv "$YOLO_CSV" \
    --jobs "$JOBS" \
    "${LABEL_DIRS[@]}"

echo "[INFO] Computing abundance."
ABUNDANCE_ARGS=(
    --yolo-csv "$YOLO_CSV"
    --data-yaml "$DATA_YAML"
    --sensor-csv "$SENSOR_CSV"
    --media-csv "$MEDIA_CSV"
    --out-csv "$ABUNDANCE_OUT_CSV"
    --score-thresh "$SCORE_THRESH"
    --bin-width "$BIN_WIDTH"
    --image-width "$IMAGE_WIDTH"
    --image-height "$IMAGE_HEIGHT"
    --um-per-pixel "$UM_PER_PIXEL"
    --volume-per-frame "$VOLUME_PER_FRAME"
)

if [[ "$ADD_CI" == "1" ]]; then
    ABUNDANCE_ARGS+=(--add-ci)
fi

stingray images abundance "${ABUNDANCE_ARGS[@]}" --no-file-log

echo "[DONE] YOLO abundance output: $ABUNDANCE_OUT_CSV"
