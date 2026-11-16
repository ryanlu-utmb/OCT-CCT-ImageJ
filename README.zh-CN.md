# OCT CCT — 用于测量中央角膜厚度的 ImageJ/Fiji 宏

[English](README.md) | 简体中文

在眼前节 OCT 容积数据（`.OCT.tiff` B-scan 图像栈）上测量中央角膜厚度（CCT）

## 安装
1. 在本页点击 **Code ▸ Download ZIP**，下载后解压。
2. 将解压目录中的 `OCT CCT` 文件夹复制到 ImageJ/Fiji 的 `plugins` 文件夹
   （可通过 *File ▸ Show Folder ▸ Plugins* 找到）。
3. 重启 ImageJ（或执行 *Help ▸ Refresh Menus*）。

菜单位置：**Plugins ▸ OCT CCT ▸**

| 菜单项 | 功能 |
|---|---|
| 1 Pick Frames | 手动：以虚拟栈方式逐个打开容积数据，滚动到 7 帧窗口的中间帧（避开中央反光）→ `CCT/frames.csv` |
| 2 Extract Averages | 自动：为每个容积生成 7 帧平均图 → `CCT/avg/*.tif` |
| 3 Measure and Crop | 手动：绘制 CCT 测量线、裁剪并导出 PNG → `CCT/*.png`、`CCT/CCT_results.csv`；可选盲法模式（随机顺序、隐藏 ID） |
| Single Image CCT | 对当前打开的单个容积执行完整流程（方法与输出文件相同） |

## 方法
- **CCT = 测量线的垂直距离 × 轴向像素尺寸**（读取自图像标定信息），
  因此测量线略有倾斜也不会使数值偏大。
- 默认每个样本画 1 条线（可设为 1–5 条，结果取平均值）。
- 样本 ID（文件名中首个“字母+数字”片段，如 `M12`）、眼别（OD/OS/OU）、
  时间点（`d3`、`BL` 等）和扫描编号均通过正则表达式从文件名/文件夹名中解析，
  保存前可手动修改。
- 默认使用固定尺寸裁剪框（只能移动、不能缩放），保证所有导出图像比例一致；
  也可选择自由裁剪。
- 每一步都会跳过已完成的工作，可随时中断后继续。如需重做某个样本，
  删除其在 `frames.csv` / `CCT_results.csv` 中的对应行即可
  （若更换了中间帧，还需删除对应的平均图 `.tif`）。

## 输出（位于容积数据同目录下的 `CCT` 子文件夹）
- `frames.csv` — 每个容积选定的中间帧
- `avg/*.tif` — 7 帧平均图（保留标定信息）
- `*.png` — 1024×768 裁剪图，命名格式为 `<样本 ID> <眼别> <时间点> Stack_<帧号> L_<CCT>.png`
- `CCT_results.csv` — 每个样本的 `L1_um … L5_um` 及 `mean_um`

## 更新
重新下载 ZIP，并替换 `OCT CCT/octcctcore.ijm`（四个菜单文件很少变动）。
`CCT/` 中已有的结果会被保留并继续使用。
