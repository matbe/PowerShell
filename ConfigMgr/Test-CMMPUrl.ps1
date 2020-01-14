Function Test-CMMPUrl {
    <#
.SYNOPSIS
  Tests urls on CM Management points

.DESCRIPTION
  This script will test if the urls "/sms_mp/.sms_aut?mpcert" and "/sms_mp/.sms_aut?mpcert" are responding correctly on a CM Management Point.

.PARAMETER FQDN
  Fully Qualified Domain Name for the MECM MP server

.PARAMETER  Detail
    Gives a more detailed output using the custom "Webresponse" class

.PARAMETER Timeout
    Specifies the Timeout paramater for the Invoke-webrequest command

.PARAMETER HTTPS
    Switch specifying that HTTPS connection should be tested

.PARAMETER Thumbprint
    Mandatory paramter if "HTTPS" is used.
    Specifies the thumbprint of the certificate that should be used to make the connection. Usually the computer certificate.
    Use "Get-ChildItem -Path cert:\LocalMachine\My\" to find the correct thumbprint.

.INPUTS
  None

.OUTPUTS
  Default output is true or false.
  If using the -Details switch it outputs the custom "Webresponse" class instead of true/false

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2020-01-10
  Purpose/Change: Initial script development
  Based on a script made by Jeff Hicks, https://www.petri.com/testing-uris-urls-powershell

.EXAMPLE
    $thumbprint = (Get-ChildItem -Path cert:\LocalMachine\My\)[0].ThumbPrint

    Test-CMMPURL -FQDN "<FQDNForMP>","<FQDNForMP2>" -Detail -HTTPS -Thumbprint $thumbprint

#>
    [CmdletBinding(DefaultParametersetName = 'Default')] 
    Param(
        [Parameter(Position = 0, Mandatory, HelpMessage = "Enter the FQDN of the MP server/servers",
            ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern( "(.)" )][string[]]$FQDN,
        [Parameter(Position = 1)][Switch]$Detail,
        [Parameter(Position = 2)][ValidateScript( { $_ -ge 0 })][int]$Timeout = 30,
        [Parameter(ParameterSetName = 'PKI', Mandatory = $false)][switch]$HTTPS,      
        [Parameter(ParameterSetName = 'PKI', Mandatory = $true)][string]$Thumbprint
    )
     
    Begin {
        Write-Verbose -Message "Starting $($MyInvocation.Mycommand)" 
        Write-Verbose -message "Using parameter set $($PSCmdlet.ParameterSetName)"
        Class WebResponse {
            [string]$ResponseUri
            [int]$ContentLength 
            [string]$ContentType
            [DateTime]$LastModified 
            [int]$Status 
        }

        $returnobject = @() #create array for return object
		
		# Make sure Invoke-Webrequest use TLS 1.2 otherwise the script will fail on 2019 servers or servers that require TLS1.2 communication
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		
    } #close begin block
     
    Process {
        Foreach ($Computer in $FQDN) {
         
            $urlsToTest = @()
            $urlsToTest += "://$Computer/sms_mp/.sms_aut?mpcert"
            $urlsToTest += "://$Computer/sms_mp/.sms_aut?mplist"

            Foreach ($url in $urlsToTest) {
                Write-Verbose -Message "Testing $Computer"

                If ($HTTPS) {
                    $url = "https" + $url
                }
                else {
                    $url = "http" + $url
                }
                Try {
                
                    if ($HTTPS) { 
                        $url = "https" + $url
                        #hash table of parameter values for Invoke-Webrequest
                        $paramHash = @{
                            UseBasicParsing  = $True
                            DisableKeepAlive = $True
                            Uri              = $url
                            Method           = 'Get'
                            ErrorAction      = 'stop'
                            TimeoutSec       = $Timeout
                            Certificate      = Get-ChildItem -Path "cert:\LocalMachine\My\$($thumbprint)"
                        }
                    }
                    else {
                        $url = "http" + $url
                        #hash table of parameter values for Invoke-Webrequest
                        $paramHash = @{
                            UseBasicParsing  = $True
                            DisableKeepAlive = $True
                            Uri              = $url
                            Method           = 'Get'
                            ErrorAction      = 'stop'
                            TimeoutSec       = $Timeout
                        }
                    }
     
                    $test = Invoke-WebRequest @paramHash
     
                    if ($Detail) {
                        # $objProp = $test.BaseResponse | Select-Object ResponseURI,ContentLength,ContentType,LastModified, @{Name="Status";Expression={$Test.StatusCode}}
                        $returnobject += New-Object WebResponse -Property @{
                            ResponseUri   = $test.BaseResponse.ResponseURI
                            ContentLength = $test.BaseResponse.ContentLength
                            ContentType   = $test.BaseResponse.ContentType
                            LastModified  = $test.BaseResponse.LastModified
                            Status        = $Test.StatusCode
                        }
                    } #if $detail
                    else {
                        if ($test.statuscode -ne 200) {
                            #it is unlikely this code will ever run but just in case
                            Write-Verbose "Statuscode response = $test.Status"
                            Write-Verbose -Message "Failed to request $uri"
                            write-Verbose -message ($test | out-string)
                            $False
                        }
                        else {
                            Write-Verbose "Statuscode response = $($test.StatusCode)"
                            $True
                        }
                    } #else quiet
         
                }
                Catch {
                    #there was an exception getting the URI
                    write-verbose -message $_.exception
                    if ($Detail) {
                        #most likely the resource is 404
                        $returnobject += New-Object WebResponse -Property @{
                            ResponseUri   = $url
                            ContentLength = 0
                            ContentType   = $null
                            LastModified  = 0
                            Status        = 404
                        }
                        #write a matching custom object to the pipeline
                        New-Object -TypeName psobject -Property $objProp

                    } #if $detail
                    else {
                        $False
                    }
                } #close Catch block
            }
        }
    } #close Process block
     
    End {
        $returnobject 
        Write-Verbose -Message "Ending $($MyInvocation.Mycommand)"
    } #close end block
     
} #close Test-CMMPUrl Function