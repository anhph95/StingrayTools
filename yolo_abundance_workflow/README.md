# YOLO Abundance Workflow

This workflow merges YOLO label `.txt` files, builds optional media/frame
timestamp CSVs, and computes time-binned shadowgraph abundance from existing
Stingray sensor data.

## Files

- `merge_yolo_labels.sh` scans YOLO label directories and writes one detection
  table.
- `run_local.sh` builds optional media CSV, merges labels, and computes
  abundance on a local machine or HPC node.
- `run_slurm.sbatch` builds optional media CSV, merges labels, and computes
  abundance as one Slurm job.
- `run_frame_timestamps_local.sh` builds only the media/frame timestamp CSV.
- `run_frame_timestamps_slurm.sbatch` builds only the media/frame timestamp CSV
  as one Slurm job.

## Dependencies

The combined abundance runners create or reuse a virtual environment and
install:

```bash
stingraytools[pipeline]
```

That provides `stingray images frame-timestamp` and `stingray images
abundance`.

The frame timestamp runners install:

```bash
stingraytools[images]
```

That provides OpenCV for inspecting image/video files and writing the media CSV
used by abundance.

## Data Paths

Edit paths directly in the runner configuration block. Shared storage may be
mounted under `/mnt/vast` or `/srv/vast`.

```bash
SENSOR_CSV="/mnt/vast/nes-lter/Stingray/data/dashboard_data/data/stingray_NESLTER/YYYYMMDD_EN706.csv"
MEDIA_CSV="/mnt/vast/nes-lter/Stingray/data/media_list/ISIIS1/YYYYMMDD_EN706_fast.csv"
ABUNDANCE_OUT_CSV="/mnt/vast/nes-lter/Stingray/data/dashboard_data/data/shadowgraph/YYYYMMDD_EN706.csv"
```

The file naming template is:

```text
YYYYMMDD_CRUISE.csv
YYYYMMDD_CRUISE_fast.csv
YYYYMMDD_CRUISE_yolo_labels.csv
```

## Copy Workflow Files

Clone only the workflow folder into a working directory:

```bash
git clone --filter=blob:none --no-checkout https://github.com/anhph95/stingraytools.git stingraytools-workflows
cd stingraytools-workflows
git sparse-checkout init --cone
git sparse-checkout set yolo_abundance_workflow
git checkout main
```

Run commands from the parent working directory or from the sparse checkout:

```bash
sbatch stingraytools-workflows/yolo_abundance_workflow/run_slurm.sbatch
```

## Local Run

Edit the configuration block in `run_local.sh`, then run:

```bash
bash yolo_abundance_workflow/run_local.sh
```

For media CSV generation only:

```bash
bash yolo_abundance_workflow/run_frame_timestamps_local.sh
```

## Slurm Run

Edit the configuration block and `#SBATCH` resources in `run_slurm.sbatch`,
then submit:

```bash
sbatch yolo_abundance_workflow/run_slurm.sbatch
```

For media CSV generation only:

```bash
sbatch yolo_abundance_workflow/run_frame_timestamps_slurm.sbatch
```

## Command Steps

The workflow runners call these processing steps:

```bash
stingray images frame-timestamp ...
bash yolo_abundance_workflow/merge_yolo_labels.sh ...
stingray images abundance ...
```
