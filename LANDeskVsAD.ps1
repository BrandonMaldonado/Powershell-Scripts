# Load Modules
Import-Module ActiveDirectory

$from = "landesk@contoso.com"
$to = "team_one@contoso.com"
$cc = "team_two@contoso.com"
$subject = (Get-Date).ToString("%d-MMMM-yyyy") + " - Active Directory vs LANDesk"
$smtpServer = "mailserver.contoso.com"

# Define HTML Report Header Style
$header = @"
<style>
body { font-size:12px; font-family:Verdana, Geneva, sans-serif;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #e5efff;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
tr:nth-child(even) {background: #ededed}
tr:nth-child(odd) {background: #FFF}
</style>
"@

# Get ALL AD Computers and Export
$adData = get-adcomputer -Filter * -searchbase "OU=computers,DC=contoso,DC=com" | 
Select-Object @{ Name = "Device Name"; Expression = { $_. "Name" } } | Sort-Object 'Device Name' -Unique

# Connect to LANDesk and Export
$ldws = New-WebServiceProxy -Uri 'https://landesk.contoso.com/MBSDKService/MsgSDK.asmx?WSDL' -UseDefaultCredential
$ldws.ResolveScopeRights() | Out-Null

# Query in LanDesk will just list all workstations in the enviorment.
$ldList = $ldws.RunQuery("All_Windows_Devices") 

# Create Hashtables
$ldTable = @{}
$adTable = @{}

# Varibles
$missingPCs = @()

# Process datasets and add to hashtable
$ldList.Tables[0].Rows | ForEach-Object { $ldTable[$_.'Device Name'] = $_.Data }
$adData | ForEach-Object { $adTable[$_.'Device Name'] = $_.Data }

# Compare hashtables
foreach ($pc in $adTable.Keys) {
    if ($ldTable.ContainsKey($pc) -eq $false) {
        $item = New-Object PSObject
        $item | Add-Member -type NoteProperty -Name 'Device Name' -Value $pc
        $missingPCs += $item
    }
}

# Print final report to console
Write-Host ""
Write-Host -ForegroundColor DarkMagenta 'Missing Devices:'
$missingPCs | Sort-Object 'Device Name' | Format-Table -HideTableHeaders
Write-Host ""

if ($missingPCs) {
    # Generate Report
    $HTMLReport = $missingPCs | Sort-Object 'Device Name' | ConvertTo-Html -property 'Device Name' -Head $Header -pre "<h1>Active Directory vs LANDesk</h1><p><b>Generated:</b> $(get-date)<br /><b>Total Records Processed:</b> $($missingPCs | Measure | Select-Object Count | ft -HideTableHeaders | Out-String)</p> <P>PCs on this list either: Need to be removed from Active Directory or added to LanDesk immediately"

    # Send Email
    Send-MailMessage -To $to -Cc $cc -From $from -SmtpServer $smtpServer -Subject $subject-Body ($HTMLReport | Out-String) -BodyAsHtml
}
