<#
.SYNOPSIS
  Import-IntuneDeviceConfigurationFromJSON

.DESCRIPTION
  Imports all device configurations in a folder to a specified tenant

.PARAMETER Output
  If set to TRUE the it will create a csv file with autopilot info for manual import in intune.

.PARAMETER GroupTag
  If set to TRUE the grouptags will be read from GroupTags.txt and the selected tag will be imported into intune.
  
.PARAMETER Tenant
  Specifies which tentant to use. <sometenant.onmicrosoft.com>

.PARAMETER RestartOnSucess
  Automatically restarts the computer once the import have been imported sucessfully.

.PARAMETER Force
  Skip confirmation to import into tenant.


.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2020-01-07
  Purpose/Change: Initial script development
  Credits to Michael Niehaus for parts that gets and creates the hardware hash for AutoPilot. https://www.powershellgallery.com/packages/Get-WindowsAutoPilotInfo/1.6 created by Michael Niehaus. 

.EXAMPLE
  Assign-AutoPilotDevice.ps1 
  
#>
#region --------------------------------------------------[Script Parameters]------------------------------------------------------
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)] [switch] $Output = $true, 
    [Parameter(Mandatory = $False)] [switch] $GroupTag = $true, 
    [Parameter(Mandatory = $False)] [string] $Tenant = "<tenant>.onmicrosoft.com",
    [Parameter(Mandatory = $False)] [switch] $RestartOnSucess = $true,
    [Parameter(Mandatory = $False)] [switch] $Force = $false
)

$script:Tenant = $Tenant
#endregion --------------------------------------------------[Script Parameters]------------------------------------------------------
#region ---------------------------------------------------[Declarations]----------------------------------------------------------

#Any Global Declarations go here
$script:graphApiVersion = "Beta"

try {
    import-Module ".\AzureAD"
}
catch { }

While ($null -eq (Get-Module -Name "AzureAD")) {
    $path = Read-Host "Enter path to AzureAD module, eg D:\AzureAD"
    if (!(Test-Path $path)) {
        Write-host "$path not found"
    }
    else {
        import-Module $path
    }
}

#endregion ---------------------------------------------------[Declarations]----------------------------------------------------------
#region ---------------------------------------------------[Functions]------------------------------------------------------------

function Get-AuthToken {
    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $User
    )
    
     #$tenant = $userUpn.Host
    Write-Host "Checking for AzureAD module..."
    $AadModule = Get-Module -Name "AzureAD"
    
    if ($null -eq $AadModule) {
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }
    
    if ($null -eq $AadModule) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }
    
    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    if ($AadModule.count -gt 1) {
        $Latest_Version = ($AadModule | Select-Object version | Sort-Object)[-1]
        $aadModule = $AadModule | Where-Object { $_.version -eq $Latest_Version.version }
        # Checking if there are multiple versions of the same module found
    
        if ($AadModule.count -gt 1) {
            $aadModule = $AadModule | Select-Object -Unique
        }
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }
    else {
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$script:Tenant"
    
    try {
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
        # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
        $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
        $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
        $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result
        # If the accesstoken is valid then create the authentication header
        if ($authResult.AccessToken) {
            # Creating header for Authorization token
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = "Bearer " + $authResult.AccessToken
                'ExpiresOn'     = $authResult.ExpiresOn
            }
            return $authHeader
        }
        else {
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
        }
    }
    catch {
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    }
}

Function Get-AutoPilotImportedDevice() {
    <# 
    .SYNOPSIS 
    Gets information about devices being imported into Windows Autopilot. 
     
    .DESCRIPTION 
    The Get-AutoPilotImportedDevice cmdlet retrieves either the full list of devices being imported into Windows Autopilot for the current Azure AD tenant, or information for a specific device if the ID of the device is specified. Once the import is complete, the information instance is expected to be deleted. 
    
    .PARAMETER id 
    Optionally specifies the ID (GUID) for a specific Windows Autopilot device being imported. 
     
    .EXAMPLE 
    Get a list of all devices being imported into Windows Autopilot for the current Azure AD tenant. 
     
    Get-AutoPilotImportedDevice 
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] $id
    )
    
    # Defining Variables
    $DCP_resource = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    
    if ($id) {
        $uri = "https://graph.microsoft.com/$($script:graphApiVersion)/$DCP_resource/$id"
    }
    else {
        $uri = "https://graph.microsoft.com/$($script:graphApiVersion)/$DCP_resource"
    }
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get
        if ($id) {
            $response
        }
        else {
            $devices = $response.value
        
            $devicesNextLink = $response."@odata.nextLink"
        
            while ($null -ne $devicesNextLink) {
                $devicesResponse = (Invoke-RestMethod -Uri $devicesNextLink -Headers $authToken -Method Get)
                $devicesNextLink = $devicesResponse."@odata.nextLink"
                $devices += $devicesResponse.value
            }
        
            $devices
        }
    }
    catch {
    
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
    
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    
        break
    }
    
}

Function Get-AutoPilotDevice() {
    <# 
        .SYNOPSIS 
        Gets devices currently registered with Windows Autopilot. 
         
        .DESCRIPTION 
        The Get-AutoPilotDevice cmdlet retrieves either the full list of devices registered with Windows Autopilot for the current Azure AD tenant, or a specific device if the ID of the device is specified. 
         
        .PARAMETER id 
        Optionally specifies the ID (GUID) for a specific Windows Autopilot device (which is typically returned after importing a new device) 
         
        .EXAMPLE 
        Get a list of all devices registered with Windows Autopilot 
         
        Get-AutoPilotDevice 
        #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] $id
    )
            
    # Defining Variables
    $DCP_resource = "deviceManagement/windowsAutopilotDeviceIdentities"
            
    if ($id) {
        $uri = "https://graph.microsoft.com/$($script:graphApiVersion)/$DCP_resource/$id" + '?$expand=deploymentProfile'
    }
    else {
        $uri = "https://graph.microsoft.com/$($script:graphApiVersion)/$DCP_resource"
    }
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get
        if ($id) {
            $response
        }
        else {
            $devices = $response.value
        
            $devicesNextLink = $response."@odata.nextLink"
            
            while ($null -ne $devicesNextLink) {
                $devicesResponse = (Invoke-RestMethod -Uri $devicesNextLink -Headers $authToken -Method Get)
                $devicesNextLink = $devicesResponse."@odata.nextLink"
                $devices += $devicesResponse.value
            }
            
            $devices
        }
    }
    catch {
            
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
            
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            
        break
    }
            
}

Function Add-AutoPilotDevice() {
    <#
.SYNOPSIS
This function is used to add an device configuration policy using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a device configuration policy
.EXAMPLE
Add-DeviceConfigurationPolicy -JSON $JSON
Adds a device configuration policy in Intune
.NOTES
NAME: Add-DeviceConfigurationPolicy
#>
    [cmdletbinding()]
    param
    (
        $JSON
    )
    $DCP_resource = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    Write-Verbose "Resource: $DCP_resource"
    $response = ""

    try {
        if ($JSON -eq "" -or $null -eq $JSON) {
            write-host "No JSON specified, please specify valid JSON for the Device Configuration Policy..." -f Red
        }
        else {
            Test-JSON -JSON $JSON
            $uri = "https://graph.microsoft.com/$script:graphApiVersion/$($DCP_resource)"
            $response = Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $JSON -ContentType "application/json; charset=utf-8" 
        }
    }
    catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        write-host
        break
    }
    return $response
}
    
####################################################
    
Function Test-JSON() {
    <#
    .SYNOPSIS
    This function is used to test if the JSON passed to a REST Post request is valid
    .DESCRIPTION
    The function tests if the JSON passed to the REST Post is valid
    .EXAMPLE
    Test-JSON -JSON $JSON
    Test if the JSON is valid before calling the Graph REST interface
    .NOTES
    NAME: Test-AuthHeader
    #>
    param (
        $JSON
    )
    
    try {
        $TestJSON = ConvertFrom-Json $JSON -ErrorAction Stop
        $validJson = $true
    }
    catch {
        $validJson = $false
        $_.Exception
    }
    
    if (!$validJson) {
        Write-Host "Provided JSON isn't in valid JSON format" -f Red
        break
    }
}

function Show-Menu {
    <#
    .SYNOPSIS
    Creates a commandline menu
    .DESCRIPTION
    Creates a commandline menu
    .EXAMPLE
    Show-Menu -Title "My Title"

    #>
    param (
        [string]$Title = ""
    )
    Clear-Host
    Write-Host "================ $Title ================"

    for ($i = 0; $i -lt $grouptagselection.Count; $i++) {
        Write-Host "$i`: $($grouptagselection[$i].Keys)"
    }
    Write-Host "Q: Press 'Q' to quit."
}

#endregion ---------------------------------------------------[Functions]------------------------------------------------------------

#-----------------------------------------------------------[Execution]------------------------------------------------------------
If ($GroupTag) {

    $grouptagselection = (Get-Content .\GroupTags.txt) | Sort-Object
    $grouptagselection = $grouptagselection.Where( { $_ -ne "" })
    $grouptagselection = $grouptagselection | ConvertFrom-StringData

    do {
        Show-Menu -Title GroupTag
        $selection = Read-Host "Please make a selection"
   
        If ($selection -ge 0 -and $selection -lt $grouptagselection.Count) {
           
            $script:GroupTagSelected = (($grouptagselection[[int]($selection)]).Values | Out-String).Trim()
        }
        Elseif ($selection -eq "q") {
            Write-host "Quiting script." -ForegroundColor Red
            pause
            exit
        }
        Else {
            Write-host "Not a valid selection, try again." -ForegroundColor Red
            pause
        }
   
    }
    until ($selection -eq 'q' -or ($selection -ge 0 -and $selection -lt $grouptagselection.Count))
}
else {
	$script:GroupTagSelected = ""
}

#region AutoPilot
# This part is from https://www.powershellgallery.com/packages/Get-WindowsAutoPilotInfo/1.6 created by Michael Niehaus. 

$computers = @()
$session = New-CimSession

# Get the common properties.
Write-Verbose "Checking $comp"
$serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber

# Get the hash (if available)
$devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
if ($devDetail -and (-not $Force)) {
    $hash = $devDetail.DeviceHardwareData
}
else {
    $bad = $true
    $hash = ""
}

# If the hash isn't available, get the make and model
if ($bad -or $Force) {
    $cs = Get-CimInstance -CimSession $session -Class Win32_ComputerSystem
    $make = $cs.Manufacturer.Trim()
    $model = $cs.Model.Trim()
    if ($Partner) {
        $bad = $false
    }
}
else {
    $make = ""
    $model = ""
}

# Getting the PKID is generally problematic for anyone other than OEMs, so let's skip it here
$product = ""

# Create a pipeline object
$c = New-Object psobject -Property @{
    "Device Serial Number" = $serial
    "Windows Product ID"   = $product
    "Hardware Hash"        = $hash
    "Group Tag"            = $script:GroupTagSelected
}

# Write the object to the pipeline or array
if ($bad) {
    # Report an error when the hash isn't available
    Write-Error -Message "Unable to retrieve device hardware data (hash) from computer $comp" -Category DeviceError
    exit
}
else {
    $computers += $c
}

Remove-CimSession $session

if ($Output) {
    $filename = $computers[0]."Device Serial Number"
    $computers | Select-Object "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag" | ConvertTo-CSV -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File "AP-$($filename).csv"
}

$AutopilotDevice = [ordered]@{
    '@odata.type'               = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
    'orderIdentifier'           = if ($($computers[0]."Group Tag")) { "$($computers[0]."Group Tag".ToString())" } else { "" }
    'serialNumber'              = $computers[0]."Device Serial Number"
    'productKey'                = $computers[0]."Windows Product ID" 
    'hardwareIdentifier'        = $computers[0]."Hardware Hash"
    'assignedUserPrincipalName' = "" #if ($UserPrincipalName) { "$($UserPrincipalName)" } else { "" }
    'state'                     = @{
        '@odata.type'          = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
        'deviceImportStatus'   = 'pending'
        'deviceRegistrationId' = ''
        'deviceErrorCode'      = 0
        'deviceErrorName'      = ''
    }
}

$AutopilotDeviceJSON = $AutopilotDevice | ConvertTo-Json
#endregion AutoPilot

If ($script:Tenant -eq "") {
    $script:Tenant = Read-Host -Prompt "Please specify Tenant to connect to."
}

Write-Host "Trying to connect to $script:Tenant, do you want to continue? Y or N?" -ForegroundColor Yellow
        
$Confirm = read-host
if ($Confirm -eq "y" -or $Confirm -eq "Y") {
    Write-Host "Connecting to $script:Tenant.."
    Write-Host    
}
else {
    Write-Host "Aborting..." -ForegroundColor Red
    Write-Host
    break
}

#region Authentication
# Checking if authToken exists before running authentication
if ($global:authToken) {
    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()
    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes
    if ($TokenExpires -le 0) {
        write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
        write-host
        # Defining User Principal Name if not present
        if ($null -eq $User -or $User -eq "") {
            $User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
            Write-Host
        }
        $global:authToken = Get-AuthToken -User $User
    }
}
# Authentication doesn't exist, calling Get-AuthToken function
else {
    if ($null -eq $User -or $User -eq "") {
        $User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
        Write-Host
    }
    # Getting the authorization token
    $global:authToken = Get-AuthToken -User $User
}
#endregion Authentication

Write-host "Importing device and waiting until import is complete"
$newdevice = Add-AutoPilotDevice($AutopilotDeviceJSON)

Write-Progress -Activity "Waiting for Device import.. " -Completed
$i = 1
Do {
    If ($i -lt 100) {
        write-progress -Activity "Waiting for Device import.. " -PercentComplete $i
    }
    else {
        $i = 1
    }
    $i++
    start-sleep -seconds 5
    if ((Get-AutoPilotImportedDevice($($newdevice.ID))).state.deviceImportStatus -eq "failed") {
        Write-Error "Import failed!"
        exit
    }
}
Until((Get-AutoPilotImportedDevice($($newdevice.ID))).state.deviceImportStatus -eq "complete")
Write-Progress -Activity "Waiting for Device import.. " -Completed

$intunedeviceID = (Get-AutoPilotImportedDevice($($newdevice.ID))).state.deviceRegistrationId

Write-Host "Device $($computers[0]."Device Serial Number") imported with ID=$intunedeviceID"
Write-Host "Waiting 20 seconds for device to be available"
Start-Sleep -Seconds 20
Write-host "Waiting for device to be assigned , can take a long time so grab a coffee.. (max wait 15 min)"

$starttime = Get-date
$waitvalues = "unknown", "pending", "notAssigned", "", $null
write-host "Time is now $starttime"

$i = 1
while ((New-TimeSpan -Start $starttime -End (get-date)).Minutes -lt 15) {

    $device = Get-AutoPilotDevice($intunedeviceID)
    if (!($device.deploymentProfileAssignmentStatus -in $waitvalues)) {
        break
    }

    If ($i -lt 100) {
        write-progress -Activity "Waiting for Device assignment ($($device.deploymentProfileAssignmentStatus)).. $((New-TimeSpan -Start $starttime -End (get-date)).Minutes) Minutes have passed.." -PercentComplete $i
    }
    else {
        $i = 1
    }
    $i++
    start-sleep -seconds 10
}
Write-Progress -Activity "Waiting for Device assignment" -Completed

if ((New-TimeSpan -Start $starttime -End (get-date)).Minutes -ge 15) {
    Write-host "This took longer than expected, , check the Intune console for more information" -ForegroundColor Red
    exit 1
}

$device = Get-AutoPilotDevice($intunedeviceID)
Write-Host "$($device.deploymentProfileAssignmentStatus) : $($device.deploymentProfileAssignedDateTime)"

If ((Get-AutoPilotDevice($intunedeviceID)).deploymentProfileAssignmentStatus -eq "unknown" -or (Get-AutoPilotDevice($intunedeviceID)).deploymentProfileAssignmentStatus -eq "failed") {
    Write-Warning "Something went wrong, check the Intune console for more information"
}
else {
    write-host "Triggers a manual Windows Autopilot enrollment sync"
    $uri = 'https://graph.microsoft.com/Beta/deviceManagement/windowsAutopilotSettings/sync'
    Invoke-RestMethod -Uri $uri -Headers $authToken -Method POST |Out-Null
    write-host "Complete! Device imported and assigned to $($computers[0]."Group Tag".ToString()), serial number:"
    write-host $computers[0]."Device Serial Number"
    write-host "This Computer will reboot in 5 minutes, press Ctrl+C to abort!" -ForegroundColor Green
    Start-Sleep -Seconds 300
    If ($RestartOnSucess) { Restart-Computer -Force }
}
  
