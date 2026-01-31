# API Permission Request: SPO Assistant Sync Service Principal

**Document Type:** Security Review Request
**Date:** 2026-01-30
**Requested By:** [Your Name]
**Application:** SPO Assistant Sync
**Review Priority:** High (Time-Sensitive due to Microsoft deprecation timeline)

---

## Executive Summary

This document requests approval for API permissions required to operate an automated workflow that synchronizes executive assistant information from an internal JSON data source to SharePoint Online user profiles. The workflow runs daily via Windows Task Scheduler using a Service Principal for authentication.

**Important:** This request includes a critical timeline consideration. The currently functional authentication method (Azure ACS) is scheduled for retirement by Microsoft on **April 2, 2026**. This document outlines both the immediate requirements and long-term migration considerations.

---

## Business Purpose

The SPO Assistant Sync workflow automates the maintenance of the "Assistant" property in SharePoint Online user profiles. This ensures:

- Accurate organizational hierarchy data in SharePoint
- Consistent assistant information across Microsoft 365 services
- Reduced manual administrative overhead for profile management

---

## Technical Architecture

### Workflow Overview

```
┌─────────────────────┐      ┌──────────────────────┐      ┌─────────────────────┐
│   JSON Data Source  │ ──── │  PowerShell Script   │ ──── │  SharePoint Online  │
│   (assistants.json) │      │  (PnP PowerShell)    │      │  User Profile Store │
└─────────────────────┘      └──────────────────────┘      └─────────────────────┘
                                       │
                                       ▼
                             ┌──────────────────────┐
                             │   Service Principal  │
                             │   (Authentication)   │
                             └──────────────────────┘
```

### Components

| Component           | Description                                                   |
| ------------------- | ------------------------------------------------------------- |
| **Script**          | `Sync-AssistantProfiles.ps1` (PowerShell)                     |
| **Module**          | PnP.PowerShell                                                |
| **Data Source**     | Local JSON file (`c:\scripts\assistant_sync\assistants.json`) |
| **Target**          | SharePoint Online User Profile Service Application (UPA)      |
| **Target Property** | `Assistant` user profile property                             |
| **Schedule**        | Daily execution via Windows Task Scheduler                    |
| **Cmdlet Used**     | `Set-PnPUserProfileProperty`                                  |

### SharePoint Admin URL

```
https://{ORG}-admin.sharepoint.com
```

---

## Requested Permissions

### Primary Request: Azure ACS App-Only (Legacy)

Due to a known limitation with modern Entra ID authentication (detailed in the Technical Constraints section), the functional requirement is to use **Azure ACS (Access Control Services) App-Only** authentication.

#### Registration Method

| Step             | URL                                                             |
| ---------------- | --------------------------------------------------------------- |
| App Registration | `https://{ORG}-admin.sharepoint.com/_layouts/15/appregnew.aspx` |
| Permission Grant | `https://{ORG}-admin.sharepoint.com/_layouts/15/appinv.aspx`    |

#### Permission XML

The following permission request XML is required for `appinv.aspx`:

```xml
<AppPermissionRequests AllowAppOnlyPolicy="true">
  <AppPermissionRequest Scope="http://sharepoint/content/tenant" Right="FullControl"/>
</AppPermissionRequests>
```

#### Permission Justification

| Permission    | Scope          | Justification                                                                                                                                                                                                                                                        |
| ------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FullControl` | Tenant Content | Required for User Profile Service Application write operations. The SharePoint UPA does not expose granular permissions for profile property updates; FullControl at tenant scope is the minimum permission that enables `Set-PnPUserProfileProperty` functionality. |

### Alternative: Entra ID App Registration (Non-Functional for This Use Case)

For reference, the modern Entra ID equivalent permissions would be:

| API             | Permission                | Type        |
| --------------- | ------------------------- | ----------- |
| SharePoint      | `Sites.FullControl.All`   | Application |
| SharePoint      | `User.ReadWrite.All`      | Application |
| SharePoint      | `TermStore.ReadWrite.All` | Application |
| Microsoft Graph | `User.Read`               | Application |

**Note:** These permissions are documented here for completeness, but as detailed in the Technical Constraints section, they do not currently enable User Profile write operations in app-only context.

---

## Technical Constraints

### Known Limitation: Entra ID App-Only Authentication

Microsoft's modern Entra ID application permissions **do not support write operations** to the SharePoint User Profile Service Application when using app-only (certificate-based) authentication.

Multiple Microsoft community threads and GitHub issues document this limitation:

> "When using `Set-PnPUserProfileProperty` in Azure Function with Application Permissions, once connected to the admin site URL using client id, tenant and cert and trying to update the User Profile Property, it throws the error: **Access denied. You do not have permission to perform this action or access this resource.**"

This limitation exists even when all available SharePoint API permissions (`Sites.FullControl.All`, `User.ReadWrite.All`) are granted and admin-consented.

#### Documented Issues

| Source                   | Reference                                                                                                                                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub                   | [pnp/powershell Issue #277](https://github.com/pnp/powershell/issues/277)                                                                                                                                     |
| GitHub                   | [pnp/powershell Discussion #2155](https://github.com/pnp/powershell/discussions/2155)                                                                                                                         |
| Microsoft Tech Community | [Set-PnPUserProfileProperty with Application Permission](https://techcommunity.microsoft.com/discussions/sharepoint_general/set-pnpuserprofileproperty-with-application-permission-in-azure-function/1229940) |
| Microsoft Tech Community | [Set-PnPUserProfileProperty using Application Permissions](https://techcommunity.microsoft.com/discussions/sharepointdev/set-pnpuserprofileproperty-using-application-permissions/386859)                     |

### Workaround Requirement

The only functional authentication method for this use case is **Azure ACS App-Only with Client Secret**, which uses the legacy SharePoint app registration model.

---

## Risk Assessment

### Azure ACS Deprecation Timeline

Microsoft has announced the retirement of Azure Access Control Services (ACS) for SharePoint Online:

| Milestone                    | Date              | Impact                                              |
| ---------------------------- | ----------------- | --------------------------------------------------- |
| ACS disabled for new tenants | November 1, 2024  | New tenant deployments blocked                      |
| **ACS fully retired**        | **April 2, 2026** | All ACS-based authentication will cease to function |

**Source:** [Azure ACS retirement in Microsoft 365 - Microsoft Learn](https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/retirement-announcement-for-azure-acs)

> "There will not be an option to extend using Azure ACS with SharePoint Online beyond April 2nd, 2026."

### Risk Matrix

| Risk                                              | Likelihood  | Impact | Mitigation                                                                |
| ------------------------------------------------- | ----------- | ------ | ------------------------------------------------------------------------- |
| ACS authentication stops working after April 2026 | **Certain** | High   | Plan migration to alternative solution before deadline                    |
| Client Secret exposure                            | Low         | High   | Store secret securely; rotate regularly; limit Service Principal scope    |
| FullControl permission abuse                      | Low         | High   | Dedicated Service Principal for this workflow only; audit logging enabled |
| Script failure due to PnP module updates          | Medium      | Low    | Pin module version; test updates in non-production first                  |

### Security Controls

The following controls are recommended to mitigate risks:

1. **Credential Storage:** Store Client ID and Client Secret in a secure vault (e.g., Azure Key Vault, CyberArk)
2. **Dedicated Principal:** Use a Service Principal exclusively for this workflow
3. **Audit Logging:** Enable Entra ID sign-in logging for the Service Principal
4. **Secret Rotation:** Implement 90-day secret rotation policy
5. **Network Restrictions:** If possible, restrict Service Principal sign-ins to known IP ranges
6. **Monitoring:** Alert on failed authentication attempts or unusual activity

---

## Migration Planning

### Post-April 2026 Options

Given the ACS retirement deadline, the following alternatives should be evaluated:

| Option                           | Description                                           | Feasibility                                                |
| -------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------- |
| **Microsoft Graph API**          | Use Graph endpoints for user profile management       | Partial - Limited UPA property support                     |
| **Entra ID with Delegated Auth** | Interactive flow with service account                 | Possible - Requires stored credentials or managed identity |
| **Wait for Microsoft Fix**       | Microsoft may enable UPA writes via Entra ID app-only | Uncertain - No announced timeline                          |
| **Power Automate**               | Low-code alternative using delegated permissions      | Possible - May require Premium licensing                   |

### Recommended Timeline

| Phase    | Date          | Action                                          |
| -------- | ------------- | ----------------------------------------------- |
| Phase 1  | Now - Q1 2026 | Deploy using ACS App-Only (this request)        |
| Phase 2  | Q2 2025       | Begin evaluating Graph API capabilities for UPA |
| Phase 3  | Q3 2025       | Develop and test migration path                 |
| Phase 4  | Q1 2026       | Deploy replacement solution                     |
| Deadline | April 2, 2026 | ACS retirement                                  |

---

## Official Microsoft Documentation References

### User Profile Service Application

| Document                                    | URL                                                                                                          |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| User Profile Service Overview               | https://learn.microsoft.com/en-us/sharepoint/install/user-profile-service-overview                           |
| About User Profile Synchronization          | https://learn.microsoft.com/en-us/sharepoint/user-profile-sync                                               |
| User Profile Service Protocol Specification | https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-spo/2c0023f2-b91a-4b2d-af40-230671696674 |
| Plan User Profiles in SharePoint Server     | https://learn.microsoft.com/en-us/sharepoint/administration/plan-user-profiles                               |

### Authentication & Permissions

| Document                                      | URL                                                                                                                                                      |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Granting Access via Entra ID App-Only         | https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azuread                                                              |
| Granting Access via SharePoint ACS (Legacy)   | https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azureacs                                                             |
| Tenant Admin Permissions for App-Only Add-ins | https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/how-to-provide-add-in-app-only-tenant-administrative-permissions-in-sharepoint-online |

### ACS Retirement & Migration

| Document                                  | URL                                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Azure ACS Retirement Announcement         | https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/retirement-announcement-for-azure-acs |
| SharePoint Add-Ins and ACS Retirement FAQ | https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/add-ins-and-azure-acs-retirements-faq |
| Upgrading from ACS to Azure AD            | https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins-modernize/from-acs-to-aad-apps        |
| SharePoint Add-In Retirement Announcement | https://learn.microsoft.com/en-us/sharepoint/dev/sp-add-ins/retirement-announcement-for-add-ins   |

### PnP PowerShell

| Document                          | URL                                                                      |
| --------------------------------- | ------------------------------------------------------------------------ |
| Set-PnPUserProfileProperty Cmdlet | https://pnp.github.io/powershell/cmdlets/Set-PnPUserProfileProperty.html |
| Determining Required Permissions  | https://pnp.github.io/powershell/articles/determinepermissions.html      |
| PnP PowerShell GitHub Repository  | https://github.com/pnp/powershell                                        |

---

## Approval Request

### Requested Actions

1. **Approve** the creation of an Azure ACS App-Only registration for the SPO Assistant Sync workflow
2. **Approve** granting `FullControl` permission at tenant scope for User Profile Service operations
3. **Acknowledge** the April 2, 2026 deprecation deadline and the need for future migration planning
4. **Recommend** security controls to be implemented (credential storage, monitoring, etc.)

### Service Principal Details

| Field              | Value                                                     |
| ------------------ | --------------------------------------------------------- |
| Application Name   | SPO-AssistantSync                                         |
| Purpose            | Automated User Profile Assistant property synchronization |
| Authentication     | ACS App-Only (Client ID + Client Secret)                  |
| Target Environment | SharePoint Online ({ORG} tenant)                          |
| Execution Schedule | Daily                                                     |
| Execution Context  | Windows Task Scheduler on [Server Name]                   |

---

## Approvals

| Role                     | Name | Date | Signature |
| ------------------------ | ---- | ---- | --------- |
| Requestor                |      |      |           |
| Information Security     |      |      |           |
| SharePoint Administrator |      |      |           |
| IT Manager               |      |      |           |

---

## Document History

| Version | Date       | Author | Changes       |
| ------- | ---------- | ------ | ------------- |
| 1.0     | 2026-01-30 |        | Initial draft |

---

_This document was prepared to support a formal security review request. All technical details and Microsoft documentation references were verified as of the document date._
