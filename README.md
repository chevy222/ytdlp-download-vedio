# yt-dlp-download —— 双击即用的 1080P 视频下载器

单文件 Windows 批处理脚本，封装 [yt-dlp](https://github.com/yt-dlp/yt-dlp)：**粘贴链接 → 得到一个音量拉满、封面完整、1080P 的 mp4**。下到哪由你决定：在哪个目录打开 cmd，就下到哪个目录，双击运行则落到桌面。

> **一句话简介：** 一个双击即用的 Windows 视频下载器：yt-dlp 抓 1080P mp4、自动嵌封面与元数据、按站点分流代理与 Cookie，源超过 1080P 时用 Intel QSV HEVC 硬件转码缩到 1080P（封面与音轨原样保留），下载完成后音频峰值自动归一到 0 dBFS 且不削波；输出目录跟随 cmd 的当前目录，桌面兜底。

---

## 与旧脚本的核心差异

| 维度       | 旧版本                                     | 新脚本                                                                                                                           |
| -------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| >1080P 源 | 格式串硬过滤 `height<=1080`，4K-only 视频**下不到** | 允许回落 `bv*+ba`，抓到 4K 后自动 **Intel QSV HEVC 硬件转码**到 1080P；QSV 不可用时回落 `libx265` 软件编码                                              |
| 视频重编码    | 永远 `-c:v copy`（画质零损失，但拿不到 4K 内容）        | ≤1080P 源仍是 `-c:v copy`；>1080P 源才触发重编码                                                                                         |
| 封面在转码后   | N/A（不转码）                                | `-map 0 -c copy -c:v:0 hevc_qsv -filter:v:0 scale=<短边定向：竖屏 1080:-2 / 横屏 -2:1080>`，只重编主视频流，mjpeg 封面流原样保留、`attached_pic=1` 标记不丢 |
| 其它所有特性   | —                                       | 与参考脚本一致                                                                                                                       |

---

## 功能一览

| 项目     | 行为                                                                                             |
| ------ | ---------------------------------------------------------------------------------------------- |
| 画质     | 最高 1080P（按**短边**计：竖屏 Shorts 的 1080x1920 就是 1080P），H.264+AAC 优先直拷；超过则自动 QSV HEVC 硬件转码到 1080P    |
| 容器     | 统一 MP4（`--merge-output-format mp4 --remux-video mp4`）                                          |
| 封面     | 缩略图转 JPG 后作为 attached_pic 嵌入（`--embed-thumbnail --convert-thumbnails jpg`），转码链路中通过 `-map 0` 保留 |
| 元数据    | 标题、UP 主 / 作者、来源链接写入文件（`--embed-metadata`）。实测抖音产物：`title=@xx创作的原声`、`artist=xx`、`comment=<视频链接>`；音轨的 `language` 标签来自源文件本身（常见为 `und`），脚本不改它 |
| 字幕     | 不下载、不嵌入（`--no-write-subs --no-write-auto-subs --no-embed-subs`）                                |
| 音轨     | `-S "vcodec:h264,lang,..."` 中的 `lang` 字段让**原声音轨**在多音轨视频里胜出配音轨                                  |
| 音量     | 下载完成后峰值归一到 0 dBFS，保证不削波（见[音量放大原理](#音量放大原理amplify)）                                             |
| 代理     | 仅 `youtube.com` / `youtu.be` / `pornhub.com` / `x.com` / `twitter.com` 走 `socks5://127.0.0.1:10808`，其它直连  |
| Cookie | 按 URL 真实 HOST 自动匹配（如 `m.bilibili.com_cookies.txt`），带站点级回退到 `www.<site>.com_cookies.txt`；X/Twitter 额外回退到 `x.com` ↔ `twitter.com` 姊妹域名 |
| 合集     | `--no-playlist`，只下你点开的那一个视频                                                                    |
| 并发     | `-N 4`（`--concurrent-fragments 4`），DASH/HLS 分片并行下载，B 站与 YouTube 提速 2–4 倍                       |
| 输入方式   | 双击后粘贴 / 把链接拖到 .bat 图标上 / 作为 `%1` 参数传入（后两种单次运行不进循环，失败时会暂停显示原因）                                  |
| 输出目录   | 跟随 cmd 的**当前目录**（`OUT_MODE=cwd`）：自己在哪打开 cmd、`cd` 到哪就下到哪；双击 / 拖拽 / 快捷方式启动时 cmd 落在脚本自己所在目录，这种情况回落桌面。可改成 `OUT_MODE=desktop` 固定下桌面 |
| emoji 标题 | 标题里有 emoji 也能正常走完探测 / 转码 / 放大（控制台切 UTF-8，见[为什么脚本是纯 ASCII](#为什么脚本是纯-ascii)）。旧版会静默跳过后处理 |
| 列格式    | URL 前加 `f ` 只列出可用画质不下载，排查利器                                                                    |
| 退出     | 循环模式下输入 `q` / `quit` / `exit`                                                                  |
| 文件名    | `%(title).180B.%(ext)s` + `--windows-filenames`（非法字符交给 yt-dlp 清洗）；多 P 视频标题自带 `p01`/`p02` 序号（yt-dlp 提取器行为），天然防重名                          |
| 同名文件   | `--no-overwrites`，重复下载会跳过；想重下请先删旧文件                                                            |
| 脚本编码   | **纯 ASCII，无 BOM**；启动时 `chcp 65001`、退出还原（见[为什么脚本是纯 ASCII](#为什么脚本是纯-ascii)）                          |

---

## 环境要求

| 工具                                                      | 版本 / 说明                                                                            |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Windows 10 / 11                                         | 用 `cmd.exe`，主流程**不需要 PowerShell**                                                  |
| [yt-dlp.exe](https://github.com/yt-dlp/yt-dlp/releases) | 建议 2025.11 起（YouTube 开始强制要求 JS 运行时）                                                |
| ffmpeg + ffprobe                                        | 放同一目录；用于音画合并、封面嵌入、转码与音量处理。ffmpeg 需带 **hevc_qsv** 编码器（Intel 核显）；无 QSV 会自动回落 libx265 |
| node.exe（或 deno）                                        | yt-dlp 默认只启用 deno，本脚本显式指向 node，YouTube 必需。Node ≥ 22.0（yt-dlp 官方最低要求）               |
| Cookie 文件                                               | Netscape 格式。**B 站必需**（无 cookie 请求会返回 HTTP 412），**X/Twitter 必需登录态 cookie**（否则报 Login required），**抖音建议放**（实测带 `www.douyin.com_cookies.txt` 可正常解析），YouTube / Pornhub 视登录需求可选           |
| Intel 核显（可选）                                            | 有则 QSV HEVC 硬件转码，速度快、CPU 占用低；没有则用 libx265 软件编码，慢但结果一致                              |

---

## 快速开始

### 1. 修改 CONFIG 段指向你的路径

打开 `download_video.bat`，顶部 CONFIG 区所有可调项集中在一起：

```bat
set "YTDLP_DIR=D:\Software\yt-dlp"
set "FFMPEG_DIR=D:\Software\ffmpeg\bin"
set "NODE_DIR=D:\Software\node-v26.7.0-win-x64"
set "OUT_MODE=cwd"
set "DESKTOP_DIR=%USERPROFILE%\Desktop"
set "PROXY_URL=socks5://127.0.0.1:10808"
set "COOKIE_DIR=%YTDLP_DIR%"
set "MAX_H=1080"
set "OUT_TPL=%%(title).180B.%%(ext)s"
set "FRAGMENTS=4"
set "AMPLIFY_ON=1"
set "TRANSCODE_ON=1"
set "MAX_DL_H=2160"
set "MAXGAIN=24"
set "X265_PRESET=fast"
set "AUTO_UPDATE=0"
```

| 变量             | 作用                                                      | 建议                                                    |
| -------------- | ------------------------------------------------------- | ----------------------------------------------------- |
| `YTDLP_DIR`    | yt-dlp.exe 所在目录                                         | 找不到会回落到 PATH                                          |
| `FFMPEG_DIR`   | ffmpeg.exe / ffprobe.exe 所在目录                           | 找不到会回落到 PATH                                          |
| `NODE_DIR`     | node.exe 所在目录（YouTube 必需）                               | 找不到会回落 PATH 里的 node → deno                            |
| `OUT_MODE`     | 输出目录策略：`cwd` = 用 cmd 的当前目录、不合适才回落桌面；`desktop` = 永远桌面            | `cwd`                                                  |
| `DESKTOP_DIR`  | 回落 / 固定用的桌面目录                                             | `%USERPROFILE%\Desktop` 不存在时自动回落 `%OneDrive%\Desktop` |
| `PROXY_URL`    | 代理地址（仅 YouTube / Pornhub / X(Twitter) 使用）                            | v2rayN 默认 SOCKS5 端口 10808；HTTP 端口就改成 `http://`        |
| `COOKIE_DIR`   | Cookie 目录                                               | 默认与 yt-dlp 同目录                                        |
| `MAX_H`        | 最大画质上限（按**短边**计，竖屏 1080x1920 = 1080P），超过则触发 QSV HEVC 转码 | 1080；改 720 可省空间                                       |
| `OUT_TPL`      | 输出文件名模板                                                 | 见[文件名模板备选](#文件名模板备选)                                  |
| `FRAGMENTS`    | DASH/HLS 并发分片数                                          | 4；被限速时改成 1                                            |
| `AMPLIFY_ON`   | 音量归一化开关                                                 | 1 开 / 0 关                                             |
| `TRANSCODE_ON` | >MAX_H 转码开关                                             | 1 开 / 0 关（关掉后 4K 源将保留 4K）                             |
| `MAX_DL_H`     | **下载**高度的硬上限，防止 8K-only 源下几十 GB                         | 2160；见[格式链](#格式选择串format)                             |
| `MAXGAIN`      | 音频增益上限 dB                                               | 24；防止近静音源被放大 50-90 dB 把底噪推到满刻度                        |
| `X265_PRESET`  | libx265 兜底 preset                                       | `fast`（比 `medium` 快约一倍，观感几乎无差）                        |
| `AUTO_UPDATE`  | 启动时跑一次 `yt-dlp -U`                                      | 0 关 / 1 开                                             |

### 2. 按域名放 Cookie

Cookie 文件放到 `%COOKIE_DIR%`（默认 `D:\Software\yt-dlp\`），命名规则 `<HOST>_cookies.txt`：

```
www.bilibili.com_cookies.txt     B 站必需，否则 HTTP 412
www.youtube.com_cookies.txt      可选，YouTube 要求登录时才需要
www.pornhub.com_cookies.txt      可选
www.douyin.com_cookies.txt       抖音建议放（实测带上后能正常解析），本机已放
m.bilibili.com_cookies.txt       移动端分享链会自动匹配这个（如果放了）
v.douyin.com_cookies.txt         抖音短链走这个域名，放了才会被匹配到
x.com_cookies.txt                X/Twitter 必需（登录态），配合代理才能拿到视频
twitter.com_cookies.txt          与 x.com 通用，二者放其一即可，姊妹域名会自动互相回退
```

> `www.douyin.com` 与 `v.douyin.com` 是**两个不同的 HOST**，脚本按 HOST 匹配，所以短链要单独放一份（或者干脆把短链先展开成 `www.douyin.com/video/<id>` 再喂给脚本）。

匹配顺序：

1. 从 URL 提取真实 HOST（如 `www.bilibili.com`），找 `<HOST>_cookies.txt` —— **抖音、快手这类非内置站点走的就是这一步**
2. 找不到则回落到 `www.<SITE>.com_cookies.txt`（SITE = youtube / bilibili / pornhub / twitter / other；对 `other` 来说这一级等于没用）
3. X/Twitter 专属再回退：`www.x.com_cookies.txt` → `x.com_cookies.txt` → `twitter.com_cookies.txt`（因为 `x.com` 与 `twitter.com` 是同一账号同一会话，导出哪个域名、放哪个文件名都能解锁另一个，双向对称）
4. 都找不到就匿名下载

### 3. 运行

下载到哪，取决于你怎么启动它（`OUT_MODE=cwd`）：

| 启动方式                              | cmd 的当前目录         | 实际输出目录      |
| --------------------------------- | ----------------- | ----------- |
| 自己开 cmd → `cd D:\Videos` → 运行脚本   | `D:\Videos`       | `D:\Videos` |
| 在该目录里写个 .bat 快捷方式并运行               | 快捷方式的「起始位置」       | 该目录         |
| 双击 `download_video.bat`           | 脚本自己所在目录          | 桌面（回落）      |
| 把链接拖到 .bat 图标上                     | 脚本自己所在目录          | 桌面（回落）      |
| 右键「以管理员身份运行」                      | `C:\Windows\System32` | 桌面（回落）      |

「不合适」的目录一律回落桌面：脚本自身目录、盘根（`C:\`）、UNC 路径（`\\server\share`）、`System32` 系，以及**写不进去的目录**（启动时用一个临时小文件探一次，探完立刻删）。

```
============================================================
  Video Downloader   output: "C:\Users\you\Desktop"
  Paste a URL and press Enter   ("f URL" = list formats only)
  Type q and press Enter to quit
============================================================

Enter URL: https://www.bilibili.com/video/BV1xx411c7mD

  Site     : bilibili   [ "www.bilibili.com" ]
  Proxy    : direct, no proxy
  Cookie   : "D:\Software\yt-dlp\www.bilibili.com_cookies.txt"
  Quality  : up to 1080p / H.264+AAC preferred / mp4
  Node     : --js-runtimes "node:D:\Software\node-v26.7.0-win-x64"
  Mode     : download

[yt-dlp 输出...]
  File     : "C:\Users\you\Desktop\Some Title.mp4"
  Rebuild  : video copy / +9.5dB @ 128k    <-- ≤1080P：视频流零重编，只放大音量
  Rebuild  : done

  Done. Files are in: C:\Users\you\Desktop
```

---

## 画质与转码链路

### 格式选择串（`FORMAT`）

七级回落，从"最优直拷"到"兜底"，能不重编码就不重编码。

**为什么要同时限制宽和高**：yt-dlp 的过滤器只能分别测 width / height，而"1080P"有两种形态——横屏 1920x1080、竖屏 1080x1920（YouTube Shorts）。如果只写 `height<=1080`，竖屏 1080P 流（高度 1920）会被前几级整级排除，实际回落到 **480x854**。所以前四级改用 `MAX_LONG = MAX_H*16/9`（1080→1920，脚本自动计算）**同时卡宽和高**：两种方向的 1080P 都放行，1440P+（2560x1440 / 1440x2560）依然被挡住。

```
bv*[h<=1920][w<=1920][vcodec*=avc]+ba[acodec*=mp4a]  1. H.264 + AAC，纯 stream copy 到 MP4，零重编码
bv*[h<=1920][w<=1920][vcodec*=avc]+ba                2. H.264 + 任意音频（音频会被 yt-dlp 转成 AAC 合入 MP4）
bv*[h<=1920][w<=1920]+ba                             3. 任意编码 ≤1080P + 最佳音频
b[h<=1920][w<=1920]                                  4. 单文件 ≤1080P（原生 ≤1080P 就不下载更大的流再转回来）
bv*[h<=3840][w<=3840]+ba                             5. 任意编码 ≤2160 + 最佳音频（触发重建，MAX_DL_H 挡住 8K）
bv*+ba                                               6. 任意分辨率最佳音视频
b                                                    7. 单文件兜底
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

> 这串排序基本就是 yt-dlp 内置的 `-t mp4` 预设（`-S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac`，可用 `yt-dlp --help` 查到），脚本复刻它并追加了 `size,proto,ext`。**唯一的差异是少了 `hdr:12`**（官方预设想让 SDR 排在 HDR 前面）：本脚本 `vcodec:h264` 已经把 H.264 排在前面，SDR/HDR 之争通常轮不到；只有当某个视频压根没有 H.264 档、而 AV1/VP9 同时有 SDR 和 HDR 时，脚本可能选中 HDR 那档。真遇到了，把 `hdr:12` 插到 `fps` 后面即可。

> **前两级对抖音 / B 站不生效，这没关系。** 那两级用 `[vcodec*=avc]` 卡编码，匹配的是 yt-dlp 报出来的**编码名字符串**：YouTube 报 `avc1.640028`（含 `avc`）→ 命中；抖音 / B 站报的是 `h264` / `h265`（不含 `avc`）→ 前两级落空，落到第 3 级。第 3 级不带编码限制，但 `SORT` 里的 `vcodec:h264` 仍然把 H.264 排在最前，最终选出来还是 H.264+AAC。实测抖音：`[info] Downloading 1 format(s): h264_540p_1500787-3`（同分辨率下它优先选了 h264 那档，而不是码率更高的 `bytevc1_*`/H.265）。

### 重建子程序（REBUILD）

下载完成后只跑**一次** ffmpeg，把「>MAX_H 降分辨率」和「音量归一化」一起做掉——早期版本是 TRANSCODE 写一遍、AMPLIFY 再写一遍，4K 大文件等于重写两次。

流程：

1. `PROBE_HEIGHT`：ffprobe **一次**读取 v:0 的编码与宽高——编码用于识别封面流（mjpeg/png/bmp/gif 若在 v:0，真实视频在 v:1，转码作用到 v:1，尺寸也改从 v:1 读取）；宽高**取短边**与 MAX_H 比较（竖屏 1080x1920 即 1080P，高度 1920 不会误触发降尺度），非数字（`N/A`）直接跳过。
2. `PROBE_AUDIO`：ffprobe **一次**拿到音轨数与 a:0 码率 → `volumedetect` 峰值 → 增益（上限 `MAXGAIN` dB）。
3. 两个都不需要改动时**直接跳过**，完全不重写文件。
4. 需要改动才调用 `REBUILD`，一条命令完成：

```bat
ffmpeg -y -i src.mp4 ^
  -map 0 -c copy ^
  [-c:v:0 hevc_qsv -global_quality 22 -preset slower -tag:v:0 hvc1 -filter:v:0 scale=<竖屏 1080:-2 / 横屏 -2:1080>] ^
  [-af volume=+9.5dB -c:a aac -b:a 128k] ^
  -f mp4 -movflags +faststart "src.mp4.rebuild"
```

注意产物名是 `src.mp4.rebuild`（**故意不带 `.mp4` 后缀**，理由见[临时文件的生命周期](#临时文件的生命周期)），因此输出必须显式 `-f mp4` 告诉 ffmpeg 用哪个封装——扩展名缺了 `.mp4`，ffmpeg 就没法自己推断。

缩放目标**按方向自动选择**：短边超过 MAX_H 才触发，竖屏（Shorts）封宽度（`1080:-2`），横屏封高度（`-2:1080`），保证 4K 竖屏源（1440x2560）正确降到 1080x1920 而不是 608x1080。

- `-map 0 -c copy` 拿到全部流（主视频 / 音频 / mjpeg 封面 / 章节）
- 只有主视频流和音频流被重编码（封面流在 v:0 时自动改作用到 v:1），封面原样保留、`attached_pic` 标记不丢
- **用 `ERRORLEVEL` 而不是 `if not exist` 判断成败**：编码到一半失败时 ffmpeg 会留下残缺文件，只判断"文件存在"会把它 `move` 去覆盖原始下载
- QSV 失败自动回落到 `libx265`（preset 由 `X265_PRESET` 控制）
- 替换前还会校验产物大小（< 1 KB 视为失败，保留原文件）

**实测记录**（本机 ffmpeg + Intel QSV，跑的是脚本里同一条命令）：

| 用例 | 结果 |
| --------------------------------------------- | ---------------------------------------------- |
| 2560x1440（横屏）→ `scale=-2:1080` | hevc 1920x1080 ✓ |
| 1440x2560（竖屏）→ `scale=1080:-2` | hevc 1080x1920 ✓ 短边判定正确 |
| `-hwaccel qsv` + `hwdownload,format=nv12,scale=` | exit 0 ✓ |
| yt-dlp 用 mutagen 写入的 `covr` 封面 | 转码后仍在（`covr` 原子 + `attached_pic` 流都保留）✓ |
| 源文件里封面流的位置 | yt-dlp/mutagen 的 mp4 是 **主视频 v:0、封面 v:1**（`attached_pic=1`），所以 `MAINV` 通常是 0；`MAINV=1` 那条分支是给封面排在前面的容器兜底的 |
| `ffprobe -show_entries stream=codec_name,width,height -of csv=p=0` | 输出 `h264,2560,1440`，与 token1/2/3 对齐 ✓ |
| `volumedetect` 的 `max_volume` 行 | `[Parsed_volumedetect_0 @ ...] max_volume: -17.2 dB`，token5 = `-17.2` ✓ |
| ffmpeg 失败时的退出码 | QSV/滤波失败会给 `4294967274`（= -22）这类大数，`if not "%ERRORLEVEL%"=="0"` 判定为失败 ✓ |
| 输出到 `*.rebuild` + `-f mp4` | exit 0，产物是合法 mp4，`move` 覆盖原文件后 `ffprobe` 读数正确 ✓ |

**整条链路的实测记录**（都跑脚本本体。抖音那条是真实站点；4K / emoji 那两条是把测试片挂在本机 HTTP 服务上，走的是同一条 `yt-dlp → 探测 → REBUILD` 链路，为了能控制分辨率、音量和文件名）：

| 用例 | 结果 |
| --------------------------------------------- | ---------------------------------------------- |
| 抖音 `www.douyin.com/video/7641502032595045642`（768x576 h264+aac 单文件） | 走直连 + `www.douyin.com_cookies.txt`；封面 `mjpeg attached_pic=1` 嵌入、`title/artist/comment` 元数据写入；无转码；音量峰值 `-0.5 dB` 按规则**跳过**放大；文件落到输出目录，临时文件清空 ✓ |
| 2560x1440 h264 + 极小声（需转码 + 放大） | `hevc 1920x1080 + aac`，`Rebuild : scale to 1080p HEVC (source 2560x1440) / +24dB @ 64k`，增益被 `MAXGAIN` 封顶 ✓ |
| 标题含 emoji `⚡` + 括号 + `#` | 探测、转码、放大全部执行，落盘文件名里的 emoji 完好 ✓（修复前此用例后处理会被静默跳过） |

---

### 脚本怎么知道刚下到的文件叫什么

输出文件名来自视频标题（`%(title).180B.%(ext)s`），下载前无法预知，所以脚本有两条路：

1. **首选**：yt-dlp 用 `--print-to-file after_move` 把**真实落盘路径**写进 `%TEMP%\ytdlp_last_<随机数>.txt`（日志最后一行 `Writing '%(filepath)s' to: ...` 就是它）。这个文件是 **UTF-8 无 BOM、CRLF 结尾**（实测字节验证过）。
2. **兜底**：下载前先记下输出目录里最新的 .mp4（按**创建时间**），下载后再取一次，变了就说明那个新文件是本轮产物。只在第 1 条完全没出现时才会用到——例如 yt-dlp 在 `after_move` 之前就失败了，或记录文件读不出来。

**两条路过去都靠“文件名文本往返”活着**，而 cmd 用的是**控制台代码页**。中文 Windows 是 936/GBK，它表示不了任何 emoji，只能替换成 `?`：

以标题 `超级⚡耄里奥.mp4` 为例（实测）：

```
真实文件名        超级⚡耄里奥.mp4
dir /b 给出       超级?耄里奥.mp4           U+26A1 在 GBK 里没有对应字，退化成 1 个 "?"
                                        代理对 emoji（如 U+1F600）会退化成 2 个 "?"
yt-dlp 记录读到    瓒呯骇鈿¤?勯噷濂?.mp4     UTF-8 字节被当 GBK 解码，整串乱码
```

`?` 这一路**比乱码更阴**：`?` 是**通配符**，所以 `if exist "…超级?耄里奥.mp4"` 会**报“文件存在”**，脚本放心把带 `?` 的路径交给 ffprobe，ffprobe 按字面量找文件、找不到、返回空 → 两个探测文件都是 0 字节 → `NEEDV`/`NEEDA` 保持 0 → **整个后处理被静默跳过**（下载、嵌封面、嵌元数据都正常，只是不放大音量、不降分辨率）。

**修法**：脚本启动时把控制台切成 UTF-8（`chcp 65001`），退出时还原。两种往返立刻都无损，中文、emoji、代理对 emoji 全都通过；顺带 yt-dlp 的进度输出也显示正常了。

- 两条都没命中就**不重建任何文件**（没有新文件可重建）
- ⚠️ **`--no-overwrites` 跳过 ≠ 不走后处理**（实测纠正）：重复下同一个 URL 时 yt-dlp 会打印 `has already been downloaded`，但**仍然会跑**后处理器（重新嵌元数据、重新嵌封面），也**仍然会触发 `after_move`**、把路径写进 `ytdlp_last_*.txt`。于是脚本拿到的是那个旧文件，照常探测一遍——只是探测结论通常是"没事可做"（已经降过分辨率、音量已经在 0 dB 附近），所以不会重复转码。可以理解为"重下 = 把已有文件原样复核一遍"，代价是元数据和封面被重写一次
- 兜底看**创建时间**而不是修改时间：yt-dlp 可能拿服务端 `Last-modified` 写 mtime，而刚写出的文件创建时间一定是新的
- 兜底是启发式的：风险窗口只有“下载完成后到取最新值”这一瞬间，但万一你同时往输出目录另存了更新的 mp4，它可能被当成产物重编码
- 探测再也读不出东西时不再闷声跳过，会打印 `Transcode: no usable video info, skipped`

### 临时文件的生命周期

能在这个工具流程里出现的临时文件一共三类：① 脚本自己在 `%TEMP%` 记的 4 个记录文件、② REBUILD 的中间产物、③ yt-dlp 自己在**输出目录**里的分片/半成品。前两类脚本会自己收尾，第三类由 yt-dlp 收尾（中断时不会）。

**① `%TEMP%` 下的 4 个记录文件**（`<RND>` = 每次运行取一次的 `%RANDOM%`，多个实例不会互踩）

| 文件 | 谁写的 | 什么时候写 | 什么时候被删 |
| -------------------------------------- | -------------------- | ------------------------- | --------------------------------- |
| `ytdlp_last_<RND>.txt` | yt-dlp | 下载**成功**后（`--print-to-file after_move`） | 下一轮输入 URL 时立刻删（`:GOT_URL`），以及退出时 |
| `ytdlp_h_<RND>.txt` | ffprobe（PROBE_HEIGHT） | 进入探测且 `TRANSCODE_ON=1` 时 | 退出时（`:END`），中间轮次会被下一轮覆盖 |
| `ytdlp_cnt_<RND>.txt` | ffprobe（PROBE_AUDIO） | 进入探测且 `AMPLIFY_ON=1` 时 | 退出时（`:END`） |
| `ytdlp_vol_<RND>.txt` | ffmpeg（`volumedetect`） | **必须**先通过“音轨数 = 1”这一关才会写 | 退出时（`:END`） |

所以：

- **看不到 `ytdlp_vol_*.txt` 是正常的**——它排在“音轨数检查”之后。只要 ffprobe 读不出音轨（文件打不开 / 输出为空），`ACNT` 就是 0，脚本在写 `vol` 之前就 `exit /b 0` 了，于是只留下另外 3 个。这正是 emoji 标题那次的现场：`ytdlp_h_6442.txt` 和 `ytdlp_cnt_6442.txt` 都是 **0 字节**，`ytdlp_last_6442.txt` 里是 UTF-8 的完整路径，而 `ytdlp_vol_6442.txt` 压根没生成。
- 循环模式下（双击运行、连续下多个），`last` 每轮开头就被删掉，`h`/`cnt`/`vol` 会一直躺到**你输入 `q` 退出**为止——这是设计如此，不是漏删。
- **异常退出**（关窗口、Ctrl-C、崩溃）时 bat 根本没机会跑，4 个文件全留下。所以脚本**每次启动时会先清一遍** `%TEMP%\ytdlp_{last,h,cnt,vol}_*.txt`，异常残留不会无限堆积。
- 多实例并发时，清扫最多让另一个实例的探测文件被重建一次（紧接着的重定向就会重新创建），无害。

**② 视频旁边的一个中间产物**

REBUILD 把结果写到 `<你的视频>.rebuild`，成功就 `move` 覆盖原文件，失败就删掉。故意**不带 `.mp4` 后缀**：“最新 mp4”兜底逻辑扫的是 `*.mp4`，中断留下的产物如果以 `.mp4` 结尾，就会被当成“刚下到的文件”再转一次，滚成 `…rebuild.rebuild`。它是同目录改名（同盘符秒级移动），不会白占一份空间。

**③ yt-dlp 自己的临时文件（在输出目录里）**

不是脚本写的，但会在输出目录出现，排查时容易看花眼。实测两种下载方式：

```
单文件直链（一个 http mp4）   下载中：<标题>.mp4.part
                             完成后：<标题>.mp4

分片下载（DASH / HLS）        下载中：<标题>.mp4.part
                                     <标题>.mp4.part-Frag1.part   <- 正在下的那个分片
                                     <标题>.mp4.ytdl              <- 分片进度记录
                             完成后：<标题>.mp4
```

- 这些后缀是 `.part` / `.ytdl`，**都不以 `.mp4` 结尾**，所以「最新 mp4」兜底扫描不会把它们误当成成品——这点很重要：否则中断残留会被当成“刚下到的文件”再转一遍
- 下载成功后 yt-dlp 自己会全部清掉（实测输出目录只剩最终 mp4）
- 中断则会留下，而且脚本**不清扫**这些（只清自己那 4 个 `%TEMP%` 记录文件），看到直接删即可
- 封面另有一个 `<标题>.jpeg`/`.jpg` 中转文件：下载封面 → 嵌入 mp4 → 删掉。实测抖音那次成功后**不留图**，只有嵌入环节失败或被打断才会残留


### 交互细节

- **空回车不再退出循环**。误触 Enter 只会重新提示，只有 `q` / `quit` / `exit` 才退出（旧版空回车直接结束，和提示语不一致）。
- **站点检测不再用 `echo | findstr`**：先取 HOST，再精确 / 后缀匹配（详见[站点分流](#站点分流)），全程只有变量展开，不启动子进程，URL 里的 `^`、`%` 也不会被管道搞坏。

## 音量放大原理（AMPLIFY）

下载下来的视频经常母带音量偏小。每次下载成功后（已经和 >MAX_H 降分辨率合并进[重建子程序](#重建子程序rebuild)，见下文），脚本会把音频归一化到不削波前提下的最大音量——经典的两遍式峰值归一化：

1. `ffmpeg -af volumedetect` 测出真实峰值（例如 `max_volume: -9.5 dB`）
2. 增益 = 该值去掉负号 = `9.5 dB`，正好把最高峰推到 0 dBFS
3. 跳过规则（任一命中即不动）：
   - 峰值已在 `-0.x dB`（接近满刻度，增益 <1 dB 不值得重编）——实测抖音那条就是 `peak -0.5 dB, already near full scale, skipped`
   - 峰值为正（源本身已削波，再放大只会更糟）
   - 文件含多条音轨（`volumedetect` 只测了一条，一个码率也塞不下多轨）
   - 没有音轨
4. 视频流 `-c:v copy` **完全不重编**，画质零损失；封面靠 `-map 0` 保留
5. 音轨重编为 AAC，码率跟随源文件，夹在 64–192k
6. 增益超过 `MAXGAIN`（默认 24 dB）会被封顶——近静音源放大 50-90 dB 只会把底噪推到满刻度

> 现在这一步和 >MAX_H 降分辨率合并成了一次 ffmpeg 调用，见[重建子程序](#重建子程序rebuild)。

```
源峰值 : -9.5 dB
增益   : 9.5 dB
结果   : 0.0 dB  （满刻度，无削波）
```

> 实测（1000 Hz 正弦 + AAC 128k 重编码）：按 `volume = -峰值` 放大再编码后，测到的峰值比理论值高约 **0.2 dB**。所以“不削波”成立，但准确说法是“0 dBFS ± 0.2 dB”，不是数学上的精确 0。

关闭：CONFIG 段 `set "AMPLIFY_ON=0"`。

---

## 站点分流

先取 HOST，再用 HOST 匹配站点：**精确等于**，或以点结尾的**后缀**（`www.youtube.com`、`m.x.com`）。全程只有变量展开，不起子进程，URL 里的 `^`、`%` 也不会被管道破坏。

> 早期版本直接拿整条 URL 做子串匹配（`%URL:x.com=%`），`netflix.com` / `box.com` / `max.com` 这类域名里也含 `x.com`，会被误判成 X 而强行走代理；而且那个匹配区分大小写。改成 HOST 匹配后两个问题都消失了。
> HOST 提取的 delims 里带了 `:`，所以 `https://x.com:443/...` 得到干净的 `x.com`，cookie 文件名也不带端口。

| 站点 HOST | SITE 标签 | 代理 | Cookie 回落 |
| -------------------------- | ------------ | ----------------------------- | ------------------------------ |
| `youtube.com` / `*.youtube.com` / `youtu.be` | youtube | SOCKS5 10808 | `www.youtube.com_cookies.txt` |
| `pornhub.com` / `*.pornhub.com` | pornhub | SOCKS5 10808 | `www.pornhub.com_cookies.txt` |
| `bilibili.com` / `*.bilibili.com` / `b23.tv` | bilibili | 直连 | `www.bilibili.com_cookies.txt` |
| `x.com` / `*.x.com` / `twitter.com` / `*.twitter.com` | twitter | SOCKS5 10808 | 姊妹域名互回退 `x.com` ↔ `twitter.com` |
| 抖音 `www.douyin.com` / `v.douyin.com`、快手等 | other | 直连 | 无站点级回退，只按 HOST 找（抖音= `www.douyin.com_cookies.txt`） |

Cookie 名优先用 URL 的真实 HOST（如 `m.bilibili.com_cookies.txt`），站点级回退只是兜底。`other` 这一档没有站点级回退，所以**非内置站点全靠 `<HOST>_cookies.txt` 命名对得上**；`www.douyin.com` 与 `v.douyin.com` 算两个 HOST，短链要另放一份。

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
download_video.bat https://www.bilibili.com/video/BV1xx411c7mD
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

### X/Twitter "Login required" / 拿不到格式

X（`x.com` / `twitter.com`）的视频**强制登录**，匿名请求会直接返回 `Login required` 或只有极低画质。按顺序排查：

1. 代理是否开启（脚本对 X/Twitter 自动走 `PROXY_URL`，端口错了必挂）
2. 放登录态 cookie：在**已登录**的浏览器导出 `x.com_cookies.txt` 或 `twitter.com_cookies.txt`，放其一即可（脚本会在姊妹域名间自动回退）
3. cookie 是否过期：登录后重新导出一次；只导出的游客态 cookie 无效
4. 用 `f https://x.com/...` 先列格式，能列出 `https-x-pc` 之类才说明登录态通了

### 代理相关

- 下载失败后脚本会打印常见原因清单，先看那个
- 确认 `127.0.0.1:10808` 是 SOCKS5 端口（v2rayN 默认）。如果是 HTTP 端口，把 `PROXY_URL` 里的 `socks5` 改成 `http`
- 想全局不用代理：`set "PROXY_URL="` 或直接注释掉 site detection 里的 `PROXY_OPT` 赋值

### 同名文件被跳过

`--no-overwrites` 是刻意的，避免误重下。想重下请先删旧文件，或临时改成 `--force-overwrites`。注意"跳过"只是不重新下载视频流，yt-dlp 仍会把元数据和封面**重写一遍**、脚本也仍会复核一次该文件（见[上文](#脚本怎么知道刚下到的文件叫什么)）。

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

> **本脚本为什么要 `chcp 65001`（以及为什么它安全）**
>
> 脚本启动时确实会切到 UTF-8，因为文件名必须经文本往返，而 936 控制台会把 emoji 变成 `?`（详见[脚本怎么知道刚下到的文件叫什么](#脚本怎么知道刚下到的文件叫什么)），退出时再切回原代码页。
>
> 上面那条"`chcp` 会错位"的坑，前提是**脚本文件里本身有多字节字符**：cmd 按字节偏移跳行，多字节字符会让偏移错位。本脚本是**纯 ASCII**，切码前后其字节序列完全一样，跳行不会错位——实测把整个流程（读 `dir` 输出、读 UTF-8 记录文件、`for /l` 循环、`call` 传中文参数、三处 ffprobe/ffmpeg 输出解析）在 `65001` 下逐个跑过，全部正常。
>
> 两个约束必须同时守住：**① 文件保持纯 ASCII；② 别删掉 `chcp` 和 `:FATAL`/`:END` 里的还原行。** 只要往脚本里粘中文（哪怕只是注释），第 ① 条就破了，这时应当改用 GBK 存盘并放弃 `chcp`。

### 改脚本前必看：几个 cmd 解析陷阱

这些坑本脚本都真实踩过，改代码时不要“顺手清理”掉防护写法：

| 陷阱 | 症状 | 正确写法 |
| ---------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `if ( ... )` 块里的 `echo` 出现**未转义右括号** | 报 `此时不应有 xxx。`（xxx = 右括号后面那个词），**整个 .bat 立刻终止**（解析错误终止批处理，不是跳过一行），连“下载完成后”那段后处理都进不去 | 用 `^)` 转义，或整行加引号；块内的 `rem` 注释同样不能出现裸右括号 |
| 在 `( )` 块内读 `%ERRORLEVEL%` / 用 `if errorlevel` | 拿到进入块之前的旧值，失败被判成成功 | 判断一律放在块**外**；且按**文本**比较（ffmpeg 会返回 `4294967274` 这种大数，`if errorlevel 1` 会漏掉负值） |
| `set "X=--opt "%PATH%""` 这类**嵌套引号** | 路径含 `( )` 或 `&` 时报 `\file was unexpected at this time`，或变量被静默截断 | 用不带动引号的 `set X=--opt "%PATH%"`，让路径落在同一段引号里（`FFMPEG_OPT` / `COOKIE_OPT` 就是这么写的） |
| 把 yt-dlp 写的 UTF-8 文本文件当路径读回 | 非 ASCII 标题变乱码 → `if not exist` 说不存在 → 后处理被**静默跳过** | 控制台切 UTF-8 后无损（见[脚本怎么知道刚下到的文件叫什么](#脚本怎么知道刚下到的文件叫什么)）。别再退回"按 GBK 读 UTF-8"的写法 |
| 用 `dir` / `for /f` 之外的手段拿中文文件名 | `for %%F in ("<含 ? 的路径>")` 看似能还原真名，但那只是因为 `?` 恰好是通配符；换成没有 `?` 的字符串（纯中文名）就失败 | 要枚举文件名就用**纯 ASCII 通配符**：`for %%F in ("%DIR%\*.mp4")`，cmd 走的是宽字符 API，拿到的就是真实名字 |
| emoji 标题下探测全部失败、后处理静默跳过 | `ytdlp_h_*.txt` / `ytdlp_cnt_*.txt` 是 0 字节，`ytdlp_vol_*.txt` 不存在，视频没放大也没降分辨率 | 先确认 `chcp 65001` 那行还在（`chcp` 是全局的，被删掉后所有非 GBK 字符都会退化成 `?`） |
| `for /f` + 引号对不上 | `for /f "..." %%i in ('exe "arg"')` 里引号数量为奇数时，cmd 的引号配对会错位 | 让 `'...'` 里的引号成对（`where xxx 2^>nul` 那几行就是范例） |

---

## 已知限制

- **多音轨视频不做音量归一化**：见上文 AMPLIFY 跳过规则
- **下载高度上限不是绝对的**：`MAX_DL_H=2160` 让 >4K 的源优先取 4K 那档（第 5 级，下完再降到 `MAX_H`），但如果**所有**格式都超过它，第 6/7 级仍会退到“最佳分辨率”——宁可下个大文件也不下不到。真想彻底禁掉 8K，得删掉 `FORMAT` 串尾部的 `bv*+ba/b` 两级（代价是那类视频直接失败）
- **带旋转元数据的 >MAX_H 源可能被缩错方向**：缩放目标用的宽高来自 ffprobe 的**原始**值，而重编码时 ffmpeg 默认按**旋转后**的画面进滤波，两者不一致时短边会算错（如原始 3840x2160 + rotate=90）。这类源建议 `TRANSCODE_ON=0`（然后接受原分辨率文件），或手动用 ffmpeg 转码
- **后处理靠“目录里最新的 mp4”兜底**：见[上文](#脚本怎么知道刚下到的文件叫什么)，是启发式而非绝对精确
- **空回车不会退出**：只有 `q` / `quit` / `exit` 退出循环
- **播放列表不下**：`--no-playlist`，只下 URL 指向的单个视频。想下整个播放列表请手动去掉这个参数
- **>1080P 源必然重编码**：无法"零损失"降到 1080P；想要零损失请把 `MAX_H` 改成 2160 或 `TRANSCODE_ON=0`（然后接受 4K 文件）
- **封面格式限 JPG**：MP4 容器的 attached_pic 只吃 mjpeg，yt-dlp 用 `--convert-thumbnails jpg` 自动转换
- **QSV HEVC 需要 Intel 核显**：AMD/纯 CPU 机器会走 libx265 软编，慢很多

---

## 目录结构

```
ytdlp-download-video/
├── download_video.bat      单文件脚本，所有逻辑都在这里
└── README.md               本文档
```

依赖工具**不在**本仓库，需自行安装到 CONFIG 段指向的路径：

```
D:\Software\yt-dlp\
├── yt-dlp.exe
├── www.bilibili.com_cookies.txt
├── www.douyin.com_cookies.txt       抖音（非内置站点，按 HOST 匹配）
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

```text
MIT License
Copyright (c) 2026 Chevy Yang
```
