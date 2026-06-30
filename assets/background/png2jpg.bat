@echo off

@echo off
for %%i in (*.png) do (
    ffmpeg -i "%%i" -q:v 2 "%%~ni.jpg"
)

del /q /s *.png

echo 完成
pause

