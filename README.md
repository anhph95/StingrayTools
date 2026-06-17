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
- Each plot has its own option panel beside it.
- Plot dimensions are controlled by width and height inputs in each plot option panel.
- The URL query string stores the current dashboard state for reproducible views.
- Cruise-track selections filter the main transect, T-S, and profile plots.
- Main plot selections synchronize with the T-S and profile plots.

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

The dashboard can also be run with Docker Compose.

### Start the dashboard

```bash
docker compose up --build
```

This builds the image, mounts `dash_data/`, and serves the app at:

```text
http://localhost:8050
```

### Stop the dashboard

```bash
docker compose down
```

### Run in detached mode

```bash
docker compose up -d
```

Stop it with:

```bash
docker compose down
```

### Updating data

If `dash_data/` is mounted as a bind volume, updating CSV files does not require rebuilding the Docker image.

### Rebuilding after code changes

Rebuild after modifying source code, dashboard code, assets, dependencies, or Docker configuration:

```bash
docker compose up --build
```

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
