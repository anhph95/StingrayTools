#!/usr/bin/env python3
from __future__ import annotations

import argparse
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from stingray.utils.gridding import assign_time_bins
from stingray.utils.temporal import convert_timestamp
from stingray.stats.poisson import add_poisson_ci
from stingray.logging.setup import log_command_options, setup_logging

ORIGIN = datetime(1904, 1, 1)
logger = logging.getLogger(__name__)


def require_columns(df: pd.DataFrame, columns: list[str], source: Path) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        missing_str = ", ".join(missing)
        raise ValueError(f"{source} is missing required columns: {missing_str}")


def clean_yaml_value(value: str) -> str:
    value = value.strip()
    if value.startswith(("'", '"')) and value.endswith(("'", '"')):
        value = value[1:-1]
    return value


def load_class_names(data_yaml: Path) -> dict[int, str]:
    """Read the simple YOLO data.yaml names section without requiring PyYAML."""
    lines = data_yaml.read_text(encoding="utf-8").splitlines()
    names_started = False
    names_by_id: dict[int, str] = {}
    names_list: list[str] = []

    for raw_line in lines:
        line_without_comment = raw_line.split("#", 1)[0].rstrip()
        stripped = line_without_comment.strip()
        if not stripped:
            continue

        if not names_started:
            if stripped == "names:":
                names_started = True
            continue

        if not raw_line.startswith((" ", "\t", "-")) and stripped != "names:":
            break

        list_match = re.match(r"^-\s*(.+)$", stripped)
        if list_match:
            names_list.append(clean_yaml_value(list_match.group(1)))
            continue

        dict_match = re.match(r"^(\d+)\s*:\s*(.+)$", stripped)
        if dict_match:
            class_id = int(dict_match.group(1))
            names_by_id[class_id] = clean_yaml_value(dict_match.group(2))

    if names_by_id:
        return names_by_id
    if names_list:
        return dict(enumerate(names_list))
    raise ValueError(f"{data_yaml} does not contain a supported names section.")


@dataclass(frozen=True)
class Config:
    yolo_csv: Path
    data_yaml: Path
    sensor_csv: Path
    media_csv: Path
    out_csv: Path
    score_thresh: float
    bin_width: float
    image_width: int
    image_height: int
    um_per_pixel: float
    volume_per_frame: float
    add_ci: bool


def process(config: Config) -> pd.DataFrame:
    """Convert YOLO detections into time-binned abundance merged onto sensor data."""
    logger.info("Loading YOLO CSV...")
    df = pd.read_csv(config.yolo_csv, sep=" ")
    require_columns(
        df,
        [
            "filename",
            "class_id",
            "x_center",
            "y_center",
            "width",
            "height",
            "confidence",
        ],
        config.yolo_csv,
    )

    logger.info("Loading class dictionary...")
    class_dict = load_class_names(config.data_yaml)

    df[["media", "frame"]] = df["filename"].str.extract(r"^(.*)_(\d+)\.txt$")
    df["frame"] = df["frame"].astype(int)

    df["score"] = df["confidence"]
    df["x"] = df["x_center"]
    df["y"] = df["y_center"]
    df["class_idx"] = df["class_id"].astype(int)
    df["class"] = df["class_idx"].map(class_dict)
    if df["class"].isna().any():
        missing_ids = sorted(df.loc[df["class"].isna(), "class_idx"].unique())
        raise ValueError(f"Class IDs missing from data.yaml names section: {missing_ids}")

    df["area"] = (
        df["width"]
        * df["height"]
        * config.image_width
        * config.image_height
        * config.um_per_pixel
        * 0.001
    )
    df["size"] = (
        np.maximum(
            df["width"] * config.image_width,
            df["height"] * config.image_height,
        )
        * config.um_per_pixel
        * 0.001
    )

    df = (
        df.loc[df["score"] >= config.score_thresh]
        .sort_values(["media", "frame", "x", "y"])
        .reset_index(drop=True)
    )

    df_count = (
        df.groupby(["media", "frame", "class"])
        .size()
        .unstack(fill_value=0)
        .reset_index()
    )
    data_cols = df_count.columns.difference(
        ["media", "frame", "total_abundance"]
    ).to_list()

    logger.info("Loading sensor + media CSVs...")
    sensor_df = pd.read_csv(config.sensor_csv)
    media_df = pd.read_csv(config.media_csv)
    require_columns(sensor_df, ["times"], config.sensor_csv)
    require_columns(media_df, ["times", "media", "frame"], config.media_csv)

    abundance_df = media_df[["times", "media", "frame"]].merge(
        df_count,
        on=["media", "frame"],
        how="left",
    )
    abundance_df[data_cols] = abundance_df[data_cols].fillna(0)

    sensor_df["times"] = pd.to_datetime(sensor_df["times"], errors="coerce")
    abundance_df["times"] = pd.to_datetime(abundance_df["times"], errors="coerce")

    sensor_df = sensor_df.sort_values("times")
    abundance_df = abundance_df.sort_values("times")

    sensor_df["timestamp"] = (sensor_df["times"] - ORIGIN).dt.total_seconds()
    abundance_df["timestamp"] = (abundance_df["times"] - ORIGIN).dt.total_seconds()

    abundance_df["timestamp"] = assign_time_bins(
        abundance_df["timestamp"].to_numpy(),
        bin_width=config.bin_width,
        grid_start=sensor_df["timestamp"].min(),
        grid_end=sensor_df["timestamp"].max(),
    )
    abundance_df["times"] = pd.to_datetime(
        convert_timestamp(abundance_df["timestamp"])[0]
    )

    df_bin = abundance_df.groupby("times", as_index=False).agg(
        {
            "times": "first",
            "media": lambda x: x.dropna().iloc[0] if not x.dropna().empty else np.nan,
            "frame": lambda x: x.dropna().iloc[0] if not x.dropna().empty else np.nan,
            **{col: "mean" for col in data_cols},
        }
    )

    frame_num = abundance_df.groupby("times").size().rename("frame_num").reset_index()
    df_bin = df_bin.merge(frame_num, on="times", how="left")

    scale_factor = 1 / config.volume_per_frame
    df_bin[data_cols] = df_bin[data_cols] * scale_factor
    df_bin["total_abundance"] = df_bin[data_cols].sum(axis=1)

    if config.add_ci:
        logger.info("Computing Poisson confidence intervals...")
        raw_counts_by_bin = (
            abundance_df.groupby("times")[data_cols]
            .sum()
            .reset_index()
            .set_index("times")
            .reindex(df_bin["times"])
            .fillna(0)
            .astype(int)
        )
        df_bin = add_poisson_ci(
            df_bin,
            raw_counts_by_bin,
            data_cols,
            scale_factor,
        )

    df_merged = (
        sensor_df.merge(
            df_bin.drop(columns=["media", "frame"], errors="ignore"),
            on="times",
            how="left",
        )
        .sort_values("times")
        .reset_index(drop=True)
    )

    logger.info("Writing output: %s", config.out_csv)
    config.out_csv.parent.mkdir(parents=True, exist_ok=True)
    df_merged.to_csv(config.out_csv, index=False)
    logger.info("Done")

    return df_merged


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert YOLO shadowgraph detections to time-binned abundance."
    )

    required = parser.add_argument_group("required file paths")
    required.add_argument(
        "--yolo-csv",
        required=True,
        help="YOLO concatenated results CSV, e.g. concatenated_results.csv",
    )
    required.add_argument(
        "--data-yaml",
        required=True,
        help="YOLO data.yaml file, e.g. training_data_v3/data.yaml",
    )
    required.add_argument(
        "--sensor-csv",
        required=True,
        help="Sensor CSV to merge onto, e.g. dash_data/data/stingray_timebinned/20250424_AR88.csv",
    )
    required.add_argument(
        "--media-csv",
        required=True,
        help="Media/frame timestamp CSV, e.g. media_list/ISIIS1/20250418_AR88.csv",
    )
    required.add_argument(
        "--out-csv",
        required=True,
        help="Output CSV path, e.g. shadowgraph_concentration.csv",
    )

    options = parser.add_argument_group("processing options")
    options.add_argument(
        "--work-dir",
        default=".",
        help="Workspace whose logs directory receives command logs.",
    )
    options.add_argument("--score-thresh", type=float, required=True)
    options.add_argument(
        "--bin-width",
        type=float,
        required=True,
        help="Time-bin width in seconds",
    )
    options.add_argument("--image-width", type=int, required=True)
    options.add_argument("--image-height", type=int, required=True)
    options.add_argument("--um-per-pixel", type=float, required=True)
    options.add_argument("--volume-per-frame", type=float, required=True)
    options.add_argument("--add-ci", action="store_true", help="Add Poisson confidence intervals")
    options.add_argument(
        "--no-file-log",
        action="store_true",
        help="Disable Stingray log files and write logs only to the console.",
    )

    return parser.parse_args(argv)


def config_from_args(args: argparse.Namespace) -> Config:
    return Config(
        yolo_csv=Path(os.path.expanduser(args.yolo_csv)),
        data_yaml=Path(os.path.expanduser(args.data_yaml)),
        sensor_csv=Path(os.path.expanduser(args.sensor_csv)),
        media_csv=Path(os.path.expanduser(args.media_csv)),
        out_csv=Path(os.path.expanduser(args.out_csv)),
        score_thresh=args.score_thresh,
        bin_width=args.bin_width,
        image_width=args.image_width,
        image_height=args.image_height,
        um_per_pixel=args.um_per_pixel,
        volume_per_frame=args.volume_per_frame,
        add_ci=args.add_ci,
    )


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    work_dir = Path(args.work_dir).expanduser().resolve()
    setup_logging(
        log_dir=work_dir / "logs",
        name="stingray_images_abundance",
        file=not args.no_file_log,
    )
    log_command_options(logger, args)
    config = config_from_args(args)
    process(config)


if __name__ == "__main__":
    main()
