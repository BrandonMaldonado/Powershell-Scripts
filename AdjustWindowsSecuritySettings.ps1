# -----------------------------------
# Check Windows Version
# -----------------------------------
$checkOSver = (Get-WmiObject -class Win32_OperatingSystem).Caption

# -----------------------------------
# Update RDP Security Levels
# -----------------------------------
$getRDPSec = Get-WmiObject -class "Win32_TSGeneralSetting" -Namespace root\cimv2\terminalservices
$getRDPSec.SecurityLayer = "2"
$getRDPSec.MinEncryptionLevel = "3"

# -----------------------------------
# Create keys for TLS 1.0 if not created
# -----------------------------------
new-item -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols" -Name "TLS 1.0"
new-item -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0" -Name "Server"
new-item -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0" -Name "Client"
new-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Name "Enabled" -Value 0
new-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Name "DisabledByDefault" -Value 1
new-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "Enabled" -Value 0
new-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "DisabledByDefault" -Value 1

# -----------------------------------
# Sets value if TLS 1.0 already exists
# -----------------------------------
set-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Name "Enabled" -Value 0
set-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Name "DisabledByDefault" -Value 1
set-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "Enabled" -Value 0
set-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "DisabledByDefault" -Value 1

# -----------------------------------
# Run on Windows 2012 or Windows 10
#------------------------------------
if ($checkOSver -like "Microsoft Windows Server 2012*" -or $checkOSver -like "Microsoft Windows 10*" -or $checkOSver -like "Microsoft Windows 8.1*"){

    # Disable TCP Timestamps
    Set-netTCPsetting -SettingName InternetCustom -Timestamps disabled

    # Disable SMBv1
    $checkSMBv1Server = Get-SmbServerConfiguration | Select EnableSMB1Protocol
    if ($checkSMBv1Server){
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
    }
}
else {
    # Disable TCP Timestamps
    new-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Tcp1323Opts" -Value 0
    set-itemproperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Tcp1323Opts" -Value 0

    #Disable SMBv1 - Client
    $checkSMB1 = Get-Item HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters | ForEach-Object {Get-ItemProperty $_.pspath}
    if ($checkSMB1){
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" SMB1 -Type DWORD -Value 0 –Force
    }
}
