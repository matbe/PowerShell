<#
.SYNOPSIS
  Get-EdgeEnterpriseMSI

.DESCRIPTION
  Imports all device configurations in a folder to a specified tenant

.PARAMETER Channel
  Channel to download, Valid Options are: Dev, Beta, Stable, EdgeUpdate, Policy.

.PARAMETER Platform
  Platform to download, Valid Options are: Windows or MacOS, if using channel "Policy" this should be set to "any"
  Defaults to Windows if not set.

.PARAMETER Architecture
  Architecture to download, Valid Options are: x86, x64, arm64, if using channel "Policy" this should be set to "any"
  Defaults to x64 if not set.

.PARAMETER Version
  If set the script will try and download a specific version. If not set it will download the latest.

.PARAMETER Folder
  Specifies the Download folder

.PARAMETER Force
  Overwrites the file without asking.

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2020-07-01
  Purpose/Change: Initial script development
  
  https://docs.microsoft.com/en-us/mem/configmgr/apps/deploy-use/deploy-edge

.EXAMPLE
  
  Download the latest version for the Beta channel and overwrite any existing file
  .\Get-EdgeEnterpriseMSI.ps1 -Channel Beta -Folder D:\SourceCode\PowerShell\Div -Force
  
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $True, HelpMessage = 'Channel to download, Valid Options are: Dev, Beta, Stable, EdgeUpdate, Policy')]
  [ValidateSet('Dev', 'Beta', 'Stable', 'EdgeUpdate', 'Policy')]
  [string]$Channel,    
  [Parameter(Mandatory = $True, HelpMessage = 'Folder where the file will be downloaded')]
  [ValidateNotNullOrEmpty()]
  [string]$Folder,
  [Parameter(Mandatory = $false, HelpMessage = 'Platform to download, Valid Options are: Windows or MacOS')]
  [ValidateSet('Windows', 'MacOS', 'any')]
  [string]$Platform = "Windows",
  [Parameter(Mandatory = $false, HelpMessage = "Architecture to download, Valid Options are: x86, x64, arm64, any")]
  [ValidateSet('x86', 'x64', 'arm64', 'any')]
  [string]$Architecture = "x64",
  [parameter(Mandatory = $false, HelpMessage = "Specifies which version to download")]
  [ValidateNotNullOrEmpty()]
  [string]$ProductVersion,
  [parameter(Mandatory = $false, HelpMessage = "Overwrites the file without asking")]
  [Switch]$Force
)

Write-Host "Getting available files from https://edgeupdates.microsoft.com/api/products?view=enterprise" -ForegroundColor Green
$response = Invoke-WebRequest -Uri "https://edgeupdates.microsoft.com/api/products?view=enterprise" -Method Get -ContentType "application/json" -ErrorAction Stop
$jsonObj = ConvertFrom-Json $([String]::new($response.Content))
Write-Host "Succefully retrived data" -ForegroundColor Green

# Alternative is to use Invoke-RestMethod to get a Json object directly
# $jsonObj = Invoke-RestMethod -Uri "https://edgeupdates.microsoft.com/api/products?view=enterprise"

$SelectedIndex = [array]::indexof($jsonObj.Product, "$Channel")

if ([string]::IsNullOrEmpty($ProductVersion)) {
  Write-host "No version specified, getting the latest for $Channel" -ForegroundColor Green
  $SelectedVersion = (([Version[]](($jsonObj[$SelectedIndex].Releases | Where-Object { $_.Architecture -eq $Architecture -and $_.Platform -eq $Platform }).ProductVersion) | Sort-Object -Descending)[0]).ToString(4)
  Write-Host "Latest Version for Chanel $Channel is $SelectedVersion" -ForegroundColor Green
  $SelectedObject = $jsonObj[$SelectedIndex].Releases | Where-Object { $_.Architecture -eq $Architecture -and $_.Platform -eq $Platform -and $_.ProductVersion -eq $SelectedVersion }
}
else {
  Write-Host "Matching $ProductVersion on Channel $Channel" -ForegroundColor Green
  $SelectedObject = ($jsonObj[$SelectedIndex].Releases | Where-Object { $_.Architecture -eq $Architecture -and $_.Platform -eq $Platform -and $_.ProductVersion -eq $ProductVersion })
  $SelectedObject
  If ($null -eq $SelectedObject) {
    Write-Host "No version matching $ProductVersion found using Channel $channel and Arch $Architecture!" -ForegroundColor Red
    break
  }
  else {
    Write-Host "Found matchings version" -ForegroundColor Green
    $SelectedObject
  }
}

$FileName = ($SelectedObject.Artifacts.Location -split "/")[-1]
Write-Host "File to be downloaded $FileName" -ForegroundColor Green
Write-host "Starting download of $($SelectedObject.Artifacts.Location)" -ForegroundColor Green
if (Test-Path $Folder) {
  if (Test-Path "$Folder\$FileName" -ErrorAction SilentlyContinue) {
    If ($Force) {
      Write-Host "Using Force and to Download and overwrite existing file." -ForegroundColor Green
      Invoke-WebRequest -Uri $SelectedObject.Artifacts.Location -OutFile "$Folder\$FileName" -ErrorAction Stop  
    }
    else {
      Write-Host "$Folder\$FileName already exists!" -ForegroundColor Yellow
      $OverWrite = Read-Host -Prompt "Press Y to overwrite or N to quit." 
      if ($OverWrite -eq "Y") {
        Write-Host "Starting Download" -ForegroundColor Green
        Invoke-WebRequest -Uri $SelectedObject.Artifacts.Location -OutFile "$Folder\$FileName" -ErrorAction Stop
      }
      else {
        Write-Host "User aborted, will not overwrite file." -ForegroundColor Red  
        break
      }
    }
  }
  else {
    Invoke-WebRequest -Uri $SelectedObject.Artifacts.Location -OutFile "$Folder\$FileName" -ErrorAction Stop
  }
  
}
else {
  Write-Host "Folder $Folder does not exist" -ForegroundColor Red
  break
}

if (((Get-FileHash -Algorithm $SelectedObject.Artifacts.HashAlgorithm -Path "$Folder\$FileName").Hash) -eq $SelectedObject.Artifacts.Hash) {
  Write-Host "CheckSum OK" -ForegroundColor Green
}
else {
  Write-host "Checksum mismatch!" -ForegroundColor Red
  Write-Host "Expected Hash        : $($SelectedObject.Artifacts.Hash)" -ForegroundColor Yellow
  Write-Host "Downloaded file Hash : $((Get-FileHash -Algorithm $SelectedObject.Artifacts.HashAlgorithm -Path "$Folder\$FileName").Hash)" -ForegroundColor Yellow
}
Write-Host " -- Completed --" -ForegroundColor Green