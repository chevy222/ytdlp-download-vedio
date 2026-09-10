@echo off
setlocal EnableExtensions
title Video Downloader - yt-dlp

rem ============================================================================
rem  Video Downloader (yt-dlp)
rem
rem  THIS FILE IS PURE ASCII. No BOM, no chcp. ASCII bytes are identical in
rem  UTF-8, GBK and ANSI, so this script has no encoding problem under any
rem  Windows code page. Do NOT save it as UTF-8 with BOM: cmd decodes the 3
rem  BOM bytes as junk, "@echo off" turns into garbage and the whole script
rem  gets echoed.
rem
rem  Usage:
rem    1) Double click, paste a URL, press Enter
rem    2) Or pass the URL as the first argument / drag a link onto this file
rem       (runs once and exits, no loop)
rem    3) Prefix the URL with "f " to only list available formats
rem    4) Type q / quit / exit and press Enter to leave the loop
rem
rem  Pipeline:
rem    - Up to 1080p on the SHORT side of the frame (portrait Shorts
rem      1080x1920 counts as 1080p), H.264+AAC preferred for direct stream
rem      copy into MP4
rem    - If only >1080p source exists, download best and re-encode with Intel
rem      QSV HEVC (falls back to libx265 if QSV unavailable). Cover art is
rem      preserved via -map 0 with per-stream codec overrides.
rem    - Original-language audio preferred via `lang` in the sort string
rem    - Thumbnail embedded (converted to JPG first), metadata embedded
rem    - No subtitles written or embedded
rem    - After download: ONE rebuild pass does peak-normalize (to 0 dBFS) and
rem      >MAX_H downscale together, so the file is rewritten at most once
rem    - SOCKS5 proxy 127.0.0.1:10808 for YouTube, Pornhub and X/Twitter only
rem      (all are blocked in CN and need the proxy; X/Twitter also needs login
rem      cookies to reach the video at all)
rem    - Bilibili direct, b23.tv short link recognized
rem    - Cookie file auto-matched by URL host, then by site name; X/Twitter
rem      additionally probes the sibling x.com / twitter.com cookie file since
rem      either domain unlocks the other
rem    - Single video only (--no-playlist), no overwrite
rem    - Output: Desktop root
rem ============================================================================

rem ############################ CONFIG ############################

rem yt-dlp location: prefer D:\Software\yt-dlp, then PATH
set "YTDLP_DIR=D:\Software\yt-dlp"

rem Directory holding ffmpeg.exe and ffprobe.exe
set "FFMPEG_DIR=D:\Software\ffmpeg\bin"

rem Node.js directory. YouTube needs a JS runtime now; yt-dlp only enables
rem deno by default. Node is used here because it is already installed.
set "NODE_DIR=D:\Software\node-v26.4.0-win-x64"

rem Output directory (Desktop root). Falls back to OneDrive\Desktop if the
rem local profile Desktop does not exist.
set "OUT_DIR=%USERPROFILE%\Desktop"

rem SOCKS5 proxy for YouTube / Pornhub / X(Twitter) only
set "PROXY_URL=socks5://127.0.0.1:10808"

rem Cookie directory. Files are named <HOST>_cookies.txt
set "COOKIE_DIR=%YTDLP_DIR%"

rem Max video quality, measured on the SHORT side of the frame. Landscape
rem 1080p = 1920x1080; portrait 1080p (Shorts) = 1080x1920. Sources above
rem this are re-encoded down to it.
set "MAX_H=1080"

rem Long-side companion of MAX_H (16:9, rounded up). yt-dlp format filters
rem can only test width and height separately, so "1080p of either
rem orientation" is expressed as: BOTH dimensions <= MAX_LONG. This admits
rem 1920x1080 AND 1080x1920 while still excluding 1440p+ (2560x1440 /
rem 1440x2560).
set /a MAX_LONG=(MAX_H*16+8)/9

rem Download ceiling. Levels 1-4 above stay under MAX_H; this one decides what
rem a source that ONLY offers more than MAX_H is allowed to pull: with a 4K tier
rem available, level 5 takes 4K (3840x2160) and REBUILD brings it down, so an
rem 8K+4K video never downloads its 8K stream. It is NOT an absolute wall: if
rem every format is above it, levels 6/7 still fall back to the best available,
rem because a very large file beats downloading nothing at all.
set "MAX_DL_H=2160"

rem Same long-side companion for the download ceiling above.
set /a MAX_DL_LONG=(MAX_DL_H*16+8)/9

rem Output template. For multi-part videos (e.g. bilibili multi-P) yt-dlp's
rem title already ends with " p01 ...", " p02 ...", so parts never collide.
rem Alternatives:
rem   %%(uploader)s - %%(title).180B.%%(ext)s
rem   %%(upload_date)s %%(title).180B.%%(ext)s
rem   %%(title).180B [%%(id)s].%%(ext)s
set "OUT_TPL=%%(title).180B.%%(ext)s"

rem Concurrent fragments for DASH/HLS. Set to 1 if you get throttled.
set "FRAGMENTS=4"

rem Peak-normalize audio to 0 dBFS after download (0 = off)
set "AMPLIFY_ON=1"

rem Re-encode sources > MAX_H down to MAX_H with Intel QSV HEVC (0 = off)
set "TRANSCODE_ON=1"

rem Audio gain ceiling in dB. A near-silent track would otherwise be amplified
rem by 50-90 dB and its noise floor would end up at full scale.
set "MAXGAIN=24"

rem libx265 fallback preset. "fast" is roughly 2x quicker than "medium" on
rem 4K->1080P with almost no visible quality difference.
set "X265_PRESET=fast"

rem Run "yt-dlp -U" once at startup (0 = off). yt-dlp breaks whenever YouTube
rem changes something; turning this on trades a few seconds for far fewer
rem "why did it stop working" moments.
set "AUTO_UPDATE=0"

rem ################################################################

rem Temp files: %RANDOM% suffix so two instances do not clobber each other.
rem (Tried capturing ffprobe output with for /f instead; cmd eats bare `=` as
rem a separator inside the in() clause, and quoting the exe path AND the args
rem breaks cmd's quote pairing - see workspace notes. Temp files it is.)
set "RND=%RANDOM%"
rem yt-dlp writes the final file path here. The output name comes from the
rem video title, so this file is the only way for the post-processing step to
rem learn what was actually written.
set "LASTFILE=%TEMP%\ytdlp_last_%RND%.txt"
rem video probe: "codec_name,height" of stream v:0 - feeds both the height
rem check below and REBUILD's cover-art detection (MAINV)
set "HFILE=%TEMP%\ytdlp_h_%RND%.txt"
rem audio probe: one bit_rate line per audio track - line count = track
rem count, first line = a:0 bitrate
set "CNTFILE=%TEMP%\ytdlp_cnt_%RND%.txt"
rem volumedetect peak output
set "VOLFILE=%TEMP%\ytdlp_vol_%RND%.txt"


rem ---------- locate yt-dlp ----------
set "YTDLP="
if exist "%YTDLP_DIR%\yt-dlp.exe" set "YTDLP=%YTDLP_DIR%\yt-dlp.exe"
if not defined YTDLP for /f "delims=" %%i in ('where yt-dlp.exe 2^>nul') do if not defined YTDLP set "YTDLP=%%i"
if not defined YTDLP (
    echo [ERROR] yt-dlp.exe not found, check YTDLP_DIR
    pause
    exit /b 1
)

rem ---------- optional self update ----------
if "%AUTO_UPDATE%"=="1" (
    echo   Updating yt-dlp...
    "%YTDLP%" -U
    echo.
)

rem ---------- locate ffmpeg / ffprobe ----------
rem FFMPEG_OPT is set OUTSIDE the if/else block on purpose: in the PATH
rem fallback branch FFMPEG_EXE is only assigned at RUNTIME inside the
rem block, and a %FFMPEG_EXE% inside ( ) would expand to the pre-block
rem (empty) value - one of the cmd traps, see convert_h265.bat's README.
set "FFMPEG_OPT="
set "FFMPEG_EXE="
set "FFPROBE_EXE="
if exist "%FFMPEG_DIR%\ffmpeg.exe" (
    set "FFMPEG_EXE=%FFMPEG_DIR%\ffmpeg.exe"
    set "FFPROBE_EXE=%FFMPEG_DIR%\ffprobe.exe"
) else (
    for /f "delims=" %%i in ('where ffmpeg.exe 2^>nul') do if not defined FFMPEG_EXE (
        set "FFMPEG_EXE=%%i"
        set "FFPROBE_EXE=%%~dpifprobe.exe"
    )
)
if defined FFMPEG_EXE set FFMPEG_OPT=--ffmpeg-location "%FFMPEG_EXE%"
if not defined FFMPEG_EXE echo [WARN] ffmpeg not found: no merge, no transcode, no amplify

rem ---------- JS runtime: YouTube needs one, yt-dlp defaults to deno only ----------
set "JSRT_OPT="
if exist "%NODE_DIR%\node.exe" (
    set JSRT_OPT=--js-runtimes "node:%NODE_DIR%"
) else (
    for /f "delims=" %%i in ('where node.exe 2^>nul') do if not defined JSRT_OPT set "JSRT_OPT=--js-runtimes node"
    if not defined JSRT_OPT for /f "delims=" %%i in ('where deno.exe 2^>nul') do if not defined JSRT_OPT set "JSRT_OPT=--js-runtimes deno"
)
if not defined JSRT_OPT echo [WARN] no node/deno found, YouTube will fail, other sites are fine

rem ---------- verify Desktop ----------
if not exist "%OUT_DIR%" (
    if defined OneDrive if exist "%OneDrive%\Desktop" set "OUT_DIR=%OneDrive%\Desktop"
)
if not exist "%OUT_DIR%" (
    echo [ERROR] Desktop folder not found
    pause
    exit /b 1
)

rem ---------- quality / codec policy ----------
rem Chain. Height AND width are capped at MAX_LONG (not MAX_H): a Shorts
rem 1080P stream is 1080x1920 - height 1920 - and a plain height<=MAX_H
rem filter would silently drop it to 480x854. Capping both dimensions
rem admits the 1080p tier of either orientation. See MAX_LONG above.
rem   1. H.264 <=MAX_LONG dims + AAC   (best case: pure stream copy into MP4)
rem   2. H.264 <=MAX_LONG dims + best audio   (audio transcoded to AAC on merge)
rem   3. any codec <=MAX_LONG dims + best audio
rem   4. single file <=MAX_LONG dims  (a native <=MAX_H file beats downloading
rem      a bigger stream just to re-encode it back down)
rem   5. any codec <=MAX_DL_LONG dims + best audio   (triggers the rebuild
rem      step; picks the 4K tier of a >4K source instead of its 8K stream)
rem   6. best video + best audio, any resolution     (last resort, uncapped)
rem   7. best single file, any resolution            (last resort, uncapped)
set "FORMAT=bv*[height<=%MAX_LONG%][width<=%MAX_LONG%][vcodec*=avc]+ba[acodec*=mp4a]/bv*[height<=%MAX_LONG%][width<=%MAX_LONG%][vcodec*=avc]+ba/bv*[height<=%MAX_LONG%][width<=%MAX_LONG%]+ba/b[height<=%MAX_LONG%][width<=%MAX_LONG%]/bv*[height<=%MAX_DL_LONG%][width<=%MAX_DL_LONG%]+ba/bv*+ba/b"

rem Sort: H.264 first, then `lang` so the original audio track beats dubbed
rem ones, then quality / resolution / fps; AAC preferred for MP4 compat.
set "SORT=vcodec:h264,lang,quality,res,fps,acodec:aac,size,proto,ext"


rem ============================== MAIN ==============================

if not "%~1"=="" (
    set "URL=%~1"
    goto GOT_URL
)

:LOOP
echo.
echo ============================================================
echo   Video Downloader   output: "%OUT_DIR%"
echo   Paste a URL and press Enter   ("f URL" = list formats only)
echo   Type q and press Enter to quit
echo ============================================================
echo.

set "URL="
set /p "URL=Enter URL: "

rem an empty line is almost always a slip of the Enter key; only q quits
if not defined URL goto LOOP

:GOT_URL
rem drop the file path recorded by the previous round
del "%LASTFILE%" >nul 2>&1

rem strip quotes
set "URL=%URL:"=%"

rem mode detection must happen before stripping spaces
set "MODE=download"
if /i "%URL:~0,2%"=="f " (
    set "MODE=list"
    set "URL=%URL:~2%"
)

rem strip all spaces (also trims leading / trailing)
set "URL=%URL: =%"
if not defined URL goto LOOP
for %%q in (q quit exit) do if /i "%URL%"=="%%q" goto END

rem ---------- extract host from the URL ----------
rem Done BEFORE site detection: the host is the only reliable place to match a
rem site. Matching the whole URL as a substring was wrong - "x.com" also sits
rem inside netflix.com / box.com / max.com, which then got SITE=twitter and were
rem dragged through the SOCKS5 proxy for nothing. Still one variable expansion
rem per test, still no child process, still no risk from ^ or % in the URL.
rem ":" is in the delims too, so "https://x.com:443/..." yields a clean host and
rem the cookie file name stays free of the port.
set "TMPHOST=%URL:*//=%"
set "HOST="
for /f "delims=/:?&" %%H in ("%TMPHOST%") do set "HOST=%%H"
if not defined HOST set "HOST=%TMPHOST%"

rem ---------- detect site from the host ----------
rem Either the bare host, or the host suffix behind a dot (www.* / m.*). The
rem ~-N length is that of ".<domain>" including the leading dot. /i because the
rem old substring tests were case sensitive, so an uppercase URL slipped through.
set "SITE=other"
set "PROXY_OPT="
if /i "%HOST%"=="youtube.com" set "SITE=youtube"
if /i "%HOST:~-12%"==".youtube.com" set "SITE=youtube"
if /i "%HOST%"=="youtu.be" set "SITE=youtube"
if /i "%HOST%"=="pornhub.com" set "SITE=pornhub"
if /i "%HOST:~-12%"==".pornhub.com" set "SITE=pornhub"
if /i "%HOST%"=="bilibili.com" set "SITE=bilibili"
if /i "%HOST:~-13%"==".bilibili.com" set "SITE=bilibili"
if /i "%HOST%"=="b23.tv" set "SITE=bilibili"
rem X (formerly Twitter): x.com is the current host, twitter.com still appears
rem in older / shared links. Both map to SITE=twitter.
if /i "%HOST%"=="x.com" set "SITE=twitter"
if /i "%HOST:~-6%"==".x.com" set "SITE=twitter"
if /i "%HOST%"=="twitter.com" set "SITE=twitter"
if /i "%HOST:~-12%"==".twitter.com" set "SITE=twitter"
if "%SITE%"=="youtube" set "PROXY_OPT=--proxy %PROXY_URL%"
if "%SITE%"=="pornhub" set "PROXY_OPT=--proxy %PROXY_URL%"
if "%SITE%"=="twitter" set "PROXY_OPT=--proxy %PROXY_URL%"

set "COOKIE_OPT="
set "COOKIE_FILE=%COOKIE_DIR%\%HOST%_cookies.txt"
if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\www.%SITE%.com_cookies.txt"
rem X/Twitter: twitter.com and x.com cookies are interchangeable (same account,
rem same session). Make the sibling fallback SYMMETRIC so "either file is enough"
rem holds in BOTH directions. The generic www.%SITE% line above already covers
rem www.twitter.com; here we additionally probe the sibling domain's bare and
rem www file names. Case: an x.com URL with only a bare twitter.com_cookies.txt
rem would otherwise fall through (www.twitter.com / www.x.com / x.com all miss),
rem wrongly reporting "cookie not used". All guarded to SITE=twitter so a stray
rem x.com_cookies.txt is never attached to some other site's download.
if "%SITE%"=="twitter" if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\www.x.com_cookies.txt"
if "%SITE%"=="twitter" if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\x.com_cookies.txt"
if "%SITE%"=="twitter" if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\twitter.com_cookies.txt"
if exist "%COOKIE_FILE%" set COOKIE_OPT=--cookies "%COOKIE_FILE%"
if not exist "%COOKIE_FILE%" set "COOKIE_FILE="

echo.
echo   Site     : %SITE%   [ "%HOST%" ]
if defined PROXY_OPT (echo   Proxy    : %PROXY_URL%) else (echo   Proxy    : direct, no proxy)
if defined COOKIE_FILE (echo   Cookie   : "%COOKIE_FILE%") else (echo   Cookie   : not used)
echo   Quality  : up to %MAX_H%p / H.264+AAC preferred / mp4
if defined JSRT_OPT (echo   Node     : %JSRT_OPT%) else (echo   Node     : NOT FOUND, YouTube will fail)
echo   Mode     : %MODE%
echo.

rem Baseline for the post-process fallback: the newest .mp4 already sitting in
rem OUT_DIR. Taken before BOTH branches on purpose - if list mode ("f URL") ran
rem without a baseline, the fallback would see the current newest file as "new"
rem and rebuild some unrelated video off the Desktop.
call :NEWEST_MP4
set "MP4_BEFORE=%MP4_NEWEST%"

if "%MODE%"=="list" (
    "%YTDLP%" %PROXY_OPT% %COOKIE_OPT% %JSRT_OPT% -F "%URL%"
    goto AFTER_RUN
)

"%YTDLP%" ^
    %FFMPEG_OPT% %JSRT_OPT% ^
    -f "%FORMAT%" -S "%SORT%" ^
    --merge-output-format mp4 --remux-video mp4 ^
    --embed-thumbnail --convert-thumbnails jpg --embed-metadata ^
    --no-write-subs --no-write-auto-subs --no-embed-subs ^
    --no-playlist --windows-filenames --no-overwrites ^
    -N %FRAGMENTS% --retries 10 --fragment-retries 10 --file-access-retries 3 ^
    --console-title ^
    -P "%OUT_DIR%" -o "%OUT_TPL%" ^
    --print-to-file after_move:"%%(filepath)s" "%LASTFILE%" ^
    %PROXY_OPT% %COOKIE_OPT% ^
    "%URL%"

:AFTER_RUN
rem text compare, not `if errorlevel 1`: that form is ">= 1" and misses the
rem large negative exit codes a killed/crashed yt-dlp can produce
if not "%ERRORLEVEL%"=="0" (
    echo.
    echo [FAILED] yt-dlp reported an error. Usual causes:
    echo   1. YouTube 403 / Sign in to confirm: needs PO Token or fresh cookies
    echo   2. Proxy not running or wrong port: check %PROXY_URL%
    echo   3. Format not available: run  f URL  to list real formats
    echo   4. Cookie expired: export cookies.txt again
    echo   5. X/Twitter "Login required": x.com needs a logged-in cookie
    rem Trap: the parens in the NEXT line are caret-escaped on purpose, and the
    rem comment itself is written without a bare paren character for the same
    rem reason: a bare closing-paren inside an if block ends the block right
    rem there, the following word on that line is then parsed as a command, and
    rem cmd aborts the whole batch with "... was unexpected at this time." - the
    rem word it named here was "plus". Every run died right after yt-dlp exited
    rem because of this, so REBUILD / AMPLIFY never got a chance to run.
    rem Do NOT strip the carets from the next line.
    echo      ^(x.com_cookies.txt or twitter.com_cookies.txt^) plus the proxy
    echo.
    if not "%~1"=="" pause
    goto NEXT_ROUND
)

rem ---------- post-process: one rebuild pass for scale + amplify ----------
rem Two ways to learn which file yt-dlp actually wrote (the name comes from the
rem video title, so it cannot be known before the download):
rem   1. --print-to-file stored the real path in %LASTFILE%. Good for ASCII
rem      titles only. For a Chinese title it does NOT work: yt-dlp writes that
rem      file as UTF-8, cmd reads it back in the console code page (936 on a
rem      Chinese Windows), so the path comes out as mojibake and "if not exist"
rem      reports "no such file". Reproduced in test: the mojibake path does not
rem      resolve, while the real file is sitting right there.
rem   2. Fall back to the newest *.mp4 in OUT_DIR, snapshotted before the
rem      download (MP4_BEFORE). This name comes out of "dir", which encodes it
rem      and cmd decodes it with the same code page, so Chinese titles survive
rem      the round trip. CREATION time, not mtime: yt-dlp can stamp a file's
rem      mtime with the server's Last-modified header.
rem Both are skipped when yt-dlp downloaded nothing - e.g. --no-overwrites
rem skipped the file because it already exists - in that case there is no new
rem mp4 and nothing should be rebuilt.
set "OUTFILE="
if not exist "%LASTFILE%" goto RESOLVE_FALLBACK
for /f "usebackq delims=" %%a in ("%LASTFILE%") do if not defined OUTFILE set "OUTFILE=%%a"
if not defined OUTFILE goto RESOLVE_FALLBACK
if not exist "%OUTFILE%" goto RESOLVE_FALLBACK
goto HAVE_OUTFILE

:RESOLVE_FALLBACK
call :NEWEST_MP4
if not defined MP4_NEWEST goto AFTER_POST
if /i "%MP4_NEWEST%"=="%MP4_BEFORE%" goto AFTER_POST
set "OUTFILE=%OUT_DIR%\%MP4_NEWEST%"
if not exist "%OUTFILE%" goto AFTER_POST

:HAVE_OUTFILE
echo   File     : "%OUTFILE%"

set "NEEDV=0"
set "NEEDA=0"
set "GAIN=0"
set "ABK=128"
set "VTXT=video copy"
set "ATXT=audio copy"
rem The probes and REBUILD take the path via the CALLSRC variable, NOT as a
rem call argument: `call` re-parses its arguments and doubles every ^ in
rem them, so a title like "5^2.mp4" would no longer match the file on disk
rem (same trap as convert_h265.bat - see its README).
set "CALLSRC=%OUTFILE%"
if "%TRANSCODE_ON%"=="1" call :PROBE_HEIGHT
if "%AMPLIFY_ON%"=="1" call :PROBE_AUDIO
if "%NEEDV%"=="0" if "%NEEDA%"=="0" goto AFTER_POST
call :REBUILD

:AFTER_POST
echo.
echo   Done. Files are in: "%OUT_DIR%"

:NEXT_ROUND
if not "%~1"=="" goto END
goto LOOP

:END
del "%LASTFILE%" "%HFILE%" "%VOLFILE%" "%CNTFILE%" 2>nul
if "%~1"=="" pause
exit /b 0


rem ==========================================================================
rem  NEWEST_MP4 - name (no path) of the most recently CREATED *.mp4 in OUT_DIR,
rem  or empty when there is no mp4 at all. Used as the fallback way to find out
rem  what yt-dlp wrote - see the post-process block in the main flow for why the
rem  --print-to-file path cannot be trusted for non-ASCII titles.
rem
rem  "dir" is a child process, but that is the point: it emits the name in the
rem  console code page and cmd reads the pipe back with the same code page, so a
rem  Chinese title survives. A UTF-8 file written by yt-dlp does not.
rem  /o-d /t:c sorts by creation time, newest first, so the first line wins.
rem  Creation time rather than mtime because yt-dlp can stamp the mtime from
rem  the server's Last-modified header, while a freshly written file always has
rem  a fresh creation time.
rem ==========================================================================
:NEWEST_MP4
set "MP4_NEWEST="
for /f "delims=" %%F in ('dir /b /a-d /o-d /t:c "%OUT_DIR%\*.mp4" 2^>nul') do if not defined MP4_NEWEST set "MP4_NEWEST=%%F"
exit /b 0


rem ==========================================================================
rem  PROBE_HEIGHT - set NEEDV=1 when the MAIN video stream's SHORT side is
rem  above MAX_H. Portrait video (Shorts): 1080x1920 IS 1080p - its height
rem  1920 must not trigger a downscale, its short side 1080 must.
rem  Also sets MAINV (cover-art stream offset) and SCL (orientation-aware
rem  scale target for REBUILD: cap the short side, keep the other side).
rem ==========================================================================
:PROBE_HEIGHT
if not defined FFPROBE_EXE exit /b 0
set "SRC=%CALLSRC%"
if not defined SRC exit /b 0
if not exist "%SRC%" (
    echo   Transcode: "%SRC%" not found, skipped
    exit /b 0
)

rem one probe feeds the size check and the MAINV detection
"%FFPROBE_EXE%" -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "%SRC%" > "%HFILE%" 2>nul
set "V0C="
set "W0="
set "H0="
for /f "usebackq tokens=1,2,3 delims=," %%c in ("%HFILE%") do if not defined H0 (
    set "V0C=%%c"
    set "W0=%%d"
    set "H0=%%e"
)

rem cover art at v:0 means the real video stream is v:1; probe THAT one,
rem the cover's dimensions say nothing about the video.
rem Measured layout of a yt-dlp output that had its thumbnail embedded by
rem mutagen: video v:0, audio, cover mjpeg v:1 (attached_pic=1) - so MAINV
rem stays 0 there and the encoding below correctly targets v:0. The MAINV=1
rem branch is the fallback for containers that put the cover first.
set "MAINV=0"
if /i "%V0C%"=="mjpeg" set "MAINV=1"
if /i "%V0C%"=="png"   set "MAINV=1"
if /i "%V0C%"=="bmp"   set "MAINV=1"
if /i "%V0C%"=="gif"   set "MAINV=1"
set "MAINW=%W0%"
set "MAINH=%H0%"
if "%MAINV%"=="1" (
    "%FFPROBE_EXE%" -v error -select_streams v:1 -show_entries stream=width,height -of csv=p=0 "%SRC%" > "%HFILE%" 2>nul
    set "MAINW="
    set "MAINH="
    for /f "usebackq tokens=1,2 delims=," %%c in ("%HFILE%") do if not defined MAINH (
        set "MAINW=%%c"
        set "MAINH=%%d"
    )
)
if not defined MAINW exit /b 0
if not defined MAINH exit /b 0

rem both sides must be numbers; comparing N/A as a number would be a string
rem compare and would wrongly decide "needs transcode"
echo %MAINW%%MAINH%| findstr /r "^[0-9][0-9]*$" >nul
if not "%ERRORLEVEL%"=="0" (
    echo   Transcode: size "%MAINW%x%MAINH%" is not numeric, skipped
    exit /b 0
)

rem quality lives on the SHORT side; the scale target caps it:
rem portrait/square caps the width (MAX_H:-2), landscape caps the height
set "SCL=%MAX_H%:-2"
set "SHORTSIDE=%MAINW%"
if %MAINH% LSS %MAINW% (
    set "SCL=-2:%MAX_H%"
    set "SHORTSIDE=%MAINH%"
)
if %SHORTSIDE% LEQ %MAX_H% exit /b 0
set "NEEDV=1"
set "VTXT=scale to %MAX_H%p HEVC ^(source %MAINW%x%MAINH%^)"
exit /b 0


rem ==========================================================================
rem  PROBE_AUDIO - set NEEDA=1 plus GAIN / ABK when a safe gain is possible
rem    1) volumedetect reports max_volume, e.g. -6.0 dB
rem    2) gain = the value without the minus sign = 6.0 dB, pushing the loudest
rem       peak exactly to 0 dBFS, no clipping
rem    3) only the integer part is tested: -0.x dB means skip, never clip
rem    4) a positive peak means the source already clips, skip, never boost
rem    5) files with more than one audio track are skipped: the peak was
rem       measured on one track and one bitrate cannot fit all tracks
rem    6) gain is capped at MAXGAIN dB so a near-silent track does not get its
rem       noise floor pushed to full scale
rem    7) audio bitrate follows the source, clamped to 64-192k
rem ==========================================================================
:PROBE_AUDIO
if not defined FFMPEG_EXE exit /b 0
if not defined FFPROBE_EXE exit /b 0
set "SRC=%CALLSRC%"
if not defined SRC exit /b 0
if not exist "%SRC%" (
    echo   Volume   : "%SRC%" not found, skipped
    exit /b 0
)

set "MAXVOL="

rem one probe for track count AND a:0 bitrate: one bit_rate line per audio
rem track, first line = a:0 (multi-track files are skipped below anyway)
"%FFPROBE_EXE%" -v error -select_streams a -show_entries stream=bit_rate -of csv=p=0 "%SRC%" > "%CNTFILE%" 2>nul
set "ACNT=0"
set "ABR="
for /f "usebackq delims=" %%s in ("%CNTFILE%") do (
    set /a ACNT+=1
    if not defined ABR set "ABR=%%s"
)
if %ACNT% GTR 1 (
    echo   Volume   : %ACNT% audio tracks, skipped
    exit /b 0
)
if %ACNT% EQU 0 (
    echo   Volume   : no audio track, skipped
    exit /b 0
)

rem volumedetect prints at info level, so no -v error here.
rem findstr (not find) because Git Bash / Cygwin put their own find on PATH.
"%FFMPEG_EXE%" -hide_banner -nostats -nostdin -i "%SRC%" -vn -af volumedetect -f null NUL 2>&1 | findstr /c:"max_volume" > "%VOLFILE%"
for /f "usebackq tokens=5" %%a in ("%VOLFILE%") do set "MAXVOL=%%a"
if not defined MAXVOL (
    echo   Volume   : peak detection failed, skipped
    exit /b 0
)

rem a positive or zero peak means the source is already at (or over) full
rem scale, boosting it would only clip harder
if not "%MAXVOL:~0,1%"=="-" (
    echo   Volume   : peak %MAXVOL% dB, already at or over full scale, skipped
    exit /b 0
)
set "GAIN=%MAXVOL:-=%"
set "GI=0"
for /f "delims=." %%i in ("%GAIN%") do set "GI=%%i"
if "%GI%"=="0" (
    echo   Volume   : peak %MAXVOL% dB, already near full scale, skipped
    exit /b 0
)
rem GTR alone would miss GI == MAXGAIN with a fraction on top (a -24.7 dB
rem peak with MAXGAIN=24); GEQ catches that. The second test spares an exact
rem MAXGAIN.0 peak, which needs no capping.
if %GI% GEQ %MAXGAIN% if not "%GAIN%"=="%MAXGAIN%.0" (
    set "GAIN=%MAXGAIN%"
    echo   Volume   : peak %MAXVOL% dB needs more than %MAXGAIN% dB, gain capped
)

rem audio bitrate follows the source (captured above), clamped to 64-192k
if not defined ABR set "ABR=128000"
if "%ABR%"=="N/A" set "ABR=128000"
set /a ABK=%ABR% / 1000
if %ABK% LSS 64 set /a ABK=64
if %ABK% GTR 192 set /a ABK=192

set "NEEDA=1"
set "ATXT=+%GAIN%dB @ %ABK%k"
exit /b 0


rem ==========================================================================
rem  REBUILD - one ffmpeg pass doing scale and/or amplify together.
rem    -map 0 keeps every stream (audio, cover art, chapters); -c copy is the
rem    default and only the main video stream / the audio get re-encoded, so
rem    the mjpeg cover art survives untouched.
rem    MAINV comes from PROBE_HEIGHT (0 normally, 1 when cover art sits at
rem    v:0). REBUILD is only reached when NEEDV=1 or NEEDA=1; the NEEDV=1
rem    path implies PROBE_HEIGHT ran on this same file.
rem  ERRORLEVEL is only read OUTSIDE parentheses, and compared as text: ffmpeg
rem    can exit with a large negative code, which `if errorlevel 1` misses.
rem ==========================================================================
:REBUILD
if not defined FFMPEG_EXE exit /b 0
set "SRC=%CALLSRC%"
if not defined SRC exit /b 0
if not exist "%SRC%" (
    echo   Rebuild  : "%SRC%" not found, skipped
    exit /b 0
)

rem Scaling path decodes on the GPU. -hwaccel qsv feeds QSV frames straight
rem into the filter graph, so hwdownload is mandatory before the CPU scale.
rem SCL comes from PROBE_HEIGHT: it caps the SHORT side, whichever it is.
set "VOPT=-c:v copy"
set "DECOPT="
if "%NEEDV%"=="1" (
    set "DECOPT=-hwaccel qsv"
    set "VOPT=-c:v:%MAINV% hevc_qsv -global_quality 22 -preset slower -tag:v:%MAINV% hvc1 -filter:v:%MAINV% hwdownload,format=nv12,scale=%SCL%"
)
set "AOPT=-c:a copy"
if "%NEEDA%"=="1" set "AOPT=-af volume=%GAIN%dB -c:a aac -b:a %ABK%k"

set "TMPOUT=%SRC%.rebuild.mp4"
del "%TMPOUT%" >nul 2>&1

echo   Rebuild  : %VTXT% / %ATXT%
"%FFMPEG_EXE%" -y -hide_banner -loglevel error -stats -nostdin ^
    %DECOPT% -i "%SRC%" ^
    -map 0 -c copy ^
    %VOPT% %AOPT% ^
    -movflags +faststart "%TMPOUT%"
if "%ERRORLEVEL%"=="0" goto REBUILD_CHECK

rem QSV missing or broken -> software encode (only relevant when scaling).
rem No -hwaccel on this path: if QSV is the problem, plain CPU is what works.
if "%NEEDV%"=="0" goto REBUILD_FAILED
echo   Rebuild  : QSV failed, falling back to libx265 ^(software^)...
del "%TMPOUT%" >nul 2>&1
"%FFMPEG_EXE%" -y -hide_banner -loglevel error -stats -nostdin ^
    -i "%SRC%" ^
    -map 0 -c copy ^
    -c:v:%MAINV% libx265 -crf 22 -preset %X265_PRESET% -tag:v:%MAINV% hvc1 ^
    -filter:v:%MAINV% scale=%SCL% ^
    %AOPT% ^
    -movflags +faststart "%TMPOUT%"
if not "%ERRORLEVEL%"=="0" goto REBUILD_FAILED

:REBUILD_CHECK
rem a failed run can still leave an empty or truncated file behind
set "TSIZE=0"
if exist "%TMPOUT%" for %%A in ("%TMPOUT%") do set "TSIZE=%%~zA"
if %TSIZE% LSS 1024 (
    echo   Rebuild  : output is only %TSIZE% bytes, original kept
    del "%TMPOUT%" >nul 2>&1
    exit /b 0
)
move /y "%TMPOUT%" "%SRC%" >nul
if not "%ERRORLEVEL%"=="0" (
    echo   Rebuild  : could not replace the original, file in use?
    echo   Rebuilt copy kept as: "%TMPOUT%"
    exit /b 0
)
echo   Rebuild  : done
exit /b 0

:REBUILD_FAILED
echo   Rebuild  : failed, original kept as-is
del "%TMPOUT%" >nul 2>&1
exit /b 0
