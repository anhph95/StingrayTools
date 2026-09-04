# StingrayTools

StingrayTools is a collection of installable tools for processing, organizing,
and visualizing NES-LTER Stingray / ISIIS sensor and imaging data.

The repository contains two user-facing packages:

- [stingraytools](packages/stingraytools/README.md) processes Stingray sensor data, image metadata, YOLO abundance products, and CTD reference data.
- [stingray-dashboard](packages/stingray-dashboard/README.md) provides interactive exploration and Docker deployment of dashboard datasets.

[![DOI](https://zenodo.org/badge/946902610.svg)](https://doi.org/10.5281/zenodo.15025961)

## Installation

Install the Stingray sensor-processing dependencies. This also supports image
abundance, which reuses the sensor gridding and Poisson confidence-interval
tools:

```bash
pip install "stingraytools[sensors] @ git+https://github.com/anhph95/StingrayTools.git"
```

Install the Stingray image-metadata and training-data dependencies. Use this for
frame timestamp/media CSV generation and YOLO training-data preparation:

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

Install the dashboard package separately:

```bash
pip install "stingray-dashboard @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

Install the dashboard with the Gunicorn production-server dependency:

```bash
pip install "stingray-dashboard[server] @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

## Docker dashboard install

Docker is enough to install and run the dashboard on Linux, macOS, or Windows
with Docker Desktop. Use the released image from GitHub Container Registry
rather than building the dashboard from source. The container visualizes
existing `dash_data/` files; use the Python package workflow when you need to
process raw Stingray sensor data.

Unix shell:

```bash
curl -O https://raw.githubusercontent.com/anhph95/stingraytools/main/compose.ghcr.yml
DASH_DATA_DIR=/path/to/dash_data \
STINGRAY_DEFAULT_DATASET=stingray \
  docker compose -f compose.ghcr.yml pull
DASH_DATA_DIR=/path/to/dash_data \
STINGRAY_DEFAULT_DATASET=stingray \
  docker compose -f compose.ghcr.yml up -d --pull always
```

Windows PowerShell:

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/anhph95/stingraytools/main/compose.ghcr.yml" `
  -OutFile "compose.ghcr.yml"
$env:DASH_DATA_DIR = "C:\path\to\dash_data"
$env:STINGRAY_DEFAULT_DATASET = "stingray"
docker compose -f compose.ghcr.yml pull
docker compose -f compose.ghcr.yml up -d --pull always
```

Open `http://127.0.0.1:8050`. Leave `STINGRAY_DEFAULT_DATASET` unset to open
the first dataset folder under `dash_data/data/`. If host port `8050` is already
in use, set `STINGRAY_DASHBOARD_PORT`, for example
`STINGRAY_DASHBOARD_PORT=8051 docker compose -f compose.ghcr.yml up -d --pull always`,
and open `http://127.0.0.1:8051`.

Usage, data-layout, development, and deployment instructions are maintained in
the package READMEs linked above.

## Common workflows

### Shipboard processing and dashboard deployment

Use this path when data are written to a shared shipboard or server-mounted
workspace and the dashboard is served from Docker.

```bash
# Create an isolated processing environment on the Linux host.
python3 -m venv ~/venv/stingray
source ~/venv/stingray/bin/activate

# Install the processing dependencies needed for this workflow.
pip install "stingraytools[pipeline] @ git+https://github.com/anhph95/StingrayTools.git"

# Enter the mounted shared workspace that contains sensor_data/ and media_list/.
cd /mnt/stingray_share

# Process one cruise into dash_data/data/stingray/ for dashboard consumption.
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14 \
  --cal-year 2021

# Compile CTD reference files into dash_data/data/ctd/ when needed by the dashboard.
stingray ctd download \
  --work-dir . \
  --skip-existing

# Serve the generated dashboard data with the released container image.
DASH_DATA_DIR=/mnt/stingray_share/dash_data \
STINGRAY_DEFAULT_DATASET=stingray \
  docker compose -f compose.ghcr.yml pull
DASH_DATA_DIR=/mnt/stingray_share/dash_data \
STINGRAY_DEFAULT_DATASET=stingray \
  docker compose -f compose.ghcr.yml up -d --pull always
```

The processing environment writes CSV products into `dash_data/`; the Docker
container mounts that directory read-only and visualizes the same files.

### WSL2 development and local checks

Use this path when developing or batch-editing data from a Windows-mounted drive
and checking the dashboard before publishing outputs.

```bash
# Activate the WSL2 environment used for StingrayTools development.
source /home/anhph/venv/stingray/bin/activate

# From a local checkout, install the full Stingray CLI development environment.
pip install -e ".[dev]"

# Work from the mounted drive or shared workspace that contains runtime data.
cd "/mnt/c/path/to/stingray_workspace"

# Reprocess or batch-edit dashboard inputs in place.
stingray sensors merge \
  --work-dir . \
  --cruise EN706 \
  --start 2023-08-07 \
  --end 2023-08-14

# Install the dashboard package when local dashboard review is needed.
pip install -e "./packages/stingray-dashboard"

# Run the dashboard locally against the generated files for review.
stingray-dashboard \
  --work-dir dash_data \
  --default-dataset stingray \
  --host 127.0.0.1 \
  --port 8050
```

Open `http://127.0.0.1:8050` from Windows or WSL2 to inspect the result.

## License

StingrayTools is distributed under the MIT License. See [LICENSE](LICENSE).

## Contributors

- Anh Pham
- Sidney Batchelder
- Heidi Sosik
