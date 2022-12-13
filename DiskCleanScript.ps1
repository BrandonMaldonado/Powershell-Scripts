#### Variables
$deviceModel = (Get-WmiObject -Class:Win32_ComputerSystem).Model
$ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -ne "Disconnected" } | Select-Object -ExpandProperty IPv4Address).IPAddressToString

Function IsUEFI {
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
            GetFirmwareEnvironmentVariableA("","{00000000-0000-0000-0000-000000000000}",IntPtr.Zero,0);
            return (Marshal.GetLastWin32Error() != ERROR_INVALID_FUNCTION);
        }
    }
'@

    [CheckUEFI]::IsUEFI()
}

function diskSelection {
    Clear-Host
    Write-Host -ForegroundColor Cyan "List of your disks:"
    $getDisks = get-disk | Format-Table -AutoSize

    do {
        $userDiskSelection = Read-Host -Prompt "What disk would you like to select? `nVaild Options: $($getDisks.DiskNumber -split ','), (q)uit, (m)ain menu"
        $vaildDiskSelection = $getDisks.DiskNumber -contains $userDiskSelection
        if ($userDiskSelection -like "m") {
            Launcher
            break
        }
        elseif ($userDiskSelection -like "q") {
            Write-Host 'Quiting'
            break
        }
        if ($vaildDiskSelection) {
            if (IsUEFI) { formatUEFI } else { formatBIOS }
            $continue = $true
        }
        else {
            Clear-Host
            $vaildDiskSelection = $null
            Write-Host -ForegroundColor red "Invaild Selection ($userDiskSelection) - please try again.`n"
            $getDisks | Format-Table -AutoSize 
            $continue = $false
        }
    } while ($continue -eq $false)
}

DiskNumber

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

    # Check to see if Disk is RAW
    # If it is - Initlize it
    $RawDisk = Get-Disk -Number $userDiskSelection
    If ($RawDisk.PartitionStyle -eq 'RAW') {
        Initialize-Disk $userDiskSelection -PartitionStyle GPT
    }

    # Wipe Disk
    Write-Host -ForegroundColor Cyan "`nWiping Disk `n"
    Clear-Disk -number $userDiskSelection -RemoveOEM -RemoveData

    # Define Windows OS partition size
    $WinPartSize = (Get-Disk -Number $userDiskSelection).Size - ($RESize + $SysSize + $MSRSize + $RecoverySize)

    # Create the RE Tools partition
    Write-Host -ForegroundColor Cyan "Creating a Windows RE Tools partition `n"
    New-Partition -DiskNumber $userDiskSelection -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -Size $RESize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows RE Tools" -confirm:$false | Out-null
 
    $partitionNumber = (get-disk $userDiskSelection | Get-Partition | Where-Object { $_.type -eq 'recovery' }).PartitionNumber
 
    Write-Host -ForegroundColor Cyan "Retrieved partition number $partitionnumber - preventing the partition from accidental removal `n"

    # Protect WinRE Tools
    # Create diskpart script and export
    $diskpart_script = "select disk $userDiskSelection; select partition $partitionNumber; gpt attributes=0x8000000000000001; exit"
    $diskpart_script | Out-File -FilePath "X:\WINReToolsPartition.txt" -Encoding utf8
    # Run Diskpart with generated script
    Start-Process -FilePath "$env:systemroot\system32\diskpart.exe" -ArgumentList "/s X:\WINReToolsPartition.txt" -PassThru -Wait

    # Create the system partition
    Write-Host -ForegroundColor Cyan "Creating a System partition `n"
 
    $sysPartition = New-Partition -DiskNumber $userDiskSelection -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -Size $SysSize -DriveLetter S
    $systemNumber = $sysPartition.PartitionNumber
 
    Write-Host -ForegroundColor Cyan "Retrieved system partition number $systemNumber - formating the system partition `n"
    
    # Create diskpart script and export
    $diskpart_script = "select disk $userDiskSelection; select partition $systemNumber; format quick fs=fat32 label=System; exit"
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
 
    # Create diskpart script and export
    $diskpart_script = "select disk $userDiskSelection; select partition $RecoveryPartitionNumber; gpt attributes=0x8000000000000001; exit"
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
    do {
        Clear-Host
        Write-Host -ForegroundColor Cyan "Disk Cleanup Script"
        Write-Host "`nQuick Info"
        Write-Host "  IP Address: $(ipconfig | Where-Object { $_ -match 'IPv4.+\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' } | out-null; $Matches[1])"
        Write-Host "  Device Model: $deviceModel"
        Write-Host "  Boot Mode: $(if (IsUEFI) { "UEFI" } else { "Legacy - BIOS" })"
        Write-Host "`nHelpful Hints"
        Write-Host "  * What does this do?`n    Clears existing disk paritions and recreates the standard paritions. This is a requirement at the moment."
        Write-Host -ForegroundColor Cyan "`nOptions"
        Write-Host "  (S)art`n  (Q)uit"
        $userInput = Read-Host -Prompt "What do you want to do?"
        switch ($userInput) {
            "s" {
                Clear-Host
                diskSelection
                break
            } 
            "q" {
                exit
            }
        }
    } while ($true)
}

# Start the menu function
Launcher
