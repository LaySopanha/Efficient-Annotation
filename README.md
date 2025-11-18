# Annotation Pipeline

This repository contains a lightweight pipeline for running PaddleOCR text detection on batches of images and preparing Label Studio pre-annotations that can be imported for rapid labeling.

## Repository Layout

- `scripts/run_paddle_annotation.py` – Python CLI that iterates over images, runs PaddleOCR `TextDetection`, normalizes polygons, and writes `output/ls_preannotations.json` in the format Label Studio expects.
- `scripts/run_annotation.sh` – Bash wrapper that can orchestrate the whole workflow: start Label Studio, launch the local file server, and kick off the Python CLI (with optional support for opening each process in its own terminal window).
- `serve_local_files.py` – Simple HTTP server with permissive CORS headers so Label Studio can access local files through the `http` storage type.
- `data/` – Place raw images under `data/raw/` (or point the scripts at another directory via flags) plus any train/valid/test splits you maintain.
- `notebooks/testingPaddle.ipynb` – Original exploratory notebook demonstrating the detection logic that the scripts now automate.

## Requirements

- Python 3.10+ (matching the Conda env you use for PaddleOCR).
- Packages: `paddleocr`, `pillow`, `label-studio` (and their transitive dependencies).
- Optional: a terminal emulator such as `gnome-terminal` if you want the wrapper to spawn separate windows.

Example Conda setup:

```bash
conda create -n handwritten-ocr python=3.10
conda activate handwritten-ocr
pip install paddleocr pillow label-studio
```

## Usage

### End-to-end (recommended)

Run everything in one command after activating your environment:

```bash
scripts/run_annotation.sh --serve-dir data/raw --recursive
```

This will:

1. Start Label Studio (`label-studio start` by default).
2. Serve `data/raw` over HTTP on port 8081 via `serve_local_files.py`.
3. Execute the PaddleOCR batch annotator and save predictions to `output/ls_preannotations.json`.

Optional flags:

- `--terminals` – open Label Studio, the file server, and the annotator in three terminal windows (use `--terminal-cmd` to choose another emulator).
- `--no-labelstudio` / `--no-serve` – skip launching those services if you already have them running.
- `--serve-dir DIR` – change which directory is exposed and used as `LABEL_STUDIO_ROOT`.
- `--labelstudio-cmd CMD` – customize how Label Studio is launched (handy if you need `conda run -n env label-studio start`).

All other arguments after the wrapper options are forwarded to the Python CLI (see below).

### Python CLI directly

```bash
python scripts/run_paddle_annotation.py data/raw \
  --recursive \
  --output-json output/ls_preannotations.json \
  --model-name PP-OCRv5_server_det
```

Key flags:

- `images_dir` (positional) – directory containing images.
- `--recursive` – scan subdirectories.
- `--extensions` – comma-separated list of file extensions (default covers common image types).
- `--from-name`, `--to-name`, `--label`, `--model-version` – metadata written into the Label Studio predictions.

Ensure the relevant `LABEL_STUDIO_MODE`, `LABEL_STUDIO_ROOT`, and `LABEL_STUDIO_PREFIX` env vars are set before running (the bash wrapper does this automatically).

### Serve files manually (optional)

To run the HTTP server yourself:

```bash
python serve_local_files.py --directory data/raw --port 8081
```

Then configure Label Studio to use `http://localhost:8081/…` for data sources.

## Outputs

- `output/ls_preannotations.json` – predictions ready for import into Label Studio (`Import > Predictions`). Each entry references the image via `LABEL_STUDIO_PREFIX` and includes polygon labels scaled to percentages as expected by Label Studio.
- `output/res.json` and other intermediate artifacts can be produced when running the notebook or adapting the scripts.

## Troubleshooting

- **No images found** – verify files exist under the directory you passed (`--serve-dir` / CLI positional) and that extensions match (the check is case-insensitive).
- **ModuleNotFoundError** – confirm you’re running inside the Conda/virtualenv that has `paddleocr` and `label-studio`.
- **Label Studio/server closing too soon** – run the wrapper with `--no-labelstudio --no-serve` and manage them yourself, or use `--terminals` to keep windows open until you close them manually.

## Syncing data from Google Drive with rclone

If your images live on Google Drive, rclone is a convenient way to mirror them locally before running the pipeline.

1. Install rclone (via package manager or <https://rclone.org/downloads/>).
2. Run `rclone config` and create a remote (e.g., `drive:`) using the Google Drive guide from rclone.
3. Sync the folder you need into `data/raw` (adjust the path as needed):

   ```bash
   rclone sync drive:path/to/folder data/raw
   ```

4. Run `scripts/run_annotation.sh --serve-dir data/raw --recursive` (or your preferred options).
5. After annotating, you can push new files or outputs back to Drive in the same way:

   ```bash
   rclone copy output/ drive:path/to/outputs
   ```
