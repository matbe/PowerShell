<#
.SYNOPSIS
  Functions for using Cim instance and methods with ConfigMgr

.DESCRIPTION
  Examples how to use Invoke-CimMethod with Configuration Manager to add or remove a direct collection member

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2023-04-02
  Purpose/Change: Initial script development

.EXAMPLE
    Gets a Computer object using Get-CimInstance
    $CMResource = Get-CMCimClient -CMServerFQDN CM01.corp.mblab.org -SiteCode PS1 -ComputerName "COMPUTER01"

.EXAMPLE
    Gets a Collection object using Get-CimInstance
    $CMCollection = Get-CMCimCollection -CMServerFQDN CM01.corp.mblab.org -SiteCode PS1 -CollectionID 'PS100015'

.EXAMPLE
    Adds a direct membership rule using Invoke-CimMethod
    Add-CMCimDirectMembershipRule -Collection $CMCollection -Resource $CMResource

.EXAMPLE
    Removes a direct membership rule using Invoke-CimMethod
    Remove-CMCimDirectMembershipRule -Collection $CMCollection -ResourceID $CMResource.ResourceId
#>

function Get-CMCimClient {
param (
    [Parameter(Mandatory = $true)]
    [string]$CMServerFQDN,
    [Parameter(Mandatory = $true)]
    [string]$SiteCode,
    [Parameter(Mandatory = $true)]
    [string]$ComputerName
)
    [array]$resource = Get-CimInstance -ComputerName $CMServerFQDN -Namespace "ROOT\SMS\Site_$SiteCode" -ClassName "SMS_R_System" -Filter "Name = '$ComputerName'"
    If ($resource) {
        If ($resource.Count -eq 1) {
            return $resource
        }
        else {
            Write-Error -Message "Multiple resources found matching name $client =  $($resource -join ",")" -LogLevel 3
            return $null
        }
    }
}

function Get-CMCimCollection {
param (
    [Parameter(Mandatory = $true)]
    [string]$CMServerFQDN,
    [Parameter(Mandatory = $true)]
    [string]$SiteCode,
    [Parameter(Mandatory = $true)]
    [string]$CollectionID
)

    $Collection = Get-CimInstance -ComputerName $CMServerFQDN -Namespace "ROOT\SMS\Site_$SiteCode" -ClassName "SMS_Collection" -Filter "CollectionID = '$CollectionID'"
    return $Collection
}


function Add-CMCimDirectMembershipRule {
param (
    $Collection,
    [Parameter(Mandatory = $true)]
    $Resource
)

$null = New-CimInstance -Namespace "ROOT\SMS\Site_PS1" -OutVariable collectionRule -ClassName SMS_CollectionRuleDirect -ClientOnly -Property @{
           ResourceClassName = [string]"SMS_R_System"
           RuleName          = [string]$Resource.Name
           ResourceID        = [uint32]$Resource.ResourceID
       }

    Invoke-CimMethod -InputObject $Collection -MethodName AddMemberShipRule -Arguments @{ CollectionRule = [CimInstance]$collectionRule[0] } -ErrorAction Stop

}

function Remove-CMCimDirectMembershipRule {
param (
    [Parameter(Mandatory = $true)]
    $Collection,
    [Parameter(Mandatory = $true)]
    [uint32]$ResourceID
)

    [ciminstance[]]$collRules = Get-CimInstance -InputObject $Collection | Select-Object -ExpandProperty  CollectionRules
    Foreach ($rule in $collRules) { 
        If ($rule.CimClass.CimClassName -eq  "SMS_CollectionRuleDirect") {
            If($rule.ResourceID -eq "16777225")
            {
                $params = @{ collectionRule = $rule }
                Invoke-CimMethod -InputObject $Collection -MethodName DeleteMembershipRule -Arguments $params -ErrorAction Stop
            }
        }
    }
}
