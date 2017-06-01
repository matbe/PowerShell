<#
.SYNOPSIS
  Function for reading CM logs in powershell

.DESCRIPTION
  <Brief description of script>

.PARAMETER path
  Sets one or more paths to load logfiles from

.PARAMETER LogLevel
    Sets the Minimum level for log level that will be displayed, default is everything.

.PARAMETER Gridview
    Opens the output in a gridview windows

.PARAMETER passthru
    Outputs the array directly without any formating for further use.

.INPUTS
  None

.OUTPUTS
  Array of logentries

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2017-05-04
  Purpose/Change: Initial script development

.EXAMPLE
    Gets all warnings and errors from multiple logfiles
    .\Read-CMLog.ps1 -path C:\Windows\CCM\logs\DcmWmiProvider.log,C:\Windows\CCM\logs\ccmexec.log -LogLevel Warning

.EXAMPLE
    Gets multiple logfiles and present in a GridView
    .\Read-CMLog.ps1 -path C:\Windows\CCM\logs\DcmWmiProvider.log,C:\Windows\CCM\logs\ccmexec.log -Gridview

#>
#Requires -RunAsAdministrator

#region --------------------------------------------------[Script Parameters]------------------------------------------------------
param (
    [Parameter(Mandatory = $true)]
    [array]$path,
		
    [Parameter()]
    [ValidateSet("Informational", "Warning", "Error")]
    [string]$LogLevel = "None",

    [Parameter()]
    [switch]$Gridview,

    [Parameter()]
    [switch]$passthru
    )  
#endregion

#region ---------------------------------------------------[Declarations]----------------------------------------------------------
#Create an Enum for the diffrent log levels
 Add-Type -TypeDefinition @"
    public enum LogType
    {
        None,
        Informational,
        Warning,
        Error
     }
"@
#endregion

#region ---------------------------------------------------[Functions]------------------------------------------------------------

Function Read-CMLogfile([array]$paths) {

    $result = $null
    $result = @()
    Foreach($path in $paths){
        $cmlogformat = $false
        $cmslimlogformat = $false
        # Use .Net function instead of Get-Content, much faster.
        $file = [System.io.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.StreamReader($file)
        [string]$LogFileRaw = $reader.ReadToEnd()
        $reader.Close()
        $file.Close()

        $pattern = "LOG\[(.*?)\]LOG(.*?)time(.*?)date"
        $patternslim = '\$\$\<(.*?)\>\<thread='
        
        if(([Regex]::Match($LogFileRaw, $pattern)).Success -eq $true){ $cmlogformat = $true}
        elseif(([Regex]::Match($LogFileRaw, $patternslim)).Success -eq $true){ $cmslimlogformat = $true}
        
        If($cmlogformat){
                
            # Split each Logentry into an array since each entry can span over multiple lines
            $logarray = $LogFileRaw -split "<!"

            foreach($logline in $logarray){
                
                If($logline){            
                    # split Log text and meta data values
                    $metadata = $logline -split "><"

                    # Clean up Log text by stripping the start and end of each entry
                    $logtext = ($metadata[0]).Substring(0,($metadata[0]).Length-6).Substring(5)
            
                    # Split metadata into an array
                    $metaarray = $metadata[1] -split '"'

                    # Rebuild the result into a custom PSObject
                    $result += $logtext |select-object @{Label="LogText";Expression={$logtext}}, @{Label="Type";Expression={[LogType]$metaarray[9]}},@{Label="Component";Expression={$metaarray[5]}},@{Label="DateTime";Expression={[datetime]::ParseExact($metaarray[3]+($metaarray[1]).Split("-")[0].ToString(), "MM-dd-yyyyHH:mm:ss.fff", $null)}},@{Label="Thread";Expression={$metaarray[11]}}
                }        
            }
        }

        If($cmslimlogformat){
       
        # Split each Logentry into an array since each entry can span over multiple lines
        $logarray = $LogFileRaw -split [System.Environment]::NewLine
              
        foreach($logline in $logarray){
            
            If($logline){  

                    # split Log text and meta data values
                    $metadata = $logline -split '\$\$<'

                    # Clean up Log text by stripping the start and end of each entry
                    $logtext = $metadata[0]
            
                    # Split metadata into an array
                    $metaarray = $metadata[1] -split '><'
                    If($logtext){
                        # Rebuild the result into a custom PSObject
                        $result += $logtext |select-object @{Label="LogText";Expression={$logtext}}, @{Label="Type";Expression={[LogType]0}},@{Label="Component";Expression={$metaarray[0]}},@{Label="DateTime";Expression={[datetime]::ParseExact(($metaarray[1]).Substring(0, ($metaarray[1]).Length - (($metaarray[1]).Length - ($metaarray[1]).LastIndexOf("-"))), "MM-dd-yyyy HH:mm:ss.fff", $null)}},@{Label="Thread";Expression={($metaarray[2] -split " ")[0].Substring(7)}}
                    }
                }
            }
        }
    }

    
    $result #return data
}
#endregion

#-----------------------------------------------------------[Execution]------------------------------------------------------------

If($Gridview){
    Read-CMLogfile -path $path |Where-Object {$_.Type -ge ([LogType]::($LogLevel).value__)} |Sort-Object DateTime | Out-GridView -Title "Powershell Logviewer by Mattias Benninge" -Wait
}
Elseif($passthru){
    Read-CMLogfile -path $path |Where-Object {$_.Type -ge ([LogType]::($LogLevel).value__)}
}
else {
    Read-CMLogfile -path $path |Where-Object {$_.Type -ge ([LogType]::($LogLevel).value__)} |Sort-Object DateTime |ft
}


