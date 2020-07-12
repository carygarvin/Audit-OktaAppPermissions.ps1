# ***************************************************************************************************
# ***************************************************************************************************
#
#  Author       : Cary GARVIN
#  Contact      : cary(at)garvin.tech
#  LinkedIn     : https://www.linkedin.com/in/cary-garvin-99909582
#  GitHub       : https://github.com/carygarvin/
#
#
#  Script Name  : Audit-OktaAppPermissions.ps1
#  Version      : 1.0
#  Release date : 07/01/2019 (CET)
#  History      : The present script has been developped as an auditing tool to gather Okta App Assignments and Revocations made by a particular Organization in the Okta authentication Cloud platform.
#  Purpose      : The present script can be used for auditing Okta App Assignments and Revocations for an organization using Okta authentication services. The computer running this present script requires Microsoft Excel to be installed as Excel is used to build the report using CDO.
#
#
#  The present PowerShell Script cannot be run with a locked computer or System account (as a Scheduled Task for instance) since CDO operations using Excel perform Copy/Paste operations which take place interactively within the context of a logged on user.
#  This is for performnce issues since pasting entire Worksheets in one shot is way faster than filing cells one by one using CDO.
#  Therefore ensure the computer running this script remains unlocked throughout the entire Script's operation.
#
#
#  There are 2 configurable variables (see lines 29 and 30 below) which need to be set by IT Administrator prior to using the present Script:
#  Variable '$OktaOrgName' which is the name, in the Okta Portal URL, corresponding to your organization.
#  Variable '$OktaAPItoken' which is the temporary token Okta issued for you upon request. This token can be issued and taken from Admin>Security>API>Token once your are logged in the Okta Admin Portal.



# Configurable parameters by IT Administrator as referred in the script's instructions. Modify these 2 varaiable values to match your Okta configuration.
$OktaOrgName = "contoso"
$OktaAPItoken = "GoAndGenerateYourTokenThenCopyItAndPasteItHere"	# Temporary token generated from Okta Portal (Admin/Security/API/Tokens)



$ThrottlingBatchSize = 95											# Max number of unthrottled consecutive WebRequest queries to Okta
$ThrottlingPauseDelay = 65											# In seconds
$LookBackPeriod = 180												# In days





############################################################################################################################################
# Function collecting direct user Assignments and Revocations to App                                                                       #
############################################################################################################################################
Function Get-AppPermissionActions
	{
    param (
		[Parameter (Mandatory=$true)]
		[string] $LoggedAction,
        [string] $AppID,
        [string] $AppLabel
		)
		
	$script:uri = "https://$OktaOrgName.okta-emea.com/api/v1/logs?filter=event_type+eq+%22application.user_membership.$LoggedAction%22+and+outcome.result+eq+%22SUCCESS%22+and+target.id+eq+%22$AppID%22"

	If ($LoggedAction -eq "add") {$ActionType = "Addition to App"; $Action = "Add"; $Action2 = "assignment"}
	ElseIf ($LoggedAction -eq "remove") {$ActionType = "Removal from App"; $Action = "Remove"; $Action2 = "revocation"}

	$PreviousPage = "anything"
	$NextPage = $script:uri

	While ($NextPage -and ($NextPage -ne $PreviousPage))
		{
		If ($script:WebRequestsCounter % $ThrottlingBatchSize -eq 0) {write-host "$($script:WebRequestsCounter) web requests reached. Pausing for $ThrottlingPauseDelay seconds!"; start-sleep -s $ThrottlingPauseDelay}
		$webresponse = Invoke-WebRequest -Headers $headers -Method Get -Uri $NextPage
		$script:WebRequestsCounter++
		$PreviousPage = $NextPage
		$NextPage = $webresponse.Headers.Link.Split("<").Split(">")[3]

		 If (($webresponse | ConvertFrom-Json).length -ge 1)
			{
			write-host ">>>> >$(($webresponse | ConvertFrom-Json).length)< Assignments found for App '$Applabel' [$AppID]. Recording $Action2(s) :" -foregroundcolor "cyan"

			ForEach ($LogAssignmentEntry in ($webresponse.content | ConvertFrom-Json))
				{
				$LogAssignment = New-Object PSObject
				$LogAssignment | Add-Member NoteProperty -Name "ActionTimeStamp" -Value ([DateTime]::ParseExact($LogAssignmentEntry.published, 'yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture))
				$LogAssignment | Add-Member NoteProperty -Name "AppLabel" -Value $Applabel
				$LogAssignment | Add-Member NoteProperty -Name "AppID" -Value $AppID
				$LogAssignment | Add-Member NoteProperty -Name "UserSMTP" -Value $LogAssignmentEntry.target.alternateId[0]
				$LogAssignment | Add-Member NoteProperty -Name "UserDN" -Value $LogAssignmentEntry.target.displayName[0]
				$LogAssignment | Add-Member NoteProperty -Name "AppGroup" -Value "N/A"
				$LogAssignment | Add-Member NoteProperty -Name "Operator" -Value $LogAssignmentEntry.actor.alternateId
				$LogAssignment | Add-Member NoteProperty -Name "ActionType" -Value $ActionType
				$LogAssignment | Add-Member NoteProperty -Name "Action" -Value "$Action by '$($LogAssignment.Operator)' on '$($LogAssignment.ActionTimeStamp)'"
				$script:AllAssignments += $LogAssignment
				}
			}
		Else
			{
			If ($PreviousPage -ne "anything")
				{
				If ($LogAssignment) {write-host ">>>> No more direct App assignment logged for >$($_.AppLabel)< in the last $LookBackPeriod days!" -foregroundcolor "cyan"}
				Else {write-host ">>>> No direct App assignment logged for >$($_.AppLabel)< in the last $LookBackPeriod days!" -foregroundcolor "cyan"}
				}
			}
		}
	}




############################################################################################################################################
# Function collecting indirect user Assignments and Revocations to App via App Group(s)                                                    #
############################################################################################################################################
Function Get-GroupPermissionActions
	{
    param (
		[Parameter (Mandatory=$true)]
		[string] $LoggedAction,
        [string] $AppID,
        [string] $AppLabel,
		[array] $AppGroups
		)

	If ($LoggedAction -eq "add") {$ActionType = "Addition to App"; $Action = "Add"; $Action2 = "assignment"}
	ElseIf ($LoggedAction -eq "remove") {$ActionType = "Removal from App"; $Action = "Remove"; $Action2 = "revocation"}


	ForEach ($GroupId in $AppGroups)
		{
		$uri = "https://$OktaOrgName.okta-emea.com/api/v1/groups/$GroupId"
		If ($script:WebRequestsCounter % $ThrottlingBatchSize -eq 0) {write-host "$($script:WebRequestsCounter) web requests reached. Pausing for $ThrottlingPauseDelay seconds!"; start-sleep -s $ThrottlingPauseDelay}
		$webresponse = Invoke-WebRequest -Headers $headers -Method Get -Uri $uri
		$script:WebRequestsCounter++
		$GroupName = ($webresponse | ConvertFrom-Json).profile.name

		write-host "`t Processing $Action2 log events for App Group '$GroupName' [$GroupId] for App '$AppLabel'" -foregroundcolor "cyan"
		$uri = "https://$OktaOrgName.okta-emea.com/api/v1/logs?filter=event_type+eq+%22group.user_membership.$LoggedAction%22+and+outcome.result+eq+%22SUCCESS%22+and+target.id+eq+%22$GroupId%22"
		$PreviousPage = "anything"
		$NextPage = $uri

		While ($NextPage-and ($NextPage -ne $PreviousPage))
			{
			If ($script:WebRequestsCounter % $ThrottlingBatchSize -eq 0) {write-host "$($script:WebRequestsCounter) web requests reached. Pausing for $ThrottlingPauseDelay seconds!"; start-sleep -s $ThrottlingPauseDelay}
			$webresponse = Invoke-WebRequest -Headers $headers -Method Get -Uri $NextPage
			$script:WebRequestsCounter++
			$PreviousPage = $NextPage
			$NextPage = $webresponse.Headers.Link.Split("<").Split(">")[3]

			If (($webresponse | ConvertFrom-Json).length -ge 1)
				{
				write-host ">>>> >$(($webresponse | ConvertFrom-Json).length)< Assignments found for App '$Applabel' [$AppID]. Recording $Action2(s) :" -foregroundcolor "cyan"

				ForEach ($LogAssignmentEntry in ($webresponse.content | ConvertFrom-Json))
					{
					$LogAssignment = New-Object PSObject
					$LogAssignment | Add-Member NoteProperty -Name "ActionTimeStamp" -Value ([DateTime]::ParseExact($LogAssignmentEntry.published, 'yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture))
					$LogAssignment | Add-Member NoteProperty -Name "AppLabel" -Value $Applabel
					$LogAssignment | Add-Member NoteProperty -Name "AppID" -Value $AppID
					$LogAssignment | Add-Member NoteProperty -Name "UserSMTP" -Value $LogAssignmentEntry.target.alternateId[0]
					$LogAssignment | Add-Member NoteProperty -Name "UserDN" -Value $LogAssignmentEntry.target.displayName[0]
					$LogAssignment | Add-Member NoteProperty -Name "AppGroup" -Value $GroupName
					$LogAssignment | Add-Member NoteProperty -Name "Operator" -Value $LogAssignmentEntry.actor.alternateId
					$LogAssignment | Add-Member NoteProperty -Name "ActionType" -Value $ActionType
					$LogAssignment | Add-Member NoteProperty -Name "Action" -Value "$Action by '$($LogAssignment.Operator)' on '$($LogAssignment.ActionTimeStamp)'"
					$script:AllAssignments += $LogAssignment
					}
				}
			Else
				{
				If ($PreviousPage -ne "anything")
					{
					If ($LogAssignment) {write-host ">>>> No more App assignment via groups logged for '$AppLabel' in the last $LookBackPeriod days!" -foregroundcolor "cyan"}
					Else {write-host ">>>> No App assignment via groups logged for '$AppLabel' in the last $LookBackPeriod days!" -foregroundcolor "cyan"}
					}
				}
			}
		}
	}




############################################################################################################################################
# Script Main                                                                                                                              #
############################################################################################################################################

$error.clear()


[threading.thread]::CurrentThread.CurrentCulture = 'en-US'


$script:ScriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$script:ScriptName = (Get-Item $MyInvocation.MyCommand).basename
$script:ExecutionTimeStamp = get-date -format "yyyy-MM-dd_HH-mm-ss"
$script:ScriptLaunch = get-date -format "yyyy/MM/dd HH:mm:ss"
$UserMyDocs = [Environment]::GetFolderPath("MyDocuments")


$headers = @{"Authorization" = "SSWS $OktaAPItoken"; "Accept" = "application/json"; "Content-Type" = "application/json"}
$script:WebRequestsCounter = 0




############################################################################################################################################
# 1. Gather full list of Apps                                                                                                              #
############################################################################################################################################

write-host "`r`n`r`nStep 1: Building list of Okta Apps." -foregroundcolor "yellow"

$AllApps = @()
$uri = "https://$OktaOrgName.okta-emea.com/api/v1/apps"
$NextPage = $uri
While ($NextPage)
	{
	Try
		{
		If (($script:WebRequestsCounter -ne 0) -and ($script:WebRequestsCounter % $ThrottlingBatchSize -eq 0)) {write-host "$($script:WebRequestsCounter) web requests reached. Pausing for $ThrottlingPauseDelay seconds!"; start-sleep -s $ThrottlingPauseDelay}
		$webresponse = Invoke-WebRequest -Headers $headers -Method Get -Uri $NextPage
		$script:WebRequestsCounter++

		If (!$webresponse.Headers.Link) {$NextPage = $null}
		Else
			{
			$NextPage = $webresponse.Headers.Link.Split("<").Split(">")[3]
			ForEach ($AppEntry in ($webresponse | ConvertFrom-Json))
				{
				$AppProp = New-Object PSObject
				$AppProp | Add-Member NoteProperty -Name "AppLabel" -Value $AppEntry.label
				$AppProp | Add-Member NoteProperty -Name "id" -Value $AppEntry.id
				$AllApps += $AppProp
				}
			}
		}
	Catch [System.Net.WebException]
		{
		write-host "Invalid or expired Okta token!" -foregroundcolor "red"
		write-host "Check Okta API Token '$OktaAPItoken' and relaunch script!" -foregroundcolor "red"
		Exit
		}
	Catch
		{
		write-host "App enumeration completed!" -foregroundcolor "red"
		break
		}
	}
write-host "The >$($AllApps.length)< number of Okta Apps are as follows:"
$AllApps | ft




############################################################################################################################################
# 2. For each App, find the list of Groups assigning it                                                                                    #
############################################################################################################################################

write-host "`r`n`r`nStep 2: Devising for each App the list of associated Okta Groups." -foregroundcolor "yellow"

$AllAppInfo = @()
$AllApps | ForEach {
	write-host "`r`n####################################################################################################" -foregroundcolor "yellow"
	write-host "Processing App $($_.AppLabel) / $($_.id)" -foregroundcolor "yellow"
	$AllAppGroups = @()
	$uri = "https://$OktaOrgName.okta-emea.com/api/v1/apps/$($_.id)/groups"
	$NextPage = $uri
	While ($NextPage)
		{
		If ($script:WebRequestsCounter % $ThrottlingBatchSize -eq 0) {write-host "$($script:WebRequestsCounter) web requests reached. Pausing for $ThrottlingPauseDelay seconds!"; start-sleep -s $ThrottlingPauseDelay}
		$webresponse = Invoke-WebRequest -Headers $headers -Method Get -Uri $NextPage
		$script:WebRequestsCounter++
		write-host "The WebRequestsCounter is at >$($script:WebRequestsCounter)<" -foregroundcolor "green"
		$NextPage = $webresponse.Headers.Link.Split("<").Split(">")[3]
		$AppGroups = @()
		$AppGroups = ($webresponse | ConvertFrom-Json).id

		If ($AppGroups)
			{
			$AppGroups
			write-host "`$AppGroups is of type >$($AppGroups.GetType())<" -foregroundcolor "cyan"
			$AllAppGroups += $AppGroups
			}
		}
	$AllAppInfo += $_ | Select-Object *, @{l="AppGroups"; e={$AllAppGroups}}
	}
write-host "-----------------------------------------------------"
$AllAppInfo | format-table -Property AppLabel, id, AppGroups -AutoSize

$EventsFromDate = ((Get-Date).AddDays(-$LookBackPeriod)).ToString("yyyy-MM-dd") + "T00%3A00%3A00.000Z"




############################################################################################################################################
# 3. Iterate through the list of Apps and query for each App the Okta logs to find direct App assignments and revocations                  #
############################################################################################################################################

write-host "`r`n`r`nStep 3: Consulting Okta logs for direct App assignments and revocations" -foregroundcolor "yellow"
$script:AllAssignments = @()


############################################################################################################################################
# 3.(A) Direct User Assignments to App                                                                                                     #
############################################################################################################################################

write-host "`r`n`r`nStep 3A: Querying Okta logs for direct App assignments..." -foregroundcolor "yellow"
$AllAppInfo | ForEach {Get-AppPermissionActions "add" $_.id $_.AppLabel}


############################################################################################################################################
# 3.(B) Direct User Revocations to App                                                                                                     #
############################################################################################################################################

write-host "`r`n`r`nStep 3B: Querying Okta logs for direct App revocations..." -foregroundcolor "yellow"
$AllAppInfo | ForEach {Get-AppPermissionActions "remove" $_.id $_.AppLabel}




############################################################################################################################################
# 4. Iterate through the list of Apps and query Groups for each App the Okta logs to find assignments and revocations via these Groups     #
############################################################################################################################################

write-host "`r`n`r`nStep 4: Consulting Okta logs for indirect App assignments and revocations via Groups" -foregroundcolor "yellow"


############################################################################################################################################
# 4.(A) Indirect User Assignments to App via App Group(s)                                                                                  #
############################################################################################################################################

write-host "`r`n`r`nStep 4A: Querying Okta logs for indirect assignments via App Groups!" -foregroundcolor "yellow"
$AllAppInfo | ForEach {Get-GroupPermissionActions "add" $_.id $_.AppLabel $_.AppGroups}


############################################################################################################################################
# 4.(B) Indirect User Revocaions to App via App Group(s)                                                                                   #
############################################################################################################################################

write-host "`r`n`r`nStep 4B: Consulting Okta logs for indirect revocations via App Groups!" -foregroundcolor "yellow"
$AllAppInfo | ForEach {Get-GroupPermissionActions "remove" $_.id $_.AppLabel $_.AppGroups}




############################################################################################################################################
# 5. Deduplication and save of raw results into CSV file                                                                                   #
############################################################################################################################################

write-host "`r`n`r`nStep 5 : Deduplication of results in progress. Please wait..." -foregroundcolor "yellow"

$InitialNrOfEntries = $script:AllAssignments.length
$FilteredAssignments = $script:AllAssignments | Select @{Label = "ConcatIndex"; Expression = {"$($_.ActionTimeStamp)%$($_.UserSMTP)%$($_.AppID)%$(If ($_.ActionType.contains(""Addition"")) {""+""} ElseIf ($_.ActionType.contains(""Removal"")) {""-""})"}}, @{Label = 'GroupIndexer'; Expression = {"$($_.AppGroup.Replace('N/A', 'ZZZ'))"}}, * | Group-Object ConcatIndex | %{ $_.Group | Sort-Object $_.Group.GroupIndexer -Unique} | select ActionTimeStamp, AppLabel, AppID, UserSMTP, UserDN, AppGroup, Operator, ActionType, Action 
$FilteredNrOfEntries = $FilteredAssignments.length

write-host "Completed. Report reduced from $InitialNrOfEntries to $FilteredNrOfEntries entries ($($InitialNrOfEntries-$FilteredNrOfEntries) redundant entries filtered out, i.e. cleanup rate of $(($InitialNrOfEntries-$FilteredNrOfEntries)/100) %)."
$FilteredAssignments | format-table -Property AppLabel, AppID, UserSMTP, UserDN, AppGroup, Operator, ActionType, Action, ActionTimeStamp -AutoSize
$FilteredAssignments | sort -Property ActionTimeStamp -Descending | export-csv "$UserMyDocs\$($script:ExecutionTimeStamp)_AllAppAssignments_in_last_$($LookBackPeriod)_days.csv" -NoTypeInformation
$FilteredAssignments | sort -Property ActionTimeStamp -Descending | export-csv "$UserMyDocs\$($script:ExecutionTimeStamp)_AllAppAssignments_in_last_$($LookBackPeriod)_days_UTF8.csv" -NoTypeInformation -Encoding UTF8




############################################################################################################################################
# 6. Compilation of results into Excel with one worksheet per App                                                                          #
############################################################################################################################################

write-host "`r`n`r`nStep 6 : Compiling information into Excel" -foregroundcolor "yellow"

$XLFilePath = "$($script:ScriptPath)\$(get-date -f ""yyyy-MM-dd_HH-mm-ss"")_Okta_AppPermissionsReport.xlsx"
$objExcel = New-Object -ComObject Excel.Application
$objExcel.Visible = $True
$objExcel.DisplayAlerts = $False
$Workbook = $objExcel.Workbooks.Add()



$AppsWithNoMovementsInLastPeriod = @()
$NumberOfWorkSheets = 0


$AllAppInfo | ForEach {
	$CurrentApp = $_.AppLabel
	$AppActions = $FilteredAssignments | where {$_.AppLabel -eq $CurrentApp}

	If ($AppActions)
		{
		$SortedAppActions = $AppActions | sort -Property ActionTimeStamp -Descending
		write-host "`r`nList of log entries for App '$CurrentApp'" -foregroundcolor "yellow"
		$SortedAppActions | format-table -Property AppLabel, UserSMTP, ActionType, AppGroup, Operator, ActionTimeStamp -AutoSize
		
		$enc = [System.Text.Encoding]::UTF8
		$SortedAppActions | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | PowerShell -NoProfile -STA -Command {Add-Type -Assembly PresentationCore; $TextToClipboard = ($input | Out-String -Stream) -join "`r`n"; [Windows.Clipboard]::SetText($TextToClipboard)}
		
		$NumberOfWorkSheets++
		If ($NumberOfWorkSheets -gt $Workbook.WorkSheets.count)
			{
			write-host "I should now have $NumberOfWorkSheets worksheets while I have in fact there are $($Workbook.WorkSheets.count) worksheets. Adding worksheet!" -foregroundcolor "yellow"
			$WorkSheet = $Workbook.WorkSheets.add() 
			}
		Else
			{
			write-host "Not adding additional worksheet. `$NumberOfWorkSheets = >$NumberOfWorkSheets< and currently >$($Workbook.WorkSheets.count)< worksheets in the workbook!" -foregroundcolor "yellow"
			$WorkSheet = $Workbook.WorkSheets.item(1) 
			}
			
		
		$WorkSheet.Activate() | Out-Null
		
		If ($CurrentApp.length -le 31)
			{
			write-host "Setting sheet name '$CurrentApp'" -foregroundcolor "gray"
			$WorkSheet.Name = "$CurrentApp"
			}
		Else
			{
			$ListOfWorkSheets = @()
			ForEach ($objWorksheet in $Workbook.Worksheets) {$ListOfWorkSheets += $objWorksheet.Name}
			$PotentialSheetName = "$($CurrentApp.SubString(0,28))-00"
			While ($ListOfWorkSheets -contains $PotentialSheetName)
				{
				$PotentialSheetName = "$($CurrentApp.SubString(0,28))-$(Get-Random -Maximum 100)"
				ForEach ($objWorksheet in $Workbook.Worksheets) {$ListOfWorkSheets += $objWorksheet.Name}
				}
			write-host "Setting sheet name >=31 '$PotentialSheetName'" -foregroundcolor "gray"
			$WorkSheet.Name = "$PotentialSheetName"
			}
		

		If ($SortedAppActions.count)
			{
			write-host ">$($SortedAppActions.count)< entries to paste" -foregroundcolor "cyan"
			$range = $WorkSheet.Range("A1","J$($SortedAppActions.count + 1)")
			}
		Else
			{
			write-host ">1< entry to paste" -foregroundcolor "cyan"
			$range = $WorkSheet.Range("A1","J2")
			}
		
		$WorkSheet.Paste($range, $false)
		$Workbook.ActiveSheet.UsedRange.EntireColumn.AutoFit() | Out-Null
		$workSheet.Rows(1).EntireRow.Font.Bold = $true
		}
	Else
		{
		write-host "No log entries for App '$CurrentApp'" -foregroundcolor "yellow"
		$AppsWithNoMovementsInLastPeriod += $CurrentApp
		}
	}
	
$Workbook.BuiltinDocumentProperties("author").Value = "Cary GARVIN"
$Workbook.BuiltinDocumentProperties("comments").Value = "Report generated by the 'Audit-OktaAppPermissions.ps1' Script written by Cary GARVIN and downloaded from https://github.com/carygarvin/Audit-OktaAppPermissions.ps1"
$Workbook.BuiltinDocumentProperties("subject").Value = "Okta App Permission Events for $OktaOrgName during last $LookBackPeriod days"
	
$Workbook.SaveAs("$UserMyDocs\$($script:ExecutionTimeStamp)_AppPermissionsEvents_in_last_$($LookBackPeriod)_days.xlsx")
$Workbook.Close()
$objExcel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject([System.__ComObject]$objExcel) | Out-Null
Remove-Variable -Name objExcel 



	
	
write-host "Apps with no movements in last $LookBackPeriod days:" -foregroundcolor "cyan"
$AppsWithNoMovementsInLastPeriod
write-host ">$($AppsWithNoMovementsInLastPeriod.length)< applications with NO log entries in the last $LookBackPeriod days" -foregroundcolor "cyan"
write-host
write-host "A total of $($FilteredAssignments.length) log entries in the last $LookBackPeriod days have been recorded in Excel file '$($script:ExecutionTimeStamp)_AppPermissionsEvents_in_last_$($LookBackPeriod)_days.xlsx'." -foregroundcolor "green"


If ($error) {$error | out-file "$($script:ScriptPath)\$($script:ExecutionTimeStamp)_$($script:ScriptName)_errors.log"}
$error.clear()



# ***************************************************************************************************
# ***************************************************************************************************

