# NOAA Storms Pipeline

A one-command pipeline that downloads three years (2022–2024) of NOAA Storm Events data, converts each to GeoParquet, and bundles them into a single GeoPackage ready for analysis in DuckDB, GeoPandas, or QGIS.

## What it does

`process_storm_data.sh` pulls the raw `details` files from NOAA's public archive for 2022, 2023, and 2024, decompresses them, converts each to a spatial GeoParquet file, and assembles all three into a multi-layer GeoPackage at `data/storm_events_2022_2024.gpkg`.

Total runtime: about 3–5 minutes on a typical home internet connection.

## The data

- **Source:** [NOAA Storm Events Database](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/)
- **License:** Public domain (US federal data)
- **What's in it:** every recorded storm event in the United States for the given years, including type, location, and damages

## What I learned

One unexpected challenge was tracking NOAA's file naming conventions — specifically the timestamp suffix (`cYYYYMMDD`) which changes whenever they republish corrected data. Each year can have a *different* creation date, so the script uses a Bash associative array to map each year to its current suffix. Setting up the GDAL environment on Windows via OSGeo4W was also tricky, as it required carefully exporting `GDAL_DATA` and `PROJ_LIB` variables into Git Bash so `ogr2ogr` could correctly project the WGS 84 geometries. Finally, passing the raw CSV fields `BEGIN_LON` and `BEGIN_LAT` into ogr2ogr using the `-oo` open options made generating a spatial file completely seamless.

## Stack

- bash
- curl
- GDAL / ogr2ogr
- GeoParquet
- GeoPackage (GPKG)

---

## Pipeline Architecture

The pipeline runs in 4 sequential steps per year, each idempotent — meaning it's safe to re-run without re-downloading or re-processing files that already exist.

```
NOAA Archive (HTTPS)
       │
       ▼
[Step 1] mkdir -p data/
       │
       ▼                              ┐
[Step 2] curl  →  data/StormEvents_details-ftp_v1.0_d{YEAR}_c{DATE}.csv.gz │
       │                              │
       ▼                              │  Repeated for
[Step 3] gunzip -k  →  data/StormEvents_details_d{YEAR}.csv                │  2022, 2023, 2024
       │                              │
       ▼                              │
[Step 4] ogr2ogr  →  data/storm_events_{YEAR}.parquet                      │
                                      ┘
       │
       ▼
[Step 5] ogr2ogr  →  data/storm_events_2022_2024.gpkg  (3 layers)
```

## Directory Structure

```
.
├── process_storm_data.sh    # Main pipeline script
├── PIPELINE.md              # Detailed pipeline documentation
├── README.md                # This file
├── .gitignore               # Excludes data/ directory from git
└── data/                    # Created at runtime (not committed)
    ├── StormEvents_details-ftp_v1.0_d2022_c20260625.csv.gz
    ├── StormEvents_details_d2022.csv
    ├── storm_events_2022.parquet
    ├── StormEvents_details-ftp_v1.0_d2023_c20260323.csv.gz
    ├── StormEvents_details_d2023.csv
    ├── storm_events_2023.parquet
    ├── StormEvents_details-ftp_v1.0_d2024_c20260421.csv.gz
    ├── StormEvents_details_d2024.csv
    ├── storm_events_2024.parquet
    └── storm_events_2022_2024.gpkg
```

> **Note:** The `data/` directory is excluded from git via `.gitignore`. Raw files can be hundreds of MB.

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `bash` | Run the script | Git Bash / WSL / macOS terminal |
| `curl` | Download from NOAA | Bundled with Git Bash |
| `gunzip` | Decompress `.gz` files | Bundled with Git Bash |
| `ogr2ogr` (GDAL ≥ 3.5) | Convert CSV → GeoParquet | See below |

## How to Run

### macOS / Linux

```bash
# Clone the repo
git clone https://github.com/kollaSrinivas369/noaa-storms-pipeline.git
cd noaa-storms-pipeline

# Make script executable
chmod +x process_storm_data.sh

# Run the pipeline
./process_storm_data.sh
```

### Windows (Git Bash + OSGeo4W)

1. Install [Git for Windows](https://git-scm.com/download/win) (includes Git Bash)
2. Install [OSGeo4W](https://trac.osgeo.org/osgeo4w/) (includes GDAL/ogr2ogr)
3. Open **Git Bash** and run:

```bash
# Add ogr2ogr to your PATH for this session
export PATH="/c/OSGeo4W/bin:$PATH"
export GDAL_DATA="/c/OSGeo4W/apps/gdal/share/gdal"
export PROJ_LIB="/c/OSGeo4W/share/proj"

# Run the pipeline
bash process_storm_data.sh
```

> **Tip:** Add the three `export` lines to your `~/.bashrc` to make them permanent.

## Configuration

All configuration lives at the top of `process_storm_data.sh`:

| Variable | Default | Description |
|---|---|---|
| `YEARS` | `(2022 2023 2024)` | Array of years to download |
| `CREATION_DATES` | Per-year associative array | NOAA's republish date for each file. Check the [NOAA index](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/) if you get a 404 |
| `BASE_URL` | NOAA csvfiles URL | The base URL of the NOAA archive |
| `DATA_DIR` | `./data` | Where all downloads and outputs are stored |

> **Important:** If you get a `404` error on download, the creation date has changed. Visit the [NOAA file index](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/) and look up the correct date suffix for the year you want, then update `CREATION_DATES` in the script.

## Output

The pipeline produces two types of spatial files:

**Per-year GeoParquet** at `data/storm_events_{YEAR}.parquet`:
- **CRS:** WGS 84 (EPSG:4326)
- **Geometry:** Point geometry derived from `BEGIN_LON` / `BEGIN_LAT` columns
- **Format:** Apache Parquet with GeoParquet metadata

**Combined GeoPackage** at `data/storm_events_2022_2024.gpkg`:
- One layer per year (`storm_events_2022`, `storm_events_2023`, `storm_events_2024`)
- Open in QGIS and toggle layers on/off for comparison

### Key columns

| Column | Description |
|---|---|
| `BEGIN_YEARMONTH` | Year and month the event began |
| `EVENT_TYPE` | Type of storm (e.g., Tornado, Flash Flood) |
| `STATE` | US state where the event occurred |
| `BEGIN_LAT` / `BEGIN_LON` | Start coordinates of the event |
| `DAMAGE_PROPERTY` | Estimated property damage |
| `DAMAGE_CROPS` | Estimated crop damage |
| `DEATHS_DIRECT` | Direct fatalities |

### Querying the output

**DuckDB:**
```sql
INSTALL spatial;
LOAD spatial;
SELECT event_type, COUNT(*) AS n
FROM read_parquet('data/storm_events_2024.parquet')
GROUP BY event_type
ORDER BY n DESC
LIMIT 10;
```

**Python (GeoPandas):**
```python
import geopandas as gpd

gdf = gpd.read_parquet("data/storm_events_2024.parquet")
print(gdf.shape)
print(gdf["EVENT_TYPE"].value_counts().head(10))
```

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `curl: (22) ... 404` | `CREATION_DATES` entry is stale | Check the [NOAA index](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/) for the correct date suffix and update `CREATION_DATES` in the script |
| `unexpected end of file` (gunzip) | Previous download was interrupted | Delete `data/` directory and re-run: `rm -rf data && bash process_storm_data.sh` |
| `ogr2ogr: command not found` | GDAL not on PATH | On Windows, run `export PATH="/c/OSGeo4W/bin:$PATH"` first |
| `PROJ: proj_create_from_database` error | `PROJ_LIB` not set | Run `export PROJ_LIB="/c/OSGeo4W/share/proj"` |
| Empty geometry column | Storm had no coordinates | Expected — some events lack `BEGIN_LON`/`BEGIN_LAT` |
