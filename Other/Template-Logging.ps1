<#
.SYNOPSIS
  <Script Name>

.DESCRIPTION
  <Brief description of script>

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
  <Inputs if any, otherwise state None>

.OUTPUTS
  <Outputs if any, otherwise state None>

.NOTES
  Version:        1.0
  Author:         <Name>
  Creation Date:  <Date>
  Purpose/Change: Initial script development

.EXAMPLE
  <Example explanation goes here>
  
  <Example goes here. Repeat this attribute for more than one example>
#>
<#
#Requires -RunAsAdministrator
#Requires -Version <N>[.<n>] 
#Requires –PSSnapin <PSSnapin-Name> [-Version <N>[.<n>]]
#Requires -Modules { <Module-Name> | <Hashtable> } 
#Requires –ShellId <ShellId>
#>
#region --------------------------------------------------[Script Parameters]------------------------------------------------------

Param (
  [switch]$verbose
  # Additiona Script parameters go here
  #	,[parameter(Mandatory=$true)]
  # [string]$string1
  # ,[parameter(Mandatory=$true)]
  # [string]$string2
)

#endregion -----------------------------------------------[Script Parameters]------------------------------------------------------
#region --------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
#$ErrorActionPreference = 'SilentlyContinue'

#Import Modules & Snap-ins
#endregion -----------------------------------------------[Initialisations]--------------------------------------------------------
#region --------------------------------------------------[Declarations]-----------------------------------------------------------

#Any Global Declarations go here
$maxlogfilesize = 5Mb
try {
  $Verbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
}
catch {}


#endregion -----------------------------------------------[Declarations]-----------------------------------------------------------
#region --------------------------------------------------[Functions]--------------------------------------------------------------

#region Logging: Functions used for Logging, do not edit!
Function Start-Log {
  [CmdletBinding()]
  param (
    [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
    [string]$FilePath
  )

  try {
    if (!(Test-Path $FilePath)) {
      ## Create the log file
      $filepath = (New-Item $FilePath -Type File).FullName
    }
    else {
      $FilePath = (Get-Item $FilePath).FullName
    }
  
    ## Set the global variable to be used as the FilePath for all subsequent Write-Log
    ## calls in this session
    $global:ScriptLogFilePath = $FilePath
  }
  catch {
    Write-Error $_.Exception.Message
  }
}

Function Write-Log {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Message,
  
    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [int]$LogLevel = 1
  )    
  $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
  $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
  
  if ($MyInvocation.ScriptName) {
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
  }
  else {
    #if the script havn't been saved yet and does not have a name this will state unknown.
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "Unknown", $LogLevel
  }
  $Line = $Line -f $LineFormat

  If ($Verbose) {
    switch ($LogLevel) {
      2 { $TextColor = "Yellow" }
      3 { $TextColor = "Red" }
      Default { $TextColor = "Gray" }
    }
    Write-Host -nonewline -f $TextColor "$Message`r`n" 
  }

  #Make sure the logfile do not exceed the $maxlogfilesize
  if (Test-Path $ScriptLogFilePath) { 
    if ((Get-Item $ScriptLogFilePath).length -ge $maxlogfilesize) {
      If (Test-Path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_") {
        Remove-Item -path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
      }
      Rename-Item -Path $ScriptLogFilePath -NewName "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
    }
  }

  $stream = [System.IO.StreamWriter]::new($ScriptLogFilePath, $true, ([System.Text.Utf8Encoding]::new()))
  $stream.WriteLine("$Line")
  $stream.close()

  # Remove above 3 lines with $stream and uncomment line below if you want to use Out-File instead of StreamWriter as log write metod
  # Out-File -InputObject $Line -FilePath $ScriptLogFilePath -Encoding UTF8 -Append 
}
#endregion

# Add functions Here


#endregion -----------------------------------------------[Functions]--------------------------------------------------------------
#region---------------------------------------------------[Execution]--------------------------------------------------------------
#Default logging to %temp%\scriptname.log, change if needed.
Start-Log -FilePath "$($env:TEMP)\$([io.path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)).log"
# Syntax is:
# Loglevel 1 is default and does not need to be specified
# Write-Log -Message "<message goes here>"
# Write-Log -Message "<message goes here>" -LogLevel 2

#Script Execution goes here
