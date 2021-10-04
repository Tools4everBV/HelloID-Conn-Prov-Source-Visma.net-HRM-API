########################################################################
# HelloID-Conn-Prov-Source-Raet-Visma-API-Departments
#
# Version: 1.0.0.0
########################################################################
$VerbosePreference = "Continue"

#region functions
function Get-VismaDepartmentData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [string]
        $CallBackUrl,

        [Parameter(Mandatory)]
        [string]
        $ClientID,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $TenantID
    )

    $waitSeconds = 4
    [System.Collections.Generic.List[object]]$resultList = @()

    try {
        Write-Verbose 'Retrieving Visma AccessToken'
        $accessToken = Get-VismaOauthToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object 'System.Collections.Generic.Dictionary[[String], [String]]'
        $headers.Add('Authorization', "Bearer $($AccessToken.access_token)")

        $splatParams = @{
            CallBackUrl   = $CallBackUrl
            ExportJobName = 'organizational-units'
            RequestUri    = "$BaseUrl/v1/command/nl/hrm/metadata/organization-units"
            QueryUri      = "$BaseUrl/v1/query/nl/hrm/metadata/organization-units"
            Headers       = $headers
            WaitSeconds   = $waitSeconds
        }
        $orgUnits = Get-VismaExportData @splatParams | ConvertFrom-Csv

        foreach ($orgUnit in $orgUnits){
            $orgUnit | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $orgUnit.orgunitid
            $orgUnit | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $orgUnit.orgname
        }

        Write-Verbose 'Importing raw data in HelloID'
        if (-not ($dryRun -eq $true)){
            Write-Verbose "[Full import] importing '$($orgUnits.count)' departments"
            Write-Output $orgUnits | ConvertTo-Json -Depth 10
        } else {
            Write-Verbose "[Preview] importing '$($orgUnits.count)' departments"
            Write-Output $orgUnits[1..2] | ConvertTo-Json -Depth 10
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            Write-Verbose "Could not retrieve Visma departments. Error: $errorMessage"
        } else {
            Write-Verbose "Could not retrieve Visma departments. Error: $($ex.Exception.Message)"
        }
    }
}

function Get-VismaExportData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $RequestUri,

        [Parameter(Mandatory)]
        [string]
        $QueryUri,

        [Parameter(Mandatory)]
        [string]
        $CallBackUrl,

        [Parameter(Mandatory)]
        [string]
        $ExportJobName,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[[String], [String]]]
        $Headers,

        [Parameter(Mandatory)]
        [int]
        $WaitSeconds
    )

    try {
        Write-Verbose " Requesting jobId for export '$ExportJobName'"
        $splatResponseJobParams = @{
            Method      = 'POST'
            Uri         = $RequestUri
            ContentType = 'application/json'
            Body        = @{ callbackAddress = $CallBackUrl } | ConvertTo-Json
            Headers     = $Headers
        }
        $responseJob = Invoke-RestMethod @splatResponseJobParams

        do {
            Write-Verbose "Checking if export for '$ExportJobName' is ready for download"
            $splatResponseUrlParams = @{
                Method  = 'GET'
                Uri     = "$QueryUri/$($responseJob.jobId)"
                Headers = $Headers
            }
            $responseUrl = Invoke-RestMethod @splatResponseUrlParams
            Start-Sleep -Seconds $WaitSeconds
        } while ($responseUrl.status -eq 'InProgress')

        if ($responseUrl.status -eq 'Completed'){
            Write-Verbose "Downloading '$ExportJobName' data"
            if ($responseUrl.organizationUnitsFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.organizationUnitsFileUris[0] -Method 'GET'
            }
        } else {
            throw "Could not download export data. Error: $($responseUrl.status)"
        }
        Write-Output $result
    } catch {
        $PScmdlet.ThrowTerminatingError($_)
    }
}

function Get-VismaOAuthtoken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $ClientID,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $TenantID
    )

    try {
        $body =  @( "grant_type=client_credentials")
        $body += "scope=hrmanalytics%3Anlhrm%3Aexportemployees%20hrmanalytics%3Anlhrm%3Aexportcontracts%20hrmanalytics%3Anlhrm%3Aexportorganizationunits%20hrmanalytics%3Anlhrm%3Aexportmetadata"
        $body += "client_id=$ClientID"
        $body += "client_secret=$ClientSecret"
        $body += "tenant_id=$TenantID"

        $splatParams = @{
            Uri     =  'https://connect.visma.com/connect/token'
            Method  = 'POST'
            Body    = $body -join '&'
            Headers = @{
                'content-type' = 'application/x-www-form-urlencoded'
            }
        }
        Invoke-RestMethod @splatParams
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

#region helpers
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj.ErrorMessage = $errorResponse
        }
        Write-Output $HttpErrorObj
    }
}
#endregion

$config = $Configuration | ConvertFrom-Json
$splatParams = @{
    BaseUrl      = $($config.BaseUrl)
    CallBackUrl  = $($config.CallBackUrl)
    ClientID     = $($config.ClientID)
    ClientSecret = $($config.ClientSecret)
    TenantID     = $($config.TenantID)
}
Get-VismaDepartmentData @splatParams
