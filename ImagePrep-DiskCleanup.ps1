#Variables
$deviceModel = (Get-WmiObject -Class:Win32_ComputerSystem).Model
$ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -ne "Disconnected" } | Select-Object -ExpandProperty IPv4Address).IPAddressToString

#Function to check if UEFI or BIOS
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

#Function to select disk
function diskSelection {
    try {
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
    catch {
        Write-Host -ForegroundColor Red "Error Occured: $_"
    }
}

#Function to format disk in UEFI
function formatUEFI {
    try {
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
        Write-Host -ForegroundColor Cyan "Creating a Windows RE Tools partition"
        $CreateREToolsPart = New-Partition -DiskNumber $userDiskSelection -Size $RESize -GptType 0FC63DAF-8483-4772-8E79-3D69D8477DE4 -IsActive:$true

        # Create the System partition
        Write-Host -ForegroundColor Cyan "Creating a System partition"
        $CreateSystemPart = New-Partition -DiskNumber $userDiskSelection -Size $SysSize -GptType E3C9E316-0B5C-4DB8-817D-F92DF00215AE -IsActive:$true

        # Create the MSR partition
        Write-Host -ForegroundColor Cyan "Creating an MSR partition"
        $CreateMSRPart = New-Partition -DiskNumber $userDiskSelection -Size $MSRSize -GptType DE94BBA4-06D1-4D40-A16A-BFD50179D6AC

        #Create the Windows OS partition
        Write-Host -ForegroundColor Cyan "Creating an OS partition"
        $CreateOSPart = New-Partition -DiskNumber $userDiskSelection -Size $WinPartSize -GptType EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 -IsActive:$true

        #Create the Recovery partition
        Write-Host -ForegroundColor Cyan "Creating a Recovery partition"
        $CreateRecoveryPart = New-Partition -DiskNumber $userDiskSelection -Size $RecoverySize -GptType DE94BBA4-06D1-4D40-A16A-BFD50179D6AC

        #Format the partitions
        Write-Host -ForegroundColor Cyan "Formatting the partitions"
        Get-Partition -DiskNumber $userDiskSelection | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false -ErrorAction Stop

        #Set the drive letter
        Write-Host -ForegroundColor Cyan "Setting the drive letters"
        Get-Partition -DriveLetter Y -ErrorAction SilentlyContinue | Set-Partition -NewDriveLetter C
        Get-Partition -GptType 0FC63DAF-8483-4772-8E79-3D69D8477DE4 | Set-Partition -NewDriveLetter R
        Get-Partition -GptType E3C9E316-0B5C-4DB8-817D-F92DF00215AE | Set-Partition -NewDriveLetter S
        Get-Partition -GptType DE94BBA4-06D1-4D40-A16A-BFD50179D6AC | Set-Partition -NewDriveLetter M

        # Make the System partition active
        Write-Host -ForegroundColor Cyan "Making the System partition active"
        Set-Partition -DiskNumber $userDiskSelection -PartitionNumber 2 -IsActive $true

        # Assign a drive letter to the recovery partition
        Write-Host -ForegroundColor Cyan "Assigning a drive letter to the Recovery partition"
        Get-Partition -GptType DE94BBA4-06D1-4D40-A16A-BFD50179D6AC | Set-Partition -NewDriveLetter W

        # Create the partition layout
        Write-Host -ForegroundColor Cyan "Creating the partition layout"
        $PartLayout = Get-Partition -DiskNumber $userDiskSelection | Select-Object -Property @{Name = "Partition"; Expression = { $_.PartitionNumber } }, DriveLetter, @{Name = "Size (MB)"; Expression = { [math]::Round($_.Size / 1MB) } }, @{Name = "Type"; Expression = { $_.GptType } }
        $PartLayout | Format-Table -AutoSize
    }
    catch {
        Write-Host -ForegroundColor Red "Error Occured: $_"
    }
}

#Function to format disk in BIOS
function formatBIOS {
    try {
        #initialize some variables
        $RESize = 300MB
        $SysSize = 100MB
        $MSRSize = 128MB
        $RecoverySize = 15GB

        # Workaround for EliteBook x360 1030 g4 due to 2 disks (primary disk  which was smaller was taking C drive)
        if ($userDiskSelection -gt '0') {
            # Create an array to store the results of Get-Partition
            $partitions = Get-Partition

            # Create an array to store the disk numbers of the partitions
            $diskNumbers = @()

            # Loop through the partitions and store the disk numbers of each partition in the array
            foreach ($partition in $partitions) {
                $diskNumbers += $partition.DiskNumber
            }

            # Find the most likely primary hard drive
            $mostLikelyPrimary = $partitions | Where-Object { $_.DiskNumber -eq ($diskNumbers | Sort-Object -Unique | Select-Object -First 1) }

            # If the most likely primary hard drive is not the drive assigned letter 'C', change it
            if ($mostLikelyPrimary.DriveLetter -ne "C") {
                $mostLikelyPrimary | Set-Partition -DriveLetter "C"
            }
        }

        # Check to see if Disk is RAW
        # If it is - Initlize it
        $RawDisk = Get-Disk -Number $userDiskSelection
        If ($RawDisk.PartitionStyle -eq 'RAW') {
            Initialize-Disk $userDiskSelection -PartitionStyle MBR
        }

        # Wipe Disk
        Write-Host -ForegroundColor Cyan "`nWiping Disk `n"
        Clear-Disk -number $userDiskSelection -RemoveOEM -RemoveData

        # Define Windows OS partition size
        $WinPartSize = (Get-Disk -Number $userDiskSelection).Size - ($RESize + $SysSize + $MSRSize + $RecoverySize)

        # Create the RE Tools partition
        Write-Host -ForegroundColor Cyan "Creating a Windows RE Tools partition"
        $CreateREToolsPart = New-Partition -DiskNumber $userDiskSelection -Size $RESize -IsActive:$true

        # Create the System partition
        Write-Host -ForegroundColor Cyan "Creating a System partition"
        $CreateSystemPart = New-Partition -DiskNumber $userDiskSelection -Size $SysSize -IsActive:$true

        # Create the MSR partition
        Write-Host -ForegroundColor Cyan "Creating an MSR partition"
        $CreateMSRPart = New-Partition -DiskNumber $userDiskSelection -Size $MSRSize

        #Create the Windows OS partition
        Write-Host -ForegroundColor Cyan "Creating an OS partition"
        $CreateOSPart = New-Partition -DiskNumber $userDiskSelection -Size $WinPartSize -IsActive:$true

        #Create the Recovery partition
        Write-Host -ForegroundColor Cyan "Creating a Recovery partition"
        $CreateRecoveryPart = New-Partition -DiskNumber $userDiskSelection -Size $RecoverySize

        #Format the partitions
        Write-Host -ForegroundColor Cyan "Formatting the partitions"
        Get-Partition -DiskNumber $userDiskSelection | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Hard Drive" -Confirm:$false -ErrorAction Stop

        #Set the drive letter
        Write-Host -ForegroundColor Cyan "Setting the drive letters"
        Get-Partition -DriveLetter Y -ErrorAction SilentlyContinue | Set-Partition -NewDriveLetter C
        Get-Partition -PartitionNumber 1 | Set-Partition -NewDriveLetter R
        Get-Partition -PartitionNumber 2 | Set-Partition -NewDriveLetter S
        Get-Partition -PartitionNumber 3 | Set-Partition -NewDriveLetter M

        # Make the System partition active
        Write-Host -ForegroundColor Cyan "Making the System partition active"
        Set-Partition -DiskNumber $userDiskSelection -PartitionNumber 2 -IsActive $true

        # Assign a drive letter to the recovery partition
        Write-Host -ForegroundColor Cyan "Assigning a drive letter to the Recovery partition"
        Get-Partition -PartitionNumber 4 | Set-Partition -NewDriveLetter W

        # Create the partition layout
        Write-Host -ForegroundColor Cyan "Creating the partition layout"
        $PartLayout = Get-Partition -DiskNumber $userDiskSelection | Select-Object -Property @{Name = "Partition"; Expression = { $_.PartitionNumber } }, DriveLetter, @{Name = "Size (MB)"; Expression = { [math]::Round($_.Size / 1MB) } }, @{Name = "Type"; Expression = { $_.PartitionStyle } }
        $PartLayout | Format-Table -AutoSize
    }
    catch {
        Write-Host -ForegroundColor Red "Error Occured: $_"
    }
}

#Menu Function
function Launcher {
    try {
        Clear-Host
        Write-Host -ForegroundColor Cyan "`nYou have selected $deviceModel`n"
        Write-Host -ForegroundColor Cyan "Your IP Address is: $ip`n"
        $userInput = Read-Host -Prompt "What would you like to do?`n(s)elect disk, (q)uit"
        switch ($userInput) {
            's' {
                diskSelection
            }
            'q' {
                Write-Host -ForegroundColor Cyan "Quiting"
            }
            default {
                Write-Host -ForegroundColor Red "Invaild Selection - please try again.`n"
                Launcher
            }
        }
    }
    catch {
        Write-Host -ForegroundColor Red "Error Occured: $_"
    }
}

#Run Script
Launcher
