#!/usr/bin/env bash
# process_storm_data.sh
# ---------------------------------------------------------------------------
# Downloads NOAA Storm Events "details" CSVs for 2022–2024, decompresses
# them, and converts each to a spatial GeoParquet file using ogr2ogr.
#
# The NOAA CSVs contain BEGIN_LAT and BEGIN_LON columns. ogr2ogr uses these
# to create Point geometries in EPSG:4326 (WGS 84).
#
# Inputs:   None — downloads from NOAA public FTP.
# Outputs:  For each year in data/:
#             - StormEvents_details_dYYYY.csv       (decompressed CSV)
#             - storm_events_YYYY.parquet            (spatial Parquet)
#
# Prerequisites:
#   - GDAL installed (ogr2ogr --version to check)
#   - Internet connection
#
# Usage:    bash process_storm_data.sh
# ---------------------------------------------------------------------------

set -e  # Stop on first error so students see exactly which step failed

# --- Configuration --------------------------------------------------------

DATA_DIR="./data"
BASE_URL="https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles"

# NOAA Storm Events "details" files — one per year
# Filename pattern: StormEvents_details-ftp_v1.0_dYYYY_cDATE.csv.gz
# The "c" date is when NOAA last rebuilt the file; it changes periodically.
# If a download fails with 404, visit the URL below and find the current filename:
#   https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/
YEARS=(2022 2023 2024)
declare -A CREATION_DATES=(
    [2022]="20260625"
    [2023]="20260323"
    [2024]="20260421"
)

# --- Create data directory ------------------------------------------------
mkdir -p "$DATA_DIR"
echo "📁 Data directory: $DATA_DIR"

# --- Download, decompress, and convert each year -------------------------

for YEAR in "${YEARS[@]}"; do
    GZ_FILE="StormEvents_details-ftp_v1.0_d${YEAR}_c${CREATION_DATES[$YEAR]}.csv.gz"
    CSV_FILE="StormEvents_details_d${YEAR}.csv"
    PARQUET_FILE="storm_events_${YEAR}.parquet"

    echo ""
    echo "================================================================"
    echo "  Processing ${YEAR}"
    echo "================================================================"

    # --- Download ---------------------------------------------------------
    if [ -f "$DATA_DIR/$GZ_FILE" ]; then
        echo "⏭️  Already downloaded: $GZ_FILE"
    else
        echo "⬇️  Downloading $GZ_FILE ..."
        curl -L --progress-bar -o "$DATA_DIR/$GZ_FILE" "$BASE_URL/$GZ_FILE"

        # Guard against failed downloads (HTML error pages are small)
        FILE_SIZE=$(wc -c < "$DATA_DIR/$GZ_FILE" | tr -d ' ')
        if [ "$FILE_SIZE" -lt 10000 ]; then
            echo "❌ ERROR: $GZ_FILE is only $FILE_SIZE bytes — download likely failed."
            echo "   Check that the filename is current at:"
            echo "   $BASE_URL/"
            rm "$DATA_DIR/$GZ_FILE"
            exit 1
        fi
        echo "✅ Downloaded ($FILE_SIZE bytes compressed)"
    fi

    # --- Decompress -------------------------------------------------------
    if [ -f "$DATA_DIR/$CSV_FILE" ]; then
        echo "⏭️  Already decompressed: $CSV_FILE"
    else
        echo "📦 Decompressing..."
        # gunzip deletes the .gz by default; -k keeps the original
        gunzip -k "$DATA_DIR/$GZ_FILE"
        # The decompressed file keeps the original long name; rename for clarity
        mv "$DATA_DIR/StormEvents_details-ftp_v1.0_d${YEAR}_c${CREATION_DATES[$YEAR]}.csv" \
           "$DATA_DIR/$CSV_FILE"
        echo "✅ Decompressed to $CSV_FILE"
    fi

    # --- Show basic stats -------------------------------------------------
    ROW_COUNT=$(($(wc -l < "$DATA_DIR/$CSV_FILE" | tr -d ' ') - 1))
    CSV_SIZE=$(wc -c < "$DATA_DIR/$CSV_FILE" | tr -d ' ')
    echo "📊 $CSV_FILE: $ROW_COUNT rows, $CSV_SIZE bytes"

    # Preview columns (first time only)
    if [ "$YEAR" = "${YEARS[0]}" ]; then
        echo ""
        echo "📋 Column names:"
        head -n 1 "$DATA_DIR/$CSV_FILE" | tr ',' '\n' | head -20
        echo "   ... ($(head -n 1 "$DATA_DIR/$CSV_FILE" | tr ',' '\n' | wc -l | tr -d ' ') columns total)"
    fi

    # --- Convert to spatial GeoParquet ------------------------------------
    echo ""
    echo "🔄 Converting to GeoParquet with point geometry from BEGIN_LAT/BEGIN_LON..."
    # -oo AUTODETECT_TYPE=YES  → detect numeric vs string columns
    # -oo X_POSSIBLE_NAMES     → column to use for longitude (X)
    # -oo Y_POSSIBLE_NAMES     → column to use for latitude (Y)
    # -a_srs EPSG:4326         → assign WGS84 coordinate system
    # Remove existing file first — Parquet driver can't overwrite in place
    rm -f "$DATA_DIR/$PARQUET_FILE"
    ogr2ogr \
        -f "Parquet" \
        "$DATA_DIR/$PARQUET_FILE" \
        "$DATA_DIR/$CSV_FILE" \
        -oo AUTODETECT_TYPE=YES \
        -oo X_POSSIBLE_NAMES=BEGIN_LON \
        -oo Y_POSSIBLE_NAMES=BEGIN_LAT \
        -a_srs EPSG:4326

    PARQUET_SIZE=$(wc -c < "$DATA_DIR/$PARQUET_FILE" | tr -d ' ')
    echo "✅ Created $PARQUET_FILE ($PARQUET_SIZE bytes)"

done

# --- Build a GeoPackage for visual inspection in QGIS --------------------
# GeoPackage supports multiple layers in one file, so we add each year as
# its own layer. Students can open this single file in QGIS and toggle
# years on/off.
GPKG_FILE="storm_events_2022_2024.gpkg"
echo ""
echo "📦 Building GeoPackage for QGIS ($GPKG_FILE)..."
rm -f "$DATA_DIR/$GPKG_FILE"

for YEAR in "${YEARS[@]}"; do
    PARQUET_FILE="storm_events_${YEAR}.parquet"
    echo "   Adding layer: storm_events_${YEAR}"
    ogr2ogr \
        -f "GPKG" \
        "$DATA_DIR/$GPKG_FILE" \
        "$DATA_DIR/$PARQUET_FILE" \
        -nln "storm_events_${YEAR}" \
        -update -append
done

GPKG_SIZE=$(wc -c < "$DATA_DIR/$GPKG_FILE" | tr -d ' ')
echo "✅ Created $GPKG_FILE ($((GPKG_SIZE / 1048576)) MB, ${#YEARS[@]} layers)"

# --- Final summary --------------------------------------------------------
echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo ""
echo "Files in $DATA_DIR:"
ls -lh "$DATA_DIR"/*.parquet "$DATA_DIR"/*.gpkg
echo ""

# Verify one parquet file with ogrinfo
echo "🔍 Verifying storm_events_${YEARS[0]}.parquet with ogrinfo:"
ogrinfo -so "$DATA_DIR/storm_events_${YEARS[0]}.parquet" "storm_events_${YEARS[0]}"
echo ""

echo "🔍 Layers in $GPKG_FILE:"
ogrinfo "$DATA_DIR/$GPKG_FILE"
echo ""
echo "🎉 All done! Three years of NOAA Storm Events data ready."
echo "   Open $DATA_DIR/$GPKG_FILE in QGIS to explore the data visually."
