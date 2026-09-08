@echo off
setlocal
title Video Downloader - yt-dlp

rem ============================================================================
rem  Video Downloader (yt-dlp)
rem
rem  THIS FILE IS PURE ASCII.
rem  ASCII bytes are identical in UTF-8, GBK and ANSI, so this script has no
rem  encoding problem at all under any Windows code page. That is why it is
rem  safe to save it as UTF-8.
rem
rem  Why the Chinese version is saved as GBK instead of UTF-8:
rem    1) A UTF-8 BOM breaks line 1 - cmd decodes the 3 BOM bytes as junk and
rem       "@echo off" turns into garbage, so the whole script gets echoed and
rem       the first command fails.
rem    2) Switching code page with "chcp 65001" in the middle of a batch file
rem       corrupts cmd's byte offset bookkeeping when the file holds multi-byte
rem       characters: "rem" gets chopped into "em", lines get split apart and
rem       half a sentence ends up being executed as a command.
rem    GBK (code page 936) is the native code page of Chinese Windows, cmd
rem    handles it natively, so neither bug can happen.
rem    Note: no chcp line here. Pure ASCII does not need one, and not switching
rem    code pages is exactly what keeps the byte offsets sane.
rem
rem  Usage:
rem    1) Double click, paste a URL, press Enter
rem    2) Or pass the URL as the first argument / drag a link onto this file
rem    3) Prefix the URL with "f " to only list available formats
rem    4) Type q and press Enter to quit
rem
rem  Defaults: up to 1080p, H.264 + AAC in mp4, thumbnail and metadata
rem  embedded, no subtitles, SOCKS5 proxy for YouTube and Pornhub only,
rem  cookies auto-matched by domain, single video only (no playlists),
rem  output goes to the Desktop root.
rem ============================================================================

rem ############################ CONFIG ############################

rem yt-dlp location: prefer D:\Software\yt-dlp, then PATH
set "YTDLP_DIR=D:\Software\yt-dlp"

rem Directory holding ffmpeg.exe and ffprobe.exe
set "FFMPEG_DIR=D:\Software\ffmpeg\bin"

rem node directory. YouTube needs a JS runtime now; yt-dlp only enables deno by
rem default and deno is not installed here, so point it at node explicitly.
rem Do NOT use D:\Software\node-v14.19.3-win-x64, it is too old.
set "NODE_DIR=D:\Software\node-v26.7.0-win-x64"

rem Output directory (Desktop root)
set "OUT_DIR=%USERPROFILE%\Desktop"

rem Proxy for YouTube / Pornhub only. Change socks5 to http if needed.
set "PROXY_URL=socks5://127.0.0.1:10808"

rem Cookie directory. Files are named (domain)_cookies.txt
set "COOKIE_DIR=%YTDLP_DIR%"

rem Max video height
set "MAX_H=1080"

rem Output template. Multi-part videos automatically get a " P2" style suffix.
rem Alternatives:
rem   %%(uploader)s - %%(title).180B.%%(ext)s
rem   %%(upload_date)s %%(title).180B.%%(ext)s
rem   %%(title).180B [%%(id)s].%%(ext)s
set "OUT_TPL=%%(title).180B%%(playlist_index& P{}|)s.%%(ext)s"

rem Input method: 0 = command line (recommended, needs no PowerShell)
rem                1 = popup dialog (needs PowerShell 7 or 5.1, prefills clipboard)
set "USE_GUI_INPUT=0"

rem Concurrent fragments for DASH/HLS. Set to 1 if you get throttled.
set "FRAGMENTS=4"

rem Auto-amplify audio to full scale (0 dBFS, guaranteed no clipping) after
rem download. Same logic as convert_h265.bat. Video stream is copied untouched,
rem only the audio track is re-encoded. Set to 0 to disable.
set "AMPLIFY=1"

rem ################################################################

rem Temp file, only used by popup mode to hand the URL back to this script
set "URLFILE=%TEMP%\ytdlp_url.txt"
rem Temp file: yt-dlp writes the final file path here, used by the amplify step
set "LASTFILE=%TEMP%\ytdlp_last.txt"


rem ---------- locate yt-dlp ----------
set "YTDLP="
if exist "%YTDLP_DIR%\yt-dlp.exe" set "YTDLP=%YTDLP_DIR%\yt-dlp.exe"
if not defined YTDLP for /f "delims=" %%i in ('where yt-dlp.exe 2^>nul') do if not defined YTDLP set "YTDLP=%%i"
if not defined YTDLP (
    echo [ERROR] yt-dlp.exe not found, check YTDLP_DIR
    pause
    exit /b 1
)

rem ---------- locate ffmpeg ----------
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
if not defined FFMPEG_EXE echo [WARN] ffmpeg not found: no merge, no amplify

rem ---------- JS runtime: YouTube needs one, yt-dlp defaults to deno only ----------
set "JSRT_OPT="
if exist "%NODE_DIR%\node.exe" (
    set "JSRT_OPT=--js-runtimes node:%NODE_DIR%"
) else (
    for /f "delims=" %%i in ('where node.exe 2^>nul') do if not defined JSRT_OPT set "JSRT_OPT=--js-runtimes node"
    if not defined JSRT_OPT for /f "delims=" %%i in ('where deno.exe 2^>nul') do if not defined JSRT_OPT set "JSRT_OPT=--js-runtimes deno"
)
if not defined JSRT_OPT echo [WARN] no node/deno found, YouTube will fail, other sites are fine

rem ---------- locate PowerShell: popup mode only, skipped otherwise ----------
if "%USE_GUI_INPUT%"=="0" goto SKIP_PS
set "PWSH="
set "PS_VER="
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
    set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
    set "PS_VER=PowerShell 7"
)
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
    set "PS_VER=PowerShell 7"
)
if not defined PWSH for /f "delims=" %%i in ('where pwsh.exe 2^>nul') do if not defined PWSH (
    set "PWSH=%%i"
    set "PS_VER=PowerShell 7"
)
if not defined PWSH if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    set "PS_VER=Windows PowerShell 5.1"
)
if not defined PWSH for /f "delims=" %%i in ('where powershell.exe 2^>nul') do if not defined PWSH (
    set "PWSH=%%i"
    set "PS_VER=Windows PowerShell"
)
if not defined PWSH set "USE_GUI_INPUT=0"

:SKIP_PS

rem ---------- quality / codec policy ----------
rem Chain: H.264+AAC up to 1080 / H.264+best audio / any video up to 1080
rem        +best audio / single file up to 1080 / fallback
set "FORMAT=bv*[height<=%MAX_H%][vcodec*=avc]+ba[acodec*=mp4a]/bv*[height<=%MAX_H%][vcodec*=avc]+ba/bv*[height<=%MAX_H%]+ba/b[height<=%MAX_H%]/b"
rem Sort: H.264 first, then "lang" so the original audio track beats dubbed ones,
rem then quality / resolution / fps; AAC preferred.
rem Add  ,hdr:12  after fps if you want HDR to win (may look washed out on SDR).
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
if defined PS_VER (echo   Input: %PS_VER% dialog) else (echo   Input: command line)
echo   Paste a URL and press Enter  (prefix "f " to list formats only)
echo   Type q and press Enter to quit
echo ============================================================
echo.

set "URL="
if "%USE_GUI_INPUT%"=="1" (
    if exist "%URLFILE%" del "%URLFILE%" >nul 2>&1
    "%PWSH%" -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "$f='%URLFILE%'; $p=''; $c=''; try{$c=Get-Clipboard -Raw}catch{$c=''}; if($c){$t=$c.Trim()}else{$t=''}; if($t -match 'https?://[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=]+'){$p=$Matches[0]}; Add-Type -AssemblyName Microsoft.VisualBasic; $m='Paste video URL'+[char]10+[char]10+'Prefix with  f space  to list formats only'+[char]10+[char]10+'Link from clipboard is prefilled'; $v=[Microsoft.VisualBasic.Interaction]::InputBox($m,'Video Downloader',$p); if($v){[IO.File]::WriteAllText($f,$v)}"
    if exist "%URLFILE%" set /p "URL=" < "%URLFILE%"
    if exist "%URLFILE%" del "%URLFILE%" >nul 2>&1
) else (
    set /p "URL=Enter URL: "
)

if not defined URL goto END

:GOT_URL
rem drop the file path recorded by the previous round
if exist "%LASTFILE%" del "%LASTFILE%" >nul 2>&1
rem strip quotes
set "URL=%URL:"=%"

rem mode: "f " prefix means list formats only (must run before stripping spaces)
set "MODE=download"
if /i "%URL:~0,2%"=="f " (
    set "MODE=list"
    set "URL=%URL:~2%"
)

rem strip all spaces (also trims leading / trailing ones)
set "URL=%URL: =%"
if not defined URL goto END
if /i "%URL%"=="q" goto END
if /i "%URL%"=="quit" goto END
if /i "%URL%"=="exit" goto END

rem ---------- detect site ----------
set "SITE=other"
set "PROXY_OPT="
echo "%URL%" | findstr /i /c:"youtube.com" /c:"youtu.be" >nul && (
    set "SITE=youtube"
    set "PROXY_OPT=--proxy %PROXY_URL%"
)
echo "%URL%" | findstr /i /c:"pornhub.com" >nul && (
    set "SITE=pornhub"
    set "PROXY_OPT=--proxy %PROXY_URL%"
)
echo "%URL%" | findstr /i /c:"bilibili.com" /c:"b23.tv" >nul && set "SITE=bilibili"

rem ---------- extract domain from URL, match cookie ----------
set "TMPHOST=%URL:*//=%"
set "HOST="
for /f "delims=/?" %%H in ("%TMPHOST%") do set "HOST=%%H"
if not defined HOST set "HOST=%TMPHOST%"

set "COOKIE_OPT="
set "COOKIE_FILE=%COOKIE_DIR%\%HOST%_cookies.txt"
if not exist "%COOKIE_FILE%" set "COOKIE_FILE=%COOKIE_DIR%\www.%SITE%.com_cookies.txt"
if exist "%COOKIE_FILE%" set "COOKIE_OPT=--cookies "%COOKIE_FILE%""
if not exist "%COOKIE_FILE%" set "COOKIE_FILE="

echo.
echo   Site     : %SITE%   [ %HOST% ]
if defined PROXY_OPT (echo   Proxy    : %PROXY_OPT%) else (echo   Proxy    : direct, no proxy)
if defined COOKIE_FILE (echo   Cookie   : %COOKIE_FILE%) else (echo   Cookie   : not used)
echo   Quality  : up to %MAX_H%P / H.264+AAC / mp4
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
    --print-to-file after_move:"%(filepath)s" "%LASTFILE%" ^
    %PROXY_OPT% %COOKIE_OPT% ^
    "%URL%"

:AFTER_RUN
if errorlevel 1 (
    echo.
    echo [FAILED] yt-dlp reported an error. Usual causes:
    echo   1. YouTube 403 / Sign in to confirm: needs PO Token or cookies
    echo   2. Proxy not running or wrong port: check 10808
    echo   3. Format not available: run  f URL  to list real formats
    echo   4. Cookie expired: export cookies.txt again
    echo.
    goto AFTER_AMP
)

rem ---------- download succeeded, amplify if enabled ----------
if "%AMPLIFY%"=="0" goto AFTER_AMP
if not exist "%LASTFILE%" goto AFTER_AMP
set "OUTFILE="
set /p "OUTFILE=" < "%LASTFILE%"
if not defined OUTFILE goto AFTER_AMP
call :AMPLIFY "%OUTFILE%"

:AFTER_AMP
echo.
echo   Done. Files are in: %OUT_DIR%
if not "%~1"=="" goto END
goto LOOP

:END
if "%USE_GUI_INPUT%"=="0" pause
exit /b 0


rem ==========================================================================
rem  Amplify: peak normalize to 0 dBFS (same logic as convert_h265.bat)
rem    1) volumedetect reports max_volume, e.g. -6.0 dB
rem    2) gain = the value without minus sign = 6.0 dB, pushing the loudest
rem       peak exactly to 0 dBFS, no clipping
rem    3) only the integer part is tested: -0.x dB means skip, never clip
rem    4) audio bitrate follows the source, clamped to 64-192k
rem  Video is copied untouched (-c:v copy), cover art survives too
rem ==========================================================================
:AMPLIFY
if not defined FFMPEG_EXE exit /b 0
set "SRC=%~1"
if not defined SRC exit /b 0
if not exist "%SRC%" exit /b 0

set "VOLFILE=%TEMP%\ytdlp_vol.txt"
set "ABRFILE=%TEMP%\ytdlp_abr.txt"
set "MAXVOL="

rem volumedetect prints at info level, so no -v error here
"%FFMPEG_EXE%" -hide_banner -nostats -nostdin -i "%SRC%" -vn -af volumedetect -f null NUL 2>&1 | find "max_volume" > "%VOLFILE%"
for /f "usebackq tokens=5" %%a in ("%VOLFILE%") do set "MAXVOL=%%a"
if not defined MAXVOL (
    echo   Volume   : peak detection failed, skipped
    exit /b 0
)

set "GAIN=%MAXVOL:-=%"
set "GI=0"
for /f "delims=." %%i in ("%GAIN%") do set "GI=%%i"
if "%GI%"=="0" (
    echo   Volume   : peak %MAXVOL% dB, already near full scale, skipped
    exit /b 0
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

set "TMPOUT=%SRC%.amp.mp4"
rem -map 0 is required: without it ffmpeg keeps only the "best" video stream
rem and silently drops the cover art (mjpeg)
"%FFMPEG_EXE%" -v error -stats -nostdin -y -i "%SRC%" -map 0 -af "volume=%GAIN%dB" -c:v copy -c:a aac -b:a %ABK%k -movflags +faststart "%TMPOUT%"
if errorlevel 1 (
    echo   Volume   : amplify failed, original kept
    if exist "%TMPOUT%" del "%TMPOUT%" >nul 2>&1
    exit /b 0
)
move /y "%TMPOUT%" "%SRC%" >nul
echo   Volume   : peak %MAXVOL% dB, amplified %GAIN% dB to full scale (audio %ABK%k, video untouched)
exit /b 0
