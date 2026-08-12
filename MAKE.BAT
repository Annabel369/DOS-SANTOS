@echo off
echo ==================================================
echo   COMPILADOR DE UTILITARIOS ESP32 PARA MS-DOS
echo ==================================================
echo.

:: Detectar caminho do Borland C++ 3.1
:: Assumindo que a unidade atual eh onde o DOS bootou (C:)
set BCDIR=..\game\BCPP31

if not exist %BCDIR%\bin\bcc.exe (
    echo [ERRO] O compilador BCC.EXE nao foi encontrado em %BCDIR%\bin\
    echo Verifique se a pasta GAME\BCPP31 existe na raiz do drive.
    goto end
)

echo [+] Compilando dos_ser.cpp (Comunicador Serial)...
%BCDIR%\bin\bcc -I%BCDIR%\include -L%BCDIR%\lib -ml dos_ser.cpp
if errorlevel 1 goto error

echo [+] Compilando dos_pkt.cpp (Detector de Packet Driver)...
%BCDIR%\bin\bcc -I%BCDIR%\include -L%BCDIR%\lib -ml dos_pkt.cpp
if errorlevel 1 goto error

echo [+] Compilando pxe_scan.cpp (Diagnosticador PXE)...
%BCDIR%\bin\bcc -I%BCDIR%\include -L%BCDIR%\lib -ml pxe_scan.cpp
if errorlevel 1 goto error

echo [+] Compilando send_esp.cpp (Envio com ID aleatorio)...
%BCDIR%\bin\bcc -I%BCDIR%\include -L%BCDIR%\lib -ml send_esp.cpp
if errorlevel 1 goto error

echo.
echo [SUCESSO] Compilacao concluida!
echo Executaveis gerados: DOS_SER.EXE, DOS_PKT.EXE, PXE_SCAN.EXE e SEND_ESP.EXE
goto end

:error
echo.
echo [ERRO] Falha ao compilar os arquivos! Verifique os erros acima.

:end
echo.
pause
