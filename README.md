# ytdlp-oneclick —— 双击即用的视频下载器

单文件 Windows 批处理脚本，封装 [yt-dlp](https://github.com/yt-dlp/yt-dlp)：双击 → 粘贴链接 → 桌面上得到一个音量拉满的 1080P mp4。

> **仓库简介（可贴到 Description 栏）：** 一个双击即用的 Windows 视频下载器：yt-dlp 下载 1080P mp4、自动嵌封面、按站点分流代理与 Cookie，下载完成后音量自动放大到满刻度且不削波。

---

## 为什么做这个

在 Windows 上用 yt-dlp 通常要记住一堆参数、按站点折腾代理、导出 cookie，而下下来的视频往往音量偏小。ytdlp-oneclick 把这些全部封装进一个 `.bat` 文件，放到桌面双击就能用：

- **单文件、零安装** —— 只需在配置区指向你的 `yt-dlp.exe`、`ffmpeg.exe` 和 `node.exe`
- **站点自动分流** —— YouTube / Pornhub 走 SOCKS5 代理，其它站点直连
- **Cookie 按域名自动匹配** —— 把 `<域名>_cookies.txt` 放到指定目录即可生效
- **音量拉满** —— 每次下载后自动做峰值归一化到 0 dBFS，保证不削波
- **脚本编码免疫** —— `.bat` 是纯 ASCII，任何 Windows 代码页下都不会乱码

## 功能一览

| 项目 | 行为 |
|---|---|
| 画质 | 最高 1080P，优先 H.264 + AAC，统一输出 mp4 |
| 封面 | 缩略图转 jpg 后作为封面嵌入 |
| 元数据 | 标题、UP 主、来源链接写入文件 |
| 字幕 | 不下载、不嵌入 |
| 代理 | 仅 youtube.com / youtu.be / pornhub.com 走 `socks5://127.0.0.1:10808`，其它直连 |
| Cookie | 按 URL 域名自动匹配（如 `www.bilibili.com_cookies.txt`），带站点级回退 |
| 合集 | `--no-playlist`，只下载你点开的那一个视频 |
| 音量增强 | 下载完成后峰值归一化到 0 dBFS（见[音量放大原理](#音量放大原理)） |
| 输入方式 | 双击后粘贴、把链接拖到图标上、或作为参数传入 |
| 文件名 | `标题.mp4`，B 站多 P 视频自动追加 ` P2` 式序号防重名 |

## 环境要求

| 工具 | 说明 |
|---|---|
| Windows 10 / 11 | 用 cmd.exe，不需要 PowerShell（可选的弹窗输入模式支持 PS 7 或 5.1） |
| [yt-dlp.exe](https://github.com/yt-dlp/yt-dlp/releases) | 建议较新版本（2025.11 起下载 YouTube 需要 JS 运行时） |
| ffmpeg + ffprobe | 放同一目录；用于音画合并、封面嵌入和音量处理 |
| node.exe（或 deno） | yt-dlp 默认只启用 deno，本脚本显式指向 node，YouTube 必需 |
| Cookie 文件 | Netscape 格式。B 站**必需**（无 cookie 请求会返回 HTTP 412） |

## 快速开始

1. 把脚本放到任意位置打开，所有可调项都在顶部 `CONFIG` 配置区：

```bat
set "YTDLP_DIR=D:\Software\yt-dlp"
set "FFMPEG_DIR=D:\Software\ffmpeg\bin"
set "NODE_DIR=D:\Software\node-v26.7.0-win-x64"
set "OUT_DIR=%USERPROFILE%\Desktop"
set "PROXY_URL=socks5://127.0.0.1:10808"
set "COOKIE_DIR=%YTDLP_DIR%"
set "MAX_H=1080"
set "AMPLIFY=1"
```

2. 按域名命名 cookie 文件，放进 `COOKIE_DIR`：

```
www.bilibili.com_cookies.txt
www.youtube.com_cookies.txt      （可选，YouTube 要求登录时才需要）
www.pornhub.com_cookies.txt      （可选）
```

3. 双击 `download_vedio.bat`，粘贴链接，回车：

```
============================================================
  Video Downloader   output: C:\Users\you\Desktop
  Input: command line
  Paste a URL and press Enter  (prefix "f " to list formats only)
  Type q and press Enter to quit
============================================================

  Site     : bilibili   [ www.bilibili.com ]
  Proxy    : direct, no proxy
  Cookie   : D:\Software\yt-dlp\www.bilibili.com_cookies.txt
  Quality  : up to 1080P / H.264+AAC / mp4
  Node     : --js-runtimes node:D:\Software\node-v26.7.0-win-x64
  Mode     : download
```

其它技巧：

- **`f + 空格 + 链接`** —— 只列出可用画质，不下载
- **拖拽** —— 把链接拖到 `.bat` 图标上，或作为第一个参数传入
- **`AMPLIFY=0`** —— 关闭音量增强

## 音量放大原理

下载下来的视频经常母带音量偏小。每次下载成功后，脚本会把音频归一化到不削波前提下的最大音量——经典的两遍式峰值归一化：

1. 用 `ffmpeg -af volumedetect` 测出真实峰值（例如 `max_volume: -9.5 dB`）
2. 增益就是该值去掉负号（`9.5 dB`），正好把最高峰推到 0 dBFS
3. 如果峰值已经在 `-0.x dB` 接近满刻度，则跳过不动
4. 画面流**直接 copy 不重新编码**（`-c:v copy`）——画质零损失；只有音轨重编码为 AAC，码率跟随源文件（限制在 64–192k），并用 `-map 0` 保留已嵌入的封面

```
源峰值 : -9.5 dB
增益   : 9.5 dB
结果   : 0.0 dB  （满刻度，无削波）
```

## 注意事项与排错

- **B 站不带 cookie 会返回 HTTP 412** —— cookie 对 B 站是必需的，不只是为了高清。
- **YouTube 403 / "Sign in to confirm"** —— 导出 `www.youtube.com_cookies.txt`，确认运行时 `Node :` 一行有值，并保持代理开启。
- **代理没开** —— 下载失败后脚本会提示；确认 `127.0.0.1:10808` 确实是 SOCKS5 端口（v2rayN 默认）。如果是 HTTP 端口，把 `PROXY_URL` 里的 `socks5` 改成 `http`。
- **同名文件** —— 文件名模板不含 BV 号，重复下载同一视频会被跳过（`--no-overwrites`）。想要重新下载请先删除旧文件。
- **为什么脚本是纯 ASCII？** UTF-8 BOM 会破坏批处理文件的第一行；脚本中途用 `chcp` 切换代码页时，多字节字符会让 cmd 的字节偏移错位。纯 ASCII 在 UTF-8 和 GBK 下字节完全相同，两种坑都不存在。

## 许可证

MIT —— 随便用，不提供任何担保。
