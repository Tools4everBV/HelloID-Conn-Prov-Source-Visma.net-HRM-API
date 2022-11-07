########################################################################
# HelloID-Conn-Prov-Source-Visma.net-HRM-API-Persons
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
    [System.Collections.Generic.List[object]]$resultList = @()

    try {
        $exportData = @('employees', 'employee-udf', 'contracts', 'contract-udf', 'cost-centers', 'users')

        Write-Verbose 'Retrieving Visma AccessToken'
        $accessToken = Get-VismaOauthToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID

        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Authorization', "Bearer $($AccessToken.access_token)")

        $splatParams = @{
            CallBackUrl = $CallBackUrl
            Headers     = $headers
            WaitSeconds = $waitSeconds
        }

        switch ($exportData){
            'employees'{
                $splatParams['ExportJobName'] = 'employees'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/employees"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/employees"
                $employeeList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded employees: $($employeeList.count)"  -Verbose
            }

            'employee-udf'{
                $splatParams['ExportJobName'] = 'employee-user-defined-fields'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/employees/user-defined-field-histories"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/employees/user-defined-field-histories"
                $employeeUserDefinedFieldList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded employeeUserDefinedFields: $($employeeUserDefinedFieldList.count)" -Verbose
            }

            'contracts'{
                $splatParams['ExportJobName'] = 'contracts'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/contracts?fields=!rosterid,ptfactor,scaletype_en,scaletype,scale,step,stepname,garscaletype,garstep,garstepname,catsscale,catsscalename,catsscaleid,catsrspfactor,salaryhour,garsalaryhour,salaryhourort,salaryhourtravel,salaryhourextra,salarytype,distance,maxdistance,dayspw"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/contracts"
                $contractList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded contracts: $($contractList.count)" -Verbose
            }

            'contract-udf'{
                $splatParams['ExportJobName'] = 'contract-user-defined-fields'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/contracts/user-defined-field-histories"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/contracts/user-defined-field-histories"
                $contractUserDefinedFieldList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded contractUserDefinedFields: $($contractUserDefinedFieldList.count)" -Verbose
            }

            'cost-centers'{
                $splatParams['ExportJobName'] = 'cc'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/metadata/cost-centers"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/metadata/cost-centers"
                $costcenterList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded cc: $($costcenterList.count)" -Verbose
            }

            'users'{
                $splatParams['ExportJobName'] = 'users'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/users"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/users"
                $userList = Get-VismaExportData @splatParams | ConvertFrom-Csv
                Write-Verbose "Downloaded users: $($userList.count)" -Verbose
            }
        }

        $employeeList | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $null -force
        $employeeList | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $null -force
        $employeeList | Add-Member -MemberType NoteProperty -Name 'Contracts' -Value $null -force
        $employeeList | Add-Member -MemberType NoteProperty -Name 'employeeUserDefinedFields' -Value $null -force
        $employeeList | Add-Member -MemberType NoteProperty -Name 'uniqueID' -Value $null -force
        $employeeList | Add-Member -MemberType NoteProperty -Name 'userid' -Value $null -force

        $contractList | Add-Member -MemberType NoteProperty -Name 'ManagerId' -Value $null -force
        $contractList | Add-Member -MemberType NoteProperty -Name 'costcenterCode' -Value $null -force

        $lookupEmployeesEmail = $employeeList | Group-Object -Property businessemailaddress -AsHashTable
        $lookupContracts = $contractList | Group-Object -Property employeeid -AsHashTable
        $lookupUsersEmail = $userList | Group-object -Property emailaddress -AsHashTable
        $lookupUsersId = $userList | Group-object -Property userid -AsHashTable
        $lookEmployeeUserDefinedFields = $employeeUserDefinedFieldList | Group-Object -Property employeeid -AsHashTable
        #$lookContractUserDefinedFields = $contractUserDefinedFieldList | Group-Object -Property contractIdofZoiets... -AsHashTable
        $lookupCostcenters = $costcenterList | Group-Object -Property costcentername -AsHashTable

        foreach ($employee in $employeeList) {
            $employee.ExternalId = $employee.employeeId
            $employee.DisplayName = "$($employee.formattedname) ($($employee.employeeId))"
            $employee.employeeUserDefinedFields = $lookEmployeeUserDefinedFields[$employee.employeeId]

            if (-Not [string]::IsNullOrEmpty($employee.businessemailaddress)) {
                $employee.userId = $lookupUsersEmail[$($employee.businessemailaddress)].userid
            }

            $contractsEmployee = $lookupContracts[$employee.employeeId]
            [System.Collections.Generic.List[object]]$resultContractList = @()

            foreach ($contract in $contractsEmployee) {
                # Lookup manager
                # Manager lookup via UserID terug naar Employee ID. Moet via een omweg, de userid zit niet in de lookup dus kan hier pas worden herleid
                # Visma moet eigenlijk gewoon de userID meegeven op de employees, maar dit krijgen we (nog) niet voor elkaar bij ze
                if($contract.manageruserid -ne "") {
                    $managerObject = $lookupUsersId[$($contract.manageruserid)]
                    if ($managerObject.count -gt 0) {
                        if (-Not [string]::IsNullOrEmpty($managerObject.emailaddress)) {
                            $managerEmployeeRecord = $lookupEmployeesEmail[$managerObject.emailaddress]
                            if($null -ne $managerEmployeeRecord ) {
                                $contract.ManagerId = $managerEmployeeRecord.employeeId
                            } else {
                                Write-Verbose "[$($employee.DisplayName)] Employee record for manager with email [$($managerObject.emailaddress)] not found" -Verbose
                            }
                        } else {
                            Write-Verbose "[$($employee.DisplayName)] Email address for manager with userid [$($contract.manageruserid)] is empty" -Verbose
                        }
                   } else {
                        Write-Verbose "[$($employee.DisplayName)] Manager user with userid [$($contract.manageruserid)] is not found" -Verbose
                   }
                }
                $contract.costcenterCode = $lookupCostcenters[$contract.costcenter].costcenter

                #klant heeft geen custom contract velden
                #$contractFieldsInScope = $lookContractUserDefinedFields[$lookupValue)]

                $resultContractList.add($contract)
            }
            $employee.contracts = $resultContractList
            $resultList.add($employee)
        }
        Write-Verbose 'Importing raw data in HelloID'
        if (-not ($dryRun -eq $true)){
            Write-Verbose "[Full import] importing '$($resultList.count)' persons"  -Verbose
            Write-Output $resultList | ConvertTo-Json -Depth 10
        } else {
            Write-Verbose "[Preview] importing '$($resultList.count)' persons"
            Write-Output $resultList[1..10] | ConvertTo-Json -Depth 10
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            Write-Verbose "Line 253: Could not retrieve Visma employees. Error: $errorMessage" -Verbose
        } else {
            Write-Verbose "Line 255: Could not retrieve Visma employees. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)" -Verbose
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
            if ($responseUrl.employeeFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.employeeFileUris[0] -Method 'GET'
            }

            if ($responseUrl.usersFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.usersFileUris[0] -Method 'GET'
            }

            if ($responseUrl.contractFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.contractFileUris[0] -Method 'GET'
            }

            if ($responseUrl.costCentersFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.costCentersFileUris[0] -Method 'GET'
            }

            if ($responseUrl.employeeUdfHistoryFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.employeeUdfHistoryFileUris[0] -Method 'GET'
            }

            if ($responseUrl.contractUdfHistoryFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.contractUdfHistoryFileUris[0] -Method 'GET'
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
        $body += "scope=hrmanalytics%3Anlhrm%3Aexportemployees%20hrmanalytics%3Anlhrm%3Aexportcontracts%20hrmanalytics%3Anlhrm%3Aexportorganizationunits%20hrmanalytics%3Anlhrm%3Aexportmetadata%20hrmanalytics%3Anlhrm%3Aexportusers"
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