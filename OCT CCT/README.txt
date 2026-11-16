OCT CCT plugin for ImageJ / Fiji   (version 2026-11-16)

INSTALL
1. Copy the whole "OCT CCT" folder into ImageJ's plugins folder
   (Fiji: Fiji.app\plugins\ ; ImageJ: ImageJ\plugins\ ).
   Find it from ImageJ: File > Show Folder > Plugins.
2. Restart ImageJ (or Help > Refresh Menus).
3. Menu: Plugins > OCT CCT >
      1 Pick Frames         manual: scroll to the middle frame of each volume
      2 Extract Averages    automatic: 7-frame average per volume
      3 Measure and Crop    manual: CCT line(s) + crop + PNG (optional blind mode)
      Single Image CCT      whole workflow on the currently open volume

OUTPUT (subfolder "CCT" inside the folder with the .tiff volumes)
   frames.csv        chosen middle frame per volume
   avg\*.tif         7-frame averages (calibration kept)
   *.png             cropped 1024x768 images, named like before
   CCT_results.csv   CCT per sample (um); L1-L5 = individual lines, mean_um = average

METHOD
   CCT = vertical distance of the line x axial pixel size (from image calibration),
   so a slightly tilted line does not inflate the value.
   Every step skips what is already done; you can stop and resume any time.
   To redo a sample: delete its row in frames.csv / CCT_results.csv
   (and its avg .tif if you change the frame), then run again.

UPDATE
   Replace octcctcore.ijm only; the four menu files never change.
