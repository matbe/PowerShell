
<#
.SYNOPSIS
  Set-IntuneDeviceManangementScriptAssignment.ps1

.DESCRIPTION
  Sets an assignment for a windows script in Intune via the Graph API

.PARAMETER ScriptID
  The Intune ID of the script that the assignment will be created for.

.PARAMETER GroupID
  The Azure ID of the group to be added.
  
.PARAMETER Tenant
  Specifies which tentant to use. <sometenant.onmicrosoft.com>

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2022-08-22
  Purpose/Change: Initial script development
 
.EXAMPLE
  Set-IntuneDeviceManangementScriptAssignment.ps1
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $True)] [string] $ScriptID = "",
    [Parameter(Mandatory = $True)] [string] $GroupID = "",
    [Parameter(Mandatory = $False)] [string] $Tenant = "" #<tenant>.onmicrosoft.com

)


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
    
    if (!$tenant) {
        $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
        $tenant = $userUpn.Host
    }

    Write-Host "Checking for AzureAD module..."
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    if ($null -eq $AadModule) {
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"

        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }
    
    if ($null -eq $AadModule) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red

        exit 1
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

            break
        }
    }
    catch {
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        Write-host $_.Exception.Message -LogLevel 3
        Write-host $_.Exception.ItemName -LogLevel 3
        break
    }
}

Function Update-AuthToken() {
    # Checking if authToken exists before running authentication
    if ($global:authToken) {
        # Setting DateTime to Universal time to work in all timezones
        $DateTime = (Get-Date).ToUniversalTime()
        # If the authToken exists checking when it expires
        $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes
        if ($TokenExpires -le 0) {
            write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow

            # Defining User Principal Name if not present
            if ($null -eq $script:User -or $script:User -eq "") {
                $script:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
                Write-host "Connecting using user: $($script:User)"

            }
            Write-host "Updating the authToken for the Graph API"
            $global:authToken = Get-AuthToken -User $User
        }
    }
    # Authentication doesn't exist, calling Get-AuthToken function
    else {
        if ($null -eq $script:User -or $script:User -eq "") {
            $script:User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
            Write-host "Connecting using user: $($script:User)"

        }
        # Getting the authorization token
        Write-host "Updating the authToken for the Graph API"
        $global:authToken = Get-AuthToken -User $script:User
    }
}
Update-AuthToken

# https://docs.microsoft.com/en-us/graph/api/intune-shared-devicemanagementscript-assign?view=graph-rest-beta

$assignmentsuri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$ScriptID/assignments"

$Respons = (Invoke-RestMethod -Uri $assignmentsuri -Headers $authToken -Method Get).value

$requestBody = @{
    deviceManagementScriptAssignments = @()
}
#Check if there already are assigned groups to the script
if ($Respons) {
    foreach ($group in $($Respons)) {
        # Get group assignment
        if ($group.target."@odata.type" -eq "#microsoft.graph.groupAssignmentTarget") {
            # Verify so the new groupID isn't already assigned.
            if ($group.target.groupId -ne $groupID) {
                $requestBody.deviceManagementScriptAssignments += @{
                    "target" = $group.target
                }
            }
            else {
                Write-Warning "A group with ID=$groupID is already assigned to '$ScriptID'"
            }
        }
    
        # Get exclusion group assignment
        if ($group.target."@odata.type" -eq "#microsoft.graph.exclusionGroupAssignmentTarget") {
            $requestBody.deviceManagementScriptAssignments += @{
                "target" = $group.target
            }
        } 
    }
}

$requestBody.deviceManagementScriptAssignments += @{
    "target" = @{
        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
        "groupId"     = "$groupID"
    }
}

$restore = $requestBody | ConvertTo-Json -Depth 99
$assignuri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$ScriptID/assign"
Invoke-RestMethod -Uri $assignuri -Headers $authToken -Method post -Body $restore -ContentType "application/json; charset=utf-8" 