# Email Report
$From = "CameraMonitor@domain.com"
$To = "secteam@domain.com"
$Cc = "propteam@domain.com"
$Subject = (Get-Date).ToString("%d-MMMM-yyyy") + " - Weekly Report - Offline Cameras"
$SMTPServer = "mail.domain.com"

# Define HTML Report Header Style
$Header = @"
<style>
body { font-size:12px; font-family:Verdana, Geneva, sans-serif;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #e5efff;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
tr:nth-child(even) {background: #ededed}
tr:nth-child(odd) {background: #FFF}
</style>
"@

# Import Milestone Config
$xmlLocation = 'C:\ProgramData\Milestone\Milestone Surveillance\configuration.xml'
$deviceObjs = Select-Xml -Path $xmlLocation -XPath "//config/Devices/node()" | Select-Object -ExpandProperty node | Where-Object { $_.Name -ne '#whitespace' }

# Declare Report
$report = @()

# Go through each device, test, and report on offline cameras
foreach ($device in $deviceObjs) {
    Write-Host "Testing $($device.DisplayName)"

    # Test points - Camera and Firewall
    $camTestResult = (Test-NetConnection $device.IPAddress -Port 80 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).TcpTestSucceeded
    $gwTestResult = (Test-NetConnection $($device.IPAddress -replace "\.\d{1,3}$", ".1") -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).PingSucceeded

    # Check Status
    if ($camTestResult -eq $true) {
        Write-Host -ForegroundColor Green "  Status: Online"
    }

    if (($camTestResult -eq $false) -and ($gwTestResult -eq $true)) {
        # Debug Status
        Write-Host -ForegroundColor Red "  Firewall Status: $gwTestResult"
        Write-Host -ForegroundColor Red "  Camera Status: $camTestResult"
        
        # Add to Report
        $item = New-Object PSObject
        $item | Add-Member -type NoteProperty -Name 'Camera Name' -Value $($device.DisplayName)
        $item | Add-Member -type NoteProperty -Name 'Camera IP' -Value $($device.IPAddress)
        $item | Add-Member -type NoteProperty -Name 'Online' -Value $($camTestResult)
        $report += $item
    }
    elseif (($camTestResult -eq $false) -and ($gwTestResult -eq $false)) {
        Write-Host 'Status: Tunnel Down'
    }
}

if ($report) {
    $HTMLReport = $report | Sort-Object 'Camera Name' | ConvertTo-Html -property 'Camera Name', 'Camera IP', 'Online' -Head $Header -Pre "<h2>Property Weekly Report - Offline MDF Cameras</h2><p><b>Generated:</b> $(get-date)</p>"

    Send-MailMessage -To $To -Cc $Cc -From $From -SmtpServer $SMTPServer -Subject $Subject -Body ($HTMLReport | Out-String) -BodyAsHtml
}
