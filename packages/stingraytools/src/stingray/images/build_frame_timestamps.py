#!/usr/bin/env python3
import os
import cv2
import logging
import time
import argparse
import pandas as pd
from pathlib import Path
from datetime import datetime, timedelta
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from stingray.logging.setup import log_command_options, setup_logging

logger = logging.getLogger(__name__)
# =======================
# ====== DEFAULTS ======
# =======================
SLURM_CPUS = int(os.getenv("SLURM_CPUS_PER_TASK", os.cpu_count() or 1))
# Fast mode is mostly metadata + a few frame reads, so do not over-allocate
DEFAULT_MAX_WORKERS = max(1, min(8, SLURM_CPUS - 1 if SLURM_CPUS > 1 else 1))
DEFAULT_SUFFIXES = {".avi", ".mp4", ".png", ".tiff"}
FAST_SAMPLE_COUNT = 5
# Prevent thread oversubscription inside OpenCV / BLAS
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
try:
    cv2.setNumThreads(1)
except Exception:
    pass
# =======================
# ====== HELPERS ========
# =======================
def log(msg):
    logger.info(msg)
def normalize_suffixes(suffixes):
    return {
        s.lower() if str(s).startswith(".") else f".{str(s).lower()}"
        for s in suffixes
    }
def list_files(directory):
    file_list = []
    with os.scandir(directory) as it:
        for entry in it:
            if entry.is_file():
                file_list.append(entry.path)
            elif entry.is_dir():
                file_list.extend(list_files(entry.path))
    return file_list
def parse_media_time(media_name):
    try:
        return datetime.strptime(
            media_name.split("-")[-1].rstrip("Z"),
            "%Y%m%dT%H%M%S.%f",
        )
    except ValueError:
        return pd.NaT
def get_file_size(file_path):
    try:
        return (file_path, os.stat(file_path).st_size)
    except FileNotFoundError:
        return (file_path, None)
    except Exception:
        return (file_path, None)
IMAGE_SUFFIXES = {".png", ".tiff", ".tif", ".jpg", ".jpeg"}


def valid_fps(value):
    return value is not None and pd.notna(value) and value > 0


def get_media_metadata(file_path):
    suffix = Path(file_path).suffix.lower()
    if suffix in IMAGE_SUFFIXES:
        return {
            "frame_count": 1,
            "fps": None,
        }
    cap = cv2.VideoCapture(file_path)
    if not cap.isOpened():
        return {
            "frame_count": None,
            "fps": None,
        }
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not valid_fps(fps):
        fps = None
    count = 0
    while True:
        ret, _ = cap.read()
        if not ret:
            break
        count += 1
    cap.release()
    return {
        "frame_count": count,
        "fps": fps,
    }


def metadata_values_agree(values):
    valid_values = [value for value in values if value is not None and pd.notna(value)]
    if len(valid_values) != len(values):
        return False
    if not valid_values:
        return False
    return len(set(valid_values)) == 1


def fps_values_agree(values):
    valid_values = [value for value in values if valid_fps(value)]
    if len(valid_values) != len(values):
        return False
    if not valid_values:
        return False
    rounded = {round(float(value), 6) for value in valid_values}
    return len(rounded) == 1


def build_base_dataframe(media_dir, max_workers, suffixes=None, file_limit=None):
    file_paths = list_files(media_dir)
    allowed = normalize_suffixes(suffixes) if suffixes else DEFAULT_SUFFIXES
    file_paths = [f for f in file_paths if Path(f).suffix.lower() in allowed]
    if file_limit:
        file_paths = file_paths[:file_limit]
    if not file_paths:
        return pd.DataFrame()
    suffix_counts = {}
    for f in file_paths:
        suf = Path(f).suffix.lower()
        suffix_counts[suf] = suffix_counts.get(suf, 0) + 1
    log(f"Files found after suffix filter: {len(file_paths):,}")
    log(f"Suffix counts: {suffix_counts}")
    log(f"Thread workers for stat step: {max_workers}")
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        file_list_with_sizes = list(
            tqdm(
                executor.map(get_file_size, file_paths),
                total=len(file_paths),
                desc=f"Stat {Path(media_dir).name}",
            )
        )
    df = pd.DataFrame(file_list_with_sizes, columns=["media_path", "media_size"])
    df["media"] = df["media_path"].apply(lambda x: Path(x).stem)
    df["suffix"] = df["media_path"].apply(lambda x: Path(x).suffix.lower())
    df["media_time"] = df["media"].apply(parse_media_time)
    return df


def sample_group_paths(group, sample_count=FAST_SAMPLE_COUNT):
    group = group.sort_values(["media_time", "media_path"], na_position="last")
    n = len(group)
    if n <= sample_count:
        return group["media_path"].tolist()
    if sample_count == 1:
        positions = [0]
    else:
        positions = [
            round(i * (n - 1) / (sample_count - 1))
            for i in range(sample_count)
        ]
    positions = sorted(set(positions))
    return group.iloc[positions]["media_path"].tolist()


def assign_media_metadata_fast(df, max_workers):
    df = df.copy()
    valid_mask = df["media_size"].notna()
    if not valid_mask.any():
        log("No valid file sizes found.")
        df["frame_count"] = None
        df["fps"] = None
        return df

    df["frame_count"] = None
    df["fps"] = None
    groups = list(df.loc[valid_mask].groupby(["suffix", "media_size"], dropna=False))
    log(f"Fast mode file-size groups: {len(groups):,}")

    for (suffix, media_size), group in groups:
        group_index = group.index
        sample_paths = sample_group_paths(group)
        log(
            f"Group suffix={suffix} size={media_size} files={len(group):,} "
            f"samples={len(sample_paths)}"
        )
        sample_metadata = [get_media_metadata(path) for path in sample_paths]
        sample_counts = [item["frame_count"] for item in sample_metadata]
        sample_fps = [item["fps"] for item in sample_metadata]

        if suffix in IMAGE_SUFFIXES and metadata_values_agree(sample_counts):
            frame_count = sample_counts[0]
            df.loc[group_index, "frame_count"] = frame_count
            df.loc[group_index, "fps"] = None
            log(
                f"Assigned frame_count={frame_count} to "
                f"{len(group):,} files in group."
            )
            continue

        if metadata_values_agree(sample_counts) and fps_values_agree(sample_fps):
            frame_count = sample_counts[0]
            fps = sample_fps[0]
            df.loc[group_index, "frame_count"] = frame_count
            df.loc[group_index, "fps"] = fps
            log(
                f"Assigned frame_count={frame_count}, fps={fps:.6g} to "
                f"{len(group):,} files in group."
            )
            continue

        log(
            "Measuring all files in group; sampled metadata: "
            f"{sample_metadata}"
        )
        workers = max(1, min(max_workers, len(group)))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            results = list(
                tqdm(
                    executor.map(get_media_metadata, group["media_path"].tolist()),
                    total=len(group),
                    desc=f"Metadata {suffix} {media_size}",
                )
            )
        df.loc[group_index, "frame_count"] = [item["frame_count"] for item in results]
        df.loc[group_index, "fps"] = [item["fps"] for item in results]
        count_summary = pd.Series([item["frame_count"] for item in results]).value_counts(dropna=False).to_dict()
        fps_summary = pd.Series([item["fps"] for item in results]).value_counts(dropna=False).to_dict()
        log(f"Measured group frame counts: {count_summary}")
        log(f"Measured group FPS values: {fps_summary}")

    missing_counts = int(df["frame_count"].isna().sum())
    if missing_counts:
        log(f"Files with missing frame_count: {missing_counts:,}")
    video_mask = ~df["suffix"].isin(IMAGE_SUFFIXES)
    missing_fps = int((video_mask & df["fps"].isna()).sum())
    if missing_fps:
        log(f"Video files with missing fps: {missing_fps:,}")
    fps_summary = df.loc[video_mask, "fps"].value_counts(dropna=False).to_dict()
    if fps_summary:
        log(f"FPS summary: {fps_summary}")
    return df


def expand_frames(df):
    df = df.copy()
    before_rows = len(df)
    df = df.dropna(subset=["frame_count"])
    df = df[df["frame_count"] > 0].copy()
    video_mask = ~df["suffix"].isin(IMAGE_SUFFIXES)
    df = df[(~video_mask) | df["fps"].apply(valid_fps)].copy()
    log(f"Files retained for frame expansion: {len(df):,} / {before_rows:,}")
    if df.empty:
        return df
    df["frame_count"] = df["frame_count"].astype(int)
    total_frames = int(df["frame_count"].sum())
    log(f"Total frames to expand: {total_frames:,}")
    df = df.loc[df.index.repeat(df["frame_count"])].copy()
    df["frame"] = df.groupby("media_path").cumcount()
    elapsed_seconds = pd.Series(0.0, index=df.index)
    fps_mask = df["fps"].apply(valid_fps)
    elapsed_seconds.loc[fps_mask] = (
        df.loc[fps_mask, "frame"].astype(float) / df.loc[fps_mask, "fps"].astype(float)
    )
    df["times"] = df["media_time"] + pd.to_timedelta(elapsed_seconds, unit="s")
    return df
def process_media_details(file_path):
    media_name = Path(file_path).stem
    base_time = parse_media_time(media_name)
    suffix = Path(file_path).suffix.lower()
    if suffix in {".png", ".tiff", ".tif", ".jpg", ".jpeg"}:
        return [{
            "media_path": file_path,
            "media": media_name,
            "media_time": base_time,
            "frame": 0,
            "times": base_time if pd.notna(base_time) else None,
            "status": "ok",
        }]
    cap = cv2.VideoCapture(file_path)
    if not cap.isOpened():
        return [{
            "media_path": file_path,
            "media": media_name,
            "media_time": base_time,
            "frame": None,
            "times": None,
            "status": "bad_file",
        }]
    records = []
    frame_idx = 0
    while True:
        ret = cap.grab()
        if not ret:
            break
        ms = cap.get(cv2.CAP_PROP_POS_MSEC)
        if ms <= 0:
            records.append({
                "media_path": file_path,
                "media": media_name,
                "media_time": base_time,
                "frame": frame_idx,
                "times": None,
                "status": "bad_frame",
            })
        else:
            timestamp = base_time + timedelta(milliseconds=ms) if pd.notna(base_time) else None
            records.append({
                "media_path": file_path,
                "media": media_name,
                "media_time": base_time,
                "frame": frame_idx,
                "times": timestamp,
                "status": "ok",
            })
        frame_idx += 1
    cap.release()
    return records
def extract_details_dataframe(media_dir, max_workers, suffixes=None, file_limit=None):
    file_paths = list_files(media_dir)
    allowed = normalize_suffixes(suffixes) if suffixes else DEFAULT_SUFFIXES
    file_paths = [f for f in file_paths if Path(f).suffix.lower() in allowed]
    if file_limit:
        file_paths = file_paths[:file_limit]
    if not file_paths:
        return pd.DataFrame()
    suffix_counts = {}
    for f in file_paths:
        suf = Path(f).suffix.lower()
        suffix_counts[suf] = suffix_counts.get(suf, 0) + 1
    log(f"Files found after suffix filter: {len(file_paths):,}")
    log(f"Suffix counts: {suffix_counts}")
    log(f"Running full per-frame timestamp extraction for {len(file_paths):,} files")
    log(f"Process workers for details mode: {max_workers}")
    all_records = []
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        for records in tqdm(
            executor.map(process_media_details, file_paths),
            total=len(file_paths),
            desc="Details extraction",
        ):
            all_records.extend(records)
    df = pd.DataFrame(all_records)
    if not df.empty:
        bad_files = int((df["status"] == "bad_file").sum()) if "status" in df.columns else 0
        bad_frames = int((df["status"] == "bad_frame").sum()) if "status" in df.columns else 0
        log(f"Bad file rows: {bad_files:,}")
        log(f"Bad frame rows: {bad_frames:,}")
    return df
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build media CSV using fast modal-size logic or full per-frame timestamp extraction.",
    )
    parser.add_argument("--cruise", required=True, help="Cruise to process")
    parser.add_argument(
        "--media-dir",
        required=True,
        help="Directory containing image or video files.",
    )
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--max-workers", type=int, default=DEFAULT_MAX_WORKERS)
    parser.add_argument("--file-limit", type=int, default=None)
    parser.add_argument("--suffix", nargs="+", default=None)
    parser.add_argument("--details", action="store_true")
    parser.add_argument(
        "--work-dir",
        default=".",
        help="Workspace whose logs directory receives command logs.",
    )
    parser.add_argument(
        "--no-file-log",
        action="store_true",
        help="Disable Stingray log files and write logs only to the console.",
    )
    args = parser.parse_args(argv)
    work_dir = Path(args.work_dir).expanduser().resolve()
    setup_logging(
        log_dir=work_dir / "logs",
        name="stingray_images_build_frame_timestamps",
        file=not args.no_file_log,
    )
    log_command_options(logger, args)
    t0 = time.time()
    out_dir = args.out_dir
    os.makedirs(out_dir, exist_ok=True)
    cruise = args.cruise
    media_dir = Path(args.media_dir)
    if not media_dir.is_dir():
        raise FileNotFoundError(f"Media directory not found: {media_dir}")
    log(f"Processing cruise: {cruise}")
    log(f"Media dir: {media_dir}")
    log(f"Output dir: {out_dir}")
    log(f"SLURM_CPUS_PER_TASK: {SLURM_CPUS}")
    log(f"Requested max workers: {args.max_workers}")
    log(f"Mode: {'details' if args.details else 'fast'}")
    allowed_suffixes = normalize_suffixes(args.suffix) if args.suffix else DEFAULT_SUFFIXES
    log(f"Allowed suffixes: {sorted(allowed_suffixes)}")
    if args.details:
        df_out = extract_details_dataframe(
            media_dir=media_dir,
            max_workers=args.max_workers,
            suffixes=args.suffix,
            file_limit=args.file_limit,
        )
        mode_name = "details"
    else:
        df = build_base_dataframe(
            media_dir=media_dir,
            max_workers=args.max_workers,
            suffixes=args.suffix,
            file_limit=args.file_limit,
        )
        if df.empty:
            log(f"No files found in {media_dir}")
            return
        log(f"Rows in base dataframe: {len(df):,}")
        df = assign_media_metadata_fast(df, args.max_workers)
        df_out = expand_frames(df)
        mode_name = "fast"
    if df_out.empty:
        log(f"No frame data generated for {cruise}")
        return
    sort_cols = ["media", "frame"] if "frame" in df_out.columns else ["media"]
    df_out.sort_values(sort_cols, inplace=True)
    valid_times = df_out["times"].dropna() if "times" in df_out.columns else pd.Series(dtype="datetime64[ns]")
    datestr = valid_times.iloc[0].strftime("%Y%m%d") if not valid_times.empty else cruise
    out_file = f"{out_dir}/{datestr}_{cruise}_{mode_name}.csv"
    df_out.to_csv(out_file, index=False)
    log(f"Saved: {out_file}")
    log(f"Output rows: {len(df_out):,}")
    if "status" in df_out.columns:
        log(f"Status counts: {df_out['status'].value_counts(dropna=False).to_dict()}")
    log(f"Elapsed time: {time.time() - t0:.2f}s")
if __name__ == "__main__":
    main()
