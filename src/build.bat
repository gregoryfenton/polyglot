: << 'BATCH'
@echo off
echo Compiling under DOS
nasm -f bin hexscope.asm -o hexscope.com
if errorlevel 1 goto failed
echo Polyglot app hexscope.com has been successfully built.
echo The build targets are DOS and Linux 64 bit
goto end

:failed
echo Build failure

:end
exit /b
BATCH

# --- Linux Bash Section ---
echo Compiling under Linux
nasm -f bin hexscope.asm -o hexscope.com
if [ $? -ne 0 ]; then
    echo Build failure
    exit 1
fi
chmod +x hexscope.com
echo Polyglot app hexscope.com has been successfully built.
echo The build targets are DOS and Linux 64 bit
