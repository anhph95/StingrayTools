# Image Abundance Workflow

This workflow merges ML detection labels, builds optional media/frame timestamp
CSVs, and computes time-binned shadowgraph abundance from existing Stingray
sensor data. The included merge helper reads space-separated `.txt` label
files; other ML pipelines can provide the same detection and class-map tables
directly.

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

Use a prebuilt virtual environment for routine local and Slurm runs. Create it
once on the host that will run the workflow:

```bash
# Load the site Python or Miniconda module first when the HPC requires one.
python -m venv /path/to/venvs/stingraytools-image-abundance
source /path/to/venvs/stingraytools-image-abundance/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "stingraytools[pipeline] @ git+https://github.com/anhph95/stingraytools.git"
```

Set `VENV_DIR` in `run_local.sh` or `run_slurm.sbatch` to that environment and
leave `INSTALL_ENV="0"` for normal runs. Set `INSTALL_ENV="1"` only when the
environment should be rebuilt from Git during the submitted job.

For media/frame timestamp jobs that do not compute abundance, the smaller image
dependency set is enough:

```bash
python -m venv /path/to/venvs/stingraytools-frame-timestamps
source /path/to/venvs/stingraytools-frame-timestamps/bin/activate
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

## Copy Workflow Files

Clone only the workflow folder into a working directory:

```bash
git clone --filter=blob:none --no-checkout https://github.com/anhph95/stingraytools.git stingraytools-workflows
cd stingraytools-workflows
git sparse-checkout init --cone
git sparse-checkout set image_abundance_workflow
git checkout main
```

Run commands from the parent working directory or from the sparse checkout:

```bash
sbatch stingraytools-workflows/image_abundance_workflow/run_slurm.sbatch
```

## Local Run

Edit the configuration block in `run_local.sh`, then run:

```bash
bash image_abundance_workflow/run_local.sh
```

For media CSV generation only:

```bash
bash image_abundance_workflow/run_frame_timestamps_local.sh
```

## Slurm Run

Edit the configuration block and `#SBATCH` resources in `run_slurm.sbatch`,
then submit:

```bash
sbatch image_abundance_workflow/run_slurm.sbatch
```

For media CSV generation only:

```bash
sbatch image_abundance_workflow/run_frame_timestamps_slurm.sbatch
```

## Command Steps

The workflow runners call these processing steps:

```bash
stingray images frame-timestamp ...
bash image_abundance_workflow/merge_detection_labels.sh ...
stingray images abundance ...
```
