# Directory where import and export will occur
$fileLocation = "$ENV:USERPROFILE\Desktop\"
$importFileName = 'Summary_YTD_with_sn.csv'
$outputFileName = 'PCPurchaseDates.csv'

$CSVImport = Import-Csv -Path "$fileLocation$importFileName"

$report = @()

# Loop through each record in the CSV
foreach($item in $CSVImport){

    # Split Serial Numbers by ,
    $serials = $($item.Serial_Number_Set).Split(",")
    $serials = $serials.Trim() -replace "S/N: ","" -replace "S/N : ",""

    # For each serial number tag the purchase date
    foreach($serial in $serials){
        if(($item.Mfr -match "HPI*|HP*|HPE*|Hewlett*") -AND ($serial.Length -eq 10)){
            $record = New-Object PSObject
            $record | Add-Member -type NoteProperty -Name 'Serial Number' -Value $($serial)
            $record | Add-Member -type NoteProperty -Name 'Purchase Date' -Value $($item.Actual_Date)
            $report += $record
        }
        # If the manufacter is not HP or serial number is not 10 digits print it
        else{
            Write-Host "`n"
            Write-Host "Record Not Added to Report"
            Write-Host "---------------------------"
            Write-Host "Purchase Order: " $item.PO_Number
            Write-Host "Manufacter: "$item.Mfr
            Write-Host "Serial Number: "$serial
            Write-Host "Serial Number Length: "$serial.Length
        }
    }
}

# Export Report
$report | Export-Csv -Path "$fileLocation$outputFileName" -NoTypeInformation
