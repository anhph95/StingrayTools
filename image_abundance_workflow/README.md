# Image Abundance Workflow

This workflow merges ML detection labels, builds optional media/frame timestamp
CSVs, and computes time-binned shadowgraph abundance from existing Stingray
sensor data. The included merge helper reads space-separated `.txt` label
files; other ML pipelines can provide the same detection and class-map tables
directly.

## Start Here

Copy only the workflow files into a working directory:

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

# Load a Python 3.10+ module before creating the environment.
module load miniconda/25.9
python -m venv .venv/stingraytools-image-abundance
source .venv/stingraytools-image-abundance/bin/activate
python --version
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[pipeline] @ git+https://github.com/anhph95/stingraytools.git"
```

Edit `run_slurm.sbatch` before submitting. Set `VENV_DIR` to
`.venv/stingraytools-image-abundance` and leave `INSTALL_ENV="0"` for normal
runs. Repeat the copy commands from the parent working directory to update the
workflow files.

Set `INSTALL_ENV="1"` only when the environment should be rebuilt from Git
during the submitted job.

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

## Dependencies

For media/frame timestamp jobs that do not compute abundance, the smaller image
dependency set is enough:

```bash
python -m venv .venv/stingraytools-frame-timestamps
source .venv/stingraytools-frame-timestamps/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
```

The abundance environment provides `stingray images frame-timestamp` and
`stingray images abundance`. The frame timestamp environment provides OpenCV for
inspecting image/video files and writing the media CSV used by abundance.

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
