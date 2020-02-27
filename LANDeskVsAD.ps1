# Load Modules
Import-Module ActiveDirectory

$From = "noreply@domain.com"
$To = "teamone@domain.com"
$Cc = "teamtwo@domain.com"
$Subject = (Get-Date).ToString("%d-MMMM-yyyy") + " - Active Directory vs LANDesk"
$SMTPServer = "mailserver.domain.com"

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

# Get ALL AD Computers and Export
$ADdata = get-adcomputer -Filter * -searchbase "OU=Computers,DC=domain,DC=com" | 
Select-Object @{ Name = "Device Name"; Expression = { $_. "Name" } } | Sort-Object 'Device Name' -Unique

# Connect to Property LanDesk and Export
# Replace with your LANDesk server and ensure you have permissions to access the API.
$ldWS = New-WebServiceProxy -Uri https://<YOUR LANDESK SERVER>/MBSDKService/MsgSDK.asmx?WSDL -UseDefaultCredential
$ldWS.ResolveScopeRights() | Out-Null

# Query in LanDesk will just list all workstations in the enviorment.
$LDlist = $ldWS.RunQuery("<INSERT QUERY NAME>") 

# Hashtables
$LANDeskTable = @{}
$ADTable = @{}

# Varibles
$missingPCs = @()

# Process datasets and add to hashtable
$LDlist.Tables[0].Rows | ForEach-Object {$LANDeskTable[$_.'Device Name'] = $_.Data }
$ADdata | ForEach-Object  { $ADTable[$_.'Device Name'] = $_.Data }

# Compare hashtables
foreach($PC in $ADTable.Keys){
  if($LANDeskTable.ContainsKey($PC) -eq $false){
    $item = New-Object PSObject
    $item | Add-Member -type NoteProperty -Name 'Device Name' -Value $PC
    $missingPCs += $item
  }
}

Write-Host ''
Write-Host -ForegroundColor DarkMagenta 'Missing Devices:'
$missingPCs | Sort-Object 'Device Name' | Format-Table -HideTableHeaders
Write-Host ''

if($missingPCs){
  $HTMLReport = $missingPCs | Sort-Object 'Device Name' | ConvertTo-Html -property 'Device Name' -Head $Header -pre "<h1>Active Directory vs LANDesk</h1><p><b>Generated:</b> $(get-date)<br /><b>Total Records Processed:</b> $($missingPCs | Measure | Select-Object Count | ft -HideTableHeaders | Out-String)</p> <P>PCs on this list either: Need to be removed from Active Directory or added to LanDesk immediately"

  # Email Report
  Send-MailMessage -To $To -Cc $Cc -From $From -SmtpServer $SMTPServer -Subject $Subject -Body ($HTMLReport | Out-String) -BodyAsHtml
}
