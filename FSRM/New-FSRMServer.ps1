<#
.SYNOPSIS
  New-FSRMServer

.DESCRIPTION
  Install and configures the FSRM role and activates File Screen on a Windows Server

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
[array]$diskexeptions= "C","T"

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

Function Get-MyModule { 
	Param([string]$name)
 
	if(-not(Get-Module -name $name)) 
		{ 
		if(Get-Module -ListAvailable | 
			Where-Object { $_.name -eq $name }) 
			{ 
				Import-Module -Name $name 
				$true 
			} #end if module available then import 
		else { $false } #module not available 
		} # end if not module 
	else { $true } #module already loaded 
} #end function get-MyModule 
	

Function New-FSRMServer{

    $OSVersion = (Get-CimInstance Win32_OperatingSystem).Version -split "\."
    Write-Log -Message "OS Version = $((Get-CimInstance Win32_OperatingSystem).Version)"
    If([Int]("{0:N1}" -f [Int]($OSVersion[0]+"."+$OSVersion[1])) -ge 6.2){
        $FeatureOutput = Install-WindowsFeature –Name FS-Resource-Manager –IncludeManagementTools
        Write-Log -Message "FS-Resource-Manager installed, Success=$($FeatureOutput.Success) and with Exit Code=$($FeatureOutput.ExitCode)" -LogLevel 1
    }
    elseif([Int]("{0:N1}" -f [Int]($OSVersion[0]+"."+$OSVersion[1])) -le 5.9)
    {
        Write-Log -Message "OS Version not supportet for FSRM, Exiting!!" -LogLevel 3
        exit
    }
    else
    {
        Get-MyModule "ServerManager"
        If(!((Get-WindowsFeature | Where-Object {$_.Name -eq "FS-FileServer"}).Installed)){Add-WindowsFeature FS-FileServer}
        If(!((Get-WindowsFeature | Where-Object {$_.Name -eq "FS-Resource-Manager"}).Installed)){Add-WindowsFeature FS-Resource-Manager}
        Write-Log -Message "FS-Resource-Manager installed"
    }

    try{
        New-FsrmFileGroup -Name "Ransomware_Extensions" –IncludePattern $ransompattern -ErrorAction Stop |Out-Null
        Write-Log -Message "Created Ransomware File Group"
        }
        catch
        {
            Write-Log -Message $_.Exception.Message -LogLevel 3
        }

    try{
        set-fsrmSetting -AdminEmailAddress $AdminEmail -SmtpServer $SMTPServer -FromEmailAddress $SMTPFrom -ErrorAction Stop |Out-Null
        Write-Log -Message "Changed FSRM Settings to: AdminEmailAddress $AdminEmail, SmtpServer $SMTPServer, FromEmailAddress $SMTPFrom"
    }
    catch
    {
        Write-Log -Message $_.Exception.Message -LogLevel 3  
    }
    #set-FsrmFileGroup -name "Ransomware_Extensions" -IncludePattern @((Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined" -UseBasicParsing).content | convertfrom-json | % {$_.filters}) 

    #Create Notification types
    try{
        $global:emailnotification = New-FsrmAction -Type Email -Subject $emailSubject -Body $emailBody -RunLimitInterval 60 -MailTo $SMTPTo -ErrorAction Stop
        $global:eventnotification = New-FsrmAction -Type Event -Body $EventLogEntry -RunLimitInterval 0 -EventType Warning -ErrorAction Stop
        $global:commandnotification = New-FsrmAction -Type Command -Command $EventCommand -CommandParameters $EventCommandParam -SecurityLevel LocalSystem -RunLimitInterval 0 -WorkingDirectory $EventCommandWorkDir -ShouldLogError -KillTimeOut 0 -ErrorAction Stop
        Write-Log -Message "Created notifications Successfully."
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
        new-FsrmFileScreenTemplate -Name "Ransomware" -Description "Known Ransomware File Extesions" -IncludeGroup "Ransomware_Extensions" -Active: $true -Notification $notificationArray -ErrorAction Stop |Out-Null
        Write-Log -Message "Created new FSRM Template Ransomware"
    }
    catch
    {
        Write-Log -Message $_.Exception.Message -LogLevel 3  
    }    
    
    Write-Log -Message "Setting diskexeptions to: $diskexeptions File Screen will not be active on these volumes"
    
    [string[]]$diskLetters = (Get-Volume |Where-Object {$_.DriveType -eq "Fixed"}).DriveLetter
    $diskLetters = $diskLetters | ? {$_ -ne ""}
    [array]$activeLetters = Compare-Object -ReferenceObject $diskLetters  -DifferenceObject $diskexeptions -PassThru | Where-Object {$_.SideIndicator -eq '<='}
    
    Write-Log -Message "File Screen will be activated on these Drives: $activeLetters"

    
    foreach($al in $activeLetters)
    {
        if($al){
            try{
                New-FsrmFileScreen -Active -Template "Ransomware" -Path "$($al):\" -ErrorAction Stop |out-null
                Write-Log -Message "File Screen 'Ransomware' was created on drive $($al):\"
            }
            catch
            {
                Write-Log -Message $_.Exception.Message -LogLevel 3  
            }   
        }
    }
}

#endregion
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Default logging to %temp%\scriptname.log, change if needed.
Start-Log -FilePath "C:\New-FSRMServer.log"
# Syntax is:
# Loglevel 1 is default and does not need to be specified
# Write-Log -Message "<message goes here>"
# Write-Log -Message "<message goes here>" -LogLevel 2

#Script Execution goes here
New-FSRMServer
#Invoke-Command –ComputerName VANSRV532 –FilePath .\New-FSRMServer.ps1