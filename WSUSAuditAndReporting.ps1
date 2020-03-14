# Declare WSUS Tools
[void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
Import-Module ActiveDirectory

# Script Variables
$finalSummary = @()
$missingFS = $null
$adFileServerGroup = "Property File Servers"
$daysNotInAD = "-15"
$filterIP = "192.168.*"

# Find computer objects with -fs in the name and then compare to members of Property File Servers group to see if any are missing.
$findfs = Get-ADComputer -Filter "Name -like '*-fs*'" -SearchBase "OU=ComputersDC=concerto,DC=com"
$pfsmembers = Get-ADGroupMember -Identity $adFileServerGroup
$missingFS = Compare-Object -ReferenceObject $findfs.Name -DifferenceObject $pfsmembers.Name | Select-Object InputObject | Sort-Object | Format-Table -HideTableHeaders | Out-String

# Grab list of property file servers, connect to WSUS, remove clients that have not reported in within 15 days or are not on the same subnet as the file server.
Get-ADGroupMember $adFileServerGroup |
ForEach-Object {
    $wsusList = @()
    $adList = @()
    $diffList = @()
    $body = $null
    $wsusConfiguration = $null
    $missing = @()
	
    # Gets list of AD computers
    Get-ADComputer $_.Name |
    ForEach-Object {
        $x = @($_.DistinguishedName.split(","))
        $xs = $x[1] -replace '..='
        $ou = $xs.Substring(0, 3)
        $searchBase = Get-ADOrganizationalUnit -filter { name -like $ou }
        $adList = Get-ADComputer -SearchBase $searchBase -Filter *
    }

    # Attempts to connect to WSUS server
    try {
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($_.name, $False)
        $wsusConnect = $true
    }
    catch {
        $wsusConnect = $False
        $wsusError = $Error[0]
		
    }
    If ($wsusConnect) {
        # Grab IP 192.168.*
        $ip = [System.Net.Dns]::GetHostAddresses($_.name) | Where-Object { $_.IPAddressToString -like $filterIP } | Select-Object IPAddressToString | Format-Table -HideTableHeaders | Out-String
        
        #Checks WSUS server settings
        $srvSettings = New-Object system.object
        $srvSettings | Add-member -type NoteProperty -name TargetingMode -value "Client"
        $srvSettings | Add-member -type NoteProperty -name SyncFromMicrosoftUpdate -value $False
        $srvSettings | Add-member -type NoteProperty -name IsReplicaServer -value $true
        $srvSettings | Add-member -type NoteProperty -name UpstreamWsusServerName -value "WSUS"
        $srvSettings | Add-member -type NoteProperty -name UpstreamWsusServerPortNumber -value "80"
        $srvSettings | Add-member -type NoteProperty -name UpstreamWsusServerUseSsl -value $False
        $srvSettings | Add-member -type NoteProperty -name Correct -value $true
        $srvSettings | Add-member -type NoteProperty -name WsusServerPortNumber -value "80"

        $wsusConfiguration = $wsus.GetConfiguration()

        If ($wsusConfiguration.TargetingMode -ne $srvSettings.TargetingMode) { $srvSettings.correct = $False }
        If ($wsusConfiguration.SyncFromMicrosoftUpdate -ne $srvSettings.SyncFromMicrosoftUpdate) { $srvSettings.correct = $False }
        If ($wsusConfiguration.IsReplicaServer -ne $srvSettings.IsReplicaServer) { $srvSettings.correct = $False }
        If ($wsusConfiguration.UpstreamWsusServerName -ne $srvSettings.UpstreamWsusServerName) { $srvSettings.correct = $False }
        If ($wsusConfiguration.UpstreamWsusServerPortNumber -ne $srvSettings.UpstreamWsusServerPortNumber) { $srvSettings.correct = $False }
        If ($wsusConfiguration.UpstreamWsusServerUseSsl -ne $srvSettings.UpstreamWsusServerUseSsl) { $srvSettings.correct = $False }
        

        # Deletes computers that have not synched with WSUS server for more than 15 days or computers that are on a different subnet
        $wsus.GetComputerTargets() | Where-Object { $_.LastReportedStatusTime -lt (get-date).AddDays($daysNotInAD) -or $_.IPAddress -notlike ($ip.Trim().SubString(0, 11) + '*') } | Sort-Object FullDomainName |
        ForEach-Object { 
            $wsus.GetComputerTargetByName($_.FullDomainName).Delete()
        }

        # Grab OU of computer, Search for PC in AD, and compare against WSUS PCs
        # Gets list of AD computers
        Get-ADComputer $_.Name |
        ForEach-Object {
            $x = @($_.DistinguishedName.split(","))
            $xs = $x[1] -replace '..='
            $ou = $xs.Substring(0, 3)
            $searchBase = Get-ADOrganizationalUnit -filter { name -like $ou }
            $adList = Get-ADComputer -SearchBase $searchBase -Filter *
        }

        # Gets list of WSUS computers
        $wsusList = $wsus.GetComputerTargets()

        if ($wsusList -ne $null ) {

            # Compares ADList vs WSUSList - If not WSUS list comnt ADList
            foreach ($DNSHostName in $adList) {
                # Test $DNSHostName
                foreach ($FullDomainName in $wsusList) {
                    # Test $FullDomainName
                    if ($DNSHostName.DNSHostName -eq $FullDomainName.FullDomainName) {
                        $diffList += $DNSHostName
                    }
                }
            }
        }
        else {
            $diffAdd = New-Object system.object
            $diffAdd | Add-member -type NoteProperty -name Name -value "No Computers in WSUS!"
            $diffList += $diffAdd
        }
        # Create List of missing PCs
        If ($diffList) {
            $missing += compare-object $adList.Name $diffList.Name | Select-Object InputObject
        }
    }

    # Create summary of settings
    $buildSummary = New-Object system.object
    $buildSummary | Add-member -type NoteProperty -name ServerName -value $_.name
    $buildSummary | Add-member -type NoteProperty -name AbleToConnect -value $wsusConnect
    $buildSummary | Add-member -type NoteProperty -name CorrectSettings -value $srvSettings.Correct
    $buildSummary | Add-member -type NoteProperty -name MissingCount -value $missing.count
    $finalSummary += $buildSummary

    # Email Message Body
    if ($missing) {
        $missing = $missing | Select-Object InputObject | Sort-Object InputObject | Format-Table -HideTableHeaders | Out-String
        $body = "The following clients are in AD, but not WSUS:" + $missing + "Please check these clients when possible.`r`n"
    }
    if ($srvSettings.Correct -eq $False -and $wsusConnect -eq $true) {
        $body += "The server " + $_.name + " has incorrect settings.`r`n`r`n" +
        "Setting:`t`tDesired:`tCurrent:`r`n" +
        "Targeting`t`t" + $srvSettings.targetingmode + "`t`t" + $wsusConfiguration.targetingmode + "`n" +
        "Sync From MS`t" + $srvSettings.SyncFromMicrosoftUpdate + "`t`t" + $wsusConfiguration.SyncFromMicrosoftUpdate + "`n" +
        "Is Replica`t`t" + $srvSettings.IsReplicaServer + "`t`t" + $wsusConfiguration.IsReplicaServer + "`n" +
        "Upstream Srv`t" + $srvSettings.UpstreamWsusServerName + "`t`t" + $wsusConfiguration.UpstreamWsusServerName + "`n" +
        "Upstream Prt`t" + $srvSettings.UpstreamWsusServerPortNumber + "`t`t`t" + $wsusConfiguration.UpstreamWsusServerPortNumber + "`n" +
        "Upstream Ssl`t" + $srvSettings.UpstreamWsusServerUseSsl + "`t`t" + $wsusConfiguration.UpstreamWsusServerUseSsl + "`r`n`n"
    }
    If ($wsusConnect -eq $False) {
        $body += "The server " + $_.name + " generated the following error when attempting to connect:`r`n" + $wsusError +
        "`r`nIf this is a 404 error you have installed WSUS on the wrong port." 
    }
    # Send E-mail Alert 
    if ($body) {
        
        # Send Tickets
        Send-MailMessage -To "support@concerto.com" -From "noreply@concerto.com" -SmtpServer "smtp.concerto.com" -Subject "$ou WSUS Discrepancies" -Priority High -Body $body
    }
}

# Format Summary Body
$bodySummary = "Servers missing from 'Property File Servers' group:`n" + $missingFS.Trim() + "`n`nWSUS Server Summaries:`n Server:`t`tConnect:`tSettings:`tMissing PCs:`r`n" 

# Add each server to Summary Body
$finalSummary |
ForEach-Object {  
    $bodySummary += $_.ServerName.padright(12, ' ') + "`t" + $_.AbleToConnect + "`t`t" + $_.CorrectSettings + "`t`t" + $_.MissingCount + "`r`n"
}

#Send weekly summary to WSUS administrator
Send-MailMessage -To "wsusadmins@concerto.com" -From "noreply@concerto.com" -SmtpServer "smtp.concerto.com" -Subject "Weekly WSUS Summary" -Priority High -Body $bodySummary
