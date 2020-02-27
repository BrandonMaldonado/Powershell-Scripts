#### Variables
$deviceModel = (Get-WmiObject -Class:Win32_ComputerSystem).Model
$ip = (Get-NetIPConfiguration | Where-Object { ($_.IPv4DefaultGateway -ne $null) -and ($_.NetAdapter.Status -ne "Disconnected") } | Select-Object IPv4Address).IPv4Address.IPAddress

Function IsUEFI {

<#
.CREDIT
   Chris J Warwick
   https://gallery.technet.microsoft.com/scriptcenter/Determine-UEFI-or-Legacy-7dc79488
.Synopsis
   Determines underlying firmware (BIOS) type and returns True for UEFI or False for legacy BIOS.
.DESCRIPTION
   This function uses a complied Win32 API call to determine the underlying system firmware type.
.EXAMPLE
   If (IsUEFI) { # System is running UEFI firmware... }
.OUTPUTS
   [Bool] True = UEFI Firmware; False = Legacy BIOS
.FUNCTIONALITY
   Determines underlying system firmware type
#>

    [OutputType([Bool])]
    Param ()

    Add-Type -Language CSharp -TypeDefinition @'

    using System;
    using System.Runtime.InteropServices;

    public class CheckUEFI
    {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern UInt32 
        GetFirmwareEnvironmentVariableA(string lpName, string lpGuid, IntPtr pBuffer, UInt32 nSize);

        const int ERROR_INVALID_FUNCTION = 1; 

        public static bool IsUEFI()
        {
            // Try to call the GetFirmwareEnvironmentVariable API.  This is invalid on legacy BIOS.

            GetFirmwareEnvironmentVariableA("","{00000000-0000-0000-0000-000000000000}",IntPtr.Zero,0);

            if (Marshal.GetLastWin32Error() == ERROR_INVALID_FUNCTION)

                return false;     // API not supported; this is a legacy BIOS

            else

                return true;      // API error (expected) but call is supported.  This is UEFI.
        }
    }
'@


    [CheckUEFI]::IsUEFI()
}

function diskSelection {
    Clear-Host

    Write-Host -ForegroundColor Cyan "List of your disks:"
    $getDisks = get-disk

    $getDisks | Format-Table -AutoSize

    DO {

        # Get User Selection and check that the selection is valid
        $userDiskSelection = Read-Host -Prompt "What disk would you like to select? `nVaild Options: $($getDisks.DiskNumber -split ','), (q)uit, (m)ain menu"
        $vaildDiskSelection = $getDisks.DiskNumber -contains $userDiskSelection

        # Menu Special options - main menu and quit
        if ($userDiskSelection -like "m") {
            ## Go to Main Menu
            Launcher
            break
        }
        elseif ($userDiskSelection -like "q") {
            ## Break out of the script
            Write-Host 'Quiting'
            break
        }

        if ($vaildDiskSelection) {
            ## GO GO GO
            If (IsUEFI) { formatUEFI } else { formatBIOS }
            $continue = $true
        }
        else {
            Clear-Host
            $vaildDiskSelection = $null

            # Display Disks
            $getDisks | Format-Table -AutoSize 

            # Display selection and notify user the selection is incorrect
            Write-Host -ForegroundColor red "Invaild Selection ($userDiskSelection) - please try again.`n"
            $continue = $false
        }

    } while ($continue -eq $false)
}

function formatBIOS {
    if ($userDiskSelection -gt '0') {
        # Find any parition with drive letter C and change it
        Get-Partition -DriveLetter C -ErrorAction SilentlyContinue | Set-Partition -NewDriveLetter Y
    }
        
    #Check to see if Disk is RAW / IF it is - Initlize it
    $RawDisk = Get-Disk -Number $userDiskSelection
        
    If ($RawDisk.PartitionStyle -eq 'RAW') {
        Initialize-Disk $userDiskSelection -PartitionStyle MBR
    }
        
    #Wipe Disk
    Write-Host -ForegroundColor Cyan "`nWiping Disk `n"
    Clear-Disk -number $userDiskSelection -RemoveOEM -RemoveData
        
    #Inil Disk
    Write-Host -ForegroundColor Cyan "Initliazing Disk `n"
    Initialize-Disk $userDiskSelection -PartitionStyle MBR
        
    # Create System Partition
    Write-Host -ForegroundColor Cyan "Creating a System partition `n"
    New-Partition -DiskNumber $userDiskSelection -Size 350MB -DriveLetter S -IsActive | Format-Volume -NewFileSystemLabel "System" -FileSystem NTFS | Out-Null
        
    # Create Windows Partion
    Write-Host -ForegroundColor Cyan "Creating a OS partition `n"
    New-Partition -DiskNumber $userDiskSelection -UseMaximumSize -DriveLetter C | Format-Volume -NewFileSystemLabel "Windows" -FileSystem NTFS | Out-Null
        
    # Write Completed
    Write-Host -ForegroundColor Green "All Done! - you should be good to go unless an error occured"
    Pause
    exit
}

function formatUEFI {
    
    #initialize some variables
    $RESize = 300MB
    $SysSize = 100MB
    $MSRSize = 128MB
    $RecoverySize = 15GB
                    
    # Workaround for EliteBook x360 1030 g4 due to 2 disks (primary disk  which was smaller was taking C drive)
    if ($userDiskSelection -gt '0') {
        # Find any parition with drive letter C and change it
        Get-Partition -DriveLetter C -ErrorAction SilentlyContinue | Set-Partition -NewDriveLetter Y
    }

    # Check to see if Disk is RAW / IF it is - Initlize it
    $RawDisk = Get-Disk -Number $userDiskSelection
    If ($RawDisk.PartitionStyle -eq 'RAW') {
        Initialize-Disk $userDiskSelection -PartitionStyle GPT
    }

    # Wipe Disk
    Write-Host -ForegroundColor Cyan "`nWiping Disk `n"
    Clear-Disk -number $userDiskSelection -RemoveOEM -RemoveData

    #Inil Disk
    Write-Host -ForegroundColor Cyan "`nInitliazing Disk `n"
    Initialize-Disk $userDiskSelection -PartitionStyle GPT

    # Define Windows OS partition size
    $WinPartSize = (Get-Disk -Number $userDiskSelection).Size - ($RESize + $SysSize + $MSRSize + $RecoverySize)

    # Create the RE Tools partition
    Write-Host -ForegroundColor Cyan "Creating a Windows RE Tools partition `n"
    New-Partition -DiskNumber $userDiskSelection -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -Size $RESize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows RE Tools" -confirm:$false | Out-null
 
    $partitionNumber = (get-disk $userDiskSelection | Get-Partition | Where-Object { $_.type -eq 'recovery' }).PartitionNumber
 
    Write-Host -ForegroundColor Cyan "Retrieved partition number $partitionnumber - preventing the partition from accidental removal `n"

    # Protect WinRE Tools
    ## Create diskpart script:
    $diskpart_script = @()
    $diskpart_script += "select disk " + $userDiskSelection
    $diskpart_script += "select partition " + $partitionNumber
    $diskpart_script += "gpt attributes=0x8000000000000001"
    $diskpart_script += "exit"

    ## Export diskpart script:
    $diskpart_script | Out-File -FilePath "X:\WINReToolsPartition.txt" -Encoding utf8

    # Run Diskpart with generated script
    Start-Process -FilePath "$env:systemroot\system32\diskpart.exe" -ArgumentList "/s X:\WINReToolsPartition.txt" -PassThru -Wait
 
    # Create the system partition
    Write-Host -ForegroundColor Cyan "Creating a System partition `n"
 
    $sysPartition = New-Partition -DiskNumber $userDiskSelection -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -Size $SysSize -DriveLetter S
    $systemNumber = $sysPartition.PartitionNumber
 
    Write-Host -ForegroundColor Cyan "Retrieved system partition number $systemNumber - formating the system partition `n"
    
    <#
    There is a known bug where Format-Volume cannot format an EFI partition
    so formatting will be done with Diskpart
    #>

    ## System Partition
    ## Create diskpart script:
    $diskpart_script = @()
    $diskpart_script += "select disk " + $userDiskSelection
    $diskpart_script += "select partition " + $systemNumber
    $diskpart_script += "format quick fs=fat32 label=System"
    $diskpart_script += "exit"
    
    ## Export diskpart script:
    $diskpart_script | Out-File -FilePath "X:\SystemPartition.txt" -Encoding utf8

    # Run Diskpart with generated script
    Start-Process -FilePath "$env:systemroot\system32\diskpart.exe" -ArgumentList "/s X:\SystemPartition.txt" -PassThru -Wait

    # Create MSR
    Write-Host -ForegroundColor Cyan "Creating a MSR partition `n"
    New-Partition -DiskNumber $userDiskSelection -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -Size $MSRSize | Out-Null
 
    # Create OS partition
    Write-Host -ForegroundColor Cyan "Creating a OS partition `n"
    New-Partition -DiskNumber $userDiskSelection -Size $WinPartSize -DriveLetter C | 
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows" -confirm:$false | Out-Null

    # Create Recovery
    Write-Host -ForegroundColor Cyan "Creating a Recovery partition `n"
    New-Partition -DiskNumber $userDiskSelection -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -UseMaximumSize | 
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows Recovery" -confirm:$false | Out-null

    $RecoveryPartitionNumber = (Get-Disk -Number $userDiskSelection | Get-Partition | Where-Object { $_.type -eq 'Recovery' } | Select-Object -Last 1).PartitionNumber
 
    #run diskpart to set GPT attribute to prevent partition removal
    #the here string must be left justified

    ## Recovery Partition
    ## Create diskpart script:
    $diskpart_script = @()
    $diskpart_script += "select disk " + $userDiskSelection
    $diskpart_script += "select partition " + $RecoveryPartitionNumber
    $diskpart_script += "gpt attributes=0x8000000000000001"
    $diskpart_script += "exit"
        
    ## Generate diskpart script:
    $diskpart_script | Out-File -FilePath "X:\RecoveryPartition.txt" -Encoding utf8

    # Run Diskpart with generated script
    Start-Process -FilePath "$env:systemroot\system32\diskpart.exe" -ArgumentList "/s X:\RecoveryPartition.txt" -PassThru -Wait

    # Write Completed
    Write-Host -ForegroundColor Green "All Done! - you should be good to go unless an error occured"
    Pause
    exit
}

# Main Menu
function Launcher {
    $continue = $true
    do {
        Clear-Host
        Write-Host -ForegroundColor Cyan "Disk Cleanup Script"
        Write-Host "`n"
        Write-Host -ForegroundColor Cyan "Quick Info"
        Write-Host "  IP Address: $(ipconfig | Where-Object { $_ -match 'IPv4.+\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' } | out-null; $Matches[1])"
        Write-Host "  Device Model: $deviceModel"
        If (IsUEFI) { Write-Host "  Boot Mode: UEFI" } else { Write-Host "  Boot Mode: Legacy - BIOS" }
        Write-Host "`n"
        Write-Host -ForegroundColor Cyan "Helpful Hints"
        Write-Host "  * What does this do?`n    Clears existing disk paritions and recreates the standard paritions. This is a requirement at the moment."
        Write-Host -FOregroundColor Cyan "`nOptions"
        Write-Host "  (S)art`n  (Q)uit"
        $userInput = Read-Host -Prompt "What do you want to do?"
        switch ($userInput) {
            "s" {
                Clear-Host
                diskSelection
                $continue = $false
            } 
            "q" {
                exit
            }
        }
    } while ($continue -eq $true)
}

# Start the menu function
Launcher
