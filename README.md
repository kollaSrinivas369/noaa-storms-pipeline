# 🌪️ NOAA Storms Pipeline

A fully automated Bash pipeline that downloads, decompresses, and converts [NOAA Storm Events](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/) data into spatial GeoParquet and GeoPackage formats for GIS analysis.

## What It Does

```
NOAA FTP Server → .csv.gz → Raw CSV → GeoParquet (.parquet) → GeoPackage (.gpkg)
```

1. **Downloads** Storm Events "details" CSVs for 2022–2024 from NOAA's public server.
2. **Decompresses** the gzipped archives.
3. **Converts** each CSV to a spatial **GeoParquet** file using GDAL (`ogr2ogr`), creating Point geometries from `BEGIN_LAT` / `BEGIN_LON` in WGS 84 (EPSG:4326).
4. **Builds** a single multi-layer **GeoPackage** (`.gpkg`) for easy visualization in QGIS.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/kollaSrinivas369/noaa-storms-pipeline.git
cd noaa-storms-pipeline

# Run the pipeline
bash process_storm_data.sh
```

## Prerequisites

| Tool | Purpose | Check |
|------|---------|-------|
| **Bash** | Shell | `bash --version` |
| **curl** | Download files | `curl --version` |
| **gunzip** | Decompress `.gz` | `gunzip --help` |
| **GDAL/OGR** | Geospatial conversion | `ogr2ogr --version` |

> **Note**: GDAL must be compiled with Parquet driver support. Verify with:
> ```bash
> ogr2ogr --formats | grep -i parquet
> ```

## Outputs

After a successful run, the `./data` directory will contain:

| File | Description |
|------|-------------|
| `StormEvents_details_dYYYY.csv` | Decompressed source data |
| `storm_events_YYYY.parquet` | Cloud-native spatial GeoParquet |
| `storm_events_2022_2024.gpkg` | QGIS-ready GeoPackage (3 layers) |

## Documentation

See [PIPELINE.md](PIPELINE.md) for detailed pipeline architecture, stage-by-stage breakdown, and troubleshooting instructions.

## Maintenance

NOAA periodically updates file creation dates (`_cDATE` suffix). If downloads fail with 404:

1. Check the [NOAA FTP directory](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/) for current filenames.
2. Update the `CREATION_DATES` array in `process_storm_data.sh`.

## License

MIT
