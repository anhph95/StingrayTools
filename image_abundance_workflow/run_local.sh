#!/usr/bin/env bash
###############################################################################
# Run post-inference image abundance processing on a local machine or HPC node.
###############################################################################

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

###############################################################################
# Run configuration
###############################################################################

CRUISE="CRUISE_ID"

# Some hosts mount this shared storage tree under /srv/vast instead of /mnt/vast.
WORK_DIR="/mnt/vast/nes-lter/Stingray/data"
CLASS_YAML="CHANGEME_CLASS_NAMES_YAML"
SENSOR_CSV="/mnt/vast/nes-lter/Stingray/data/dashboard_data/data/SENSOR_DATASET/DATE_CRUISE.csv"
MEDIA_CSV="/mnt/vast/nes-lter/Stingray/data/media_list/CAMERA_STREAM/DATE_CRUISE_fast.csv"
DETECTIONS_CSV="/mnt/vast/nes-lter/Stingray/data/image_abundance_work/DATE_CRUISE_detection_labels.csv"
CLASS_MAP_CSV="/mnt/vast/nes-lter/Stingray/data/image_abundance_work/DATE_CRUISE_class_map.csv"
ABUNDANCE_OUT_CSV="/mnt/vast/nes-lter/Stingray/data/dashboard_data/data/shadowgraph/DATE_CRUISE.csv"

MERGE_LABELS="1"     # 1 = merge LABEL_DIRS into DETECTIONS_CSV; 0 = use existing DETECTIONS_CSV
BUILD_MEDIA_CSV="0"  # 1 = build media CSV before abundance; 0 = use existing MEDIA_CSV
MEDIA_DIR="CHANGEME_MEDIA_DIR"
MEDIA_OUT_DIR="/mnt/vast/nes-lter/Stingray/data/media_list/CAMERA_STREAM"
FPS="FPS_VALUE"
DETAILS="0"          # 1 = full per-frame timestamp extraction; 0 = fast frame count
FILE_LIMIT=""
SUFFIXES=(".avi" ".mp4" ".png" ".tiff")

SCORE_THRESH="0.7"
BIN_WIDTH="5"
VOLUME_PER_FRAME="0.00225"
ADD_CI="0"           # 1 = add Poisson confidence intervals; 0 = abundance only

LABEL_DIRS=(
    # "/path/to/ml-run/worker0/labels"
    # "/path/to/ml-run/worker1/labels"
    # "/path/to/ml-run/worker2/labels"
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
echo "  CRUISE=$CRUISE"
echo "  WORK_DIR=$WORK_DIR"
echo "  CLASS_YAML=$CLASS_YAML"
echo "  SENSOR_CSV=$SENSOR_CSV"
echo "  MEDIA_CSV=$MEDIA_CSV"
echo "  DETECTIONS_CSV=$DETECTIONS_CSV"
echo "  CLASS_MAP_CSV=$CLASS_MAP_CSV"
echo "  ABUNDANCE_OUT_CSV=$ABUNDANCE_OUT_CSV"
echo "  MERGE_LABELS=$MERGE_LABELS"
echo "  BUILD_MEDIA_CSV=$BUILD_MEDIA_CSV"
echo "  MEDIA_DIR=$MEDIA_DIR"
echo "  MEDIA_OUT_DIR=$MEDIA_OUT_DIR"
echo "  FPS=$FPS"
echo "  DETAILS=$DETAILS"
echo "  FILE_LIMIT=$FILE_LIMIT"
echo "  SUFFIXES=${SUFFIXES[*]}"
echo "  SCORE_THRESH=$SCORE_THRESH"
echo "  BIN_WIDTH=$BIN_WIDTH"
echo "  VOLUME_PER_FRAME=$VOLUME_PER_FRAME"
echo "  ADD_CI=$ADD_CI"
echo "  LABEL_DIRS=${LABEL_DIRS[*]}"

require_dir "WORK_DIR" "$WORK_DIR"
require_file "CLASS_YAML" "$CLASS_YAML"
require_file "SENSOR_CSV" "$SENSOR_CSV"
require_value "MEDIA_CSV" "$MEDIA_CSV"
require_value "DETECTIONS_CSV" "$DETECTIONS_CSV"
require_value "CLASS_MAP_CSV" "$CLASS_MAP_CSV"
require_value "ABUNDANCE_OUT_CSV" "$ABUNDANCE_OUT_CSV"

if [[ "$BUILD_MEDIA_CSV" == "1" ]]; then
    require_dir "MEDIA_DIR" "$MEDIA_DIR"
    require_value "MEDIA_OUT_DIR" "$MEDIA_OUT_DIR"
    require_value "CRUISE" "$CRUISE"
    require_value "FPS" "$FPS"
else
    require_file "MEDIA_CSV" "$MEDIA_CSV"
fi

if [[ "$MERGE_LABELS" == "1" ]]; then
    if [[ ${#LABEL_DIRS[@]} -eq 0 ]]; then
        echo "[ERROR] Add at least one label directory to LABEL_DIRS." >&2
        exit 2
    fi

    for label_dir in "${LABEL_DIRS[@]}"; do
        require_dir "LABEL_DIR" "$label_dir"
    done
else
    require_file "DETECTIONS_CSV" "$DETECTIONS_CSV"
fi

JOB_TMP="${TMPDIR:-/tmp}"
JOBS="${JOBS:-$(nproc)}"

echo "[INFO] Workflow directory: $SCRIPT_DIR"
echo "[INFO] Temporary directory: $JOB_TMP"
echo "[INFO] Virtual environment: $SCRIPT_DIR/.venv/stingraytools-image-abundance"

source "$SCRIPT_DIR/.venv/stingraytools-image-abundance/bin/activate"

echo "[INFO] Python executable: $(command -v python)"
python --version
python -m pip show stingraytools

mkdir -p "$(dirname "$DETECTIONS_CSV")" "$(dirname "$CLASS_MAP_CSV")" "$(dirname "$ABUNDANCE_OUT_CSV")"

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

if [[ "$MERGE_LABELS" == "1" ]]; then
    echo "[INFO] Merging detection labels."
    bash "$SCRIPT_DIR/merge_detection_labels.sh" \
        --output-csv "$DETECTIONS_CSV" \
        --class-map-csv "$CLASS_MAP_CSV" \
        --class-yaml "$CLASS_YAML" \
        --python-bin "$(command -v python)" \
        --jobs "$JOBS" \
        "${LABEL_DIRS[@]}"
elif [[ ! -f "$CLASS_MAP_CSV" ]]; then
    echo "[INFO] Class map CSV not found; creating it from CLASS_YAML."
    python - "$CLASS_YAML" "$CLASS_MAP_CSV" <<'PY'
import csv
import re
import sys
from pathlib import Path


def clean(value):
    value = value.strip()
    if value.startswith(("'", '"')) and value.endswith(("'", '"')):
        value = value[1:-1]
    return value


path = Path(sys.argv[1])
class_map_csv = Path(sys.argv[2])
names_started = False
names_by_id = {}
names_list = []

for raw_line in path.read_text(encoding="utf-8").splitlines():
    line_without_comment = raw_line.split("#", 1)[0].rstrip()
    stripped = line_without_comment.strip()
    if not stripped:
        continue

    if not names_started:
        if stripped == "names:":
            names_started = True
        continue

    if not raw_line.startswith((" ", "\t", "-")) and stripped != "names:":
        break

    list_match = re.match(r"^-\s*(.+)$", stripped)
    if list_match:
        names_list.append(clean(list_match.group(1)))
        continue

    dict_match = re.match(r"^(\d+)\s*:\s*(.+)$", stripped)
    if dict_match:
        names_by_id[int(dict_match.group(1))] = clean(dict_match.group(2))

if names_by_id:
    items = sorted(names_by_id.items())
elif names_list:
    items = list(enumerate(names_list))
else:
    raise SystemExit(f"{path} does not contain a supported names section.")

with class_map_csv.open("w", newline="", encoding="utf-8") as out_file:
    writer = csv.writer(out_file)
    writer.writerow(["class_id", "class", "source_file", "source_format"])
    for class_id, name in items:
        writer.writerow([class_id, name, str(path), "class_names_yaml"])
PY
else
    echo "[INFO] Reusing existing class map CSV: $CLASS_MAP_CSV"
fi

echo "[INFO] Computing abundance."
ABUNDANCE_ARGS=(
    --detections-csv "$DETECTIONS_CSV"
    --class-map-csv "$CLASS_MAP_CSV"
    --sensor-csv "$SENSOR_CSV"
    --media-csv "$MEDIA_CSV"
    --out-csv "$ABUNDANCE_OUT_CSV"
    --score-thresh "$SCORE_THRESH"
    --bin-width "$BIN_WIDTH"
    --volume-per-frame "$VOLUME_PER_FRAME"
)

if [[ "$ADD_CI" == "1" ]]; then
    ABUNDANCE_ARGS+=(--add-ci)
fi

stingray images abundance "${ABUNDANCE_ARGS[@]}" --no-file-log

echo "[DONE] Image abundance output: $ABUNDANCE_OUT_CSV"
