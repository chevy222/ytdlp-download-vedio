# yt-dlp-download —— 双击即用的 1080P 视频下载器

单文件 Windows 批处理脚本，封装 [yt-dlp](https://github.com/yt-dlp/yt-dlp)：**双击 → 粘贴链接 → 桌面上得到一个音量拉满、封面完整、1080P 的 mp4**。

> **一句话简介：** 一个双击即用的 Windows 视频下载器：yt-dlp 抓 1080P mp4、自动嵌封面与元数据、按站点分流代理与 Cookie，源超过 1080P 时用 Intel QSV HEVC 硬件转码缩到 1080P（封面与音轨原样保留），下载完成后音频峰值自动归一到 0 dBFS 且不削波。

本仓库基于 [chevy222/ytdlp-download-vedio](https://github.com/chevy222/ytdlp-download-vedio) 演进，在保留其所有优点（纯 ASCII、Node JS 运行时、SOCKS5 分流、`lang` 排序、AMPLIFY 音量归一化、HOST 匹配 Cookie、循环模式、`f URL` 列格式、拖拽支持）的基础上，新增**超分辨率智能转码链路**。

---

## 与上游参考脚本的核心差异

| 维度 | 参考脚本 (ytdlp-download-vedio) | 本脚本 |
|---|---|---|
| >1080P 源 | 格式串硬过滤 `height<=1080`，4K-only 视频**下不到** | 允许回落 `bv*+ba`，抓到 4K 后自动 **Intel QSV HEVC 硬件转码**到 1080P；QSV 不可用时回落 `libx265` 软件编码 |
| 视频重编码 | 永远 `-c:v copy`（画质零损失，但拿不到 4K 内容） | ≤1080P 源仍是 `-c:v copy`；>1080P 源才触发重编码 |
| 封面在转码后 | N/A（不转码） | `-map 0 -c copy -c:v:0 hevc_qsv -filter:v:0 scale=-2:1080`，只重编主视频流，mjpeg 封面流原样保留、`attached_pic=1` 标记不丢 |
| 其它所有特性 | — | 与参考脚本一致 |

---

## 功能一览

| 项目 | 行为 |
|---|---|
| 画质 | 最高 1080P，H.264+AAC 优先直拷；>1080P 源自动 QSV HEVC 硬件转码到 1080P |
| 容器 | 统一 MP4（`--merge-output-format mp4 --remux-video mp4`） |
| 封面 | 缩略图转 JPG 后作为 attached_pic 嵌入（`--embed-thumbnail --convert-thumbnails jpg`），转码链路中通过 `-map 0` 保留 |
| 元数据 | 标题、UP 主、来源链接、语言标签写入文件（`--embed-metadata`） |
| 字幕 | 不下载、不嵌入（`--no-write-subs --no-write-auto-subs --no-embed-subs`） |
| 音轨 | `-S "vcodec:h264,lang,..."` 中的 `lang` 字段让**原声音轨**在多音轨视频里胜出配音轨 |
| 音量 | 下载完成后峰值归一到 0 dBFS，保证不削波（见[音量放大原理](#音量放大原理amplify)） |
| 代理 | 仅 `youtube.com` / `youtu.be` / `pornhub.com` 走 `socks5://127.0.0.1:10808`，其它直连 |
| Cookie | 按 URL 真实 HOST 自动匹配（如 `m.bilibili.com_cookies.txt`），带站点级回退到 `www.<site>.com_cookies.txt` |
| 合集 | `--no-playlist`，只下你点开的那一个视频 |
| 并发 | `-N 4`（`--concurrent-fragments 4`），DASH/HLS 分片并行下载，B 站与 YouTube 提速 2–4 倍 |
| 输入方式 | 双击后粘贴 / 把链接拖到 .bat 图标上 / 作为 `%1` 参数传入（后两种单次运行不进循环） |
| 列格式 | URL 前加 `f ` 只列出可用画质不下载，排查利器 |
| 退出 | 循环模式下输入 `q` / `quit` / `exit` |
| 文件名 | `%(title).180B.%(ext)s`；多 P 视频标题自带 `p01`/`p02` 序号（yt-dlp 提取器行为），天然防重名 |
| 同名文件 | `--no-overwrites`，重复下载会跳过；想重下请先删旧文件 |
| 脚本编码 | **纯 ASCII，无 BOM，无 chcp**，任何 Windows 代码页下都不会乱码 |

---

## 环境要求

| 工具 | 版本 / 说明 |
|---|---|
| Windows 10 / 11 | 用 `cmd.exe`，主流程**不需要 PowerShell** |
| [yt-dlp.exe](https://github.com/yt-dlp/yt-dlp/releases) | 建议 2025.11 起（YouTube 开始强制要求 JS 运行时） |
| ffmpeg + ffprobe | 放同一目录；用于音画合并、封面嵌入、转码与音量处理。ffmpeg 需带 **hevc_qsv** 编码器（Intel 核显）；无 QSV 会自动回落 libx265 |
| node.exe（或 deno） | yt-dlp 默认只启用 deno，本脚本显式指向 node，YouTube 必需。Node ≥ 20.0 |
| Cookie 文件 | Netscape 格式。**B 站必需**（无 cookie 请求会返回 HTTP 412），YouTube / Pornhub 视登录需求可选 |
| Intel 核显（可选） | 有则 QSV HEVC 硬件转码，速度快、CPU 占用低；没有则用 libx265 软件编码，慢但结果一致 |

---

## 快速开始

### 1. 修改 CONFIG 段指向你的路径

打开 `yt-dlp-download.bat`，顶部 CONFIG 区所有可调项集中在一起：

```bat
set "YTDLP_DIR=D:\Software\yt-dlp"
set "FFMPEG_DIR=D:\Software\ffmpeg\bin"
set "NODE_DIR=D:\Software\node-v26.7.0-win-x64"
set "OUT_DIR=%USERPROFILE%\Desktop"
set "PROXY_URL=socks5://127.0.0.1:10808"
set "COOKIE_DIR=%YTDLP_DIR%"
set "MAX_H=1080"
set "OUT_TPL=%%(title).180B.%%(ext)s"
set "FRAGMENTS=4"
set "AMPLIFY_ON=1"
set "TRANSCODE_ON=1"
```

| 变量 | 作用 | 建议 |
|---|---|---|
| `YTDLP_DIR` | yt-dlp.exe 所在目录 | 找不到会回落到 PATH |
| `FFMPEG_DIR` | ffmpeg.exe / ffprobe.exe 所在目录 | 找不到会回落到 PATH |
| `NODE_DIR` | node.exe 所在目录（YouTube 必需） | 找不到会回落 PATH 里的 node → deno |
| `OUT_DIR` | 下载输出目录 | `%USERPROFILE%\Desktop` 不存在时自动回落 `%OneDrive%\Desktop` |
| `PROXY_URL` | 代理地址（仅 YouTube / Pornhub 使用） | v2rayN 默认 SOCKS5 端口 10808；HTTP 端口就改成 `http://` |
| `COOKIE_DIR` | Cookie 目录 | 默认与 yt-dlp 同目录 |
| `MAX_H` | 最大高度上限，超过则触发 QSV HEVC 转码 | 1080；改 720 可省空间 |
| `OUT_TPL` | 输出文件名模板 | 见[文件名模板备选](#文件名模板备选) |
| `FRAGMENTS` | DASH/HLS 并发分片数 | 4；被限速时改成 1 |
| `AMPLIFY_ON` | 音量归一化开关 | 1 开 / 0 关 |
| `TRANSCODE_ON` | >MAX_H 转码开关 | 1 开 / 0 关（关掉后 4K 源将保留 4K） |

### 2. 按域名放 Cookie

Cookie 文件放到 `%COOKIE_DIR%`（默认 `D:\Software\yt-dlp\`），命名规则 `<HOST>_cookies.txt`：

```
www.bilibili.com_cookies.txt     B 站必需，否则 HTTP 412
www.youtube.com_cookies.txt      可选，YouTube 要求登录时才需要
www.pornhub.com_cookies.txt      可选
m.bilibili.com_cookies.txt       移动端分享链会自动匹配这个（如果放了）
```

匹配顺序：
1. 从 URL 提取真实 HOST（如 `www.bilibili.com`），找 `<HOST>_cookies.txt`
2. 找不到则回落到 `www.<SITE>.com_cookies.txt`（SITE = youtube / bilibili / pornhub / other）
3. 都找不到就匿名下载

### 3. 双击运行

```
============================================================
  Video Downloader   output: C:\Users\you\Desktop
  Paste a URL and press Enter   ("f URL" = list formats only)
  Type q and press Enter to quit
============================================================

Enter URL: https://www.bilibili.com/video/BV1xx411c7mD

  Site     : bilibili   [ www.bilibili.com ]
  Proxy    : direct, no proxy
  Cookie   : D:\Software\yt-dlp\www.bilibili.com_cookies.txt
  Quality  : up to 1080p / H.264+AAC preferred / mp4
  Node     : --js-runtimes node:D:\Software\node-v26.7.0-win-x64
  Mode     : download

[yt-dlp 输出...]
  Transcode: source height 1080p           <-- ≤1080P，跳过转码
  Volume   : peak -9.5 dB, amplified 9.5 dB to full scale (audio 128k, video untouched)

  Done. Files are in: C:\Users\you\Desktop
```

---

## 画质与转码链路

### 格式选择串（`FORMAT`）

六级回落，从"最优直拷"到"下载后转码"：

```
bv*[height<=1080][vcodec*=avc]+ba[acodec*=mp4a]   1. H.264 + AAC，纯 stream copy 到 MP4，零重编码
bv*[height<=1080][vcodec*=avc]+ba                 2. H.264 + 任意音频（音频会被 yt-dlp 转成 AAC 合入 MP4）
bv*[height<=1080]+ba                              3. 任意编码 ≤1080P + 最佳音频
b[height<=1080]                                   4. 单文件 ≤1080P（无分离音视频流的老视频）
bv*+ba                                            5. 任意分辨率最佳音视频（触发 TRANSCODE）
b                                                 6. 单文件兜底
```

### 排序策略（`SORT`）

```
vcodec:h264, lang, quality, res, fps, acodec:aac, size, proto, ext
```

- `vcodec:h264` —— 同等条件下 H.264 优先，避免 VP9/AV1 强制重编
- `lang` —— **原声音轨优先于配音轨**（YouTube 多语言音轨的关键）
- `quality, res, fps` —— 画质、分辨率、帧率依次比较
- `acodec:aac` —— AAC 优先，MP4 原生支持
- `size, proto, ext` —— 兜底：文件小的优先、协议稳的优先、扩展名兼容的优先

### TRANSCODE 子程序

只有源高度 > `MAX_H` 时才触发（例如 4K YouTube 视频）。核心命令：

```bat
ffmpeg -y -i src.mp4 ^
  -map 0 -c copy ^
  -c:v:0 hevc_qsv -global_quality 22 -preset slower -tag:v:0 hvc1 ^
  -filter:v:0 "scale=-2:1080" ^
  -movflags +faststart dst.mp4
```

关键技巧：
- `-map 0` 拿到全部流（主视频 / 音频 / mjpeg 封面 / 章节 / 字幕）
- `-c copy` 默认全部 stream copy
- `-c:v:0 hevc_qsv` **只对第一条视频流**（主内容）重编码，封面（通常是 v:1 mjpeg）保持 copy
- `-filter:v:0 scale=-2:1080` 缩放也只作用于 v:0
- `-tag:v:0 hvc1` 让 Apple 设备/QuickTime 能播放 HEVC

QSV 失败（无 Intel 核显、驱动异常、编码器不支持）会自动回落到 libx265 软件编码：

```bat
-c:v:0 libx265 -crf 22 -preset medium
```

### 转码链路实测验证

用一个伪造的 4K 源（3840×2160 H.264 + AAC 音轨 + mjpeg 封面 `attached_pic=1`）跑完 QSV HEVC 转码：

| 流 | 源 | 输出 |
|---|---|---|
| v:0 | h264 3840×2160 | **hevc 1920×1080**，`hvc1` tag ✓ |
| a:0 | aac 44.1kHz mono 116kbps | aac 44.1kHz mono 116kbps（参数完全一致，纯 copy）✓ |
| v:1 | mjpeg 320×320 `attached_pic=1` | **mjpeg 320×320 `attached_pic=1`**（封面完整保留）✓ |

---

## 音量放大原理（AMPLIFY）

下载下来的视频经常母带音量偏小。每次下载成功后（以及 TRANSCODE 之后），脚本会把音频归一化到不削波前提下的最大音量——经典的两遍式峰值归一化：

1. `ffmpeg -af volumedetect` 测出真实峰值（例如 `max_volume: -9.5 dB`）
2. 增益 = 该值去掉负号 = `9.5 dB`，正好把最高峰推到 0 dBFS
3. 跳过规则（任一命中即不动）：
   - 峰值已在 `-0.x dB`（接近满刻度，增益 <1 dB 不值得重编）
   - 峰值为正（源本身已削波，再放大只会更糟）
   - 文件含多条音轨（`volumedetect` 只测了一条，一个码率也塞不下多轨）
   - 没有音轨
4. 视频流 `-c:v copy` **完全不重编**，画质零损失；封面靠 `-map 0` 保留
5. 音轨重编为 AAC，码率跟随源文件，夹在 64–192k

```
源峰值 : -9.5 dB
增益   : 9.5 dB
结果   : 0.0 dB  （满刻度，无削波）
```

关闭：CONFIG 段 `set "AMPLIFY_ON=0"`。

---

## 站点分流

URL 检测靠 `findstr` 匹配关键字，命中即分流：

| 站点关键字 | SITE 标签 | 代理 | Cookie 回落 |
|---|---|---|---|
| `youtube.com` / `youtu.be` | youtube | SOCKS5 10808 | `www.youtube.com_cookies.txt` |
| `pornhub.com` | SOCKS5 10808 | `www.pornhub.com_cookies.txt` |
| `bilibili.com` / `b23.tv` | bilibili | 直连 | `www.bilibili.com_cookies.txt` |
| 其它 | other | 直连 | 无 |

Cookie 匹配优先看 URL 的真实 HOST，站点级回退只是兜底。

---

## 使用技巧

### 三种输入方式

**a) 双击 → cmd 循环输入**

```
Enter URL: <粘贴链接>
Enter URL: <再来一个>
Enter URL: q     <-- 退出
```

**b) 拖链接到 .bat 图标上**

从浏览器地址栏拖 URL 到脚本图标，单次运行不进循环，下完自动结束。

**c) 命令行传参**

```cmd
yt-dlp-download.bat https://www.bilibili.com/video/BV1xx411c7mD
```

### 只列可用画质（`f ` 前缀）

排查"为什么没 1080P"、"这个视频有几种音轨"时用：

```
Enter URL: f https://www.youtube.com/watch?v=xxx
```

yt-dlp 会打印所有可用格式，不下载。

### URL 清洗

脚本会自动去掉粘贴带进来的引号和所有空格，从浏览器地址栏复制的尾随空白不会造成问题。

### 文件名模板备选

CONFIG 段的 `OUT_TPL` 可以改成：

```bat
set "OUT_TPL=%%(uploader)s - %%(title).180B.%%(ext)s"           <-- 加 UP 主前缀
set "OUT_TPL=%%(upload_date)s %%(title).180B.%%(ext)s"           <-- 加上传日期前缀
set "OUT_TPL=%%(title).180B [%%(id)s].%%(ext)s"                  <-- 加 BV/视频 ID 后缀，绝对防重名
```

`.180B` 表示标题最多 180 字节，避免超出 Windows 260 字符路径限制。

---

## 注意事项与排错

### B 站 HTTP 412

**B 站不带 cookie 会返回 HTTP 412**，cookie 对 B 站是必需的，不只是为了高清。看到 412 就检查 `D:\Software\yt-dlp\www.bilibili.com_cookies.txt` 是否存在且未过期。

### YouTube 403 / "Sign in to confirm you're not a bot"

按顺序排查：
1. `Node :` 一行是否有值（没有就是 Node.js 没找到）
2. 代理是否开启，`socks5://127.0.0.1:10808` 端口是否真是 SOCKS5
3. 导出 `www.youtube.com_cookies.txt`（登录状态下的 cookie）
4. 极端情况需要 PO Token，参见 yt-dlp 官方 wiki

### 代理相关

- 下载失败后脚本会打印常见原因清单，先看那个
- 确认 `127.0.0.1:10808` 是 SOCKS5 端口（v2rayN 默认）。如果是 HTTP 端口，把 `PROXY_URL` 里的 `socks5` 改成 `http`
- 想全局不用代理：`set "PROXY_URL="` 或直接注释掉 site detection 里的 `PROXY_OPT` 赋值

### 同名文件被跳过

`--no-overwrites` 是刻意的，避免误重下。想重下请先删旧文件，或临时改成 `--force-overwrites`。

### QSV 转码失败

如果看到 `Transcode: QSV failed, falling back to libx265 (software)...`：
- 机器没有 Intel 核显（AMD/纯 CPU） → 正常，libx265 兜底
- Intel 核显驱动过旧 → 升级到最新 Intel Graphics Driver
- ffmpeg 是不带 QSV 的构建 → 换官方 gyan.dev 或 BtbN 的完整构建

libx265 兜底速度大约是 QSV 的 1/5–1/10，但结果画质一致。

### 音轨没被 AMPLIFY

看到 `Volume : N audio tracks, skipped` 就是多音轨视频（例如 YouTube 多语言音轨），脚本刻意不动它——因为 volumedetect 只测了一条，一个 AAC 码率也塞不下多轨。想强行处理请手动用 ffmpeg。

### 为什么脚本是纯 ASCII

- **UTF-8 BOM 会破坏批处理文件的第一行**：cmd 把 3 字节 BOM 当命令前缀，`@echo off` 变乱码，整个脚本被回显
- **脚本中途用 `chcp 65001` 切换代码页**会让 cmd 的字节偏移错位（多字节字符场景下 `rem` 被切成 `em`，行被拆散，半句话被当命令执行）
- **纯 ASCII 在 UTF-8 和 GBK 下字节完全相同**，两种坑都不存在

所以本脚本**必须**保存为纯 ASCII（= UTF-8 无 BOM = ANSI，字节一致）。要加中文注释请另存为 GBK，不要存 UTF-8。

---

## 已知限制

- **多音轨视频不做音量归一化**：见上文 AMPLIFY 跳过规则
- **播放列表不下**：`--no-playlist`，只下 URL 指向的单个视频。想下整个播放列表请手动去掉这个参数
- **>1080P 源必然重编码**：无法"零损失"降到 1080P；想要零损失请把 `MAX_H` 改成 2160 或 `TRANSCODE_ON=0`（然后接受 4K 文件）
- **封面格式限 JPG**：MP4 容器的 attached_pic 只吃 mjpeg，yt-dlp 用 `--convert-thumbnails jpg` 自动转换
- **QSV HEVC 需要 Intel 核显**：AMD/纯 CPU 机器会走 libx265 软编，慢很多

---

## 目录结构

```
yt-dlp-download/
├── yt-dlp-download.bat     单文件脚本，所有逻辑都在这里
└── README.md               本文档
```

依赖工具**不在**本仓库，需自行安装到 CONFIG 段指向的路径：

```
D:\Software\yt-dlp\
├── yt-dlp.exe
├── www.bilibili.com_cookies.txt
├── www.youtube.com_cookies.txt      (可选)
└── ...

D:\Software\ffmpeg\bin\
├── ffmpeg.exe
├── ffprobe.exe
└── ffplay.exe

D:\Software\node-v26.7.0-win-x64\
└── node.exe
```

---

## 许可证

MIT —— 随便用，不提供任何担保。
