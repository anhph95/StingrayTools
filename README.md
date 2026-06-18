# StingrayTools

Tools for processing, organizing, and visualizing NES-LTER Stingray / ISIIS sensor and imaging data.

This package includes sensor-processing utilities, CTD/profile handling, image-link helpers, CSV I/O tools, statistical helpers, and a Dash dashboard for interactive exploration of Stingray cruise data.

[![DOI](https://zenodo.org/badge/946902610.svg)](https://doi.org/10.5281/zenodo.15025961)

---

## Installation

Install the full StingrayTools distribution, including the sensor/image tools and dashboard:

```bash
pip install "git+https://github.com/anhph95/StingrayTools.git"
```

Install only the dashboard distribution:

```bash
pip install "stingray-dashboard @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

Install only the CTD tools distribution:

```bash
pip install "ctdtools @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/ctdtools"
```

For a Linux server image that runs only the dashboard with Gunicorn:

```bash
pip install "stingray-dashboard[server] @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

---

## Command-line usage

### Process Stingray sensor data

Install the package directly from Git, then run it from any workspace containing
your data. The source repository does not need to be cloned:

```bash
pip install "git+https://github.com/anhph95/StingrayTools.git"

mkdir stingray_workspace
cd stingray_workspace
```

The default workspace layout is:

```text
stingray_workspace/
  sensor_data/          raw CTD, DVL, fluorometer, GPS, oxygen, PAR, and SUNA folders
  media_list/           optional ISIIS1 and ISIIS2 frame metadata
  suna_calibration/     optional cruise-specific SUNA calibration files
  indexes/              generated sensor-file indexes
  logs/                 processing logs
  dash_data/data/       dashboard-ready output
```

Dashboard station and bathymetry reference tables are installed with the
package. To override them for a workspace, place replacements in
`dash_data/misc/`.

#### One-cruise example

The following command processes cruise `EN706` from August 7 through
August 14, 2023. Both `--start` and `--end` are inclusive calendar dates.
Sensor observations are aggregated into bins of width
\(\Delta t = 5\) seconds.

```bash
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --cal-year 2021 \
  --time-bin-seconds 5
```

Common options:

```text
--cruise CRUISE
    Cruise ID, e.g. EN706.

--start START
    Cruise start date in YYYY-MM-DD format.

--end END
    Cruise end date in YYYY-MM-DD format.

--work-dir WORK_DIR
    Workspace containing runtime inputs and outputs. Default: current directory.

--root ROOT
    Raw sensor-data directory. Default: WORK_DIR/sensor_data.

--cal-year CAL_YEAR
    Sensor calibration year. Default: 2021.

--time-bin-seconds TIME_BIN_SECONDS
    Time-bin size in seconds. Default: 5.

--out-dir OUT_DIR
    Output directory. Default: WORK_DIR/dash_data/data/stingray.

--index-dir INDEX_DIR
    Generated sensor-file index directory. Default: WORK_DIR/indexes.

--media-list-dirs MEDIA_LIST_DIRS ...
    Media-list directories for ISIIS image links. Defaults to the ISIIS1 and
    ISIIS2 directories below WORK_DIR/media_list.

--suna-cal-file SUNA_CAL_FILE
    Optional SUNA calibration file for TSP-corrected nitrate.

--suna-cal-dir SUNA_CAL_DIR
    Optional directory containing cruise-specific SUNA calibration files.

--overwrite-index
    Rebuild cached sensor-file indexes.

--log-level {DEBUG,INFO,WARNING,ERROR}
    Logging level. Default: INFO.
```

#### Batch-process cruises from NES-LTER metadata

The following example is adapted from `data_process_all.ipynb`. It retrieves
the NES-LTER cruise table, normalizes the date fields, selects cruises beginning
on or after January 1, 2023, and runs the same sensor merge for each cruise.
When an end date is unavailable, the example assumes a seven-day cruise.

```python
import subprocess
from datetime import timedelta

import pandas as pd


# Load the NES-LTER cruise metadata table.
cruises = pd.read_csv(
    "https://nes-lter-api.whoi.edu/api/ctd/cruises/get/all"
)

# Convert API date strings to timezone-naive timestamps for comparison.
cruises["start_time"] = pd.to_datetime(
    cruises["start_time"],
    errors="coerce",
).dt.tz_localize(None)
cruises["end_time"] = pd.to_datetime(
    cruises["end_time"],
    errors="coerce",
).dt.tz_localize(None)

# Keep valid cruises in chronological order, beginning with 2023.
cruises = cruises.dropna(subset=["start_time"]).sort_values("start_time")
cruises = cruises[cruises["start_time"] >= "2023-01-01"].copy()
cruises["name"] = cruises["name"].str.upper()

# Estimate a seven-day interval when the API has no cruise end date.
cruises["end_time"] = cruises["end_time"].fillna(
    cruises["start_time"] + timedelta(days=7)
)

for cruise in cruises.itertuples():
    start = cruise.start_time.strftime("%Y-%m-%d")
    end = cruise.end_time.strftime("%Y-%m-%d")

    # Each output row represents a time bin of width Delta t = 5 seconds.
    command = [
        "stingray",
        "sensors",
        "merge",
        "--work-dir",
        ".",
        "--cruise",
        cruise.name,
        "--start",
        start,
        "--end",
        end,
        "--cal-year",
        "2021",
        "--time-bin-seconds",
        "5",
    ]

    print(f"Processing {cruise.name}: {start} through {end}")
    subprocess.run(command, check=True)
```

`subprocess.run(..., check=True)` stops the batch when a cruise fails, making
the failed cruise visible instead of silently continuing with incomplete data.
Add `--overwrite-index` to the command list when the cached sensor-file indexes
must be rebuilt.

### Sensor and image utilities

The package also includes modules for sensor-specific processing and image/media metadata handling:

```text
stingray.sensors.ctd
stingray.sensors.fluorometer
stingray.sensors.par
stingray.sensors.suna
stingray.sensors.merge
stingray.images.frame_timestamp
stingray.images.get_tator_link
stingray.images.abundance
stingray.images.generate_training
```

Use the relevant module directly or import functions from Python scripts and notebooks as needed.

### CTD-only command

When installing only `ctdtools`, use:

```bash
ctd-download --help
```

---

## Dashboard usage

The dashboard is packaged as `stingray-dashboard`. It can be installed by itself from `packages/stingray-dashboard` or as part of this repository. It reads data from a configured work directory. By default it uses `/dash_data` when that directory exists, otherwise `./dash_data`.

Expected local structure:

```text
dash_data/
  data/
    <dataset_name>/
      *.csv
  misc/
    NESLTER_station_list.csv
    NESLTER_transect_bathymetry.csv
```

For example, a local EN706 dataset can be placed at:

```text
dash_data/data/stingray/20230807_EN706.csv
```

The dashboard works best when each CSV contains:

- `times`, `latitude`, `longitude`, and `depth` for navigation and transect plots.
- `temperature` and `salinity` for the T-S diagram and density contours.
- `cast` for individual vertical profiles.
- One or more numeric sensor variables such as `chlorophyll`, `nitrate`, `par`, or `oxygen_concentration`.
- Optional `media` and `frame` columns for linked ISIIS imagery.

Common source names such as `lat`, `lon`, `t090`, `sal00`, and `pressure`
are normalized to the dashboard's canonical columns. Instrument altitude
sentinel values equal to `9999.99` are treated as missing data so they do not
distort plot ranges or averages.

### Run the dashboard locally

```bash
stingray-dashboard --work-dir dash_data --host 0.0.0.0 --port 8050
```

Then open:

```text
http://localhost:8050
```

Dashboard controls:

- Use the top row to select dataset, CSV file, sampling mode, point size, opacity, font size, and refresh the file list.
- `Subsample` keeps every \(N\)-th observation and preserves the original point identifiers.
- `Average bins` computes means within cast/deployment-aware groups of \(N\) observations. Short trailing bins are discarded rather than combined across casts or time gaps.
- Each plot has its own option panel beside it.
- Plot dimensions are controlled by width and height inputs in each plot option panel.
- The URL query string stores the current dashboard state for reproducible views.
- Cruise-track selections filter the main transect, T-S, and profile plots.
- Main plot selections synchronize with the T-S and profile plots.
- Cast coloring uses a continuous color scale to avoid creating one trace per cast.
- Multi-cast profile plots use WebGL traces for smoother rendering.

### Local development and tests

Create and activate a project-local virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

Run the dashboard regression tests:

```bash
pytest packages/stingray-dashboard/tests
```

Runtime datasets under `dash_data/` are intentionally excluded from version
control. Keep large or institution-specific CSV files in the local work
directory and commit only source code, packaged reference tables, and tests.

### Use the WHOI-hosted dashboard

Dashboard-ready data from `dash_data/data` can be copied to:

```text
\\vast.whoi.edu\proj\nes-lter\stingray_dashboard\dash_data\data
```

The dashboard can then be accessed at:

```text
https://stingraydash.whoi.edu/
```

### Deploy the packaged dashboard with Gunicorn

The installable WSGI target is:

```text
stingray_dashboard.app:application
```

Example command:

```bash
gunicorn --bind 0.0.0.0:8050 stingray_dashboard.app:application
```

For the production Docker layout, the dashboard code can be installed from Git and the only required runtime mount is the data directory:

```yaml
volumes:
  - /srv/vast/nes-lter/Stingray/data/dashboard_data:/dash_data:ro
```

---
## Docker usage

The dashboard supports three Docker workflows:

1. Run the published image for a stable production deployment.
2. Build the current GitHub source without cloning the repository.
3. Use the legacy Git-installing Compose setup used by the existing WHOI server.

In every workflow, the host workspace mounted at `/dash_data` must already
contain these directories because the container receives a read-only mount:

```text
dashboard_data/
  data/    dashboard dataset directories and CSV files
  misc/    optional workspace-specific station and bathymetry tables
```

Create the directories when preparing a new workspace:

```bash
mkdir -p dashboard_data/data dashboard_data/misc
```

Changing files below `dashboard_data/` does not require rebuilding the image.

### Recommended: run the published image

GitHub Actions builds `ghcr.io/anhph95/stingray-dashboard` from the repository
source after every push to `main`. A Git tag such as `v2.1.0` also publishes
the immutable `2.1.0` and `2.1` image tags. This separates application releases
from institution-specific datasets.

Run the rolling `latest` image with a workspace on the current host:

```bash
docker pull ghcr.io/anhph95/stingray-dashboard:latest

docker run -d \
  --name stingray-dashboard \
  --restart unless-stopped \
  -p 8050:8050 \
  --mount "type=bind,source=/absolute/path/to/dashboard_data,target=/dash_data,readonly" \
  ghcr.io/anhph95/stingray-dashboard:latest
```

Open the dashboard at:

```text
http://localhost:8050
```

For reproducible production deployments, replace `latest` with a release such
as `2.1.0`. The version remains fixed until the deployment configuration is
changed explicitly.

Stop and remove this container with:

```bash
docker rm -f stingray-dashboard
```

### Recommended Compose deployment

Download `compose.ghcr.yml`, then provide the absolute dataset path. The
absolute path keeps behavior unambiguous regardless of the directory from
which Compose is invoked.

```bash
curl -O https://raw.githubusercontent.com/anhph95/stingraytools/main/compose.ghcr.yml

DASH_DATA_DIR=/absolute/path/to/dashboard_data \
  docker compose -f compose.ghcr.yml up -d
```

Update the application while preserving the mounted datasets:

```bash
DASH_DATA_DIR=/absolute/path/to/dashboard_data \
  docker compose -f compose.ghcr.yml pull

DASH_DATA_DIR=/absolute/path/to/dashboard_data \
  docker compose -f compose.ghcr.yml up -d
```

Pin a release and optionally select another host port:

```bash
STINGRAY_DASHBOARD_IMAGE=ghcr.io/anhph95/stingray-dashboard:2.1.0 \
STINGRAY_DASHBOARD_PORT=8051 \
DASH_DATA_DIR=/absolute/path/to/dashboard_data \
  docker compose -f compose.ghcr.yml up -d
```

Stop the Compose deployment:

```bash
DASH_DATA_DIR=/absolute/path/to/dashboard_data \
  docker compose -f compose.ghcr.yml down
```

### Build directly from GitHub

This workflow is useful for testing the newest source before a published image
is available. Docker downloads the repository and builds `Dockerfile.release`
locally; no repository clone or Python installation is required.

```bash
docker build \
  -f Dockerfile.release \
  -t stingray-dashboard:git \
  "https://github.com/anhph95/stingraytools.git#main"

docker run -d \
  --name stingray-dashboard \
  --restart unless-stopped \
  -p 8050:8050 \
  --mount "type=bind,source=/absolute/path/to/dashboard_data,target=/dash_data,readonly" \
  stingray-dashboard:git
```

Replace `main` with a branch, tag, or full commit hash to select a different
source revision.

### Build from a local checkout

Developers can build the exact source currently checked out, including local
changes that have not been pushed:

```bash
git clone https://github.com/anhph95/stingraytools.git
cd stingraytools

docker build -f Dockerfile.release -t stingray-dashboard:local .

docker run -d \
  --name stingray-dashboard \
  --restart unless-stopped \
  -p 8050:8050 \
  --mount "type=bind,source=/absolute/path/to/dashboard_data,target=/dash_data,readonly" \
  stingray-dashboard:local
```

Rebuild the local image after changing application source, assets,
dependencies, or Docker configuration.

### Existing WHOI server deployment

The original `Dockerfile` and `compose.yml` remain unchanged for backward
compatibility. They install the dashboard package from the configured Git
repository and mount the server dataset at:

```text
/srv/vast/nes-lter/Stingray/data/dashboard_data
```

The current server can continue using:

```bash
docker compose up -d --build
```

This rebuild installs the configured `STINGRAYTOOLS_REF`, currently `main`.
It does not use the GHCR image unless the server is deliberately migrated to
`compose.ghcr.yml`.

### Container release process

Maintainers do not build or upload release images manually:

1. Push to `main` to publish `latest` and a commit-specific `sha-*` tag.
2. Create and push a version tag, for example `v2.1.0`, to publish `2.1.0`
   and `2.1`.
3. In the repository's Packages settings, make the container package public
   so users can pull it without registry authentication.

The commit-specific tag provides an immutable deployment identity, while a
semantic-version tag communicates a supported release and `latest` tracks the
current production branch.

---

## Command checks

```bash
stingray --help
stingray-dashboard --help
```

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## Contributors

- Anh Pham
- Sidney Batchelder
- Heidi Sosik

---

GitHub Repository: https://github.com/anhph95/StingrayTools
