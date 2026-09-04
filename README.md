# StingrayTools

StingrayTools contains processing workflows for the NES-LTER Stingray tow sled.
The workflows can run independently or as one data pipeline from raw
sensor files, image metadata, ML detections, and CTD reference data to
dashboard-ready CSV products.

[![DOI](https://zenodo.org/badge/946902610.svg)](https://doi.org/10.5281/zenodo.15025961)

## Packages

- [stingraytools](packages/stingraytools/README.md): sensor processing, image
  metadata, image abundance, CTD compilation, shared time/grid utilities, and
  command-line workflows.
- [stingray-dashboard](packages/stingray-dashboard/README.md): Dash application
  and Docker deployment for dashboard-ready datasets.

## Data Workflow

The main processing path is:

```text
raw Stingray sensor files
  -> stingray sensors merge
  -> dashboard_data/data/SENSOR_DATASET/

raw image or video files
  -> stingray images frame-timestamp
  -> media_list/CAMERA_STREAM/

ML detection label files
  -> image_abundance_workflow/merge_detection_labels.sh
  -> stingray images abundance
  -> dashboard_data/data/shadowgraph/

NES-LTER CTD API data
  -> stingray ctd download
  -> dashboard_data/data/ctd/
```

ML inference is run by an external model workflow. This repository provides
post-inference detection merge and abundance workflows.

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
  --cruise CRUISE_ID \
  --start START_DATE \
  --end END_DATE \
  --cal-year CALIBRATION_YEAR \
  --time-bin-seconds BIN_WIDTH_SECONDS
```

Build image/video frame timestamps:

```bash
stingray images frame-timestamp \
  --work-dir /path/to/stingray/data \
  --cruise CRUISE_ID \
  --media-dir /path/to/CAMERA_MEDIA_DIR \
  --out-dir /path/to/stingray/data/media_list/CAMERA_STREAM \
  --fps FPS_VALUE
```

Download CTD reference files:

```bash
stingray ctd download \
  --work-dir /path/to/stingray/data \
  --skip-existing
```

Run post-inference image abundance processing:

```bash
sbatch image_abundance_workflow/run_slurm.sbatch
```

Workflow runner details are in
[image_abundance_workflow/README.md](image_abundance_workflow/README.md).

## Development

Install the development dependency set from a local checkout:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

Run package checks:

```bash
python -m pytest packages/stingraytools/tests
python -m pytest packages/stingray-dashboard/tests
```

## License

StingrayTools is distributed under the MIT License. See [LICENSE](LICENSE).
