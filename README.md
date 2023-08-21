# HelloID-Conn-Prov-Source-Visma.net-HRM-API

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

| :warning: Warning |
|:---------------------------|
| The latest version of this connector **no longer uses the uniqueId**. Visma will also no longer generate this uniqueId. We will now use **Person Aggregation** in HelloID. If you are upgrading an existing implementation, make sure to validate the data and person aggregation. |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/vismanet-logo.png">
</p>

## Versioning
| Version | Description | Date |
| - | - | - |
| 3.0.0   | Release of v3 connector with updated logging and performance and no longer using uniqueId | 2023/02/03  |
| 2.0.0   | Release of v2 connector including support for aggregation, multiple contracts and department manager lookup | 2022/11/07  |
| 1.1.0   | Added support to only import contracts X days in past at most | 2022/08/03  |
| 1.0.0   | Initial release | 2021/10/04  |

## Table of contents
- [HelloID-Conn-Prov-Source-Visma.net-HRM-API](#helloid-conn-prov-source-vismanet-hrm-api)
  - [Versioning](#versioning)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Visma.net HRM documentation](#vismanet-hrm-documentation)
  - [Getting started](#getting-started)
    - [Scope Configuration within Visma](#scope-configuration-within-visma)
    - [Person Aggregation](#person-aggregation)
    - [Cloud agent compatibilty](#cloud-agent-compatibilty)
    - [Connection settings](#connection-settings)
    - [Contents](#contents)
  - [Remarks](#remarks)
    - [Complexity in how data must be retrieved from the Visma.Net HRM API](#complexity-in-how-data-must-be-retrieved-from-the-vismanet-hrm-api)
  - [Setup the connector](#setup-the-connector)
  - [Change history](#change-history)
  - [Getting help](#getting-help)
  - [HelloID Docs](#helloid-docs)

## Introduction
Visma is an HR System and provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed below.

- /hrm/employees (Persons & Departments script)
- /hrm/employees/user-defined-field-histories (Persons script)
- /hrm/contracts (Persons script, optional)
- /hrm/contracts/user-defined-field-histories (Persons script)
- /nl/hrm/metadata/cost-centers (Persons script)
- /nl/hrm/users (Persons & Departments script)
- /nl/hrm/metadata/organization-units (Departments script)

## Visma.net HRM documentation
Please see the following website about the Visma.net HRM API documentation.
- https://developer.visma.com/api/visma-net-hrm-payroll-api/
- https://api.analytics1.hrm.visma.net/docs/openapi.html


## Getting started
By using this connector you will have the ability to retrieve employee and contract data from the Visma.NET HR system.

### Scope Configuration within Visma 
Before the connector can be used to retrieve employee information, the following scopes need to be enabled and assigned to the connector. If you need help setting the scopes up, please consult your Visma contact.

- hrmanalytics:nlhrm:exportemployees
- hrmanalytics:nlhrm:exportcontracts
- hrmanalytics:nlhrm:exportorganizationunits
- hrmanalytics:nlhrm:exportmetadata
- hrmanalytics:nlhrm:exportusers

> Note: If one of the scopes is missing, the connector will throw a '401 Unauthorized' exception 

**Optional:**
- hrmanalytics:nlhrm:exportcontactinformation (to retrieve personal data like private mailaddress)
  > Note: make sure to toggle the option IncludePersonalData to include the scope 'hrmanalytics:nlhrm:exportcontactinformation' in the import scripts.
  
Please see the Visma HRM API documentation for more information on the required scopes per attribute. For the employee attributes, see: [NLHrmEmployeeCsvDto](https://api.analytics1.hrm.visma.net/docs/openapi.html#/:~:text=NLHrmEmployeeCsvDto,%7B)

### Person Aggregation
By default, for each contract Visma creates a new employee record (with a new employeeID). Therefore, aggregation is needed.
We have provided an example for aggregation in the mapping. Please make sure to validate this and the results.
> Note: Because aggregation is required, personal data, e.g., birthdate and birthplace are required. Make sure these fields are available.

### Cloud agent compatibilty

The _HelloID-Conn-Prov-Source-Visma.net-HRM-API_ connector is created for both Windows PowerShell 5.1 and PowerShell Core. This means that the connector can be executed in both cloud and on-premises using the HelloID agent.

### Connection settings
The following settings are required to connect to the API.

| Setting                                       | Description                                                               | Mandatory   |
| --------------------------------------------- | ------------------------------------------------------------------------- | ----------- |
| Client ID                                     | The Client ID to connect to the Visma.NET HRM API (created when registering the App in in the Visma Developer portal).                             | Yes         |
| Client Secret                                 | The Client Secret to connect to the Visma.NET HRM API (created when registering the App in in the Visma Developer portal).                         | Yes         |
| Tenant ID                                     | The Tenant ID to specify to which tenant to connect to the Visma.NET HRM API(available in the Visma Developer portal after the invitation code has been accepted).  | Yes         |
| Cut Off Days  | Amount of days expired contracts stay in scope.                      | No          |
| Exclude persons without contracts in HelloID  | Exclude persons without contracts in HelloID yes/no.                      | No          |
| Toggle debug logging  | Toggle Debug logging yes/no. When toggled, debug logging will be displayed. When set to true individual actions are logged. This may cause lots of logging, so use with cause   | No          |

### Contents
| Files       | Description                                |
| ----------- | ------------------------------------------ |
| Configuration.json | The configuration settings for the connector |
| Persons.ps1 | Retrieves the person and contract data |
| Departments.ps1 | Retrieves the department data |
| Mapping.json | A basic mapping for both persons and contracts |

## Remarks

### Complexity in how data must be retrieved from the Visma.Net HRM API
The data from Visma must be gathered in five different stages.
1. Request token
2. Request a data export (with a valid token)
3. Check (in a loop) whether or not the export is ready for download.
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
For help setting up a new source connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012388639-How-to-add-a-source-system)

## Change history

| File               | Version | Changes
| ------------------ | ------- | ----------------|
| persons.p1         | 3.0.0 | <ul><li>Release of v3 connector with updated logging and performance and no longer using uniqueId</li></ul> |
| departments.p1     | 3.0.0 | <ul><li>Release of v3 connector with updated logging and performance and no longer using uniqueId</li></ul> |
| persons.p1         | 2.0.0.0 | <ul><li>Release of v2 connector including support for aggregation, multiple contracts and department manager lookup</li></ul> |
| departments.p1     | 2.0.0.0 | <ul><li>Release of v2 connector including support for aggregation, multiple contracts and department manager lookup</li></ul> |
| persons.p1         | 1.0.0.1 | <ul><li>Added 'user-defined-fields' for both persons and contracts</li><li>Updated errorhandling</li></ul> |
| departments.p1     | 1.0.0.1 | <ul><li>Updated errorhandling</li></ul> |
| persons.p1         | 1.0.0.0 | <ul><li>Initial release</li></ul> |
| departments.p1     | 1.0.0.0 | <ul><li>Initial release</li></ul> |

## Getting help
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_
- > _For any remarks about this connector, please use the [Connector specific forum post](https://forum.helloid.com/forum/helloid-connectors/provisioning/1275-helloid-provisioning-helloid-conn-prov-source-visma-net-hrm-api)_

## HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
