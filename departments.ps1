########################################################################
# HelloID-Conn-Prov-Source-Visma.net-HRM-API-Departments
#
# Version: 2.0.0.0
########################################################################

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Get-VismaData {
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

    try {
        $exportData = @(  'organizational-units','employees','users')
        Write-Verbose 'Retrieving Visma AccessToken'
        $accessToken = Get-VismaOauthToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID

        #Write-Verbose 'Adding Authorization headers'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Authorization', "Bearer $($AccessToken.access_token)")

        $splatParams = @{
            CallBackUrl = $CallBackUrl
            Headers     = $headers
            WaitSeconds = $waitSeconds
        }
        switch ($exportData){
            'organizational-units'{
                $splatParams['ExportJobName'] = 'organizational-units'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/metadata/organization-units"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/metadata/organization-units"
                $organizationalUnitList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded organizational-units: $($organizationalUnitList.count)" -Verbose
            }

            'employees'{
                $splatParams['ExportJobName'] = 'employees'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/employees"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/employees"
                $employeeList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded employees: $($employeeList.count)" -Verbose
            }

            'users'{
                $splatParams['ExportJobName'] = 'users'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/users"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/users"
                $userList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded users: $($userList.count)" -Verbose
            }
        }

        $organizationalUnitList | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $null -force
        $organizationalUnitList | Add-Member -MemberType NoteProperty -Name 'Name' -Value $null -force
        $organizationalUnitList | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $null -force
        $organizationalUnitList | Add-Member -MemberType NoteProperty -Name 'ManagerExternalId' -Value $null -force

        $lookupUsersId = $userList | Group-object -Property userid -AsHashTable
        $lookupEmployeesEmail = $employeeList | Group-Object -Property businessemailaddress -AsHashTable

        foreach ($organizationalUnit in $organizationalUnitList){
            $organizationalUnit.ExternalId = $organizationalUnit.orgunitid
            $organizationalUnit.Name = $organizationalUnit.orgname
            $organizationalUnit.DisplayName = $organizationalUnit.orgname

            if (-Not [string]::IsNullOrEmpty($organizationalUnit.manageruserid)) {
                $managerObject = $lookupUsersId[$($organizationalUnit.manageruserid)]
                if ($managerObject.count -gt 0) {
                    if (-Not [string]::IsNullOrEmpty($managerObject.emailaddress)) {
                        $managerEmployeeRecord = $lookupEmployeesEmail[$managerObject.emailaddress]
                        if($null -ne $managerEmployeeRecord ) {
                            $organizationalUnit.ManagerExternalId = $managerEmployeeRecord.employeeId
                        } else {
                            Write-Verbose "[$($organizationalUnit.ExternalId)] Employee record for manager with email [$($managerObject.emailaddress)] not found" -Verbose
                        }
                    } else {
                        Write-Verbose "[$($organizationalUnit.ExternalId)] Email address for manager with userid [$($organizationalUnit.manageruserid)] is empty" -Verbose
                    }
                } else {
                    Write-Verbose "[$($organizationalUnit.ExternalId)] User record for manager with userid [$($organizationalUnit.ManagerExternalId)] not found" -Verbose
                }
            } else {
                Write-Verbose "[$($organizationalUnit.ExternalId)] No manager configured" -Verbose
            }
        } # foreach
        Write-Verbose 'Importing raw data in HelloID'
        if (-not ($dryRun -eq $true)){
            Write-Verbose "[Full import] importing '$($organizationalUnitList.count)' departments"
            Write-Output $organizationalUnitList | ConvertTo-Json -Depth 10
        } else {
            Write-Verbose "[Preview] importing '$($organizationalUnitList.count)' departments"
            Write-Output $organizationalUnitList[1..10] | ConvertTo-Json -Depth 10
        }
    } catch {
        $ex = $PSItem

        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            Write-Verbose "Could not retrieve Visma departments. Error: $errorMessage" -Verbose
        } else {
            Write-Verbose "Could not retrieve Visma departments. Error: $($ex.Exception.Message)" -Verbose
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
        Write-Verbose "Requesting jobId for export '$ExportJobName'"

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

            if ($responseUrl.employeeFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.employeeFileUris[0] -Method 'GET'
            }

            if ($responseUrl.usersFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.usersFileUris[0] -Method 'GET'
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
        $body += "scope=hrmanalytics%3Anlhrm%3Aexportemployees%20hrmanalytics%3Anlhrm%3Aexportorganizationunits%20hrmanalytics%3Anlhrm%3Aexportmetadata%20hrmanalytics%3Anlhrm%3Aexportusers"
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
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
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
Get-VismaData @splatParams