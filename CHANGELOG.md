# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

Historical entries are reconstructed from Git tags, commits and the previous README change history. Dates for tagged versions follow the tagged commits; dates for earlier releases follow the README.

## [3.3.2] - 23-10-2026

### Fixed

- Corrected the `Name.Convention` mapping for Visma name usage `Eig./part.` to return `BP` (birth name followed by partner name) instead of falling back to `B`.

### Added

- German connector information in `INFO_DE.md`.

## [3.3.1] - 11-06-2025

### Fixed

- Contract user-defined fields now use the contract field's properties and name instead of the person field's properties and name when building the flattened contract attributes.

## [3.3.0] - 29-01-2025

### Changed

- Employee and contract user-defined fields are exposed as individual attributes instead of nested collections, making them easier to map in HelloID. Attribute names use `employeeUserDefinedField_<fieldname>_<property>` and `contractUserDefinedField_<fieldname>_<property>`, with spaces removed from the field name, for `listname`, `value`, `startdate` and `enddate`. Existing mappings that use the nested collections must be updated.

## [3.2.1] - 29-01-2025

### Removed

- Excluded `salaryfulltime` from the contract data requested from Visma.

## [3.2.0] - 29-01-2025

### Changed

- Manager lookup for persons and departments uses the manager user's employee ID instead of email address, allowing managers without an email address to be resolved.
- Department export no longer includes `ShortName`.

### Added

- Dutch, English and French connector information in `INFO_NL.md`, `INFO_UK.md` and `INFO_FR.md`.
- Updated connector icon and logo.

## [3.1.0] - 27-10-2023

### Added

- `IncludePersonalData` configuration option to control use of the optional `hrmanalytics:nlhrm:exportcontactinformation` scope in both import scripts.

### Changed

- Department import selects organization-unit records that are active on the current date using their start and end dates.
- Employee and user matching by email address filters out null email addresses and groups without case sensitivity.
- Cost center codes are exported as strings.
- Updated connector icons and documentation for personal data and the required scopes.

### Fixed

- Person import adds all contracts to each person instead of only the last contract.
- Contract user-defined fields are attached to the corresponding contract instead of the person.
- Corrected employee count logging in the department import.

### Removed

- Default mappings for business phone numbers and personal email that depend on the optional contact information scope.

## [3.0.0] - 21-08-2023

### Changed

- Reworked both import scripts with improved logging, error handling and performance.
- Person aggregation is handled in HelloID. Existing implementations must validate their data and person aggregation when upgrading.
- Added export job IDs to debug logging.

### Removed

- Removed use of the Visma `uniqueId`, which Visma no longer generates.

The README originally recorded the v3 connector update on 03-02-2023; the `v3.0.0` Git tag points to the commit dated 21-08-2023.

## [2.0.0] - 07-11-2022

### Added

- Support for person aggregation, multiple contracts and department manager lookup.

## [1.1.0] - 03-08-2022

### Added

- Support for limiting the import of expired contracts using `CutOffDays`.
- Manager external ID on contracts.

## [1.0.0] - 04-10-2021

### Added

- Initial release of the Visma.net HRM API source connector, including person and department imports, configuration and mappings.

Subsequent changes before the documented 1.1.0 release added user-defined fields for persons and contracts and improved error handling. The former README listed these script changes as version `1.0.0.1`, without a release date.
