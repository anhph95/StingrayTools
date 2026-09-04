# StingrayTools

StingrayTools contains processing workflows for the NES-LTER Stingray / ISIIS
tow sled. The workflows can run independently or as one data pipeline from raw
sensor files, image metadata, YOLO detections, and CTD reference data to
dashboard-ready CSV products.

[![DOI](https://zenodo.org/badge/946902610.svg)](https://doi.org/10.5281/zenodo.15025961)

## Packages

- [stingraytools](packages/stingraytools/README.md): sensor processing, image
  metadata, YOLO abundance, CTD compilation, shared time/grid utilities, and
  command-line workflows.
- [stingray-dashboard](packages/stingray-dashboard/README.md): Dash application
  and Docker deployment for dashboard-ready datasets.

## Data Workflow

The main processing path is:

```text
raw Stingray sensor files
  -> stingray sensors merge
  -> dashboard_data/data/stingray_NESLTER/

raw ISIIS image or video files
  -> stingray images frame-timestamp
  -> media_list/ISIIS1/ or media_list/ISIIS2/

YOLO inference label files
  -> yolo_abundance_workflow/merge_yolo_labels.sh
  -> stingray images abundance
  -> dashboard_data/data/shadowgraph/

NES-LTER CTD API data
  -> stingray ctd download
  -> dashboard_data/data/ctd/
```

YOLO inference is run by the external model workflow. This repository provides
the post-inference merge and abundance workflow.

## Installation

Install only the dependency set needed by the job:

```bash
pip install "stingraytools[sensors] @ git+https://github.com/anhph95/stingraytools.git"
pip install "stingraytools[images] @ git+https://github.com/anhph95/stingraytools.git"
pip install "stingraytools[ctd] @ git+https://github.com/anhph95/stingraytools.git"
pip install "stingraytools[abundance] @ git+https://github.com/anhph95/stingraytools.git"
```

Install the full processing pipeline dependency set:

```bash
pip install "stingraytools[pipeline] @ git+https://github.com/anhph95/stingraytools.git"
```

Install the dashboard package:

```bash
pip install "stingray-dashboard @ git+https://github.com/anhph95/stingraytools.git#subdirectory=packages/stingray-dashboard"
```

For dashboard Docker and server deployment, see
[packages/stingray-dashboard/README.md](packages/stingray-dashboard/README.md).

## Core Commands

Merge one cruise of Stingray sensor data:

```bash
stingray sensors merge \
  --work-dir /path/to/stingray/data \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --cal-year 2021 \
  --time-bin-seconds 5
```

Build image/video frame timestamps:

```bash
stingray images frame-timestamp \
  --work-dir /path/to/stingray/data \
  --cruise EN706 \
  --media-dir /path/to/NESLTER_EN706/Basler_avA2300-25gm \
  --out-dir /path/to/stingray/data/media_list/ISIIS1 \
  --fps 15
```

Download CTD reference files:

```bash
stingray ctd download \
  --work-dir /path/to/stingray/data \
  --skip-existing
```

Run post-inference YOLO abundance processing:

```bash
sbatch yolo_abundance_workflow/run_slurm.sbatch
```

Workflow runner details are in
[yolo_abundance_workflow/README.md](yolo_abundance_workflow/README.md).

## Development

Use the configured WSL2 environment for local development:

```bash
source /home/anhph/venv/stingray/bin/activate
pip install -e ".[dev]"
```

Run package checks:

```bash
python -m pytest packages/stingraytools/tests
python -m pytest packages/stingray-dashboard/tests
```

## License

StingrayTools is distributed under the MIT License. See [LICENSE](LICENSE).

