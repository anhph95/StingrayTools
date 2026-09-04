# Image Abundance Workflow

This workflow merges ML detection labels, builds optional media/frame timestamp
CSVs, and computes time-binned shadowgraph abundance from existing Stingray
sensor data. The included merge helper reads space-separated `.txt` label
files; other ML pipelines can provide the same detection and class-map tables
directly.

## Setup

Create a working directory with only the workflow files, then create the Python
environment used by the local and Slurm runners:

```bash
curl -L \
  https://github.com/anhph95/stingraytools/archive/refs/heads/main.tar.gz \
  -o stingraytools-main.tar.gz
mkdir -p image_abundance_workflow
tar -xzf stingraytools-main.tar.gz \
  --strip-components=2 \
  -C image_abundance_workflow \
  stingraytools-main/image_abundance_workflow
rm stingraytools-main.tar.gz
cd image_abundance_workflow

module load miniconda/25.9
python -m venv .venv/stingraytools-image-abundance
source .venv/stingraytools-image-abundance/bin/activate
python --version
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
```

Run the setup block again when the workflow files or package installation should
be refreshed from Git.

## Files

- `merge_detection_labels.sh` scans label directories and writes one detection
  table plus one class-map table.
- `run_local.sh` builds optional media CSV, merges labels, and computes
  abundance on a local machine or HPC node.
- `run_slurm.sbatch` builds optional media CSV, merges labels, and computes
  abundance as one Slurm job.
- `run_frame_timestamps_local.sh` builds only the media/frame timestamp CSV.
- `run_frame_timestamps_slurm.sbatch` builds only the media/frame timestamp CSV
  as one Slurm job.

## Environment

The workflow uses `.venv/stingraytools-image-abundance` for timestamp, merge,
and abundance commands. The `stingraytools[images]` dependency set includes
OpenCV for media inspection and the scientific dependencies used by abundance.

## Data Paths

Edit paths directly in the runner configuration block. Shared storage may be
mounted under `/mnt/vast` or `/srv/vast`.

```bash
CLASS_YAML="/path/to/class_names.yaml"
SENSOR_CSV="/path/to/stingray/data/dashboard_data/data/SENSOR_DATASET/DATE_CRUISE.csv"
MEDIA_CSV="/path/to/stingray/data/media_list/CAMERA_STREAM/DATE_CRUISE_fast.csv"
DETECTIONS_CSV="/path/to/stingray/data/image_abundance_work/DATE_CRUISE_detection_labels.csv"
CLASS_MAP_CSV="/path/to/stingray/data/image_abundance_work/DATE_CRUISE_class_map.csv"
ABUNDANCE_OUT_CSV="/path/to/stingray/data/dashboard_data/data/shadowgraph/DATE_CRUISE.csv"
```

The file naming template is:

```text
DATE_CRUISE.csv
DATE_CRUISE_fast.csv
DATE_CRUISE_detection_labels.csv
DATE_CRUISE_class_map.csv
```

The canonical detection table contains one row per retained model detection:

```text
media,frame,class_id,confidence
```

The class map contains one row per model class:

```text
class_id,class,source_file,source_format
```

If `MERGE_LABELS="1"`, the runner builds both tables from `LABEL_DIRS` and
`CLASS_YAML`. If `MERGE_LABELS="0"`, the runner uses an existing detection table.
When `CLASS_MAP_CSV` is missing, the runner creates it from `CLASS_YAML` before
computing abundance.

## Local Run

Edit the configuration block in `run_local.sh`, then run:

```bash
bash run_local.sh
```

For media CSV generation only:

```bash
bash run_frame_timestamps_local.sh
```

## Slurm Run

Edit the configuration block and `#SBATCH` resources in `run_slurm.sbatch`,
then submit:

```bash
sbatch run_slurm.sbatch
```

For media CSV generation only:

```bash
sbatch run_frame_timestamps_slurm.sbatch
```

## Command Steps

The workflow runners call these processing steps:

```bash
stingray images frame-timestamp ...
bash merge_detection_labels.sh ...
stingray images abundance ...
```
