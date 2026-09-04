# stingraytools

Sensor-processing, image-metadata, YOLO abundance, CSV I/O, profile, and
statistical tools for NES-LTER Stingray / ISIIS data.

## Installation

Install the sensor-processing dependencies. This also supports image abundance,
which reuses the sensor gridding and Poisson confidence-interval tools:

```bash
pip install "stingraytools[sensors] @ git+https://github.com/anhph95/StingrayTools.git"
```

Install the image-metadata and training-data dependencies. Use this for frame
timestamp/media CSV generation and YOLO training-data preparation:

```bash
pip install "stingraytools[images] @ git+https://github.com/anhph95/StingrayTools.git"
```

Install the CTD compilation dependency set:

```bash
pip install "stingraytools[ctd] @ git+https://github.com/anhph95/StingrayTools.git"
```

Install the abundance dependency set:

```bash
pip install "stingraytools[abundance] @ git+https://github.com/anhph95/StingrayTools.git"
```

Install the complete Stingray CLI dependency set:

```bash
pip install "stingraytools[pipeline] @ git+https://github.com/anhph95/StingrayTools.git"
```

Confirm that the command-line interface is available:

```bash
stingray --help
```

## Processing workspace

The tools operate on a data workspace, so the source repository does not need
to be cloned. Create or enter a workspace containing the cruise data:

```bash
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
package. To override them for one workspace, place replacements in
`dash_data/misc/`.

## Example: shipboard processing and dashboard deployment

This workflow keeps processing and visualization connected through one shared
workspace. The Python environment produces dashboard-ready CSV files, and the
Docker dashboard reads those files through a read-only mount.

```bash
# Create a dedicated virtual environment on the shipboard or server Linux host.
python3 -m venv ~/venv/stingray
source ~/venv/stingray/bin/activate

# Install only the sensor-processing dependencies for this job.
pip install "stingraytools[sensors] @ git+https://github.com/anhph95/StingrayTools.git"

# Mount the network share using the method appropriate for the host system.
# This example assumes the share is available at /mnt/stingray_share.
cd /mnt/stingray_share

# Confirm the workspace contains the expected runtime inputs before processing.
# sensor_data/ contains raw instrument folders; media_list/ is optional.
ls sensor_data

# Process one cruise into dash_data/data/stingray/.
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --cal-year 2021 \
  --time-bin-seconds 5

# Compile CTD reference files into dash_data/data/ctd/ when needed.
stingray ctd download \
  --work-dir . \
  --skip-existing

# Download the release Compose file if it is not already present on the server.
curl -O https://raw.githubusercontent.com/anhph95/stingraytools/main/compose.ghcr.yml

# Pull the published dashboard release; no local image build is required.
DASH_DATA_DIR=/mnt/stingray_share/dash_data \
  docker compose -f compose.ghcr.yml pull

# Serve the generated dashboard files with the released container image.
# STINGRAY_DEFAULT_DATASET pins the initial dataset selector to the processing output.
DASH_DATA_DIR=/mnt/stingray_share/dash_data \
STINGRAY_DEFAULT_DATASET=stingray \
  docker compose -f compose.ghcr.yml up -d --pull always
```

The dashboard container does not write into `dash_data/`. Re-run
`stingray sensors merge` when new cruise data arrive, then refresh the dashboard
file list or restart the container if the deployment policy prefers restarts.
Building a dashboard image locally is reserved for application development;
shipboard and server deployments should use the released GHCR image.

## Example: WSL2 development and local dashboard checks

This workflow is useful when editing code or batch-editing CSV outputs from a
Windows-mounted drive. It keeps the source checkout editable while using the
same workspace layout as the shipboard deployment.

```bash
# Activate the WSL2 virtual environment used for StingrayTools development.
source /home/anhph/venv/stingray/bin/activate

# Install the full Stingray CLI environment from the local checkout so code edits are live.
cd "/mnt/c/Users/anhph/OneDrive - Woods Hole Oceanographic Institution/stingraytools"
pip install -e ".[dev]"

# Enter the mounted data workspace, not the source repository.
cd "/mnt/c/path/to/stingray_workspace"

# Process or reprocess the cruise data into dash_data/data/stingray/.
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --time-bin-seconds 5

# Install the separate dashboard package when local dashboard review is needed.
pip install -e "./packages/stingray-dashboard"

# Run the dashboard directly from the Python environment for local inspection.
stingray-dashboard \
  --work-dir dash_data \
  --default-dataset stingray \
  --host 127.0.0.1 \
  --port 8050
```

Open `http://127.0.0.1:8050` to inspect the processed data before publishing or
copying the workspace to a server.

## Process one cruise

The following command processes cruise `EN706` from August 7 through August
14, 2023. Both `--start` and `--end` are inclusive calendar dates. Sensor
observations are aggregated into bins of width \(\Delta t = 5\) seconds.

```bash
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --cal-year 2021 \
  --time-bin-seconds 5
```

### Common options

```text
--cruise CRUISE
    Cruise ID, e.g. EN706.

--start START
    Inclusive cruise start date in YYYY-MM-DD format.

--end END
    Inclusive cruise end date in YYYY-MM-DD format.

--work-dir WORK_DIR
    Workspace containing runtime inputs and outputs. Default: current directory.

--root ROOT
    Raw sensor-data directory. Default: WORK_DIR/sensor_data.

--cal-year CAL_YEAR
    Sensor calibration year. Default: 2021.

--time-bin-seconds TIME_BIN_SECONDS
    Time-bin width Delta t in seconds. Default: 5.

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

## Batch-process cruises

The following workflow retrieves the NES-LTER cruise table, normalizes its date
fields, selects cruises beginning on or after January 1, 2023, and runs the
sensor merge for each cruise. When an end date is unavailable, it assumes a
seven-day cruise.

```python
import subprocess
from datetime import timedelta

import pandas as pd


# Load the authoritative NES-LTER cruise metadata table.
cruises = pd.read_csv(
    "https://nes-lter-api.whoi.edu/api/ctd/cruises/get/all"
)

# Convert API date strings to timezone-naive timestamps for direct comparison.
cruises["start_time"] = pd.to_datetime(
    cruises["start_time"],
    errors="coerce",
).dt.tz_localize(None)
cruises["end_time"] = pd.to_datetime(
    cruises["end_time"],
    errors="coerce",
).dt.tz_localize(None)

# Keep valid cruises in chronological order, beginning with calendar year 2023.
cruises = cruises.dropna(subset=["start_time"]).sort_values("start_time")
cruises = cruises[cruises["start_time"] >= "2023-01-01"].copy()
cruises["name"] = cruises["name"].str.upper()

# Estimate a seven-day interval when the API has no recorded cruise end date.
cruises["end_time"] = cruises["end_time"].fillna(
    cruises["start_time"] + timedelta(days=7)
)

# Process each cruise independently so failures identify a specific cruise.
for cruise in cruises.itertuples():
    # Format the inclusive processing interval expected by the command-line tool.
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

    # Report the active interval before launching the processing subprocess.
    print(f"Processing {cruise.name}: {start} through {end}")

    # Stop immediately on failure to avoid silently producing a partial batch.
    subprocess.run(command, check=True)
```

`subprocess.run(..., check=True)` exposes the first failed cruise instead of
continuing with incomplete output. Add `--overwrite-index` to `command` when
the cached sensor-file indexes must be rebuilt.

## Sensor and Image Modules

The distribution includes these processing and metadata modules:

```text
stingray.sensors.ctd
stingray.sensors.fluorometer
stingray.sensors.par
stingray.sensors.suna
stingray.sensors.merge
stingray.images.build_frame_timestamps
stingray.images.abundance
stingray.images.generate_yolo_training
stingray.ctd.download
```

Import the relevant functions from Python scripts or notebooks when a workflow
needs finer control than the command-line interface provides.

`stingray images abundance` depends on the sensor/statistics stack, so install
`stingraytools[abundance]` for abundance-only batch jobs. `stingray images
frame-timestamp` and `stingray images generate-training` depend on the image
stack, so install `stingraytools[images]` for those jobs.

## Output and related tools

The default merged output is written below
`WORK_DIR/dash_data/data/stingray/`. It can be explored with the separately
documented [stingray-dashboard](../stingray-dashboard/README.md).
