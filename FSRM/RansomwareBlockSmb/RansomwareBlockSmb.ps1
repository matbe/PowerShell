<#
.SYNOPSIS
  RansomwareBlockSmb

.DESCRIPTION
  Script that runs when a custom command is triggered on a FSRM server. It will block the bad user on SMBShare Level

  The script requires PowerShell 4.0 or later to work.

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2017-05-03
  Purpose/Change: Initial script development

.EXAMPLE

#>

#region ---------------------------------------------------[Declarations]----------------------------------------------------------

#Any Global Declarations go here
$maxlogfilesize = 5Mb

#endregion
#region ---------------------------------------------------[Functions]------------------------------------------------------------

#region Logging: Functions used for Logging, do not edit!
Function Start-Log{
[CmdletBinding()]
    param (
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
	    [string]$FilePath
    )
	
    try
    {
        if (!(Test-Path $FilePath))
	    {
	        ## Create the log file
	        New-Item $FilePath -Type File | Out-Null
	    }
		
	    ## Set the global variable to be used as the FilePath for all subsequent Write-Log
	    ## calls in this session
	    $global:ScriptLogFilePath = $FilePath
    }
    catch
    {
        Write-Error $_.Exception.Message
    }
}

Function Write-Log{
param (
    [Parameter(Mandatory = $true)]
    [string]$Message,
		
    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [int]$LogLevel = 1
    )    
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    
    if($MyInvocation.ScriptName){
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
    }
    else { #if the script havn't been saved yet and does not have a name this will state unknown.
        $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "Unknown", $LogLevel
    }
    $Line = $Line -f $LineFormat

    #Make sure the logfile do not exceed the $maxlogfilesize
    if (Test-Path $ScriptLogFilePath) { 
        if((Get-Item $ScriptLogFilePath).length -ge $maxlogfilesize){
            If(Test-Path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_")
            {
                Remove-Item -path "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
            }
            Rename-Item -Path $ScriptLogFilePath -NewName "$($ScriptLogFilePath.Substring(0,$ScriptLogFilePath.Length-1))_" -Force
        }
    }

    Add-Content -Value $Line -Path $ScriptLogFilePath

}
#endregion

# Add functions Here


#endregion
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Default logging to %temp%\scriptname.log, change if needed.
Start-Log -FilePath "C:\RansomwareBlockSmb\RansomWareBlockSmbLog.log"
# Syntax is:
# Loglevel 1 is default and does not need to be specified
# Write-Log -Message "<message goes here>"
# Write-Log -Message "<message goes here>" -LogLevel 2

#Script Execution goes here
$shares = get-WmiObject -class Win32_Share |Where-Object {$_.Description -ne "Default Share" -and $_.Description -ne "Remote IPC"}
$events = Get-WinEvent -FilterHashtable @{logname='Application';providername='SRMSVC';StartTime=(get-date).AddMinutes(-2)}

foreach ($Event in $Events)
{
    $MsgArray = $Event.Message -split ";"
    $BadUser = $MsgArray[0]
    $BadFile = $MsgArray[1]
    $Rule = $MsgArray[2]
    
    #Match filepath against local share
    foreach($share in $shares){
        $sPath = [regex]::escape("$($share.Path)")
        if($BadFile -match $sPath)
        {
            $SharePart = $share.Name
        }
    }

    if ($Rule -match "Ransomware_Extensions")
    {
        try{
            Block-SmbShareAccess -Name $SharePart -AccountName $BadUser -Force
            }
            catch
            {
                Write-Log -Message $_.Exception.Message -LogLevel 3
            }
				                       
        Write-Log -Message "$BadUser;$SharePart;$BadFile"
                    

    }
    else{exit}
}