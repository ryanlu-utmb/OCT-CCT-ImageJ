# OCT CCT — ImageJ/Fiji macros for central corneal thickness

Measure central corneal thickness (CCT) on anterior-segment OCT volumes
(`.OCT.tiff` B-scan stacks), with a batch workflow that tolerates changing file
and folder names.

## Install
1. On this page click **Code ▸ Download ZIP** and unzip it.
2. Copy the `OCT CCT` folder (inside the unzipped folder) into the ImageJ/Fiji `plugins` folder
   (find it via *File ▸ Show Folder ▸ Plugins*).
3. Restart ImageJ (or *Help ▸ Refresh Menus*).

Menu: **Plugins ▸ OCT CCT ▸**

| Entry | What it does |
|---|---|
| 1 Pick Frames | Manual: opens each volume as a virtual stack; scroll to the middle frame of the 7-frame window (avoid the central reflection) → `CCT/frames.csv` |
| 2 Extract Averages | Automatic: 7-frame average per volume → `CCT/avg/*.tif` |
| 3 Measure and Crop | Manual: draw CCT line(s), crop, export PNG → `CCT/*.png`, `CCT/CCT_results.csv`; optional blind mode (random order, IDs hidden) |
| Single Image CCT | Whole workflow on the currently open volume (same method, same output files) |

## Method
- **CCT = vertical distance of the line × axial pixel size** (read from the image
  calibration), so a slightly tilted line does not inflate the value.
- 1 line per sample by default (1–5 configurable; mean is reported).
- Sample ID (first letters+number token, e.g. `M12`), eye (OD/OS/OU), timepoint (`d3`, `BL`, …) and scan number are parsed
  from file/folder names with regular expressions and can be edited before saving.
- Fixed-size crop (move only) keeps every exported image at the same scale;
  free crop is available as an option.
- Every step skips work already done, so you can stop and resume. To redo a
  sample, delete its row in `frames.csv` / `CCT_results.csv` (and its avg `.tif`
  if the frame changes).

## Output (`CCT` subfolder next to the volumes)
- `frames.csv` – chosen middle frame per volume
- `avg/*.tif` – 7-frame averages (calibration preserved)
- `*.png` – 1024×768 crops, named `<sample ID> <eye> <timepoint> Stack_<frame> L_<CCT>.png`
- `CCT_results.csv` – `L1_um … L5_um`, `mean_um` per sample

## Update
Download the ZIP again and replace `OCT CCT/octcctcore.ijm` (the four menu files rarely change).
Results already in `CCT/` are kept and reused.
