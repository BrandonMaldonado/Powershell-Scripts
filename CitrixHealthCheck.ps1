Asnp Citrix*
Set-XDCredentials -ProfileType OnPrem

$report_ps = @()
$report_bs = @()
$report_vm = @()
$avail_reports = @()
$mail_server = 'smtp.domain.com'
$send_to = @('user1@example.com', 'user2@example.com')
$send_from = 'ctxmonitor@domain.com'
$delivery_controller = 'ctxcontroller.domain.com'

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

$DebugPreference = 'Continue'

# Attempt to connect to Citrix DCC
function Start-Connection {
    [CmdletBinding()]

    param ()

    # Connect to Citrix
    try {
        Get-BrokerSite -AdminAddress $script:delivery_controller | Out-Null
    }
    catch {
        Write-Debug "Unable to connect to " $script:delivery_controller
    }
}

# Find Citrix Servers in MX
function Get-CitrixPSStatus {
    [CmdletBinding()]

    param ()

    $citrix_ps = Get-BrokerMachine 

    foreach ($ps in $citrix_ps) {
        if (($ps.InMaintenanceMode -eq 'True') -OR ($ps.RegistrationState -ne 'Registered')) {
            Write-Debug "Server Name: $($ps.HostedMachineName)"
            Write-Debug "Server Status: $($ps.RegistrationState)"
            Write-Debug "MX mode: $($ps.InMaintenanceMode)"
            Write-Debug "Power Status: $($ps.PowerState)`n"

            # Create object with presentation server information.
            $obj = New-Object -TypeName psobject
            $obj | Add-Member -MemberType NoteProperty -Name 'Server Name' -Value $($ps.HostedMachineName)
            $obj | Add-Member -MemberType NoteProperty -Name 'Server Status' -Value $($ps.RegistrationState)
            $obj | Add-Member -MemberType NoteProperty -Name 'MX Mode' -Value $($ps.InMaintenanceMode)
            $obj | Add-Member -MemberType NoteProperty -Name 'Power State' -Value $($ps.PowerState)

            # Add object to presentation report.
            $script:report_ps += $obj
        }
    }
}

# Find sessions that have been disconnected for longe than the specified time_limit
function Get-HungSessions {
    [CmdletBinding()]

    param ()

    $citrix_bs = Get-BrokerSession -MaxRecordCount 10000 | Where-Object { $_.SessionState -ne "Active" }

    $script:time_limit = 20
    $date = (Get-Date).AddMinutes(-$script:time_limit)

    foreach ($bs in $citrix_bs) {

        if ($bs.SessionStateChangeTime -lt $date) {

            Write-Debug "Session disconnected longer than $($script:time_limit) minutes"
            Write-Debug "User Name: $($bs.UserName)"
            Write-Debug "Citrix PS: $($bs.HostedMachineName)`n"

            # Create object with broker session data.
            $obj = New-Object -TypeName psobject
            $obj | Add-Member -MemberType NoteProperty -Name 'User Name' -Value $($bs.UserName)
            $obj | Add-Member -MemberType NoteProperty -Name 'Citrix PS' -Value $($bs.HostedMachineName)
            $obj | Add-Member -MemberType NoteProperty -Name 'Session State Change Time' -Value $($bs.SessionStateChangeTime)
            $obj | Add-Member -MemberType NoteProperty -Name 'Cut Off Time' -Value $date

            # Add object to broker report.
            $script:report_bs += $obj
        }
    }
}

function Send-Report {
    [CmdletBinding()]

    param ()

    # If there are any PS servers in our report object add to our final report.
    if ($report_ps) {
        $report_pt1 = $script:report_ps | ConvertTo-Html -Pre "<h3>Citrix Presentation Servers</h3><p>The following servers are in MX mode or uninitialized" -Fragment | Out-String
        $script:avail_reports += $report_pt1
    }

    # If there are any BS sessions disconnected longer than the specified time in our report object add to final report.
    if ($report_bs) {
        $report_pt2 = $script:report_bs | ConvertTo-Html -Pre "<h3>Broker Sessions</h3><p>Each session below has been disconnected for longer than the expected cutoff time ($($script:time_limit) minutes).</p>" -Fragment | Out-String
        $script:avail_reports += $report_pt2
    }

    # Send report if there is any data in final reports.
    if ($script:avail_reports) {
        $final_report = (ConvertTo-Html -Head $Header -PostContent $script:avail_reports -PreContent "<h2>Citrix Health Report</h2>" | Out-String) -replace "(?sm)<table>\s+</table>"
        Send-MailMessage -To $script:send_to -From $script:send_from -Body $final_report -BodyAsHtml -SmtpServer $script:mail_server -Subject "$(Get-Date -Format d) - Citrix Health Report"
    }
}

Start-Connection
Get-CitrixPSStatus
Get-HungSessions
Send-Report
