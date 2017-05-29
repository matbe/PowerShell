
$ScriptSourcePath = "\\servername\FSRM\RansomwareBlockSmb"
[array]$servers = "<FSRMServer1>","<FSRMServer2>"

foreach($server in $servers)
{
    try
    {
        Copy-Item $ScriptSourcePath "\\$server\c$" -recurse -Force
        Write-Host "RansomwareBlockSmb folder copied to \\$server\c$\"
    }
    catch
    {
        Write-Host $_.Exception.Message
    }
 }