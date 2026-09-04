# YOLO Abundance Workflow

This folder is a standalone workflow for turning YOLO label `.txt` files into
time-binned shadowgraph abundance merged onto Stingray sensor data.

It is intentionally kept outside the Python package. The folder can be copied,
cloned, or called by an external scheduler while the Python processing command
is installed from the StingrayTools package.

## Files

- `merge_yolo_labels.sh` scans YOLO label directories and writes one detection
  table.
- `run_frame_timestamps_local.sh` builds the media/frame timestamp CSV on a
  local machine or local HPC node.
- `run_frame_timestamps_slurm.sbatch` builds the media/frame timestamp CSV as
  one Slurm job.
- `run_local.sh` merges labels and computes abundance on a local machine or
  local HPC node.
- `run_slurm.sbatch` merges labels and computes abundance as one Slurm job.

## Dependencies

The abundance runners create a temporary virtual environment and install:

```bash
stingraytools[abundance]
```

That provides `stingray images abundance`, including recomputation with a new
bin width or optional Poisson confidence intervals. It does not install OpenCV,
Tator, or dashboard dependencies.

The frame timestamp runners install:

```bash
stingraytools[images]
```

That provides OpenCV for inspecting image/video files and writing the media CSV
used by abundance.

## Local Run

Edit the configuration block in `run_frame_timestamps_local.sh`, then run:

```bash
bash yolo_abundance_workflow/run_frame_timestamps_local.sh
```

Edit the configuration block in `run_local.sh`, then run:

```bash
bash yolo_abundance_workflow/run_local.sh
```

## Slurm Run

Edit the configuration block and `#SBATCH` resources in
`run_frame_timestamps_slurm.sbatch`, then submit:

```bash
sbatch yolo_abundance_workflow/run_frame_timestamps_slurm.sbatch
```

Edit the configuration block and `#SBATCH` resources in `run_slurm.sbatch`,
then submit the abundance workflow:

```bash
sbatch yolo_abundance_workflow/run_slurm.sbatch
```

## External Orchestrators

Tools such as Prefect can call the helper scripts directly:

```bash
bash yolo_abundance_workflow/merge_yolo_labels.sh ...
stingray images abundance ...
```

Keep paths, thresholds, bin width, image dimensions, and volume settings in the
orchestrator or runner script so the helper scripts stay reusable.
