// =====================================================================
// OCT CCT - core macro (ImageJ plugin)            version 2026-11-16
//
// Called by the menu entries in Plugins > OCT CCT with an argument:
//   "1"      Pick frames (manual, fast)        -> CCT/frames.csv
//   "2"      Extract 7-frame averages (auto)   -> CCT/avg/*.tif
//   "3"      Measure CCT + crop (manual)       -> CCT/*.png + CCT/CCT_results.csv
//   "single" Whole workflow on the open volume (same method, same files)
// Run directly without an argument to get a chooser.
//
// CCT = vertical distance (dy) x axial pixel size, read from the image
// calibration. All outputs go to a "CCT" subfolder of the source folder;
// every step skips what is already done, so you can stop and resume.
// To redo a sample: delete its row in frames.csv / CCT_results.csv
// (and its avg .tif if the frame changes), then run again.
// This file has no underscore in its name on purpose: it stays out of
// the menu and is only called by the menu entries.
// =====================================================================
requires("1.53a");

var SRC = "";
var WORK = "";
var AVG = "";
var FRAMES = "";
var RESULTS = "";
var HDR_FRAMES = "source_file,sample_id,eye,timepoint,scan,mid_slice";
var HDR_RESULTS = "source_file,sample_id,eye,timepoint,scan,mid_slice,L1_um,L2_um,L3_um,L4_um,L5_um,mean_um,png";
// measurement options (filled by readOptionFields)
var O_blind = false;
var O_nL = 1;
var O_fixed = true;
var O_cw = 800;
var O_ch = 600;
var O_dmin = 50;
var O_dmax = 220;
// line results (filled by drawLines)
var G_lens = 0;
var G_mean = 0;
var G_unit = "";
// per-file metadata (filled by readMetaFields)
var M_mid = 0;
var M_sid = "";
var M_eye = "";
var M_tp = "";
var M_scan = "";

arg = getArgument();
if (arg == "") {
    Dialog.create("OCT CCT");
    Dialog.addChoice("Run:", newArray(
        "1 - Pick frames (manual)",
        "2 - Extract 7-frame averages (automatic)",
        "3 - Measure CCT + crop (manual)",
        "single - Current image, whole workflow"));
    Dialog.show();
    ch = Dialog.getChoice();
    arg = substring(ch, 0, indexOf(ch, " "));
}

if (arg == "single") {
    singleImage();
} else {
    d = getDirectory("Choose the folder that contains the OCT .tiff volumes");
    setupDirs(d);
    if (arg == "1") pickFrames();
    else if (arg == "2") extractAverages();
    else if (arg == "3") measureAndCrop();
    else exit("Unknown argument: " + arg);
}

// =====================================================================
// STEP 1 - pick the middle frame of the 7-frame window for each volume
// =====================================================================
function pickFrames() {
    files = listVolumes(SRC);
    if (files.length == 0) exit("No .tif/.tiff files found in:\n" + SRC);
    ensureHeader(FRAMES, HDR_FRAMES);
    done = csvColumn(FRAMES, 0);
    todo = newArray(0);
    for (i = 0; i < files.length; i++)
        if (!contains(done, files[i])) todo = Array.concat(todo, files[i]);
    if (todo.length == 0) exit("Step 1: all " + files.length + " volumes already have a frame in frames.csv.");

    stop = false;
    for (i = 0; i < todo.length && !stop; i++) {
        f = todo[i];
        run("TIFF Virtual Stack...", "open=[" + SRC + f + "]");
        id = getImageID();
        mid = pickSlice(id, f, "(" + (i + 1) + " / " + todo.length + ")");
        maxSlice = nSlices;

        Dialog.create("Confirm  (" + (i + 1) + " / " + todo.length + ")");
        addMetaFields(f, mid);
        Dialog.addChoice("Action:", newArray("Save and next", "Skip this file", "Save and stop", "Stop (don't save this one)"));
        Dialog.show();
        readMetaFields();
        action = Dialog.getChoice();
        selectImage(id);
        close();

        if (startsWith(action, "Save")) {
            ok = checkMeta(M_mid, maxSlice, M_sid, f);
            if (ok) {
                recordFrame(f, M_sid, M_eye, M_tp, M_scan, M_mid);
                call("ij.Prefs.set", "octcct.lastMid", "" + M_mid);
            }
        }
        if (endsWith(action, "stop") || startsWith(action, "Stop")) stop = true;
    }
    showMessage("Step 1", "Frames saved to:\n" + FRAMES + "\n \nNext: Plugins > OCT CCT > 2 Extract Averages");
}

// =====================================================================
// STEP 2 - average the 7 frames around each picked frame (unattended)
// =====================================================================
function extractAverages() {
    if (!File.exists(FRAMES)) exit("frames.csv not found - run Step 1 first.");
    rows = csvRows(FRAMES);
    setBatchMode(true);
    made = 0; skipped = 0; failed = "";
    for (r = 0; r < rows.length; r++) {
        c = split(rows[r], ",");
        f = c[0];
        mid = parseInt(c[5]);
        an = avgName(f, mid);
        out = AVG + an;
        showStatus("Step 2: " + (r + 1) + "/" + rows.length + "  " + f);
        showProgress(r, rows.length);
        if (File.exists(out)) {
            skipped++;
        } else if (!File.exists(SRC + f)) {
            failed = failed + "\n  missing: " + f;
        } else {
            run("TIFF Virtual Stack...", "open=[" + SRC + f + "]");
            srcID = getImageID();
            if (mid - 3 < 1 || mid + 3 > nSlices) {
                failed = failed + "\n  frame out of range: " + f;
            } else {
                avgID = makeAverage(srcID, mid, out);
                made++;
            }
            close("*");
        }
    }
    setBatchMode(false);
    msg = "Created: " + made + "\nAlready existed: " + skipped;
    if (failed != "") msg = msg + "\nProblems:" + failed;
    showMessage("Step 2 done", msg + "\n \nNext: Plugins > OCT CCT > 3 Measure and Crop");
}

// =====================================================================
// STEP 3 - CCT line(s) + crop + PNG for every extracted average
// =====================================================================
function measureAndCrop() {
    if (!File.exists(FRAMES)) exit("frames.csv not found - run Step 1 first.");
    rows = csvRows(FRAMES);
    ensureHeader(RESULTS, HDR_RESULTS);
    doneKeys = newArray(0);
    res = csvRows(RESULTS);
    for (i = 0; i < res.length; i++) {
        rc = split(res[i], ",");
        doneKeys = Array.concat(doneKeys, rc[0] + "|" + rc[5]);
    }
    todo = newArray(0);
    for (r = 0; r < rows.length; r++) {
        c = split(rows[r], ",");
        an = avgName(c[0], parseInt(c[5]));
        key = c[0] + "|" + c[5];
        if (File.exists(AVG + an) && !contains(doneKeys, key))
            todo = Array.concat(todo, rows[r]);
    }
    if (todo.length == 0) exit("Step 3: nothing to measure (all done, or run Step 2 first).");

    Dialog.create("Step 3 options");
    Dialog.addMessage(todo.length + " sample(s) to measure.");
    addOptionFields(true);
    Dialog.show();
    readOptionFields(true);

    if (O_blind) todo = shuffle(todo);

    stop = false;
    for (k = 0; k < todo.length && !stop; k++) {
        c = split(todo[k], ",");
        f = c[0]; sid = un(c[1]); eye = c[2]; tp = un(c[3]); scan = un(c[4]); mid = parseInt(c[5]);
        an = avgName(f, mid);
        open(AVG + an);
        if (O_blind) rename("Sample " + IJ.pad(k + 1, 2) + " of " + todo.length);
        else rename(sid + " " + eye + " " + tp + "  (" + (k + 1) + "/" + todo.length + ")");
        imgID = getImageID();

        act = drawLines(imgID, true);
        if (act == "accept") {
            outPath = cropScaleSave(imgID, sid, eye, tp, scan, mid);
            appendResult(f, sid, eye, tp, scan, mid, outPath);
        }
        if (act == "stop") stop = true;
        close("*");
    }
    showMessage("Step 3", "Results: " + RESULTS);
}

// =====================================================================
// SINGLE - whole workflow on the volume that is currently open
// =====================================================================
function singleImage() {
    if (nImages == 0) exit("Open an OCT volume first.");
    if (nSlices < 7) exit("The active image has fewer than 7 slices - open the original OCT volume.");
    srcID = getImageID();
    f = getInfo("image.filename");
    if (f == "") f = getTitle();
    d = getDirectory("image");
    if (d == "") d = getDirectory("Image folder unknown - choose the output folder");
    setupDirs(d);

    mid = pickSlice(srcID, f, "");
    selectImage(srcID);
    maxSlice = nSlices;

    Dialog.create("Confirm");
    addMetaFields(f, mid);
    addOptionFields(false);
    Dialog.show();
    readMetaFields();
    readOptionFields(false);
    ok = checkMeta(M_mid, maxSlice, M_sid, f);
    if (!ok) exit();
    call("ij.Prefs.set", "octcct.lastMid", "" + M_mid);

    ensureHeader(FRAMES, HDR_FRAMES);
    fr = csvRows(FRAMES);
    frKeys = newArray(0);
    for (i = 0; i < fr.length; i++) { c = split(fr[i], ","); frKeys = Array.concat(frKeys, c[0] + "|" + c[5]); }
    key = f + "|" + M_mid;
    if (!contains(frKeys, key)) recordFrame(f, M_sid, M_eye, M_tp, M_scan, M_mid);

    an = avgName(f, M_mid);
    imgID = makeAverage(srcID, M_mid, AVG + an);

    act = drawLines(imgID, false);
    if (act != "accept") exit("Cancelled - frame and average were saved, no CCT recorded.");
    outPath = cropScaleSave(imgID, M_sid, M_eye, M_tp, M_scan, M_mid);
    appendResult(f, M_sid, M_eye, M_tp, M_scan, M_mid, outPath);
    print("Saved: " + outPath + "   CCT = " + d2s(G_mean, 2) + " " + G_unit);
    close("*");
}

// =====================================================================
// shared building blocks (used by both batch and single)
// =====================================================================
function setupDirs(d) {
    SRC = d;
    WORK = SRC + "CCT" + File.separator;
    AVG = WORK + "avg" + File.separator;
    FRAMES = WORK + "frames.csv";
    RESULTS = WORK + "CCT_results.csv";
    File.makeDirectory(WORK);
    File.makeDirectory(AVG);
}

// let the user scroll to the middle frame; returns the slice number
function pickSlice(id, f, counter) {
    selectImage(id);
    lastMid = parseInt(call("ij.Prefs.get", "octcct.lastMid", "500"));
    setSlice(minOf(maxOf(lastMid, 4), nSlices - 3));
    waitForUser("Pick frame " + counter,
        f + "\n \nScroll to the MIDDLE frame of the 7-frame window\n" +
        "(avoid the strong central reflection), then click OK.");
    selectImage(id);
    s = getSliceNumber();
    return s;
}

// per-file metadata fields (parsed from the name, editable)
function addMetaFields(f, mid) {
    sid = parseSample(f);
    eye = parseEye(f);
    tp = parseTimepoint(f, SRC);
    scan = parseScan(f);
    eyeDef = defaultEye(eye);
    Dialog.addMessage(f);
    Dialog.addNumber("Middle frame:", mid, 0, 6, "");
    Dialog.addString("Sample ID:", sid);
    Dialog.addChoice("Eye:", newArray("OD", "OS", "OU"), eyeDef);
    Dialog.addString("Timepoint:", tp);
    Dialog.addString("Scan #:", scan);
}
function readMetaFields() {
    M_mid = Dialog.getNumber();
    s = Dialog.getString(); M_sid = trim(s);
    M_eye = Dialog.getChoice();
    s = Dialog.getString(); M_tp = trim(s);
    s = Dialog.getString(); M_scan = trim(s);
}
function checkMeta(mid, maxSlice, sid, f) {
    if (mid - 3 < 1 || mid + 3 > maxSlice) {
        showMessage("Frame out of range", "Frame " + mid + " is too close to the edge (1-" + maxSlice + "). Not saved:\n" + f);
        return false;
    }
    if (sid == "") {
        showMessage("Missing sample ID", "Sample ID is empty. Not saved:\n" + f);
        return false;
    }
    return true;
}

// measurement options (remembered between runs)
function addOptionFields(showBlind) {
    nL = parseInt(call("ij.Prefs.get", "octcct.nLines", "1"));
    cw = parseInt(call("ij.Prefs.get", "octcct.cropW", "800"));
    ch = parseInt(call("ij.Prefs.get", "octcct.cropH", "600"));
    if (showBlind) Dialog.addCheckbox("Blind: random order, hide sample ID", true);
    Dialog.addNumber("Lines per sample (1-5):", nL, 0, 3, "");
    Dialog.addChoice("Crop:", newArray("Fixed size (move only)", "Free rectangle (old behaviour)"));
    Dialog.addNumber("Fixed crop width (px):", cw);
    Dialog.addNumber("Fixed crop height (px):", ch);
    Dialog.addNumber("Display min:", 50);
    Dialog.addNumber("Display max:", 220);
}
function readOptionFields(showBlind) {
    O_blind = false;
    if (showBlind) O_blind = Dialog.getCheckbox();
    O_nL = Dialog.getNumber();
    O_nL = maxOf(1, minOf(5, round(O_nL)));
    c = Dialog.getChoice();
    O_fixed = startsWith(c, "Fixed");
    O_cw = Dialog.getNumber();
    O_ch = Dialog.getNumber();
    O_dmin = Dialog.getNumber();
    O_dmax = Dialog.getNumber();
    call("ij.Prefs.set", "octcct.nLines", "" + O_nL);
    call("ij.Prefs.set", "octcct.cropW", "" + O_cw);
    call("ij.Prefs.set", "octcct.cropH", "" + O_ch);
}

// 7-frame average around mid, saved to outPath; returns the saved image's ID
function makeAverage(srcID, mid, outPath) {
    selectImage(srcID);
    run("Make Substack...", "slices=" + (mid - 3) + "-" + (mid + 3));
    subID = getImageID();
    run("Z Project...", "projection=[Average Intensity]");
    saveAs("Tiff", outPath);
    aID = getImageID();
    selectImage(subID);
    close();
    selectImage(aID);
    return aID;
}

// draw O_nL lines; thickness = |dy| x pixel height.
// returns "accept" | "skip" | "stop" (batch) or "accept" | "cancel" (single)
function drawLines(imgID, batch) {
    selectImage(imgID);
    getPixelSize(unit, pw, ph);
    G_unit = unit;
    result = "";
    while (result == "") {
        roiManager("reset");
        run("Select None");
        setTool("line");
        n = 0;
        while (n < O_nL) {
            waitForUser("CCT line " + (n + 1) + " / " + O_nL,
                "Draw ONE straight line from epithelium to endothelium, then OK.\n" +
                "(Only the vertical distance is used, so a slight tilt is fine.)");
            selectImage(imgID);
            if (selectionType() != 5) {
                showMessage("Not a straight line", "Please use the straight-line tool and draw again.");
            } else {
                roiManager("add");
                roiManager("Show All without labels");
                run("Select None");
                n++;
            }
        }
        G_lens = newArray(5);
        sum = 0;
        for (j = 0; j < O_nL; j++) {
            roiManager("select", j);
            getSelectionCoordinates(xs, ys);
            G_lens[j] = abs(ys[1] - ys[0]) * ph;
            sum += G_lens[j];
        }
        G_mean = sum / O_nL;
        run("Select None");

        Dialog.create("Line(s) OK?");
        if (!O_blind) Dialog.addMessage("CCT = " + d2s(G_mean, 2) + " " + unit);
        if (batch) Dialog.addChoice("Action:", newArray("Accept", "Redo the line(s)", "Skip this sample", "Stop (resume later)"));
        else Dialog.addChoice("Action:", newArray("Accept", "Redo the line(s)", "Cancel (save nothing)"));
        Dialog.show();
        a = Dialog.getChoice();
        if (a == "Accept") result = "accept";
        else if (startsWith(a, "Skip")) result = "skip";
        else if (startsWith(a, "Stop")) result = "stop";
        else if (startsWith(a, "Cancel")) result = "cancel";
    }
    roiManager("reset");
    roiManager("Show None");
    return result;
}

// crop (fixed or free), scale to 1024x768, 8-bit, display range, save PNG; returns the path
function cropScaleSave(imgID, sid, eye, tp, scan, mid) {
    selectImage(imgID);
    W = getWidth(); H = getHeight();
    if (O_fixed) {
        bw = minOf(O_cw, W); bh = minOf(O_ch, H);
        makeRectangle(round((W - bw) / 2), round((H - bh) / 2), bw, bh);
        setTool("rectangle");
        waitForUser("Crop", "DRAG the box to frame the cornea (don't resize), then OK.");
        selectImage(imgID);
        cx = W / 2; cy = H / 2;
        if (selectionType() == 0) {
            getSelectionBounds(x, y, w, h);
            cx = x + w / 2; cy = y + h / 2;
        }
        x = round(cx - bw / 2); y = round(cy - bh / 2);
        x = maxOf(0, minOf(x, W - bw)); y = maxOf(0, minOf(y, H - bh));
        makeRectangle(x, y, bw, bh);
    } else {
        run("Select None");
        setTool("rectangle");
        do {
            waitForUser("Crop", "Draw a RECTANGLE to crop, then OK.");
            selectImage(imgID);
        } while (selectionType() != 0);
    }
    run("Crop");
    run("Scale...", "x=- y=- width=1024 height=768 interpolation=Bilinear average create");
    setOption("ScaleConversions", true);
    run("8-bit");
    setMinAndMax(O_dmin, O_dmax);

    parts = sid + " " + eye;
    if (tp != "") parts = parts + " " + tp;
    outName = parts + " Stack_" + mid + " L_" + d2s(G_mean, 2);
    outPath = WORK + outName + ".png";
    if (File.exists(outPath) && scan != "") outPath = WORK + outName + " scan" + scan + ".png";
    base = File.getNameWithoutExtension(outPath);
    v = 2;
    while (File.exists(outPath)) { outPath = WORK + base + " (" + v + ").png"; v++; }
    saveAs("PNG", outPath);
    return outPath;
}

function recordFrame(f, sid, eye, tp, scan, mid) {
    nm = na(sid); nt = na(tp); ns = na(scan);
    File.append(f + "," + nm + "," + eye + "," + nt + "," + ns + "," + mid, FRAMES);
}
function appendResult(f, sid, eye, tp, scan, mid, outPath) {
    ensureHeader(RESULTS, HDR_RESULTS);
    nm = na(sid); nt = na(tp); ns = na(scan);
    row = f + "," + nm + "," + eye + "," + nt + "," + ns + "," + mid;
    for (j = 0; j < 5; j++) {
        if (j < O_nL) row = row + "," + d2s(G_lens[j], 3);
        else row = row + ",-";
    }
    pn = File.getName(outPath);
    row = row + "," + d2s(G_mean, 3) + "," + pn;
    File.append(row, RESULTS);
}

// ============================ helpers ============================
function ensureHeader(path, header) {
    if (!File.exists(path)) File.append(header, path);
}
function listVolumes(dir) {
    list = getFileList(dir);
    out = newArray(0);
    for (i = 0; i < list.length; i++) {
        ln = toLowerCase(list[i]);
        if ((endsWith(ln, ".tif") || endsWith(ln, ".tiff")) && !startsWith(ln, "avg_"))
            out = Array.concat(out, list[i]);
    }
    return out;
}
function csvRows(path) {
    out = newArray(0);
    if (!File.exists(path)) return out;
    lines = split(File.openAsString(path), "\n");
    for (i = 1; i < lines.length; i++) {
        l = trim(lines[i]);
        if (l != "") out = Array.concat(out, l);
    }
    return out;
}
function csvColumn(path, col) {
    rows = csvRows(path);
    out = newArray(rows.length);
    for (i = 0; i < rows.length; i++) { c = split(rows[i], ","); out[i] = c[col]; }
    return out;
}
function contains(arr, v) {
    for (i = 0; i < arr.length; i++) if (arr[i] == v) return true;
    return false;
}
function shuffle(arr) {
    a = Array.copy(arr);
    for (i = a.length - 1; i > 0; i--) {
        j = floor(random() * (i + 1));
        t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
}
function avgName(f, mid) {
    b = replace(f, "(?i)\\.tiff?$", "");
    b = b + "_mid" + mid + ".tif";
    return b;
}
function trim(s) {
    t = replace(s, "^\\s+|\\s+$", "");
    return t;
}
function na(s) { if (s == "") return "-"; return s; }
function un(s) { if (s == "-") return ""; return s; }
function extract(s, regex) {
    if (matches(s, regex)) return replace(s, regex, "$1");
    return "";
}
// sample ID = first token of 1-8 letters + digits (+ optional letter), e.g. M12, S-034, ABC201N
function parseSample(f) {
    m = extract(f, "(?i)^.*?(?<![A-Za-z0-9])([A-Za-z]{1,8}[ _-]?\\d+[A-Za-z]?)(?![A-Za-z0-9]).*$");
    return m;
}
// standalone OD / OS / OU
function parseEye(f) {
    e = extract(f, "(?i).*(?<![A-Za-z])(OD|OS|OU)(?![A-Za-z]).*");
    e = toUpperCase(e);
    return e;
}
// digits right before ".OCT"  (_0000006.OCT.tiff -> 6)
function parseScan(f) {
    s = extract(f, "(?i).*_(\\d+)\\.OCT.*");
    if (s == "") return "";
    return "" + parseInt(s);
}
// d3 / D7 / BL / Baseline / pre : file name first, then folders from deepest up
function parseTimepoint(f, dir) {
    rx = "(?i).*(?<![A-Za-z0-9])(d\\d+|BL|baseline|pre)(?![A-Za-z0-9]).*";
    t = extract(f, rx);
    segs = split(dir, "\\/");
    for (k = segs.length - 1; k >= 0 && t == ""; k--) t = extract(segs[k], rx);
    return t;
}
function defaultEye(e) {
    if (e == "OD" || e == "OS" || e == "OU") return e;
    return "OD";
}
