#!/usr/bin/env bash
###############################################################################
# Merge YOLO label files into one detection table.
#
# Each input label directory is scanned recursively for *.txt files. Every
# non-empty annotation row is written to the output with the source filename
# prepended, producing the space-separated table expected by
# `stingray images abundance`.
###############################################################################

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  merge_yolo_labels.sh --output-csv PATH [options] LABEL_DIR [LABEL_DIR ...]

Required:
  --output-csv PATH       Output detection table.

Options:
  --jobs N                Number of parallel workers. Defaults to CPU count - 1.
  --temp-dir DIR          Parent directory for temporary files.
                          Defaults to SLURM_TMPDIR, then TMPDIR, then /tmp.
  --archive-filelist      Save the sorted source file list beside the output.
                          This is the default.
  --no-archive-filelist   Do not save the source file list.
  -h, --help              Show this help message.

Example:
  merge_yolo_labels.sh \
    --output-csv /path/to/en706_yolo_concatenated_results.csv \
    --jobs 32 \
    /proj/omics/sosik/yolozone/yolo-run-1/gpu0/labels \
    /proj/omics/sosik/yolozone/yolo-run-1/gpu1/labels \
    /proj/omics/sosik/yolozone/yolo-run-1/gpu2/labels
EOF
}

OUTPUT_CSV=""
JOBS=""
TEMP_PARENT="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}"
ARCHIVE_FILELIST=1
INPUT_DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-csv)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --output-csv requires a path." >&2
                exit 2
            fi
            OUTPUT_CSV="$2"
            shift 2
            ;;
        --jobs)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --jobs requires a positive integer." >&2
                exit 2
            fi
            JOBS="$2"
            shift 2
            ;;
        --temp-dir)
            if [[ $# -lt 2 ]]; then
                echo "[ERROR] --temp-dir requires a directory." >&2
                exit 2
            fi
            TEMP_PARENT="$2"
            shift 2
            ;;
        --archive-filelist)
            ARCHIVE_FILELIST=1
            shift
            ;;
        --no-archive-filelist)
            ARCHIVE_FILELIST=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                INPUT_DIRS+=("$1")
                shift
            done
            ;;
        -*)
            echo "[ERROR] Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            INPUT_DIRS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$OUTPUT_CSV" ]]; then
    echo "[ERROR] Missing required --output-csv PATH." >&2
    usage >&2
    exit 2
fi

if [[ ${#INPUT_DIRS[@]} -eq 0 ]]; then
    echo "[ERROR] Provide at least one YOLO label directory." >&2
    usage >&2
    exit 2
fi

if [[ -n "$JOBS" && ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --jobs must be a positive integer." >&2
    exit 2
fi

OUTPUT_DIR=$(dirname "$OUTPUT_CSV")
mkdir -p "$OUTPUT_DIR"

if [[ ! -d "$TEMP_PARENT" ]]; then
    echo "[ERROR] Temporary parent directory does not exist: $TEMP_PARENT" >&2
    exit 2
fi

TEMP_DIR=$(mktemp -d "${TEMP_PARENT%/}/merge_yolo_labels.XXXXXX")
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

NUM_CORES=$(nproc)
if [[ -z "$JOBS" ]]; then
    JOBS=$((NUM_CORES > 1 ? NUM_CORES - 1 : 1))
fi

echo "[INFO] Detected $NUM_CORES CPU cores; using $JOBS parallel workers."
echo "[INFO] Temporary workspace: $TEMP_DIR"
echo "[INFO] Output CSV: $OUTPUT_CSV"

# Build a reproducible, sorted list of source label files.
FILELIST="$TEMP_DIR/all_files.txt"
> "$FILELIST"

for DIR in "${INPUT_DIRS[@]}"; do
    if [[ -d "$DIR" ]]; then
        echo "[INFO] Scanning directory: $DIR"
        find "$DIR" -type f -name "*.txt"
    else
        echo "[WARN] Directory not found; skipping: $DIR" >&2
    fi
done | sort > "$FILELIST"

TOTAL_FILES=$(wc -l < "$FILELIST")
echo "[INFO] Total label files discovered: $TOTAL_FILES"

if [[ "$TOTAL_FILES" -eq 0 ]]; then
    echo "[ERROR] No .txt label files found." >&2
    exit 1
fi

if [[ "$ARCHIVE_FILELIST" -eq 1 ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ARCHIVE_PATH="$OUTPUT_DIR/filelist_${TIMESTAMP}.txt"
    cp "$FILELIST" "$ARCHIVE_PATH"
    echo "[INFO] Saved source file list: $ARCHIVE_PATH"
else
    ARCHIVE_PATH=""
fi

# Write the header before parallel workers generate body rows.
echo "filename class_id x_center y_center width height confidence" > "$OUTPUT_CSV"

# Split the file list into static batches and process batches in parallel.
BATCH_SIZE=$(( (TOTAL_FILES + JOBS - 1) / JOBS ))
echo "[INFO] Batch size: $BATCH_SIZE files per worker."

for ((i = 0; i < JOBS; i++)); do
    START=$((i * BATCH_SIZE + 1))
    END=$((START + BATCH_SIZE - 1))
    TMP_OUT="$TEMP_DIR/job_$i.txt"

    (
        sed -n "${START},${END}p" "$FILELIST" | while IFS= read -r file; do
            fname="${file##*/}"
            while IFS= read -r line; do
                [[ -n "$line" ]] && printf "%s %s\n" "$fname" "$line"
            done < "$file"
        done
    ) > "$TMP_OUT" &
done

wait

cat "$TEMP_DIR"/job_*.txt >> "$OUTPUT_CSV"

echo "[SUCCESS] Output CSV created: $OUTPUT_CSV"
if [[ -n "$ARCHIVE_PATH" ]]; then
    echo "[INFO] File list archived: $ARCHIVE_PATH"
fi
echo "[DONE]"
