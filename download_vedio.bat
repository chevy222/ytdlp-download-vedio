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
rem    - Up to 1080p, H.264+AAC preferred for direct stream copy into MP4
rem    - If only >1080p source exists, download best and re-encode with Intel
rem      QSV HEVC (falls back to libx265 if QSV unavailable). Cover art is
rem      preserved via -map 0 with per-stream codec overrides.
rem    - Original-language audio preferred via `lang` in the sort string
rem    - Thumbnail embedded (converted to JPG first), metadata embedded
rem    - No subtitles written or embedded
rem    - After download: ONE rebuild pass does peak-normalize (to 0 dBFS) and
rem      >MAX_H downscale together, so the file is rewritten at most once
rem    - SOCKS5 proxy 127.0.0.1:10808 for YouTube and Aaaornhub only
rem    - Bilibili direct, b23.tv short link recognized
rem    - Cookie file auto-matched by URL host, then by site name
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
set "NODE_DIR=D:\Software\node-v26.7.0-win-x64"

rem Output directory (Desktop root). Falls back to OneDrive\Desktop if the
rem local profile Desktop does not exist.
set "OUT_DIR=%USERPROFILE%\Desktop"

rem SOCKS5 proxy for YouTube / Aaaornhub only
set "PROXY_URL=socks5://127.0.0.1:10808"

rem Cookie directory. Files are named <HOST>_cookies.txt
set "COOKIE_DIR=%YTDLP_DIR%"

rem Max video height. Sources above this are re-encoded down to it.
set "MAX_H=1080"

rem Hard ceiling for what we are willing to DOWNLOAD. Without it an 8K-only
rem video would download tens of GB only to be re-encoded to MAX_H anyway.
set "MAX_DL_H=2160"

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
set "V0FILE=%TEMP%\ytdlp_v0_%RND%.txt"
set "HFILE=%TEMP%\ytdlp_h_%RND%.txt"
set "VOLFILE=%TEMP%\ytdlp_vol_%RND%.txt"
set "ABRFILE=%TEMP%\ytdlp_abr_%RND%.txt"
set "CNTFILE=%TEMP%\ytdlp_cnt_%RND%.txt"


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
set "FFMPEG_OPT="
set "FFMPEG_EXE="
set "FFPROBE_EXE="
if exist "%FFMPEG_DIR%\ffmpeg.exe" (
    set "FFMPEG_OPT=--ffmpeg-location "%FFMPEG_DIR%""
    set "FFMPEG_EXE=%FFMPEG_DIR%\ffmpeg.exe"
    set "FFPROBE_EXE=%FFMPEG_DIR%\ffprobe.exe"
) else (
    for /f "delims=" %%i in ('where ffmpeg.exe 2^>nul') do if not defined FFMPEG_EXE (
        set "FFMPEG_EXE=%%i"
        set "FFPROBE_EXE=%%~dpi\ffprobe.exe"
    )
    if defined FFMPEG_EXE set "FFMPEG_OPT=--ffmpeg-location "%FFMPEG_EXE%""
)
if not defined FFMPEG_EXE echo [WARN] ffmpeg not found: no merge, no transcode, no amplify

rem ---------- JS runtime: YouTube needs one, yt-dlp defaults to deno only ----------
set "JSRT_OPT="
if exist "%NODE_DIR%\node.exe" (
    set "JSRT_OPT=--js-runtimes node:%NODE_DIR%"
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
rem Chain:
rem   1. H.264 <=MAX_H + AAC          (best case: pure stream copy into MP4)
rem   2. H.264 <=MAX_H + best audio   (audio will be transcoded to AAC on merge)
rem   3. any codec <=MAX_H + best audio
rem   4. any codec <=MAX_DL_H + best audio   (triggers the rebuild step, and
rem      MAX_DL_H keeps an 8K-only video from downloading tens of GB)
rem   5. single file <=MAX_H
rem   6. best video + best audio, any resolution
rem   7. best single file, any resolution
set "FORMAT=bv*[height<=%MAX_H%][vcodec*=avc]+ba[acodec*=mp4a]/bv*[height<=%MAX_H%][vcodec*=avc]+ba/bv*[height<=%MAX_H%]+ba/bv*[height<=%MAX_DL_H%]+ba/b[height<=%MAX_H%]/bv*+ba/b"

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
echo   Video Downloader   output: %OUT_DIR%
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
if exist "%LASTFILE%" del "%LASTFILE%" >nul 2>&1

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
if /i "%URL%"=="q" goto END
if /i "%URL%"=="quit" goto END
if /i "%URL%"=="exit" goto END

rem ---------- detect site ----------
rem substring comparison instead of `echo | findstr`: no child processes, and
rem no risk from ^ or % characters in the URL
set "SITE=other"
set "PROXY_OPT="
if not "%URL:youtube.com=%"=="%URL%" set "SITE=youtube"
if not "%URL:youtu.be=%"=="%URL%" set "SITE=youtube"
if not "%URL:aaaornhub.com=%"=="%URL%" set "SITE=aaaornhub"
if not "%URL:bilibili.com=%"=="%URL%" set "SITE=bilibili"
if not "%URL:b23.tv=%"=="%URL%" set "SITE=bilibili"
if "%SITE%"=="youtube" set "PROXY_OPT=--proxy %PROXY_URL%"
if "%SITE%"=="aaaornhub" set "PROXY_OPT=--proxy %PROXY_URL%"

rem ---------- extract host from URL, match cookie ----------
set "TMPHOST=%URL:*//=%"
set "HOST="
for /f "delims=/?&" %%H in ("%TMPHOST%") do set "HOST=%%H"
if not defined HOST set "HOST=%TMPHOST%"

set "COOKIE_OPT="
set "COOKIE_FILE=%COOKIE_DIR%\%HOST%_cookies.txt"
if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\www.%SITE%.com_cookies.txt"
if exist "%COOKIE_FILE%" set "COOKIE_OPT=--cookies "%COOKIE_FILE%""
if not exist "%COOKIE_FILE%" set "COOKIE_FILE="

echo.
echo   Site     : %SITE%   [ %HOST% ]
if defined PROXY_OPT (echo   Proxy    : %PROXY_URL%) else (echo   Proxy    : direct, no proxy)
if defined COOKIE_FILE (echo   Cookie   : %COOKIE_FILE%) else (echo   Cookie   : not used)
echo   Quality  : up to %MAX_H%p / H.264+AAC preferred / mp4
if defined JSRT_OPT (echo   Node     : %JSRT_OPT%) else (echo   Node     : NOT FOUND, YouTube will fail)
echo   Mode     : %MODE%
echo.

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
    echo.
    goto NEXT_ROUND
)

rem ---------- post-process: one rebuild pass for scale + amplify ----------
set "OUTFILE="
if not exist "%LASTFILE%" goto AFTER_POST
set /p "OUTFILE=" < "%LASTFILE%"
if not defined OUTFILE goto AFTER_POST
if not exist "%OUTFILE%" goto AFTER_POST
echo   File     : %OUTFILE%

set "NEEDV=0"
set "NEEDA=0"
set "GAIN=0"
set "ABK=128"
set "VTXT=video copy"
set "ATXT=audio copy"
if "%TRANSCODE_ON%"=="1" call :PROBE_HEIGHT "%OUTFILE%"
if "%AMPLIFY_ON%"=="1" call :PROBE_AUDIO "%OUTFILE%"
if "%NEEDV%"=="0" if "%NEEDA%"=="0" goto AFTER_POST
call :REBUILD "%OUTFILE%"

:AFTER_POST
echo.
echo   Done. Files are in: %OUT_DIR%

:NEXT_ROUND
if not "%~1"=="" goto END
goto LOOP

:END
del "%LASTFILE%" "%V0FILE%" "%HFILE%" "%VOLFILE%" "%ABRFILE%" "%CNTFILE%" 2>nul
if "%~1"=="" pause
exit /b 0


rem ==========================================================================
rem  PROBE_HEIGHT - set NEEDV=1 when the file is taller than MAX_H
rem ==========================================================================
:PROBE_HEIGHT
if not defined FFPROBE_EXE exit /b 0
set "SRC=%~1"
if not defined SRC exit /b 0
if not exist "%SRC%" exit /b 0

if exist "%HFILE%" del "%HFILE%" >nul 2>&1
"%FFPROBE_EXE%" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "%SRC%" > "%HFILE%" 2>nul
set "HEIGHT="
set /p HEIGHT=<"%HFILE%"
if not defined HEIGHT exit /b 0
for /f "tokens=1 delims= " %%h in ("%HEIGHT%") do set "HEIGHT=%%h"

rem ffprobe can return N/A; comparing that as a number would be a string
rem compare and would wrongly decide "needs transcode"
echo %HEIGHT%| findstr /r "^[0-9][0-9]*$" >nul
if not "%ERRORLEVEL%"=="0" (
    echo   Transcode: height "%HEIGHT%" is not a number, skipped
    exit /b 0
)

if %HEIGHT% LEQ %MAX_H% exit /b 0
set "NEEDV=1"
set "VTXT=scale to %MAX_H%p HEVC ^(source %HEIGHT%p^)"
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
set "SRC=%~1"
if not defined SRC exit /b 0
if not exist "%SRC%" exit /b 0

set "MAXVOL="

rem single audio track only: volumedetect measures one track, see header
"%FFPROBE_EXE%" -v error -select_streams a -show_entries stream=index -of csv=p=0 "%SRC%" > "%CNTFILE%" 2>nul
set "ACNT=0"
for /f "usebackq delims=" %%s in ("%CNTFILE%") do set /a ACNT+=1
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
if %GI% GTR %MAXGAIN% (
    set "GAIN=%MAXGAIN%"
    echo   Volume   : peak %MAXVOL% dB needs more than %MAXGAIN% dB, gain capped
)

rem audio bitrate follows the source, clamped to 64-192k
set "ABR="
"%FFPROBE_EXE%" -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "%SRC%" > "%ABRFILE%" 2>nul
set /p ABR=<"%ABRFILE%"
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
rem    default and only v:0 / the audio stream get re-encoded, so the mjpeg
rem    cover art survives untouched.
rem  ERRORLEVEL is only read OUTSIDE parentheses, and compared as text: ffmpeg
rem  can exit with a large negative code, which `if errorlevel 1` misses.
rem ==========================================================================
:REBUILD
if not defined FFMPEG_EXE exit /b 0
set "SRC=%~1"
if not defined SRC exit /b 0
if not exist "%SRC%" exit /b 0

rem --- locate the real video stream. Cover art can sit at v:0 depending on the
rem muxer / yt-dlp version, and it must never be fed through the scale filter ---
set "MAINV=0"
set "V0C="
if defined FFPROBE_EXE (
    "%FFPROBE_EXE%" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "%SRC%" > "%V0FILE%" 2>nul
    set /p V0C=<"%V0FILE%"
)
if /i "%V0C%"=="mjpeg" set "MAINV=1"
if /i "%V0C%"=="png"   set "MAINV=1"
if /i "%V0C%"=="bmp"   set "MAINV=1"
if /i "%V0C%"=="gif"   set "MAINV=1"

rem Scaling path decodes on the GPU. -hwaccel qsv feeds QSV frames straight
rem into the filter graph, so hwdownload is mandatory before the CPU scale.
set "VOPT=-c:v copy"
set "DECOPT="
if "%NEEDV%"=="1" (
    set "DECOPT=-hwaccel qsv"
    set "VOPT=-c:v:%MAINV% hevc_qsv -global_quality 22 -preset slower -tag:v:%MAINV% hvc1 -filter:v:%MAINV% hwdownload,format=nv12,scale=-2:%MAX_H%"
)
set "AOPT=-c:a copy"
if "%NEEDA%"=="1" set "AOPT=-af volume=%GAIN%dB -c:a aac -b:a %ABK%k"

set "TMPOUT=%SRC%.rebuild.mp4"
if exist "%TMPOUT%" del "%TMPOUT%" >nul 2>&1

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
if exist "%TMPOUT%" del "%TMPOUT%" >nul 2>&1
"%FFMPEG_EXE%" -y -hide_banner -loglevel error -stats -nostdin ^
    -i "%SRC%" ^
    -map 0 -c copy ^
    -c:v:%MAINV% libx265 -crf 22 -preset %X265_PRESET% -tag:v:%MAINV% hvc1 ^
    -filter:v:%MAINV% scale=-2:%MAX_H% ^
    %AOPT% ^
    -movflags +faststart "%TMPOUT%"
if not "%ERRORLEVEL%"=="0" goto REBUILD_FAILED

:REBUILD_CHECK
rem a failed run can still leave an empty or truncated file behind
set "TSIZE=0"
if exist "%TMPOUT%" for %%A in ("%TMPOUT%") do set "TSIZE=%%~zA"
if %TSIZE% LSS 1024 (
    echo   Rebuild  : output is only %TSIZE% bytes, original kept
    if exist "%TMPOUT%" del "%TMPOUT%" >nul 2>&1
    exit /b 0
)
move /y "%TMPOUT%" "%SRC%" >nul
if not "%ERRORLEVEL%"=="0" (
    echo   Rebuild  : could not replace the original, file in use?
    echo   Rebuilt copy kept as: %TMPOUT%
    exit /b 0
)
echo   Rebuild  : done
exit /b 0

:REBUILD_FAILED
echo   Rebuild  : failed, original kept as-is
if exist "%TMPOUT%" del "%TMPOUT%" >nul 2>&1
exit /b 0
