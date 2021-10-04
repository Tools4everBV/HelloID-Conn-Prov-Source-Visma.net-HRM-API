# HelloID-Conn-Prov-Source-Raet-Visma-API

<p align="center">
  <img src="https://www.visma.com/globalassets/global/common-images/logos/vismalogo.svg">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Remarks](#Remarks)
  + [Contents](#Contents)
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

The _HelloID-Conn-Prov-Source-Raet-Visma-API_ connector is created for both Windows PowerShell 5.1 and PowerShell Core. This means that the connector can be executed in both cloud and on-premises using the HelloID agent.

### Connection settings

The following settings are required to connect to the API.

| Setting     | Description | Mandatory |
| ------------ | ----------- | ----------- |
| BaseUrl | The url to the Raet Visma API | Yes |
| CallBackUrl | With the CallBackUrl the results will be POSTed to the URL specified in your request. | Yes |
| ClientID | The ClientID to authenticate against the API | Yes |
| ClientSecret | The ClientSecret to authenticate against the API | Yes |
| TenantID | The TenantID for your Raet Visma environment| Yes |

### Remarks

#### HelloID import

At this point, only employees _with_ a contract are imported into HelloID.

#### API calls

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

### Contents

| Files       | Description                                |
| ----------- | ------------------------------------------ |
| Configuration.json | The configuration settings for the connector |
| Persons.ps1 | Retrieves the person and contract data |
| Departments.ps1 | Retrieves the department data |
| Mapping.json | A basic mapping for both persons and contracts |

## Setup the connector

> Make sure to configure the Primary Manager in HelloID to: __From department of primary contract__

For help setting up a new source connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012388639-How-to-add-a-source-system)

## Change history

| File               | Version | Changes
| ------------------ | ------- | ----------------|
| persons.p1         | 1.0.0.0 | Initial release |
| departments.p1     | 1.0.0.0 | Initial release |

## Getting help

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID Docs

The official HelloID documentation can be found at: https://docs.helloid.com/
