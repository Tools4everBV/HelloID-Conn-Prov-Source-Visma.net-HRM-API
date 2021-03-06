# HelloID-Conn-Prov-Source-Visma.net-HRM-API

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

| :information_source: Information |
|:---------------------------|
| Before implementing this connector, Visma.NET HRM will need to calculate and generate a uniqueId. Without this id, this connector cannot be implemented. See section: _Remarks - EmployeeId is not unique_      |

| :information_source: Information |
|:---------------------------|
| Managers are currently not matched when using the API. Visma will implement this in Q1/Q2    |

<br />

<p align="center">
  <img src="https://www.visma.com/globalassets/global/common-images/logos/vismalogo.svg">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Contents](#Contents)
- [Remarks](#Remarks)
- [Setup the connector](Setup-The-Connector)
- [Change history](Change-history)
- [Getting help](Getting-help)
- [HelloID Documentation](HelloID-Docs)

## Introduction

Visma is an HR System and provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints in the table below.

| Endpoint | Description |
| ------------ | ----------- |
| /Emloyees | Contains the employee information. |
| /Contracts | Contains the information about employments. Employees can have multiple contracts. |
| /Organizational-Units | Contains the information about departments and managers. |

## Getting started

The _HelloID-Conn-Prov-Source-Visma.net-HRM-API_ connector is created for both Windows PowerShell 5.1 and PowerShell Core. This means that the connector can be executed in both cloud and on-premises using the HelloID agent.

### Connection settings

The following settings are required to connect to the API.

| Setting     | Description | Mandatory |
| ------------ | ----------- | ----------- |
| BaseUrl | The url to the Visma.Net HRM API | Yes |
| CallBackUrl | With the CallBackUrl the results will be POSTed to the URL specified in your request. | Yes |
| ClientID | The ClientID to authenticate against the API | Yes |
| ClientSecret | The ClientSecret to authenticate against the API | Yes |
| TenantID | The TenantID for your Visma.Net HRM environment| Yes |
| CutOffDays | Amount of days expired contracts stay in scope | Yes |

### Contents

| Files       | Description                                |
| ----------- | ------------------------------------------ |
| Configuration.json | The configuration settings for the connector |
| Persons.ps1 | Retrieves the person and contract data |
| Departments.ps1 | Retrieves the department data |
| Mapping.json | A basic mapping for both persons and contracts |

## Remarks

### EmployeeId is not unique

By default, the employeeId within Visma.Net HRM does not contain a unique value. Visma.Net HRM can solve this by adding a custom calculating to generate a
_uniqueId_. This _uniqueId_ will be stored in a custom field. The field varies for each Visma.Net HRM implementation.
This field can be found in the 'Employee-UDF' array in the raw data. By default; the 'value' containing the uniqueId is mapped to the 'ExternalId' of a person.

In our test environment, the _'Employee-UDF'_ array is empty for some employees. When the array is empty, the user will not be imported.


1. Currently, a lookup table is created based on the _'UniqueID'_. We also create a 'processed' UniqueIDs array to make sure users are not imported multiple times

    ```powershell
      $uniqueIDs = @()
      $EmployeeUniqueID = $employeeUserDefinedFields | Where-Object { $_.fieldname -eq 'UniqueID'}
    ```

2. Next, we loop through all EmployeeIDs and find the Employee info. We use the highest EmployeeID for person info. 

    ```powershell
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
    ```

3. Next, we add the 'ExternalId' noteproperty on the employee object. The value for the _ExternalId_ is set to the _UniqueID_ and EmployeeID will be mapped to a custom field. 

    ```powershell
            $employee = $lookupEmployees[$employeelookupvalue]
            $employee | Add-Member -MemberType NoteProperty -Name 'ExternalId' -Value $UniqueID.value -force
            $employee | Add-Member -MemberType NoteProperty -Name 'DisplayName' -Value $employee.formattedname -force

            $EmployeeUDFList = [system.collections.generic.list[object]]::new()
            foreach ($employeeID in $employeeIDs){
                $EmployeeFieldsInScope = $lookEmployeeUserDefinedFields[$employeeID]
                $EmployeeUDFList.add($EmployeeFieldsInScope)
            }

            $employee | Add-Member -MemberType NoteProperty -Name 'Employee-UDF' -Value $EmployeeUDFList -force
    }
    ```
    
4. Finally, we add the contracts of each EmployeeID, check if the contracts are within scope and add the person to the resultlist if the UniqueID has not been processed before.

    ```powershell
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
                                   #write-output $employee
                                    $uniqueIDs = $uniqueIDs + $($employee.ExternalId)                            
                                }
                            }
                        } else {
                        write-verbose -verbose "Persoon $($employee.displayName) al verwerkt met eerder UniqueID"
                    }
            }
    ```

> Before implementing this connector, Visma.Net HRM will need to calculate and generate a uniqueId. Without this id, this connector cannot be implemented.

### Which data will be imported in HelloID

At this point, only employees _with_ contracts within scope (CutOffDays) are imported into HelloID.

### Complexity in how data must be retrieved from the Visma.Net HRM API

The data from Visma must be gathered in five different stages.
1. Request token
2. Request a data export (with a valid token)
3. Check (in a loop) wheter or not the export is ready for download.
4. Download the export
5. Import the data into HelloID

The third stage (check if the export is ready for download) returns a json object containing the status of the export.

```json
{
    "changeTimestampBefore": null,
    "employeeFileUris": null,
    "status": "InProgress"
}
```

When the is export is ready, the status changes to _Completed_. The connector will continously check the status until it has changed to _Completed_.
Now, this works fine on our test environment. However, in a real life environment, there might be a situation where the status won't change to _Completed_ and you end up with an endless loop. We haven't experienced this behavior ourselves but it's good to be aware of it.

## Setup the connector

> Make sure to configure the Primary Manager in HelloID to: __From department of primary contract__
> Make sure to create a custom field for EmployeeNumber as the ExternalID contains the UniqueID, not the EmployeeNumber. Be sure to configure display names as well
> Make sure to create a custom field for isManager, this parameter is supplied by Visma and could come in handy for target systems

For help setting up a new source connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012388639-How-to-add-a-source-system)

## Change history

| File               | Version | Changes
| ------------------ | ------- | ----------------|
| persons.p1         | 1.0.0.1 | <ul><li>Added 'user-defined-fields' for both persons and contracts</li><li>Updated errorhandling</li></ul> |
| departments.p1     | 1.0.0.1 | <ul><li>Updated errorhandling</li></ul> |
| persons.p1         | 1.0.0.0 | <ul><li>Initial release</li></ul> |
| departments.p1     | 1.0.0.0 | <ul><li>Initial release</li></ul> |

## Getting help

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID Docs

The official HelloID documentation can be found at: https://docs.helloid.com/
