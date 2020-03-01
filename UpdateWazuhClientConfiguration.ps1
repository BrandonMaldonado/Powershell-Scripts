# OSSEC CFG Path
$ossecpathcfg = 'C:\Program Files (x86)\ossec-agent\ossec.conf'

# IP Addresses
$newIP = '###.###.###.###'
$origProtocol = 'udp'
$newProtocol = 'tcp'

# Read file, change IP, and save
(Get-Content -path $ossecpathcfg -Raw) -replace "\d{1,}\.\d{1,}\.\d{1,}\.\d{1,}",$newIP | Set-Content -Path $ossecpathcfg

Start-Sleep -Seconds 2

# Read file, change IP, and save
(Get-Content -path $ossecpathcfg -Raw) -replace $origProtocol,$newProtocol | Set-Content -Path $ossecpathcfg

# Wait 5 seconds
Start-Sleep -Seconds 5

# Restart OSSEC Service
get-service -name OssecSvc | restart-service -force
