# Variables
$dataDrive = "D:\"

# Generate Property Code
$generatePropCode = $env:computername | Select-String -Pattern "\w.*(?=-)"
$propCode = ($generatePropCode.Matches.Value).Trim()

# Root Folders to create on C:\
$rootFolders = @("Media","LDSWD","Share","Users")

# Folders to create under Share
$shareFolders = @("DEPT1", "DEPT2", "DEPT3", "DEPT4", "DEPT5", "DEPT6", "DEPT7", "DEPT8", "DEPT9", "DEPT10", "DEPT11", "DEPT12")

# Create the folders mentioned above
ForEach ($folder in $rootFolders){
    Write-Host $folder
    New-Item -Path "$dataDrive\$folder" -ItemType Directory -Force
}

# Check to see if there are any shares based on what we are creating and remove them.
$foundShares = Get-SmbShare
foreach($exstShares in $foundShares){
    if($rootFolders -contains $exstShares.Name){
        Remove-SmbShare -Name $exstShares.Name -Force
    }
}

# Create Standard Shares
forEach ($item in $rootFolders){

    # LANDesk Share
    if ($item -eq 'LDSWD') {
        Write-Host "Enabling Share for $item"
        New-SmbShare -Name "LDSWD" -Path "D:\LDSWD" -FullAccess "DOMAIN\USER"
    }

    # Media Share
    if($item -eq 'Media'){
        Write-Host "Enabling Share for $item"
        New-SmbShare -Name "$item" -Path "D:\$item" -FullAccess "DOMAIN\PCADMINS"
    }

    # General Share
    if($item -eq 'Share'){
        Write-Host "Enabling Share for $item"
        New-SmbShare -Name "$item" -Path "D:\$item" -ChangeAccess "DOMAIN\SEC_$($propCode)_Everyone"
    }

    # Personal Share
    if($item -eq 'Users'){
        Write-Host "Enabling Share for $item"
        New-SmbShare -Name "$item" -Path "D:\$item" -ChangeAccess "DOMAIN\SEC_$($propCode)_Everyone"
    }

}

foreach($folder in $shareFolders){

    # Create Folders
    New-Item -ItemType 'Directory' -Path ($dataDrive + "Share\") -Name $folder -Force

    ###########  Subfolders and files only
    
    # Get the ACL for an existing folder
    $acl = Get-Acl ($dataDrive + "Share\" + $folder)

    # Strip ALL access
    $acl.SetAccessRuleProtection($true, $false)
     
    # Set an Access rule for 'Subfolders and files' only
    $permission1 = "DOMAIN\SEC_$($propCode)_$($folder)",'Modify, DeleteSubdirectoriesAndFiles','ContainerInherit, ObjectInherit', 'InheritOnly', "Allow"
    $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission1
    $acl.SetAccessRule($rule1)

    # Apply the modified access rule to the folder
    $acl | Set-Acl ($dataDrive + "Share\" + $folder)

    ###########  This folder Only

    # Get the ACL for an existing folder
    $acl = Get-Acl ($dataDrive + "Share\" + $folder)
     
    # Add an Access rule for 'This folder' only.
    $permission2 = "DOMAIN\SEC_$($propCode)_$($folder)",'DeleteSubdirectoriesAndFiles, Write, ReadAndExecute, Synchronize','none', 'none', "Allow"
    $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission2
    $acl.AddAccessRule($rule2)

    # Apply the modified access rule to the folder
    $acl | Set-Acl ($dataDrive + "Share\" + $folder)

    ###########   Admin access for folder and subfolders

    # Get the ACL for an existing folder
    $acl = Get-Acl ($dataDrive + "Share\" + $folder)
     
    # Add an Access rule
    $permission3 = "BUILTIN\Administrators", "FullControl", "Allow"
    $rule3 = New-Object System.Security.AccessControl.FileSystemAccessRule $permission3
    $acl.AddAccessRule($rule3)

    # Apply the modified access rule to the folder
    $acl | Set-Acl ($dataDrive + "Share\" + $folder)
}
