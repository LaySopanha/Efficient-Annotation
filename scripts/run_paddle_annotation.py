#!/usr/bin/env python3
"""Batch PaddleOCR detection pipeline that prepares Label Studio pre-annotations."""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence
from urllib.parse import quote

from paddleocr import TextDetection
from PIL import Image


DEFAULT_EXTENSIONS = ("jpg", "jpeg", "png", "bmp", "tif", "tiff", "webp")


@dataclass(frozen=True)
class LabelStudioConfig:
    mode: str
    root: Path
    prefix: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run PaddleOCR TextDetection over every image in a directory and "
            "emit a Label Studio compatible predictions JSON file."
        )
    )
    parser.add_argument(
        "images_dir",
        nargs="?",
        default="data/raw",
        type=Path,
        help="Directory containing the images to annotate (default: data/raw).",
    )
    parser.add_argument(
        "--output-json",
        type=Path,
        default=Path("output/ls_preannotations.json"),
        help="Where to save the aggregated pre-annotations JSON (default: output/ls_preannotations.json).",
    )
    parser.add_argument(
        "--from-name",
        default="lines",
        help="Label Studio PolygonLabels tag name (default: lines).",
    )
    parser.add_argument(
        "--to-name",
        default="image",
        help="Label Studio Image tag name (default: image).",
    )
    parser.add_argument(
        "--label",
        default="text",
        help="Polygon label value to assign to each detection (default: text).",
    )
    parser.add_argument(
        "--model-version",
        default="paddle-ppocrv5",
        help="Model version string recorded in Label Studio predictions (default: paddle-ppocrv5).",
    )
    parser.add_argument(
        "--model-name",
        default="PP-OCRv5_server_det",
        help="PaddleOCR detection model name (default: PP-OCRv5_server_det).",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1,
        help="Batch size fed into PaddleOCR predict() calls (default: 1).",
    )
    parser.add_argument(
        "--extensions",
        default=",".join(DEFAULT_EXTENSIONS),
        help="Comma-separated list of file extensions to include (default: common image formats).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional cap on the number of images processed (default: process all).",
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Recurse into subdirectories (default: only direct children).",
    )
    return parser.parse_args()


def load_label_studio_config() -> LabelStudioConfig:
    mode = os.environ.get("LABEL_STUDIO_MODE", "local-files")
    root = Path(os.environ.get("LABEL_STUDIO_ROOT", Path.cwd())).resolve()
    prefix = os.environ.get("LABEL_STUDIO_PREFIX", "/data/local-files/?d=")
    return LabelStudioConfig(mode=mode, root=root, prefix=prefix)


def iter_image_paths(root: Path, extensions: Sequence[str], recursive: bool) -> Iterable[Path]:
    pattern = "**/*" if recursive else "*"
    lowered_exts = tuple(f".{ext.lower().lstrip('.')}" for ext in extensions)
    for path in sorted(root.glob(pattern)):
        if not path.is_file():
            continue
        if path.suffix.lower() in lowered_exts:
            yield path


def make_image_entry(path: Path, cfg: LabelStudioConfig) -> str:
    path = path.resolve()
    try:
        rel = path.relative_to(cfg.root)
    except ValueError as exc:  # pragma: no cover - defensive path validation
        raise ValueError(
            f"Image {path} is not inside LABEL_STUDIO_ROOT={cfg.root}"
        ) from exc

    if cfg.mode == "http":
        prefix = cfg.prefix.rstrip("/") + "/"
        return f"{prefix}{quote(rel.as_posix())}"

    if cfg.mode == "storage":
        return rel.as_posix()

    if cfg.mode == "local-files":
        if not cfg.root.exists():
            raise FileNotFoundError(f"LABEL_STUDIO_ROOT {cfg.root} does not exist")
        return f"{cfg.prefix}{quote(rel.as_posix())}"

    raise ValueError(f"Unsupported LABEL_STUDIO_MODE '{cfg.mode}'")


def extract_detection_components(raw_detection) -> tuple:
    res_dict = raw_detection["res"] if isinstance(raw_detection, dict) and "res" in raw_detection else getattr(raw_detection, "res", raw_detection)
    dt_polys = res_dict["dt_polys"] if isinstance(res_dict, dict) else getattr(res_dict, "dt_polys", [])
    dt_scores = res_dict["dt_scores"] if isinstance(res_dict, dict) else getattr(res_dict, "dt_scores", [])
    return dt_polys, dt_scores


def detection_to_polygons(
    path: Path,
    raw_detection,
    from_name: str,
    to_name: str,
    label: str,
) -> tuple[List[dict], float | None]:
    with Image.open(path) as img:
        width, height = img.size

    dt_polys, dt_scores = extract_detection_components(raw_detection)
    try:
        poly_iter = dt_polys.tolist()
    except AttributeError:
        poly_iter = dt_polys

    polygons = []
    for poly, score in zip(poly_iter, dt_scores):
        normalized = [
            [round(x / width * 100, 4), round(y / height * 100, 4)]
            for x, y in poly
        ]
        polygons.append(
            {
                "id": str(uuid.uuid4()),
                "from_name": from_name,
                "to_name": to_name,
                "type": "polygonlabels",
                "score": float(score),
                "value": {"points": normalized, "polygonlabels": [label]},
            }
        )

    avg_score = float(sum(dt_scores) / len(dt_scores)) if dt_scores else None
    return polygons, avg_score


def build_payload_entry(
    image_entry: str,
    polygons: List[dict],
    avg_score: float | None,
    model_version: str,
) -> dict:
    prediction = {
        "model_version": model_version,
        "result": polygons,
    }
    if avg_score is not None:
        prediction["score"] = avg_score
    return {"data": {"image": image_entry}, "predictions": [prediction]}


def main() -> None:
    args = parse_args()
    images_dir: Path = args.images_dir.expanduser().resolve()
    if not images_dir.is_dir():
        print(f"[ERROR] {images_dir} is not a directory", file=sys.stderr)
        sys.exit(2)

    extensions = [ext.strip() for ext in args.extensions.split(",") if ext.strip()]
    if not extensions:
        print("[ERROR] --extensions produced an empty list", file=sys.stderr)
        sys.exit(2)

    ls_cfg = load_label_studio_config()
    image_paths = list(iter_image_paths(images_dir, extensions, args.recursive))
    if args.limit is not None:
        image_paths = image_paths[: args.limit]

    if not image_paths:
        print(f"[WARN] No images found in {images_dir} with extensions {extensions}", file=sys.stderr)
        sys.exit(1)

    detector = TextDetection(model_name=args.model_name)
    payload = []
    for idx, image_path in enumerate(image_paths, start=1):
        print(f"[INFO] ({idx}/{len(image_paths)}) Processing {image_path}")
        detections = detector.predict(str(image_path), batch_size=args.batch_size)
        if not detections:
            print(f"[WARN] No detections returned for {image_path}", file=sys.stderr)
            continue
        polygons, avg_score = detection_to_polygons(
            image_path,
            detections[0],
            args.from_name,
            args.to_name,
            args.label,
        )
        image_entry = make_image_entry(image_path, ls_cfg)
        payload.append(
            build_payload_entry(
                image_entry=image_entry,
                polygons=polygons,
                avg_score=avg_score,
                model_version=args.model_version,
            )
        )

    if not payload:
        print("[ERROR] No payload entries were generated", file=sys.stderr)
        sys.exit(1)

    output_path: Path = args.output_json.expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"[OK] Wrote {len(payload)} records to {output_path}")


if __name__ == "__main__":
    main()
