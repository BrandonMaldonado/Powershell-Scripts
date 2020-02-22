# Before Using
# Ensure AL_Agent is set to manual

# AL Personas Location
$ALPersonaRepository = '\\centralserver\ALPersonaRepository'
$ALLocalPersonaLocation = 'C:\Program Files (x86)\Common Files\AlertLogic'
$ALStageLoc = 'C:\ALstage'
$HostName = $env:COMPUTERNAME
$MyALPersona = $ALPersonaRepository + "\" + $HostName
$ALService = Get-Service -name al_agent
$DebugPreference = 'Continue'

function Start-PersonaCheck {
    [CmdletBinding()]

    param ()

    $MyPersonaExist = Test-Path -Path $Script:MyALPersona

    # Test if persona was found: Grab a copy Or Create a Persona
    if ($MyPersonaExist -eq $true) {
   
        Write-Debug 'Persona Found'

        # Stop AL Service
        if ($script:ALService.Status -eq 'Running') {
            $script:ALService | Stop-Service -Force | Out-Null
        }

        # Copy Persona to server
        Copy-Item -Path $($script:MyALPersona + "\*") -Recurse -Destination $script:ALLocalPersonaLocation -Force -WhatIf
   
        # Start AL Service
        $script:ALService | Start-Service -Force | Out-Null
        $script:ALService | Set-Service -StartupType Automatic
    }
    else {

        Write-Debug 'No Persona Found -- Creating One'

        $script:ALService | Start-Service -Force | Out-Null
        $script:ALService | Set-Service -StartupType Automatic

        # Create Persona Container
        New-Item -Path $script:MyALPersona -ItemType Directory

        # Copy Persona to Rep
        Copy-Item -Path $($script:ALLocalPersonaLocation + "\*") -Recurse -Destination $script:MyALPersona -Force -WhatIf

    }
   
}

# Detect if this server is a citrix gold image - if not run
if ($HostName -notlike '*-00') {
    Start-PersonaCheck
}
else {
    Write-Debug 'Golden Image Detected - exiting'
}
