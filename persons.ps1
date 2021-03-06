########################################################################
# HelloID-Conn-Prov-Source-Visma.net-HRM-API-Persons
#
# Version: 1.0.0.1
########################################################################
$VerbosePreference = "Continue"

#region functions
function Get-VismaEmployeeData {
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
        $TenantID,

        [Parameter(Mandatory)]
        [string]
        $CutOffDays
    )

    $waitSeconds = 4
    [System.Collections.Generic.List[object]]$resultList = @()

    try {
        $exportData = @('employees', 'employee-udf', 'contracts', 'contract-udf')

        Write-Verbose 'Retrieving Visma AccessToken'
        $accessToken = Get-VismaOauthToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object 'System.Collections.Generic.Dictionary[[String], [String]]'
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
                $employees = Get-VismaExportData @splatParams | ConvertFrom-Csv
            }

            'employee-udf'{
                $splatParams['ExportJobName'] = 'employee-user-defined-fields'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/employees/user-defined-field-histories"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/employees/user-defined-field-histories"
                $employeeUserDefinedFields = Get-VismaExportData @splatParams | ConvertFrom-Csv
            }

            'contracts'{
                $splatParams['ExportJobName'] = 'contracts'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/contracts?fields=!rosterid,ptfactor,scaletype_en,scaletype,scale,step,stepname,garscaletype,garstep,garstepname,catsscale,catsscalename,catsscaleid,catsrspfactor,salaryhour,garsalaryhour,salaryhourort,salaryhourtravel,salaryhourextra,salarytype,distance,maxdistance,dayspw,tariffid,tariffname_en,tariffname,publictransportregid,publictransportregname_en,publictransportregname,publictransportunits"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/contracts"
                $contracts = Get-VismaExportData @splatParams | ConvertFrom-Csv

            }

            'contract-udf'{
                $splatParams['ExportJobName'] = 'contract-user-defined-fields'
                $splatParams['RequestUri'] = "$BaseUrl/v1/command/nl/hrm/contracts/user-defined-field-histories"
                $splatParams['QueryUri'] = "$BaseUrl/v1/query/nl/hrm/contracts/user-defined-field-histories"
                $contractUserDefinedFields = Get-VismaExportData @splatParams | ConvertFrom-Csv
            }
        }

        $lookupEmployees = $employees | Group-Object -Property employeeid -AsHashTable
        $lookupContracts = $contracts | Group-Object -Property employeeid -AsHashTable
        $lookEmployeeUserDefinedFields = $employeeUserDefinedFields | Group-Object -Property employeeid -AsHashTable
        $lookContractUserDefinedFields = $contractUserDefinedFields | Group-Object -Property employeeid -AsHashTable

        $cutoffDate = (get-date).AddDays(-$CutOffDays)
        $uniqueIDs = @()

        $EmployeeUniqueID = $employeeUserDefinedFields | Where-Object { $_.fieldname -eq 'UniqueID'}
        
        foreach ($UniqueID in $EmployeeUniqueID){
            $employeeIDs = @()

            $AllEmployeeIDsFromPerson = $employeeUserDefinedFields | Where-Object { $_.value -eq $uniqueID.value}
            foreach ($SpecificUniqueID in $AllEmployeeIDsFromPerson){
                $employeeIDs = $employeeIDs + $($SpecificUniqueID.employeeid)
            }
            $employeeIDs = $employeeIDs | sort-object -Descending  
            
            if ($employeeIDs.count -gt 1){
                $employeelookupvalue = $employeeIDs[0]
            } else {
                $employeelookupvalue = $employeeIDs
            }
            

            $employee = $lookupEmployees[$employeelookupvalue]
            $employee | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $UniqueID.value -force
            $employee | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $employee.formattedname -force

            $EmployeeUDFList = [system.collections.generic.list[object]]::new()
            foreach ($employeeID in $employeeIDs){
                $EmployeeFieldsInScope = $lookEmployeeUserDefinedFields[$employeeID]
                $EmployeeUDFList.add($EmployeeFieldsInScope)
            }

            $employee | Add-Member -MemberType NoteProperty -Name 'Employee-UDF' -Value $EmployeeUDFList -force
            $employee = $employee[0]

            $ContractList = [system.collections.generic.list[object]]::new()
            foreach ($employeeID in $employeeIDs){
                $contractInScope = $lookupContracts[$employeeID]
                $ContractList.add($contractInScope)
            }

            
            if ($ContractList.count -ge 1){
                $employee | Add-Member @{ Contracts = [System.Collections.ArrayList]@() } -force
                Foreach($contract in $ContractList){
                    $contract = $contract[0]
                    $em = $contract.Enddate

                    $ActiveCalc = $false
                    if($em -ne ""){ [datetime]$dt = $contract.Enddate } else {write-verbose -verbose $em}
                    if($dt -gt $cutoffDate -or $em -eq ""){ $ActiveCalc = $true}
                    $contractexternalid = $contract.employeeid + "-" + $contract.contractid + "-" + $contract.subcontractid

                    $contract | Add-Member -MemberType NoteProperty -Name 'ActiveCalc' -Value $ActiveCalc -force
                    $contract | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $contractexternalid -force

                    $contractFieldsInScope = $lookContractUserDefinedFields[$($contract.employeeid)]
                    
                   ## Custom -> Location name in SubContractDepartment - Might come in handy for location attributes (For example: TOPdesk Branch)
                    $Location = ""
                    if ($contractFieldsInScope){
                        foreach ($field in $contractFieldsInScope){
                            if($field.entityname -eq "SubContractDepartment"){
                                if($field.fieldtypeid -eq "1"){
                                    $Location = $field.listname
                                }
                            }    
                        }
                    } 

                   $contract | Add-Member -MemberType NoteProperty -Name 'LocationName' -Value $Location -force
                   ##

                   if ($contractFieldsInScope){
                    $contract | Add-Member -MemberType NoteProperty -Name 'Contract-UDF' -Value $contractFieldsInScope -force
                   } 
                    
                   if($contract.ActiveCalc -eq $true){
                        $employee.Contracts.Add($contract) | Out-Null
                    }

                    if($uniqueIDs -notcontains $($employee.externalID)){
                        if($employee.externalid.length -ne 1){
                                if($employee.Contracts.count -gt 0){
                                    $resultList.add($employee)
                                    $uniqueIDs = $uniqueIDs + $($employee.ExternalId)                            
                                }
                            }
                        } else {
                        write-verbose -verbose "Persoon $($employee.displayName) al verwerkt met eerder UniqueID"
                    }
                } 
            } 
        

        }        

        Write-Verbose 'Importing raw data in HelloID'
        if (-not ($dryRun -eq $true)){
            Write-Verbose "[Full import] importing '$($resultList.count)' persons"
            Write-Output $resultList | ConvertTo-Json -Depth 10
        } else {
            Write-Verbose "[Preview] importing '$($resultList.count)' persons"
            Write-Output $resultList[1..2] | ConvertTo-Json -Depth 10
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            Write-Verbose "Could not retrieve Visma employees. Error: $errorMessage"
        } else {
            Write-Verbose "Could not retrieve Visma employees. Error: $($ex.Exception.Message)"
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
            if ($responseUrl.employeeFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.employeeFileUris[0] -Method 'GET'
            }

            if ($responseUrl.contractFileUris){
                $result = Invoke-RestMethod -Uri $responseUrl.contractFileUris[0] -Method 'GET'
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
    CutOffDays   = $($config.CutOffDays)
}
Get-VismaEmployeeData @splatParams
