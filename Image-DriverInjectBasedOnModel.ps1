# Declare the core server name
$coreServer = 'landesk-server'

# Driver Zip Download Location
$DriverZipFileLoc = 'C:\Drivers.zip'

# Driver Extraction Location
$DriverExtractionLoc = 'C:\Drivers'

# System32 Location for WinPE
$Sys32WinPELoc = 'X:\Windows\System32\'

# Try to get the model number
# Caching CimInstance to reduce call time and ensure no error
$cimInstance = Get-CimInstance -ClassName Win32_ComputerSystem
$computerModel = $cimInstance.Model

# Test connectivity to core server
if ((Test-Connection $coreServer -Quiet) -eq $true) {
    Write-Host -ForegroundColor Magenta "Debug: Able to ping core server.`n"
}
else {
    Write-Host -ForegroundColor red "Error: Not able to ping core server.`n"
    Pause
    exit
}

# Do we have a mapped drive?
Get-PSDrive | ForEach-Object {
    If ( $_.DisplayRoot -like '*\ldswd' ) {
        $mappedDriveFound = $true
        $UNCPath = "FileSystem::" + $_.DisplayRoot
        Write-Host -ForegroundColor Magenta "Debug: Found mapped drive" $UNCPath `n
    }
}

# Look for a driver, grab it, and install it
if ($mappedDriveFound) {

    # Grab Driver Latest Matrix
    # Caching DriverMatrix to reduce call time and ensure no error
    $DriverMatrix = Import-Csv -Path "$UNCPath\provisioning\Drivers\DriverMatrix.csv"

    # Loop through the matrix and add to driver hash table
    $driverTable = @{ }
    foreach ($line in $DriverMatrix) {
        $driverTable.Add($line.Name.Trim(), $line.Driver.Trim())
    }

    # Display supported device families
    Write-Host -ForegroundColor Blue "--------------- DriverMatrix -------------"
    try {
        ((($driverTable.GetEnumerator() | Select-Object @{name = 'Device Family'; Expression = { $_.Name } }, @{name = 'Driver Package'; Expression = { $_.Value } }) | Sort-Object -Property 'Device Family' | Out-String ).Replace('*', ' ')).Trim()
    }
    catch {
        Write-Host -ForegroundColor Red "Error: Unable to generate DriverMatrix"
        Write-Host $_
        Pause
        exit
    }
    Write-Host ""
    Write-Host -ForegroundColor Blue "Status Messages:"
    Write-Host "Detected Device Model: $computerModel"
    # Search through driver table to see if a match is found for device model, search for driver on preferred server, extract, and inject drivers
    $driverTable.GetEnumerator() | ForEach-Object {
        $modelFamily = $_.Key

        if ($computerModel -like $modelFamily) {
            $Modelkey = $_.Key
            $SPvalue = $_.Value

            # Set no match to false to prevent loop
            $noMatch = $false
            
            Write-Host -ForegroundColor Green "Good News! I found a driver package for this model from the DriverMatrix."
            Write-Host "Selected DriverMatrix Driver Family:" $Modelkey.Replace("*", "")
            Write-Host "Searching for driver pack on preferred server:" $SPvalue

            # Search for driver package, copy, and if not found tell user
            # Caching location to reduce call time and ensure no error
            $location = (Get-ChildItem -Path $UNCPath -Recurse -Filter *.zip | Where-Object { $_.Name -like $SPvalue + ".zip" } | Select-Object -Property FullName)
            Write-Host -ForegroundColor Green "Found Driver Pack: $($location.FullName)"

            # Make sure drivers folder exists
            if ((Test-Path -Path "$DriverExtractionLoc") -ne $true) {
                New-Item -ItemType "directory" -Path "$DriverExtractionLoc" | Out-Null
            }

            # Create driver log 
            New-Item "C:\Tools\drivers.log" -Force | Out-Null

            # Copy driver
            Write-Host "Attempting to copy the driver pack from the preferred server."
            try {

                # Generates progress bar, but uses copy instead of powershell
                Start-Process -FilePath "$Sys32WinPELoc\cmd.exe" -ArgumentList "/c copy /Z $($location.FullName) $DriverZipFileLoc" -Wait

                Write-Host "Checking hash of the file copied Vs. preferred server"

                # Get MD5 of remote file
                $md5PreferredServer = Get-FileHash -Algorithm MD5 -Path $($location.FullName) | Select-Object -ExpandProperty hash
                Write-Host " - Preferred Server Hash:" $md5PreferredServer

                if ((Test-Path -Path "$DriverZipFileLoc") -eq $true) {

                    # Get MD5 of local File
                    $md5Local = Get-FileHash -Algorithm MD5 -Path "$DriverZipFileLoc" | Select-Object -ExpandProperty hash

                    if ($md5Local) {
                        Write-Host " - Local File Hash:" $md5PreferredServer
                    }

                    if ($md5PreferredServer -eq $md5Local) {
                        Write-Host -ForegroundColor Green "Hashes Match - Driver Pack copied successfully."
                    }
                    else {
                        throw "Error: MD5 mismatch - exiting"
                    }

                }
                else {
                    throw "Error: $DriverZipFileLoc does not exist - exiting"
                }
            }
            catch {
                Write-Host -ForegroundColor Red Error: $_
                Pause
                exit
            }

            # Unzip downloaded driver
            Write-Host "Attempting to unzip the driver pack."
            try {
                Expand-Archive -Path "$DriverZipFileLoc" -DestinationPath "$DriverExtractionLoc" -ErrorAction Stop -Force -Verbose 4>> C:\Tools\drivers.log
                Write-Host -ForegroundColor Green "Successfully extracted files."
            }
            catch {
                Write-Host -ForegroundColor Red "Error: Unable to unzip the driver pack."
                Write-Host $_
                Pause
                exit
            }
            
            # Inject Driver
            Write-Host "Attempting to inject the drivers into the OS."
            Start-Process -FilePath "X:\Windows\System32\Dism.exe" -ArgumentList "/Image:C:\ /add-driver /Driver:$DriverExtractionLoc /Recurse" -Wait -NoNewWindow 4>> C:\Tools\drivers.log

            # Cleanup Drivers folder
            Remove-Item -Path "$DriverExtractionLoc" -Recurse -Force

            # ALL DONE!
            Write-Host -ForegroundColor Green "`nCompleted all steps - All Done. Pausing for 30 seconds in case any errors occured.`n"
            Start-Sleep -Seconds 30
            exit
        }
        else {
            $noMatch = $true
        }
    }
    if ($noMatch -eq $true) {
        Write-Host -ForegroundColor Yellow "Warning: No driver package found for your device model ($computerModel) in DriverMatrix. The installation will continue, but it may not be successful without drivers injected."
        pause
        exit
    }
}
else {
    # No mapped drive found
    Write-Host -ForegroundColor Yellow "Error: No mapped drive detected. Please check network connectivity."
    Pause
    exit
}
