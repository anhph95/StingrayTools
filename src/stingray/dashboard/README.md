# STINGRAY Dashboard

A Dash/Plotly web application for exploring oceanographic cruise and imaging datasets. The dashboard reads CSV files from a structured data directory, automatically detects numeric sensor variables, and provides linked interactive views for transects, cruise tracks, T-S diagrams, vertical profiles, and point-level image/data inspection.

## Main functionality

### Dataset and file discovery

- Scans available datasets from `dash_data/data/` or `/dash_data/data/` when available.
- Treats each subfolder under `data/` as one dataset.
- Lists every `.csv` file inside the selected dataset folder in the **Data file** dropdown.
- Refreshes file lists automatically every 10 minutes and manually through the **Refresh list** button.
- Clears cached data when switching datasets or refreshing the file list.

### Cruise track plot

- Displays selected CSV rows as an interactive scatter plot.
- Configurable X-axis: `times`, `latitude`, `longitude`, or `depth`.
- Configurable Y-axis: `times`, `latitude`, `longitude`, or `depth`.
- Supports box/lasso selection.
- Selected cruise-track points filter the transect plot, T-S plot, and profile plot.
- If the selection is cleared, all points are treated as selected.

### Main transect plot

- Displays a scatter/transect plot using configurable X, Y, and color variables.
- Supported X-axis options: `latitude`, `longitude`, `times`.
- Supported Y-axis options: `depth`, `latitude`.
- Supports continuous and discrete color variables.
- Uses robust default color scaling based on the 5th and 95th percentiles.
- Allows manual color limits through **Color Min** and **Color Max**.
- Supports optional bathymetry and station overlays when plotting `latitude` vs. `depth`.
- Clicks on data points populate the right-hand details panel.

### T-S plot

- Displays a temperature-salinity diagram with sensor-variable coloring.
- Requires `temperature` and `salinity` columns after column canonicalization.
- Adds seawater density anomaly contours, computed with the app's IES80 density utility.
- Supports linked selections with the main transect plot.
- Uses 5th and 95th percentile defaults for color limits unless manually set.

### Vertical profile plot

- Displays the selected profile variable against `depth`.
- If a `cast` column exists, each cast is plotted as a separate profile.
- If a main-plot point is selected and `cast` exists, the profile plot expands the selection to the full selected cast(s).
- If no `cast` column exists, the app computes a median profile by 2 m depth bins with 5th-95th percentile envelope.
- Requires `depth`, selected profile variable, `latitude`, and `longitude`.

### Point details and image preview

- Clicking a point in the main plot opens a detail card in the right panel.
- Displays time, latitude, longitude, depth, and all non-metadata sensor variables.
- If `media` and `frame` are available, builds an ISIIS image URL:

  ```text
  https://stingraydash.whoi.edu/fv/frames/{media}/{frame}?format=png
  ```

- Supports a second image source through `media_2` and `frame_2`.

### Sampling and averaging

- Default behavior automatically subsamples large datasets to roughly 30,000 displayed points.
- Manual **Bin size (N points)** overrides auto-subsampling.
- Sampling modes:
  - `subsample`: keeps every Nth row.
  - `average`: averages full bins of N points.
- Average mode respects either:
  - a `deployment` column, when available, or
  - time-gap segmentation using the **Max time gap for averaging (sec)** setting.
- Default max time gap is 300 seconds.

### URL synchronization

The app stores most dashboard controls in the URL query string, allowing a view to be shared or restored. Synced controls include dataset, file, plot axes, selected variables, color maps, sampling settings, bathymetry/station toggles, plot sizes, point size, opacity, depth limits, and font size.

### Layout controls

- Plot width and height controls are available for the cruise track, main transect, T-S plot, and profile plot.
- Plot dimensions are tracked by a browser-side resize observer and stored locally.
- Global plot font size is configurable.

## Repository structure

Recommended structure:

```text
project-root/
├── app.py
├── assets/
│   ├── WHOI_OneLineLogo_WhiteType_RGB.png
│   ├── lter-network.png
│   └── NES-LTER-horizontal.png
└── dash_data/
    ├── data/
    │   └── <dataset_name>/
    │       ├── <file_1>.csv
    │       └── <file_2>.csv
    └── misc/
        ├── NESLTER_station_list.csv
        └── NESLTER_transect_bathymetry.csv
```

The app will prefer `/dash_data` if that directory exists; otherwise it uses `./dash_data`. You can override the working directory with `--work-dir`.

## Installation

Create a Python environment and install the required packages:

```bash
python -m venv .venv
source .venv/bin/activate
pip install dash pandas numpy plotly
```

## Running locally

From the repository root:

```bash
python app.py
```

Default server settings:

```text
host: 0.0.0.0
port: 8050
work-dir: auto-detected
```

Custom examples:

```bash
python app.py --host 127.0.0.1 --port 8050
python app.py --work-dir /path/to/dash_data
python app.py --host 0.0.0.0 --port 9000 --work-dir /dash_data
```

Open the dashboard at:

```text
http://localhost:8050
```

## WSGI deployment

The app exposes a WSGI server object:

```python
application = create_app().server
```

A production server can import `application` from `app.py`. Example Gunicorn command:

```bash
gunicorn app:application --bind 0.0.0.0:8050 --workers 2 --threads 4
```

## Data directory requirements

### Dataset CSV files

Place dataset CSV files under:

```text
dash_data/data/<dataset_name>/<file_name>.csv
```

Example:

```text
dash_data/data/NESLTER_2022/cast_data.csv
```

The dashboard dropdown will show:

- Dataset: `NESLTER_2022`
- Data file: `cast_data`

### Auxiliary CSV files

These files are optional but required for station and bathymetry overlays:

#### `dash_data/misc/NESLTER_station_list.csv`

Required columns:

| Column | Required | Purpose |
|---|---:|---|
| `latitude` | Yes | Station overlay position. |
| `station` | Yes | Station label shown above the transect. |

#### `dash_data/misc/NESLTER_transect_bathymetry.csv`

Required columns:

| Column | Required | Purpose |
|---|---:|---|
| `latitude` | Yes | Bathymetry X-coordinate. |
| `bottom_depth_meters` | Yes | Bathymetry depth line. |

## Dataset CSV column requirements

The app is flexible, but different features require different columns. Column names are normalized to lowercase, and aliases are automatically mapped for common oceanographic variables.

### Minimum practical requirement

A dataset CSV must contain at least one numeric sensor/data column that is not metadata. Without numeric variables, the variable dropdowns will be empty and most plots cannot render useful data.

### Strongly recommended core columns

| Canonical column | Accepted aliases | Required for | Notes |
|---|---|---|---|
| `times` | `times`, `time`, or `date` | Cruise-track time axis; time-gap averaging; URL defaults | Non-numeric `times`/`time` is parsed as datetime. Numeric `times`/`time` is stored as `time_s`; `date` is used for datetime when present. |
| `latitude` | `latitude`, `lat` | Cruise track, transect, station overlay, profile plot | Needed for most geographic views. |
| `longitude` | `longitude`, `lon` | Cruise track, transect, profile plot | Needed for longitude-based views and profile hover text. |
| `depth` | `depth`, `depsm`, `z`, or derived from pressure | Transect, profile plot | If no depth column exists but pressure exists, depth is copied from pressure. |
| `temperature` | `temperature`, `t090`, `t090c`, `t190`, `t190c` | T-S plot; default color/profile variable | Required for T-S plot. |
| `salinity` | `salinity`, `sal00`, `sal11` | T-S plot | Required for T-S plot. |
| `pressure` | `pressure`, `press`, `prd`, `prdm` | Optional depth fallback | Used to create `depth` if no depth column exists. |
| `cast` | `cast` | Cast-based profile plotting | Optional. Enables separate profile lines by cast. |
| `deployment` | `deployment` | Average-mode segmentation | Optional. Prevents averaging across deployment boundaries. |
| `media` | `media` | Image preview | Optional. Used with `frame`. |
| `frame` | `frame` | Image preview | Optional. Used with `media`. |
| `media_2` | `media_2` | Secondary image preview | Optional. Used with `frame_2`. |
| `frame_2` | `frame_2` | Secondary image preview | Optional. Used with `media_2`. |

### Feature-specific required columns

| Feature | Required columns |
|---|---|
| Dataset appears in dropdown | CSV located in `dash_data/data/<dataset_name>/`. |
| CSV appears in dropdown | File extension must be `.csv`. |
| Cruise track | Selected X and Y axis columns must exist. Defaults expect `times` and `latitude`. |
| Main transect plot | Selected X axis, selected Y axis, and selected color variable must exist. Defaults expect `latitude`, `depth`, and `temperature` when available. |
| Bathymetry overlay | Main plot must use `x = latitude`, `y = depth`; bathymetry auxiliary CSV must exist. |
| Station overlay | Main plot must use `x = latitude`, `y = depth`; station auxiliary CSV must exist. |
| T-S plot | `temperature`, `salinity`, and selected T-S color variable. |
| Profile plot | `depth`, selected profile variable, `latitude`, and `longitude`. |
| Cast-based profile plot | `cast` plus all profile plot required columns. |
| Image preview | `media` + `frame`; optionally `media_2` + `frame_2`. |
| Average mode by deployment | `deployment`. |
| Average mode by time gaps | `times` parseable as datetime. |

### Metadata columns

The following columns are treated as metadata and are excluded from sensor-variable dropdowns:

```text
timestamp, times, matdate,
latitude, longitude, depth,
media, media_path, frame, id, link,
media_2, media_path_2, frame_2, id_2, link_2
```

Columns ending in `_std` are also excluded from variable dropdowns.

### Sensor-variable columns

Any numeric CSV column that is not metadata and does not end in `_std` is treated as a plottable sensor variable.

Examples:

```text
chlorophyll
nitrate
oxygen
backscattering
par
copepod
fish
```

The app infers units from variable names for labels and hover text. Recognized unit categories include temperature, conductivity, pressure, depth, salinity, density, latitude/longitude/attitude angles, nitrate, chlorophyll, backscattering, PAR, sound velocity, oxygen saturation, and plankton/particle abundance.

## Example dataset CSV

```csv
times,latitude,longitude,depth,temperature,salinity,chlorophyll,cast,media,frame
2022-07-01 12:00:00,40.123,-70.456,5.0,18.2,32.1,0.82,1,ISIIS001,100
2022-07-01 12:00:05,40.124,-70.457,6.0,18.1,32.2,0.79,1,ISIIS001,101
2022-07-01 12:10:00,40.130,-70.460,8.0,17.8,32.4,0.95,2,ISIIS001,220
```

## Notes for maintainers

- `load_data()` caches raw loaded data and averaged data to improve performance.
- `point_id` is added automatically when missing and used for cross-plot linking.
- CSV columns are canonicalized at load time, so downstream callbacks use standardized names.
- The app uses WebGL scatter traces (`Scattergl`) for better performance with large point clouds.
- Default auto-subsampling targets about 30,000 plotted rows.
- URL parameters are restored on page load after validating that the requested dataset and file still exist.

## Troubleshooting

### No CSV found

Check that files are located under:

```text
dash_data/data/<dataset_name>/*.csv
```

Then click **Refresh list** or wait for the automatic scanner.

### Temperature or Salinity data missing

The T-S plot requires columns that canonicalize to:

```text
temperature,salinity
```

Use accepted aliases such as `t090`, `t190`, `sal00`, or `sal11`.

### No variable selected

The selected CSV may not contain numeric sensor columns. Confirm that your data columns are numeric and are not metadata columns or `_std` columns.

### Bathymetry or station overlays do not appear

Confirm that:

- The main plot is set to `x = latitude` and `y = depth`.
- The relevant auxiliary CSV exists in `dash_data/misc/`.
- Auxiliary latitude values overlap the selected data latitude range.

### Images do not load in the details panel

Confirm that the selected row contains valid `media` and `frame` values and that the generated `stingraydash.whoi.edu/fv/frames/...` URL is reachable from the browser.
