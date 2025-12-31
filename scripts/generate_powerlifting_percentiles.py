#!/usr/bin/env python3
"""
Generate percentile data from OpenPowerlifting database.

This script downloads and processes the OpenPowerlifting CSV data to create
compact percentile lookup tables for use in the iOS app.

Usage:
    python3 generate_powerlifting_percentiles.py

Output:
    ../Resources/powerlifting_percentiles.json

Data source: https://openpowerlifting.gitlab.io/opl-csv/
"""

import json
import os
import ssl
import sys
import urllib.request
import zipfile
from collections import defaultdict
from io import BytesIO
from pathlib import Path

import csv

# Create SSL context that doesn't verify certificates (for macOS compatibility)
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# OpenPowerlifting data URL
OPL_URL = "https://openpowerlifting.gitlab.io/opl-csv/files/openpowerlifting-latest.zip"

# Weight classes (in kg) - IPF standard classes
MALE_WEIGHT_CLASSES = [59, 66, 74, 83, 93, 105, 120, 140]  # 140+ is SHW
FEMALE_WEIGHT_CLASSES = [47, 52, 57, 63, 69, 76, 84, 100]  # 100+ is SHW

# Age brackets
AGE_BRACKETS = [
    (0, 23, "junior"),
    (24, 39, "open"),
    (40, 49, "masters_40"),
    (50, 59, "masters_50"),
    (60, 69, "masters_60"),
    (70, 999, "masters_70"),
]

# Percentiles to calculate
PERCENTILES = [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]


def download_data() -> str:
    """Download and extract the OpenPowerlifting CSV."""
    print("Downloading OpenPowerlifting data...")
    print("(This may take a few minutes - the file is ~100MB)")
    
    # Download the zip file
    with urllib.request.urlopen(OPL_URL, context=ssl_context) as response:
        zip_data = BytesIO(response.read())
    
    print("Extracting...")
    
    # Extract the CSV
    with zipfile.ZipFile(zip_data) as zf:
        # Find the main CSV file
        csv_files = [f for f in zf.namelist() if f.endswith('.csv') and 'openpowerlifting' in f.lower()]
        if not csv_files:
            # Try to find any CSV
            csv_files = [f for f in zf.namelist() if f.endswith('.csv')]
        
        if not csv_files:
            raise ValueError("No CSV file found in the archive")
        
        csv_file = csv_files[0]
        print(f"Processing {csv_file}...")
        
        with zf.open(csv_file) as f:
            return f.read().decode('utf-8')


def get_weight_class(bodyweight: float, is_male: bool) -> str | None:
    """Get the weight class for a given bodyweight."""
    classes = MALE_WEIGHT_CLASSES if is_male else FEMALE_WEIGHT_CLASSES
    
    for wc in classes:
        if bodyweight <= wc:
            return str(wc)
    
    # Super heavyweight
    return f"{classes[-1]}+"


def get_age_bracket(age: float) -> str | None:
    """Get the age bracket for a given age."""
    for min_age, max_age, bracket in AGE_BRACKETS:
        if min_age <= age <= max_age:
            return bracket
    return None


def calculate_percentile(values: list[float], percentile: int) -> float:
    """Calculate the given percentile from a list of values."""
    if not values:
        return 0.0
    
    sorted_values = sorted(values)
    index = (len(sorted_values) - 1) * percentile / 100
    lower = int(index)
    upper = lower + 1
    
    if upper >= len(sorted_values):
        return sorted_values[-1]
    
    weight = index - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def process_data(csv_content: str) -> dict:
    """Process the CSV data and generate percentile tables."""
    
    # Data structure: {sex: {weight_class: {age_bracket: {lift: [values]}}}}
    data: dict[str, dict[str, dict[str, dict[str, list[float]]]]] = {
        "male": defaultdict(lambda: defaultdict(lambda: defaultdict(list))),
        "female": defaultdict(lambda: defaultdict(lambda: defaultdict(list))),
    }
    
    # Also collect "all ages" data
    all_ages_data: dict[str, dict[str, dict[str, list[float]]]] = {
        "male": defaultdict(lambda: defaultdict(list)),
        "female": defaultdict(lambda: defaultdict(list)),
    }
    
    reader = csv.DictReader(csv_content.splitlines())
    
    row_count = 0
    included_count = 0
    
    for row in reader:
        row_count += 1
        if row_count % 100000 == 0:
            print(f"  Processed {row_count:,} rows...")
        
        # Filter criteria
        # - Must have bodyweight
        # - Must have at least one lift
        # - Prefer tested federations, but include all for larger sample
        
        try:
            bodyweight_str = row.get('BodyweightKg', '')
            if not bodyweight_str:
                continue
            bodyweight = float(bodyweight_str)
            
            sex = row.get('Sex', '').lower()
            if sex not in ('m', 'f'):
                continue
            
            is_male = sex == 'm'
            sex_key = "male" if is_male else "female"
            
            weight_class = get_weight_class(bodyweight, is_male)
            if not weight_class:
                continue
            
            # Get age bracket (optional)
            age_str = row.get('Age', '')
            age_bracket = None
            if age_str:
                try:
                    age = float(age_str)
                    age_bracket = get_age_bracket(age)
                except ValueError:
                    pass
            
            # Get best lifts (in kg)
            squat = row.get('Best3SquatKg', '')
            bench = row.get('Best3BenchKg', '')
            deadlift = row.get('Best3DeadliftKg', '')
            
            # Store valid lifts
            lifts_added = False
            
            if squat and not squat.startswith('-'):
                try:
                    squat_val = float(squat)
                    if squat_val > 0:
                        all_ages_data[sex_key][weight_class]["squat"].append(squat_val)
                        if age_bracket:
                            data[sex_key][weight_class][age_bracket]["squat"].append(squat_val)
                        lifts_added = True
                except ValueError:
                    pass
            
            if bench and not bench.startswith('-'):
                try:
                    bench_val = float(bench)
                    if bench_val > 0:
                        all_ages_data[sex_key][weight_class]["bench"].append(bench_val)
                        if age_bracket:
                            data[sex_key][weight_class][age_bracket]["bench"].append(bench_val)
                        lifts_added = True
                except ValueError:
                    pass
            
            if deadlift and not deadlift.startswith('-'):
                try:
                    deadlift_val = float(deadlift)
                    if deadlift_val > 0:
                        all_ages_data[sex_key][weight_class]["deadlift"].append(deadlift_val)
                        if age_bracket:
                            data[sex_key][weight_class][age_bracket]["deadlift"].append(deadlift_val)
                        lifts_added = True
                except ValueError:
                    pass
            
            if lifts_added:
                included_count += 1
                
        except (ValueError, KeyError):
            continue
    
    print(f"Processed {row_count:,} total rows, included {included_count:,} lifters")
    
    # Generate percentile tables
    result = {
        "metadata": {
            "source": "OpenPowerlifting",
            "url": "https://www.openpowerlifting.org",
            "lifter_count": included_count,
            "description": "Percentile data from competitive powerlifting meets",
            "units": "kg",
            "percentiles": PERCENTILES,
        },
        "male": {},
        "female": {},
    }
    
    for sex_key in ["male", "female"]:
        weight_classes = MALE_WEIGHT_CLASSES if sex_key == "male" else FEMALE_WEIGHT_CLASSES
        
        for wc in weight_classes:
            wc_str = str(wc)
            wc_plus = f"{wc}+"
            
            for weight_class_key in [wc_str, wc_plus]:
                if weight_class_key not in all_ages_data[sex_key]:
                    continue
                
                wc_data = {
                    "all_ages": {},
                    "by_age": {},
                }
                
                # All ages percentiles
                for lift in ["squat", "bench", "deadlift"]:
                    values = all_ages_data[sex_key][weight_class_key][lift]
                    if len(values) >= 50:  # Minimum sample size
                        wc_data["all_ages"][lift] = {
                            "count": len(values),
                            "percentiles": {
                                str(p): round(calculate_percentile(values, p), 1)
                                for p in PERCENTILES
                            }
                        }
                
                # By age bracket
                for age_bracket in [ab[2] for ab in AGE_BRACKETS]:
                    if weight_class_key not in data[sex_key]:
                        continue
                    if age_bracket not in data[sex_key][weight_class_key]:
                        continue
                    
                    age_data = {}
                    for lift in ["squat", "bench", "deadlift"]:
                        values = data[sex_key][weight_class_key][age_bracket][lift]
                        if len(values) >= 30:  # Minimum sample size for age brackets
                            age_data[lift] = {
                                "count": len(values),
                                "percentiles": {
                                    str(p): round(calculate_percentile(values, p), 1)
                                    for p in PERCENTILES
                                }
                            }
                    
                    if age_data:
                        wc_data["by_age"][age_bracket] = age_data
                
                if wc_data["all_ages"]:
                    result[sex_key][weight_class_key] = wc_data
    
    return result


def main():
    # Check if we should use cached data
    script_dir = Path(__file__).parent
    output_path = script_dir.parent / "Resources" / "powerlifting_percentiles.json"
    
    print("=" * 60)
    print("OpenPowerlifting Percentile Generator")
    print("=" * 60)
    print()
    
    try:
        csv_content = download_data()
    except Exception as e:
        print(f"Error downloading data: {e}")
        print("\nYou can manually download from:")
        print(OPL_URL)
        sys.exit(1)
    
    print("\nCalculating percentiles...")
    result = process_data(csv_content)
    
    # Save to JSON
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"\nSaved to: {output_path}")
    print(f"File size: {output_path.stat().st_size / 1024:.1f} KB")
    
    # Print summary
    print("\nSummary:")
    for sex in ["male", "female"]:
        wc_count = len(result[sex])
        print(f"  {sex.capitalize()}: {wc_count} weight classes")


if __name__ == "__main__":
    main()

