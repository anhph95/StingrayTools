#!/usr/bin/env bash
#SBATCH --job-name=yolo_abundance
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

###############################################################################
# Run YOLO label merging and image abundance in one Slurm job.
#
# This runner creates a Python environment, installs the Stingray abundance
# dependency set from Git, then calls the local YOLO merge helper followed by
# the installed Stingray abundance command.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MERGE_SCRIPT="${MERGE_SCRIPT:-$SCRIPT_DIR/merge_yolo_labels.sh}"

###############################################################################
# Job configuration
#
# Edit this block for each run. The commented values below are templates from
# the current EN706 workflow; keep all active values explicit in this file.
###############################################################################

PYTHON_BIN="${PYTHON_BIN:-python3}"
STINGRAYTOOLS_GIT_REF="${STINGRAYTOOLS_GIT_REF:-main}"

WORK_DIR="CHANGEME_WORKSPACE"
YOLO_CSV="CHANGEME_OUTPUT_DIR/en706_yolo_concatenated_results.csv"
DATA_YAML="CHANGEME_TRAINING_DATA/data.yaml"
SENSOR_CSV="CHANGEME_WORKSPACE/dash_data/data/stingray/EN706.csv"
MEDIA_CSV="CHANGEME_WORKSPACE/media_list/ISIIS1/20230807_EN706_fast.csv"
ABUNDANCE_OUT_CSV="CHANGEME_OUTPUT_DIR/en706_shadowgraph_abundance.csv"

SCORE_THRESH="0.7"
BIN_WIDTH="5"
IMAGE_WIDTH="2330"
IMAGE_HEIGHT="1750"
UM_PER_PIXEL="40"
VOLUME_PER_FRAME="0.00225"
ADD_CI="0"

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

require_dir "WORK_DIR" "$WORK_DIR"
require_file "DATA_YAML" "$DATA_YAML"
require_file "SENSOR_CSV" "$SENSOR_CSV"
require_file "MEDIA_CSV" "$MEDIA_CSV"
require_file "MERGE_SCRIPT" "$MERGE_SCRIPT"

if [[ ${#LABEL_DIRS[@]} -eq 0 ]]; then
    echo "[ERROR] Add at least one label directory to LABEL_DIRS." >&2
    exit 2
fi

for label_dir in "${LABEL_DIRS[@]}"; do
    require_dir "LABEL_DIR" "$label_dir"
done

JOB_TMP="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}"
VENV_DIR="${VENV_DIR:-$JOB_TMP/yolo_abundance_${SLURM_JOB_ID:-$$}}"
JOBS="${SLURM_CPUS_PER_TASK:-$(nproc)}"

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Merge script: $MERGE_SCRIPT"
echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $VENV_DIR"
echo "[INFO] Installing stingraytools[abundance] from Git ref: $STINGRAYTOOLS_GIT_REF"

"$PYTHON_BIN" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install "stingraytools[abundance] @ git+https://github.com/anhph95/StingrayTools.git@$STINGRAYTOOLS_GIT_REF"

echo "[INFO] Step 1/2: merging YOLO labels."
bash "$MERGE_SCRIPT" \
    --output-csv "$YOLO_CSV" \
    --jobs "$JOBS" \
    "${LABEL_DIRS[@]}"

echo "[INFO] Step 2/2: computing abundance."
ABUNDANCE_ARGS=(
    --yolo-csv "$YOLO_CSV" \
    --data-yaml "$DATA_YAML" \
    --sensor-csv "$SENSOR_CSV" \
    --media-csv "$MEDIA_CSV" \
    --out-csv "$ABUNDANCE_OUT_CSV" \
    --score-thresh "$SCORE_THRESH" \
    --bin-width "$BIN_WIDTH" \
    --image-width "$IMAGE_WIDTH" \
    --image-height "$IMAGE_HEIGHT" \
    --um-per-pixel "$UM_PER_PIXEL" \
    --volume-per-frame "$VOLUME_PER_FRAME"
)

if [[ "$ADD_CI" == "1" ]]; then
    ABUNDANCE_ARGS+=(--add-ci)
fi

stingray images abundance "${ABUNDANCE_ARGS[@]}" --no-file-log

echo "[DONE] YOLO abundance output: $ABUNDANCE_OUT_CSV"
