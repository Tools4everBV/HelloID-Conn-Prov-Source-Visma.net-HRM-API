########################################################################
# HelloID-Conn-Prov-Source-Visma.net-HRM-API-Persons
#
# Version: 3.1.0
########################################################################
#####################################################
$c = $configuration | ConvertFrom-Json

# Set debug logging - When set to true individual actions are logged - May cause lots of logging, so use with cause
switch ($($c.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$clientId = $c.ClientID
$clientSecret = $c.ClientSecret
$tenantId = $c.TenantID
$cutOffDays = $c.CutOffDays
$excludePersonsWithoutContractsInHelloID = $c.ExcludePersonsWithoutContractsInHelloID

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
        # Group by emailaddress (filter out employees without emailadress, otherwise incorrect matching will occur)
        $personsListGrouped = $employeesList | Where-Object { $_.businessemailaddress -ne $null } | Group-Object businessemailaddress -AsHashTable -AsString

        # Set default persons object with employees data
        $persons = $employeesList
    }

    Write-Information "Successfully queried employees. Result: $($employeesList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying employees. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query employee-user-defined-fields
try {
    Write-Verbose "Querying employee-user-defined-fields"

    $splatParams = @{
        'ExportJobName' = 'employee-user-defined-fields'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/employees/user-defined-field-histories"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/employees/user-defined-field-histories"
        'ResponseField' = "employeeUdfHistoryFileUris"
    }
    $personUserDefinedFieldsList = Invoke-VismaWebRequestList @splatParams

    if (($personUserDefinedFieldsList | Measure-Object).Count -gt 0) {
        # Group by employeeid
        $personUserDefinedFieldsListGrouped = $personUserDefinedFieldsList | Group-Object employeeid -AsHashTable -AsString
    }

    Write-Information "Successfully queried employee-user-defined-fields. Result: $($personUserDefinedFieldsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying employee-user-defined-fields. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query contracts
try {
    Write-Verbose "Querying contracts"

    $splatParams = @{
        'ExportJobName' = 'contracts'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/contracts?fields=!rosterid,ptfactor,scaletype_en,scaletype,scale,step,stepname,garscaletype,garstep,garstepname,catsscale,catsscalename,catsscaleid,catsrspfactor,salaryhour,garsalaryhour,salaryhourort,salaryhourtravel,salaryhourextra,salarytype,distance,maxdistance,dayspw"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/contracts"
        'ResponseField' = "contractFileUris"
    }
    $contractsList = Invoke-VismaWebRequestList @splatParams

    if (($contractsList | Measure-Object).Count -gt 0) {
        # Filter for valid contracts - only keep contracts that ended X days in the past at most
        $contractsList = $contractsList | Where-Object {
        ($_.Enddate -as [datetime] -ge (Get-Date).AddDays(-$cutOffDays) -or [string]::IsNullOrEmpty($_.Enddate))
        }

        # Group by employeeid
        $contractsListGrouped = $contractsList | Group-Object employeeid -AsHashTable -AsString
    }

    Write-Information "Successfully queried contracts. Filtered for contracts that ended '$cutOffDays' days in the past at most. Result: $($contractsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying contracts. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query contract-user-defined-fields
try {
    Write-Verbose "Querying contract-user-defined-fields"

    $splatParams = @{
        'ExportJobName' = 'contract-user-defined-fields'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/contracts/user-defined-field-histories"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/contracts/user-defined-field-histories"
        'ResponseField' = "contractUdfHistoryFileUris"
    }
    $contractUserDefinedFieldsList = Invoke-VismaWebRequestList @splatParams

    if (($contractUserDefinedFieldsList | Measure-Object).Count -gt 0) {
        # Add ExternalId property as linking key to contract, linking key is employeeid + "_" + contractid + "_" + subcontractid
        $contractUserDefinedFieldsList | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
        $contractUserDefinedFieldsList | Foreach-Object {
            $_.ExternalId = $_.employeeid + "_" + $_.contractid + "_" + $_.subcontractid
        }

        # Group by ExternalId
        $contractUserDefinedFieldsListGrouped = $contractUserDefinedFieldsList | Group-Object ExternalId -AsHashTable -AsString
    }

    Write-Information "Successfully queried contract-user-defined-fields. Result: $($contractUserDefinedFieldsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying contract-user-defined-fields. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query cost-centers
try {
    Write-Verbose "Querying cost-centers"

    $splatParams = @{
        'ExportJobName' = 'cost-centers'
        'RequestUri'    = "$Script:BaseUrl/v1/command/nl/hrm/metadata/cost-centers"
        'QueryUri'      = "$Script:BaseUrl/v1/query/nl/hrm/metadata/cost-centers"
        'ResponseField' = "costCentersFileUris"
    }
    $costCentersList = Invoke-VismaWebRequestList @splatParams

    if (($costCentersList | Measure-Object).Count -gt 0) {
        # Group by costcentername
        $costCentersListGrouped = $costCentersList | Group-Object costcentername -AsHashTable -AsString
    }

    Write-Information "Successfully queried cost-centers. Result: $($costCentersList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Error querying cost-centers. Error Message: $($errorMessage.AuditErrorMessage)"
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

        # Group by emailaddress (filter out users without emailadress, otherwise incorrect matching will occur)
        $usersListGroupedByEmailAddress = $usersList | Where-Object { $_.emailaddress -ne $null } | Group-Object emailaddress -AsHashTable -AsString
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
    Write-Verbose 'Enhancing and exporting person objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model
    $persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    $persons | ForEach-Object {
        # Set required fields for HelloID
        $_.ExternalId = $_.employeeId
        $_.DisplayName = "$($_.formattedname) ($($_.employeeId))"

        # Add User ID to the person, linking key is businessemailaddress
        if ($null -ne $usersListGroupedByEmailAddress -and $null -ne $_.businessemailaddress) {
            $user = $usersListGroupedByEmailAddress[$_.businessemailaddress]
            if ($null -ne $user.userid) {
                $_ | Add-Member -MemberType NoteProperty -Name "userId" -Value $user.userid -Force
            }
        }

        # Add User Defined Fields to the person, linking key is employeeId
        if ($null -ne $personUserDefinedFieldsListGrouped -and $null -ne $_.employeeId) {
            $employeeUserDefinedFields = $personUserDefinedFieldsListGrouped[$_.employeeId]
            if ($null -ne $employeeUserDefinedFields) {
                $_ | Add-Member -MemberType NoteProperty -Name "employeeUserDefinedFields" -Value $employeeUserDefinedFields -Force
            }
        }

        # Create contracts object
        # Get contract for person, linking key is employeeId
        $personContracts = $contractsListGrouped[$_.employeeId]

        $contractsList = [System.Collections.ArrayList]::new()
        if ($null -ne $personContracts) {
            foreach ($contract in $personContracts) {
                # Enhance contract with manager information, such as externalId
                if ($null -ne $usersListGroupedByUserId -and -NOT[string]::IsNullOrEmpty($contract.manageruserid)) {
                    $managerUser = $usersListGroupedByUserId[$contract.manageruserid]
                    if ($null -ne $personsListGrouped -and $null -ne $managerUser) {
                        if (-NOT[string]::IsNullOrEmpty($managerUser.emailaddress)) {
                            $managerEmployee = $personsListGrouped[$managerUser.emailaddress]
                            if ($null -ne $managerEmployee.employeeId) {
                                $contract | Add-Member -MemberType NoteProperty -Name "ManagerExternalId" -Value $managerEmployee.employeeId -Force
                            }
                            else {
                                if ($($c.IsDebug) -eq $true) {
                                    ### Be very careful when logging in a loop, only use this when the amount is below 100
                                    ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                                    Write-Warning "No employee found for manager with BusinessEmailAddress '$($managerUser.emailaddress)'"
                                }
                            }
                        }
                        else {
                            if ($($c.IsDebug) -eq $true) {
                                ### Be very careful when logging in a loop, only use this when the amount is below 100
                                ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                                Write-Warning "No BusinessEmailAddress found for manager user with UserId '$($contract.manageruserid)'"
                            }
                        }
                    }
                    else {
                        if ($($c.IsDebug) -eq $true) {
                            ### Be very careful when logging in a loop, only use this when the amount is below 100
                            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                            Write-Warning "No user found for manager with UserId '$($contract.manageruserid)'"
                        }
                    }
                }

                # Enhance contract with costcenter for extra information, such as: code
                if ($null -ne $costCentersListGrouped -and $null -ne $contract.costcenter) {
                    $costCenter = $costCentersListGrouped[$contract.costcenter]
                    if ($null -ne $costCenter) {
                        $contract | Add-Member -MemberType NoteProperty -Name "costcenterCode" -Value "$($costCenter.costcenter)" -Force
                    }
                }

                # Example: Add User Defined Fields to the contract, linking key is employeeid + "_" + contractid + "_" + subcontractid
                if ($null -ne $contractUserDefinedFieldsListGrouped -and $null -ne $contract.employeeId -and $null -ne $contract.contractid -and $null -ne $contract.subcontractid) {
                    $contractUserDefinedFields = $contractUserDefinedFieldsListGrouped[$contract.employeeid + "_" + $contract.contractid + "_" + $contract.subcontractid]
                    if ($null -ne $contractUserDefinedFields) {
                        $contract | Add-Member -MemberType NoteProperty -Name "contractUserDefinedFields" -Value $contractUserDefinedFields -Force
                    }
                }

                [Void]$contractsList.Add($contract)
            }
        }
        else {
            if ($($c.IsDebug) -eq $true) {
                ### Be very careful when logging in a loop, only use this when the amount is below 100
                ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                Write-Warning "No contracts found for person: $($_.ExternalId)"
            }
        }

        # Add Contracts to person
        if ($null -ne $contractsList) {
            # This example can be used by the consultant if you want to filter out persons with an empty array as contract
            # *** Please consult with the Tools4ever consultant before enabling this code. ***
            if ($contractsList.Count -eq 0 -and $true -eq $excludePersonsWithoutContractsInHelloID) {
                if ($($c.IsDebug) -eq $true) {
                    ### Be very careful when logging in a loop, only use this when the amount is below 100
                    ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                    Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
                }
                return
            }
            else {
                $_.Contracts = $contractsList
            }
        }
        elseif ($true -eq $excludePersonsWithoutContractsInHelloID) {
            if ($($c.IsDebug) -eq $true) {
                ### Be very careful when logging in a loop, only use this when the amount is below 100
                ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
            }
            return
        }

        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person

        # Updated counter to keep track of actual exported person objects
        $exportedPersons++
    }

    Write-Information "Succesfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    throw "Could not enhance and export person objects to HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}
