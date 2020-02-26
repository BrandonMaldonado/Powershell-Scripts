
# Variables
$HPCabFileLocation = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab"
$HPCabDLLocation = "C:\HPDrivers\"
$driverLinkArray = @()
$jobs=@()
filter timestamp {"$(Get-Date -Format G): $_"}

function Get-HPCab {
    param (
    )

    try {
        if ((Test-Path $HPCabDLLocation) -eq $false) {
            New-Item -Path $HPCabDLLocation -ItemType Directory -Name 'HPDrivers'
            Write-Host 'No directory found // creating directory'
        }
    }
    catch {
        Write-Host 'Error occured when attempting to create the HP Driver location: ' + $HPCabDLLocation
    }
    
    Invoke-WebRequest -Uri $HPCabFileLocation -OutFile ($HPCabDLLocation + "HPDrivers\" + "HPDriver.cab")
 
    Start-Process -FilePath "C:\Windows\System32\expand.exe" -ArgumentList "$($HPCabDLLocation + 'HPDrivers\' + 'HPDriver.cab') $($HPCabDLLocation + 'HPDrivers\' + 'CabExtract.xml')"    
    
}

function New-HPDriverMatrix {
    param (
    )
    
    [XML]$xml = Get-Content -Path $($HPCabDLLocation + 'HPDrivers\' + 'CabExtract.xml')

    $HPSoftPaqList = ($xml).ChildNodes.SelectNodes("*/SoftPaqList/SoftPaq")

    $HPProductList = ($xml).ChildNodes.SelectNodes("*/ProductOSDriverPackList/ProductOSDriverPack")

    # TO Do: Replace with dynamic query from LANDesk
    $ModelsInEnv = @("HP Compaq Elite 8300", "HP EliteBook 820 G1", "HP EliteBook 820 G2")

    foreach ($model in $ModelsInEnv) {
        $FetchModelDetail = $HPProductList | Where-Object { ($_.SystemName -match $model) -and ($_.OSName -match "^Windows 10 64-bit, \d\d\d\d") } |
        Sort-Object -Property OSName -Descending | Select-Object -First 1

        if ($FetchModelDetail) {
            $FetchModelSoftPaq = $HPSoftPaqList | Where-Object { $_.Id -eq $FetchModelDetail.SoftPaqId }
            
            $obj1 = New-Object PSObject
            $obj1 | Add-Member -MemberType NoteProperty -Name "System Name" -Value $("*" + $model + "*")
            $obj1 | Add-Member -MemberType NoteProperty -Name "OS Version" -Value $($FetchModelDetail.OSName)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq Name" -Value $($FetchModelSoftPaq.Name)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq ID" -Value $($FetchModelSoftPaq.ID)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq URL" -Value $($FetchModelSoftPaq.Url)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq Version" -Value $($FetchModelSoftPaq.Version)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq DateRelease" -Value $($FetchModelSoftPaq.DateReleased)
            $obj1 | Add-Member -MemberType NoteProperty -Name "SoftPaq MD5" -Value $($FetchModelSoftPaq.MD5)
            $script:driverLinkArray += $obj1

            $obj1
        }
        else {
            Write-Host -ForegroundColor Red "EOL: No Windows 10 Driver for: " $model
            Write-Host ""
        }

    }

    $script:driverLinkArray | Sort-Object -Property 'System Name' -Descending -Unique | Export-Csv $($HPCabDLLocation + 'HPDrivers\' + 'DriverMatrix.csv') -NoTypeInformation
}

function Start-HPDriverDownload {
    param(
    )

    Write-Host "Processing Driver Matrix:"
    Write-Host ""

    function Start-Download {
        param (
        )
        Write-Host -ForegroundColor Cyan ' + Downloading'
        Start-BitsTransfer -Source $($driver.'SoftPaq URL') -Destination $destination
    }

    foreach ($driver in $script:driverLinkArray) {

        $drivernameregex = ".*(sp.*)"
        $drivername = ($driver.'SoftPaq URL' | Select-String -Pattern $drivernameregex -AllMatches).Matches.Groups[1].Value

        $destination = $($HPCabDLLocation + 'HPDrivers\Windows10\' + $drivername)

        #$driver
        Write-Host "Processing" $driver.'System Name'.Replace('*','')
        
        # Check that windows download folder exists
        if ((Test-Path -Path $($HPCabDLLocation + 'HPDrivers\Windows10\')) -eq $false) {
            New-Item -Path $($HPCabDLLocation + 'HPDrivers\') -ItemType Directory -Name 'Windows10'
        }

        # To Do: Add logic to see if any files exist in the folder that are no longer needed.

        # Check if the download exists and if not download it
        if ((Test-Path -Path $destination) -eq $false) {
            Start-Download
        }
        else {
            # Check MD5 and if there is no match, redownload the file.
            $Downloadedmd5 = (Get-FileHash -Algorithm MD5 -Path $destination | Select-Object Hash).Hash
            if($driver.'SoftPaq MD5' -eq $Downloadedmd5){
                Write-Host -ForegroundColor Blue " + Already downloaded & MD5 Matches:" $drivername
            }
            else {
                Write-Host 'Hash does not match - redownloading'
                Start-Download
            }
        }

        # To Do: Extract SP 
        $params = "-e -f " + $destination.Trim(".exe") + " -s"
        Write-Host "Extracting the SP"
        Start-Process -FilePath $destination -ArgumentList $params -Wait
        Write-Host "Done"

        # To Do: Zip Files

    }
    
}
