from datetime import datetime, timedelta

import pandas as pd

from stingray.images import build_frame_timestamps as timestamps


def _base_frame(media_path, media_size=100):
    return {
        "media_path": media_path,
        "media_size": media_size,
        "media": media_path.rsplit("/", 1)[-1].rsplit(".", 1)[0],
        "suffix": ".avi",
        "media_time": datetime(2024, 1, 1),
    }


def test_fast_mode_assigns_sampled_frame_count_and_fps_to_matching_group(monkeypatch):
    df = pd.DataFrame(
        [
            _base_frame("/data/cam-20240101T000000.000.avi"),
            _base_frame("/data/cam-20240101T000010.000.avi"),
            _base_frame("/data/cam-20240101T000020.000.avi"),
        ]
    )

    monkeypatch.setattr(
        timestamps,
        "get_media_metadata",
        lambda path: {"frame_count": 3, "fps": 2.0},
    )

    result = timestamps.assign_media_metadata_fast(df, max_workers=2)
    expanded = timestamps.expand_frames(result)

    assert result["frame_count"].tolist() == [3, 3, 3]
    assert result["fps"].tolist() == [2.0, 2.0, 2.0]
    assert expanded.loc[expanded["media_path"] == df.loc[0, "media_path"], "times"].tolist() == [
        datetime(2024, 1, 1),
        datetime(2024, 1, 1) + timedelta(seconds=0.5),
        datetime(2024, 1, 1) + timedelta(seconds=1.0),
    ]


def test_fast_mode_measures_full_group_when_same_size_has_mixed_fps(monkeypatch):
    df = pd.DataFrame(
        [
            _base_frame("/data/cam-20240101T000000.000.avi"),
            _base_frame("/data/cam-20240101T000010.000.avi"),
        ]
    )
    metadata = {
        "/data/cam-20240101T000000.000.avi": {"frame_count": 2, "fps": 1.0},
        "/data/cam-20240101T000010.000.avi": {"frame_count": 2, "fps": 2.0},
    }

    monkeypatch.setattr(timestamps, "get_media_metadata", lambda path: metadata[path])

    result = timestamps.assign_media_metadata_fast(df, max_workers=2)
    expanded = timestamps.expand_frames(result)

    assert result["fps"].tolist() == [1.0, 2.0]
    assert expanded.loc[expanded["media_path"] == df.loc[0, "media_path"], "times"].tolist() == [
        datetime(2024, 1, 1),
        datetime(2024, 1, 1) + timedelta(seconds=1.0),
    ]
    assert expanded.loc[expanded["media_path"] == df.loc[1, "media_path"], "times"].tolist() == [
        datetime(2024, 1, 1),
        datetime(2024, 1, 1) + timedelta(seconds=0.5),
    ]
