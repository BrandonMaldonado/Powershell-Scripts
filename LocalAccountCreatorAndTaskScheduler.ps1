# Ask user what computer they want to connect to
$remotePC = Read-Host -Prompt "What PC do you want to connect to?"

if (!$remotePC) {
    Write-Output "You didn't enter anything"
}
else {
    # Remote PS
    $pss = New-PSSession -ComputerName $remotePC
}

# Excute the following on the remote PC
Invoke-Command -Session $pss -ScriptBlock {
    # Generate Random Password
    $length = 64
    $genPASSWD = [System.Web.Security.Membership]::GeneratePassword($length, 2)

    # Declare Variables
    $acctNAME = "ACCOUNT NAME"
    $lclNAME = $env:computername + "\" + $acctNAME
    $checkACCT = Get-WmiObject -Class Win32_UserAccount | Where-Object { $_.Name -eq $acctNAME }
    $taskNAME = "TASK_NAME"
    $findEXSTTASK = Get-ScheduledTask | Where-Object { $_.TaskName -match $taskNAME }
    $taskDESC = "TASK DESCRIPTION"
    $taskCMD = "c:\windows\system32\notepad.exe"
    $taskTime = "2am"
    $taskACT = New-ScheduledTaskAction -Execute $taskCMD
    $taskTRG = New-ScheduledTaskTrigger -Daily -At $taskTime

    # Check to see if desired user exists / if the user does not exist make it. If the desired user exists update the password.
    If (!$checkACCT) {
        (net user $acctNAME $genPASSWD /add /y) | out-null 
        Get-WmiObject Win32_UserAccount -Filter "name='$($acctNAME)'" | Set-WmiInstance -Arguments @{PasswordExpires = $false }	
        Get-WmiObject Win32_UserAccount -Filter "name='$($acctNAME)'" | Set-WmiInstance -Arguments @{PasswordChangeable = $false }
        (net localgroup administrators $acctNAME /add) | out-null 
        Write-Output "Account created"
    }
    else {
        (net user $acctNAME $genPASSWD) | out-null 
        Write-Output "Updated account password."
    }


    # Check to see if an existing task exists
    if ($findEXSTTASK) {
        # Unregister existing task
        Write-Output "Deleting existing task"
        Unregister-ScheduledTask -TaskName $taskNAME -Confirm:$false | Out-Null

        # Create new scheduled task
        Write-Output "Creating new task"
        Register-ScheduledTask -Action $taskACT -Trigger $taskTRG -TaskName $taskNAME -Description $taskDESC -User $lclNAME -Password $genPASSWD -RunLevel Highest | Out-Null
    }
    else {
        # Create new scheduled task
        Write-Output "Creating new task"
        Register-ScheduledTask -Action $taskACT -Trigger $taskTRG -TaskName $taskNAME -Description $taskDESC -User $lclNAME -Password $genPASSWD -RunLevel Highest | Out-Null
    }
}

Write-Host "Script is done - please close when you are ready."
cmd /c pause | out-null
