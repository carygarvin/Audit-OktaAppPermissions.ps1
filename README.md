# Audit-OktaAppPermissions.ps1  
PowerShell Script for auditing Okta App Assignments and Revocations.
  
Author       : Cary GARVIN  
Contact      : cary(at)garvin.tech  
LinkedIn     : [https://www.linkedin.com/in/cary-garvin](https://www.linkedin.com/in/cary-garvin)  
GitHub       : [https://github.com/carygarvin/](https://github.com/carygarvin/)  


Script Name  : [Audit-OktaAppPermissions.ps1](https://github.com/carygarvin/Audit-OktaAppPermissions.ps1)  
Version      : 1.0  
Release date : 07/01/2019 (CET)  

History      : The present script has been developed as an auditing tool to gather Okta App Assignments and Revocations made by a particular Organization in the Okta authentication Cloud platform.  

Purpose      : The present script can be used for auditing Okta App Assignments and Revocations for an organization using Okta authentication services. The computer running this present script requires Microsoft Excel to be installed as Excel is used to build the report using CDO.  

# Script usage
The present PowerShell Script cannot be run with a locked computer or System account (as a Scheduled Task for instance) since CDO operations using Excel perform Copy/Paste operations which take place interactively within the context of a logged user. This is for performance considerations since pasting entire Worksheets in one shot is way faster than filling cells one by one using CDO, thus ensuring the computer running this script remains unlocked throughout the entire Script's operation.  

# Script configuration
There are 2 configurable variables (see lines 29 and 30 in the actual script) which need to be set by the IT Administrator prior to using the present Script:  
* Variable **$OktaOrgName** which is the name, in the Okta Portal URL, corresponding to your organization.  
* Variable **$OktaAPIToken** which is the temporary token Okta issued for you upon request. This token can be issued and taken from Admin>Security>API>Token once you are logged in the Okta Admin Portal.  
