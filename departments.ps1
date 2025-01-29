########################################################################
# HelloID-Conn-Prov-Source-Visma.net-HRM-API-Departments
#
# Version: 3.3.0
########################################################################
$c = $configuration | ConvertFrom-Json

# Set debug logging - When set to true individual actions are logged - May cause lots of logging, so use with cause
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId

$Script:AuthenticationUrl = "https://connect.visma.com/connect/token"
$Script:Scope = @(
    'hrmanalytics:nlhrm:exportemployees'
    , 'hrmanalytics:nlhrm:exportcontracts'
    , 'hrmanalytics:nlhrm:exportorganizationunits'
    , 'hrmanalytics:nlhrm:exportmetadata'
    , 'hrmanalytics:nlhrm:exportusers'
)
# Optional, include personal data like private mailaddress
if ($c.IncludePersonalData -eq $true) {
    $Script:Scope += 'hrmanalytics:nlhrm:exportcontactinformation'
}
$Script:BaseUrl = "https://api.analytics1.hrm.visma.net"
$Script:CallBackUrl = "https://api.analytics1.hrm.visma.net"

#region functions
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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}

function New-VismaSession {
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

    #Check if the current token is still valid
    $accessTokenValid = Confirm-AccessTokenIsValid
    if ($true -eq $accessTokenValid) {
        return
    }

    try {
        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

        $authorisationBody = @(
            "grant_type=client_credentials"
            , "client_id=$($ClientId)"
            , "client_secret=$($ClientSecret)" 
            , "tenant_id=$($TenantId)"
            , "scope=$([uri]::EscapeDataString($Script:Scope -join ' '))"
        ) -join '&' # Needs to be a single string

        $splatAccessTokenParams = @{
            Uri             = $Script:AuthenticationUrl
            Headers         = @{
                'Cache-Control' = "no-cache"
            }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorisationBody
            UseBasicParsing = $true
        }
        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false

        if ($null -eq $result.access_token) {
            throw $result
        }

        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)

        $Script:AuthenticationHeaders = @{
            'Authorization' = "Bearer $($result.access_token)"
        }

        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

        throw "Error creating Access Token at uri ''$($splatAccessTokenParams.Uri)'. Please check credentials. Error Message: $($errorMessage.AuditErrorMessage)"
    }
}

function Confirm-AccessTokenIsValid {
    if ($null -ne $Script:expirationTimeAccessToken) {
        if ((Get-Date) -le $Script:expirationTimeAccessToken) {
            return $true
        }
    }
    return $false
}

function Invoke-VismaWebRequestList {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]
        $RequestUri,

        [parameter(Mandatory = $true)]
        [string]
        $QueryUri,

        [parameter(Mandatory = $true)]
        [string]
        $ExportJobName,

        [parameter(Mandatory = $true)]
        [string]
        $ResponseField
    )
    # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

    $checkDelay = 4000 # Wait for 4 seconds before checking again when the data is not yet available for download
    $triesCounter = 0
    do {
        try {
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($true -ne $accessTokenValid) {
                New-VismaSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }

            $retry = $false

            Write-Verbose "Starting export for '$ExportJobName'"
            $splatStartExportJobParams = @{
                Uri             = $RequestUri
                Headers         = $Script:AuthenticationHeaders
                Method          = 'POST'
                ContentType     = 'application/json'
                Body            = @{ callbackAddress = $Script:CallBackUrl } | ConvertTo-Json
                UseBasicParsing = $true
            }
            $responseStartExportJob = Invoke-RestMethod @splatStartExportJobParams -Verbose:$false

            Do {
                Write-Verbose "Checking if export job with id '$($responseStartExportJob.jobId)' for '$ExportJobName' is ready for download"
                $splatCheckExportParams = @{
                    Uri             = "$QueryUri/$($responseStartExportJob.jobId)"
                    Headers         = $Script:AuthenticationHeaders
                    Method          = 'GET'
                    UseBasicParsing = $true
                }
                $responseCheckExport = Invoke-RestMethod @splatCheckExportParams -Verbose:$false
                Start-Sleep -Milliseconds $checkDelay
            } While ($responseCheckExport.status -eq 'InProgress')

            if ($responseCheckExport.status -eq 'Completed') {
                $splatGetDataParams = @{
                    Uri             = "$($responseCheckExport.$ResponseField[0])" # Since there can be multiple we always select the first
                    Method          = 'GET'
                    UseBasicParsing = $true
                }

                Write-Verbose "Querying data from '$($splatGetDataParams.Uri)'"

                $result = (Invoke-RestMethod @splatGetDataParams -Verbose:$false) | ConvertFrom-Csv -Delimiter ','
                [System.Collections.ArrayList]$ReturnValue = $result
            }
            else {
                throw "Could not download export data. Error: $($responseUrl.status)"
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex

            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

            $maxTries = 3
            if ( ($($errorMessage.AuditErrorMessage) -Like "*Too Many Requests*" -or $($errorMessage.AuditErrorMessage) -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 601 # Wait for 0,601 seconds
                Write-Warning "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $($errorMessage.AuditErrorMessage). Trying again in '$delay' milliseconds for a maximum of '$maxTries' tries."
                Start-Sleep -Milliseconds $delay
            }
            else {
                $retry = $false
                throw "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $($errorMessage.AuditErrorMessage)"
            }
        }
    }while ($retry -eq $true)

    Write-Verbose "Successfully queried data from '$($splatGetDataParams.Uri)'. Result count: $($ReturnValue.Count)"

    return $ReturnValue
}
#endregion functions

# Query organizational-units
try {
    Write-Verbose "Querying organizational-units"

    $splatParams = @{
        'ExportJobName' = 'organizational-units'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/metadata/organization-units"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/metadata/organization-units"
        'ResponseField' = "organizationUnitsFileUris"
    }
    $organizationalUnitsListApi = Invoke-VismaWebRequestList @splatParams
    $today = (Get-Date).Date
    $organizationalUnitsList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($organizationalUnit in $organizationalUnitsListApi) {
        if ([string]::IsNullOrEmpty($organizationalUnit.startdate)) {
            $startDate = [datetime]"1900-01-01"
        }
        else {
            $startDate = [datetime]$organizationalUnit.startdate
        }

        if ([string]::IsNullOrEmpty($organizationalUnit.enddate)) {
            $endDate = [datetime]"2900-01-01"
        }
        else {
            $endDate = [datetime]$organizationalUnit.enddate
        }

        if ($startDate -le $today -and $endDate -ge $today) {
            $organizationalUnitsList.Add($organizationalUnit)
        }
    }
    Write-Information "Successfully queried organizational-units. Result: $($organizationalUnitsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying organizational-units. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query employees
try {
    Write-Verbose "Querying employees"

    $splatParams = @{
        'ExportJobName' = 'employees'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/employees"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/employees"
        'ResponseField' = "employeeFileUris"
    }
    $employeesList = Invoke-VismaWebRequestList @splatParams

    # Make sure persons are unique
    $employeesList = $employeesList | Sort-Object employeeid -Unique

    if (($employeesList | Measure-Object).Count -gt 0) {
        # Group by EmployeeID (filter out employees without employeeid, otherwise incorrect matching will occur)
        $personsListGrouped = $employeesList | Where-Object { $_.employeeid -ne $null } | Group-Object employeeid  -AsHashTable -AsString
    }

    Write-Information "Successfully queried employees. Result: $($employeesList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying employees. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query users
try {
    Write-Verbose "Querying users"

    $splatParams = @{
        'ExportJobName' = 'users'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/users"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/users"
        'ResponseField' = "usersFileUris"
    }
    $usersList = Invoke-VismaWebRequestList @splatParams

    if (($usersList | Measure-Object).Count -gt 0) {
        # Group by userid
        $usersListGroupedByUserId = $usersList | Group-Object userid -AsHashTable -AsString
    }

    Write-Information "Successfully queried users. Result: $($usersList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying users. Error Message: $($errorMessage.AuditErrorMessage)"
}

try {
    Write-Verbose 'Enhancing and exporting department objects to HelloID'

    # Set counter to keep track of actual exported department objects
    $exportedDepartments = 0

    foreach ($organizationalUnit in $organizationalUnitsList) {
        # Enhance department with manager information, such as externalId
        if ($null -ne $usersListGroupedByUserId -and -not[string]::IsNullOrEmpty($organizationalUnit.manageruserid)) {
            $managerUser = $usersListGroupedByUserId[$organizationalUnit.manageruserid]
            if ($null -ne $personsListGrouped -and $null -ne $managerUser) {
                if (-NOT[string]::IsNullOrEmpty($managerUser.employeeid)) {
                    $managerEmployee = $personsListGrouped[$managerUser.employeeid]
                    if ($null -ne $managerEmployee.employeeId -and $managerEmployee.Count -eq 1) {
                        $organizationalUnit | Add-Member -MemberType NoteProperty -Name "ManagerExternalId" -Value $managerEmployee.employeeId -Force
                    }
                    else {
                        if ($($c.isDebug) -eq $true) {
                            ### Be very careful when logging in a loop, only use this when the amount is below 100
                            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                            if ($null -eq $managerEmployee.employeeId) {
                                Write-Warning "[OU: $($organizationalUnit.orgunitid)-$($organizationalUnit.orgname)] No employee record found for manager with employeeid [$($managerUser.employeeid)]"
                            }
                            if ($managerEmployee.Count -gt 1) {
                                Write-Warning "[OU: $($organizationalUnit.orgunitid)-$($organizationalUnit.orgname)] Multiple [$($managerEmployee.Count)] employee records [$($managerEmployee.employeeId)] found for manager with employeeid [$($managerUser.employeeid)]"
                            }
                        }
                    }
                }
                else {
                    if ($($c.isDebug) -eq $true) {
                        ### Be very careful when logging in a loop, only use this when the amount is below 100
                        ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                        Write-Warning "No manager found because employeeid is empty for UserId '$($contract.manageruserid)'"
                    }
                }
            }
            else {
                if ($($c.isDebug) -eq $true) {
                    ### Be very careful when logging in a loop, only use this when the amount is below 100
                    ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                    Write-Warning "No user found for manager with UserId '$($organizationalUnit.manageruserid)'"
                }
            }
        }

        $department = [PSCustomObject]@{
            ExternalId        = $organizationalUnit.orgunitid
            DisplayName       = $organizationalUnit.orgname
            ManagerExternalId = $organizationalUnit.ManagerExternalId
            ParentExternalId  = $organizationalUnit.orgunitparentid
        }

        # Sanitize and export the json
        $department = $department | ConvertTo-Json -Depth 10
        $department = $department.Replace("._", "__")

        Write-Output $department

        # Updated counter to keep track of actual exported department objects
        $exportedDepartments++
    }

    Write-Information "Succesfully enhanced and exported department objects to HelloID. Result count: $($exportedDepartments)"
    Write-Information "Department import completed"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Could not enhance and export department objects to HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}