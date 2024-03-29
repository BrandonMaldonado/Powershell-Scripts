# Variables
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$sysMon64 = 'SysMon64'
$sysMon32 = 'SysMon'
$configFile = 'sysmonconfig.xml'

# Detect and Uninstall Existing Installs
if(Get-Service -Name $sysMon64 -ErrorAction SilentlyContinue){
    # Found SysMon64
    Write-Host 'SysMon 64bit found'

    # Stop Service / Uninstall / Cleanup Files
    Stop-Service -Name $sysMon64 -ErrorAction SilentlyContinue -Force
    Start-Sleep -Seconds 3
    Start-Process -FilePath "$env:SystemRoot\$sysMon64.exe" -ArgumentList "-u" -Wait
    Start-Sleep -Seconds 3
    Remove-Item -Path "$env:SystemRoot\$sysMon64.exe" -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\$sysMon32.exe" -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\$configFile" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
elseif (Get-Service -Name $sysMon32 -ErrorAction SilentlyContinue) {
    # Found SysMon32
    Write-Host 'SysMon 32bit found'

    # Stop Service / Uninstall / Cleanup Files
    Stop-Service -Name $sysMon32 -ErrorAction SilentlyContinue -Force
    Start-Sleep -Seconds 3
    Start-Process -FilePath "$env:SystemRoot\$sysMon32.exe" -ArgumentList "-u" -Wait
    Start-Sleep -Seconds 3
    Remove-Item -Path "$env:SystemRoot\$sysMon64.exe" -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\$sysMon32.exe" -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\$configFile" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# Copy Files and Install
$OSArch = gwmi win32_operatingsystem | select osarchitecture

Get-ChildItem -Path "$ScriptDir" -Exclude *.txt, *.ps1, *.cmd | 
    Select-Object -ExpandProperty FullName | 
    Copy-Item -Destination "$env:SystemRoot\" -Force -ErrorAction SilentlyContinue

if($OSArch.osarchitecture -eq '64-bit'){
  Start-Process -FilePath "$env:SystemRoot\$sysMon64.exe" -ArgumentList "-accepteula -i $env:SystemRoot\$configFile"
}
else{
  Start-Process -FilePath "$env:SystemRoot\$sysMon32.exe" -ArgumentList "-accepteula -i $env:SystemRoot\$configFile"
}
