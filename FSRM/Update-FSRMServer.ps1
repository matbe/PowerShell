<#
.SYNOPSIS
  Update-FSRMServer

.DESCRIPTION
  Used for managing a server installed by New-FSRMServer.

.INPUTS
  None

.OUTPUTS
  None

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2017-05-24
  Purpose/Change: Initial script development

#>

#region ---------------------------------------------------[Declarations]----------------------------------------------------------

#Any Global Declarations go here
$maxlogfilesize = 5Mb

#Function Declarations
# Extensions that will block user access to the share
$ransompattern = @("*.wnry", "*.wcry", "*.wncry", "*.wncryt")

# Disk drives that will be excluded from File Screen
$diskexeptions= "C","T"

# General FSRM Settings
#-------------
$SMTPServer = "smtp.corp.SCCMTest.org"
$SMTPFrom = "noreply@corp.SCCMTest.org"
$AdminEmail = "helpdesk@corp.SCCMTest.org"
#-------------

# Event settings for the "Ransomware template
#-------------
$EventCommand = 'C:\Windows\System32\cmd.exe'
$EventCommandParam = '/c "C:\RansomwareBlockSmb\StartRansomwareBlockSmb.cmd"'
$EventCommandWorkDir = "C:\Windows\System32\"

$EventLogEntry = "[Source Io Owner];[Source File Path];[Violated File Group]"

$SMTPTo = "[Admin Email];[Source Io Owner Email]" 
$emailSubject = "Security Announcement from the IT-Department"
$emailBody = @"
Your account have been locked out. The reason is that you or someone in your name have tried to change a file extension to an extension identified as ransomware.

DO THE FOLLOWING!
1. Shut down your computer immediately
2. Have your logon name and computer name ready.
3. Contact Helpdesk immediately and inform them that you have received this message.

TECHNICAL INFORMATION FOR HELPDESK!
File: [Source File Path]
Server: [Server]
Username: [Source Io Owner]

/Your IT-Department
"@
#-------------

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

Function Update-FsrmFileGroup{
    try{
        Set-FsrmFileGroup -Name "Ransomware_Extensions" –IncludePattern $ransompattern -ErrorAction Stop |Out-Null
        Write-Log -Message "Updated Ransomware File Group"
        }
        catch
        {
            Write-Log -Message $_.Exception.Message -LogLevel 3
        }
}

Function Update-FsrmSetting{

    try{
        #set-FsrmFileGroup -name "Ransomware_Extensions" -IncludePattern @((Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined" -UseBasicParsing).content | convertfrom-json | % {$_.filters}) 
        set-FsrmSetting -AdminEmailAddress $AdminEmail -SmtpServer $SMTPServer -FromEmailAddress $SMTPFrom -ErrorAction Stop |Out-Null
        Write-Log -Message "Updated FSRM Settings to: AdminEmailAddress $AdminEmail, SmtpServer $SMTPServer, FromEmailAddress $SMTPFrom"
    }
    catch
    {
        Write-Log -Message $_.Exception.Message -LogLevel 3  
    }
 
}
    
Function Update-FsrmFileScreenTemplate{    
    #Create Notification types
    try{
        $global:emailnotification = New-FsrmAction -Type Email -Subject $emailSubject -Body $emailBody -RunLimitInterval 60 -MailTo $SMTPTo -ErrorAction Stop
        $global:eventnotification = New-FsrmAction -Type Event -Body $EventLogEntry -RunLimitInterval 0 -EventType Warning -ErrorAction Stop
        $global:commandnotification = New-FsrmAction -Type Command -Command $EventCommand -CommandParameters $EventCommandParam -SecurityLevel LocalSystem -RunLimitInterval 0 -WorkingDirectory $EventCommandWorkDir -ShouldLogError -KillTimeOut 0 -ErrorAction Stop
        Write-Log -Message "Updated notifications Successfully."
    }
    catch
    {
        Write-Log -Message $_.Exception.Message -LogLevel 3  
    }        
    
    # Add them to an array
    [Ciminstance[]]$notificationArray = $global:emailnotification,$global:eventnotification,$global:commandnotification

    #Create a new template
    try
    {
        Set-FsrmFileScreenTemplate -Name "Ransomware" -Description "Known Ransomware File Extesions" -IncludeGroup "Ransomware_Extensions" -Active: $true -Notification $notificationArray -UpdateDerived -ErrorAction Stop |Out-Null
        Write-Log -Message "Updateded FSRM Template Ransomware and all derived File Screens"
    }
    catch
    {
        Write-Log -Message $_.Exception.Message -LogLevel 3  
    }    
}    


#endregion
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Default logging to %temp%\scriptname.log, change if needed.
Start-Log -FilePath "C:\Update-FSRMServer.log"
# Syntax is:
# Loglevel 1 is default and does not need to be specified
# Write-Log -Message "<message goes here>"
# Write-Log -Message "<message goes here>" -LogLevel 2

#Script Execution goes here
Update-FsrmFileGroup
Update-FsrmSetting
Update-FsrmFileScreenTemplate
#Invoke-Command –ComputerName VANSRV532 –FilePath .\New-FSRMServer.ps1