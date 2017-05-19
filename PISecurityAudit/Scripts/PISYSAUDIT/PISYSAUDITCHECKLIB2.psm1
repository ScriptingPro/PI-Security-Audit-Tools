# ***********************************************************************
# Validation library
# ***********************************************************************
# * Modulename:   PISYSAUDIT
# * Filename:     PISYSAUDITCHECKLIB2.psm1
# * Description:  Validation rules for PI Data Archive.
# *
# * Copyright 2016 OSIsoft, LLC
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
# * 
# *   <http://www.apache.org/licenses/LICENSE-2.0>
# * 
# * Unless required by applicable law or agreed to in writing, software
# * distributed under the License is distributed on an "AS IS" BASIS,
# * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# * See the License for the specific language governing permissions and
# * limitations under the License.
# *
# * Modifications copyright (C) <YYYY> <Name>, <Org>
# * <Description of modification>
# *
# ************************************************************************
# Version History:
# ------------------------------------------------------------------------
# Version 1.0.0.8 Initial release on OSIsoft Users Community.
# Authors:  Jim Davidson, Bryan Owen and Mathieu Hamel from OSIsoft.
#
# ************************************************************************

# ........................................................................
# Internal Functions
# ........................................................................
function GetFunctionName
{ return (Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name }

function NewAuditFunction
{
    Param($name, $level)
    $obj = New-Object pscustomobject
    $obj | Add-Member -MemberType NoteProperty -Name 'Name' -Value $name
    $obj | Add-Member -MemberType NoteProperty -Name 'Level' -Value $level
    return $obj
}

# ........................................................................
# Public Functions
# ........................................................................
function Get-PISysAudit_FunctionsFromLibrary2
{
<#  
.SYNOPSIS
Get functions from PI Data Archive library at or below the specified level.
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]
param(
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lvl")]
		[int]
		$AuditLevelInt = 1)

	# Form a list of all functions that need to be called to test
	# the PI Data Archive compliance.
	$listOfFunctions = @()
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPIServerDBSecurity_PIWorldReadAccess" 1 # AU20001
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPIAdminUsage"                         1 # AU20002
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPIServerVersion"                      1 # AU20003
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckEditDays"                             1 # AU20004
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckAutoTrustConfig"                      1 # AU20005
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckExpensiveQueryProtection"             1 # AU20006
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckExplicitLoginDisabled"                1 # AU20007
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPISPN"                                1 # AU20008
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPICollective"                         1 # AU20009
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckInstalledClientSoftware"              1 # AU20010
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPIFirewall"                           1 # AU20011
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckTransportSecurity"                    2 # AU20012
	$listOfFunctions += NewAuditFunction "Get-PISysAudit_CheckPIBackup"                             1 # AU20013
				
	# Return all items at or below the specified AuditLevelInt
	return $listOfFunctions | Where-Object Level -LE $AuditLevelInt
}

function Get-PISysAudit_CheckPIServerDBSecurity_PIWorldReadAccess
{
<#  
.SYNOPSIS
AU20001 - PI Data Archive Table Security Check
.DESCRIPTION
VALIDATION: examines the database security of the PI Data Archive and flags any 
ACLs that contain access for PIWorld as weak. <br/>
COMPLIANCE: remove PIWorld access from all database security ACLs.  Note that prior
removing PIWorld access, you need to evaluate which applications are relying on that 
access so that you can grant those applications access explicitly.  This check will
also pass if PIWorld is disabled globally.
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{				
		# Initialize objects.
		$securityWeaknessCounter = 0

		$IsPIWorldEnabled = $(Get-PIIdentity -Connection $global:PIDataArchiveConnection -Name PIWorld | Select-Object -ExpandProperty IsEnabled)
		
		if(-not($IsPIWorldEnabled))
		{
			$result = $true 
			$msg = "PIWorld is disabled globally."
		}
		else
		{
			$outputFileContent = Get-PIDatabaseSecurity -Connection $global:PIDataArchiveConnection `
											| Sort-Object -Property Tablename `
											| ForEach-Object {$_.Tablename + "^" + $_.Security} `
											| ForEach-Object {$_.Replace(")",") |").Trim("|")}
		
			# Validate rules	
	
			# Example of output.
			# PIAFLINK^piadmin: A(r,w) | piadmins: A(r,w) | PIWorld: A()
			# PIARCADMIN^piadmin: A(r,w) | piadmins: A(r,w) | PIWorld: A()
			# PIARCDATA^piadmin: A(r,w) | piadmins: A(r,w) | PIWorld: A()
			# ...

			# Read each line to find the one containing the token to replace.		
			foreach($line in $outputFileContent)
			{								
				# Skip line if not containing the delimiter.
				if($line.Contains("^"))
				{             		
					$securityWeakness = $false
					# Find the delimiter
					$position = $line.IndexOf("^")			
				
					# Specific Database
					$length  = $position
					$dbName = $line.SubString(0, $length)
				
					# Find the ACL
					$length  = $line.Length - $position - 1
					$acl = ($line.SubString($position + 1, $length)).ToLower()
				
					$process = $false
					# Perform the test on specific databases.
					Switch($dbName.ToLower())
					{
						"pibatch" { $process = $true }
						"pibatchlegacy" { $process = $true }
						"picampaign" { $process = $true }
						"pidbsec" { $process = $true }
						"pids" { $process = $true }
						"piheadingsets" { $process = $true }
						"pimodules" { $process = $true }
						"pitransferrecords" { $process = $true }
						"piuser" { $process = $true }
						default { $process = $false }
					}

					if($process)
					{                    
						# Remove piadmin: A(r,w) from the ACL
						if($acl.Contains("piworld: a(r,w)")) { $securityWeakness = $true }
						elseif($acl.Contains("piworld: a(r)")) { $securityWeakness = $true }
						elseif($acl.Contains("piworld: a(w)")) { $securityWeakness = $true }
					}
                		
					# Increment the counter if a weakness has been discovered.
					if($securityWeakness)
					{
						$securityWeaknessCounter++
						if($securityWeaknessCounter -eq 1)
						{ $msg = $dbName }
						else
						{ $msg = $msg + "; " + $dbName }
					}					
				}			
			}	
	
			# Check if the counter is 0 = compliant, 1 or more it is not compliant		
			if($securityWeaknessCounter -gt 0)
			{
				$result = $false
				if($securityWeaknessCounter -eq 1)
				{ $msg = "The following database presents a weakness: " + $msg + "." }
				else
				{ $msg = "The following databases present weaknesses: " + $msg + "." }
			}
			else 
			{ 
				$result = $true 
				$msg = "No databases identified that present a weakness."
			}	
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
		
	# Define the results in the audit table
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20001" `
										-ain "PI Data Archive Table Security" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" -Group3 "DB Security" `
										-Severity "Medium"																		
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPIAdminUsage
{
<#  
.SYNOPSIS
AU20002 - PI Admin Usage Check
.DESCRIPTION
VALIDATION: verifies that the piadmin PI User is not used in mappings or trusts.<br/>
COMPLIANCE: replace any trusts or mappings that use piadmin with a mapping or trust to a
PI Identity with appropriate privilege for the applications that will use it.  Will also
check if trusts and mappings to piadmin have been disabled globally.  This can be done by  
checking "User cannot be used in a Trust" and "User cannot be used in a Mapping" in the 
Properties menu for the piadmin PI User.  To access this menu open use the Identities, 
Users, & Groups plugin in PI SMT, navigate to the PI User tab, right click the piadmin 
entry and select Properties in the context menu.  
For more information, see "Security Best Practice" #4 in KB00833: <br/>
<a href="https://techsupport.osisoft.com/Troubleshooting/KB/KB00833 ">https://techsupport.osisoft.com/Troubleshooting/KB/KB00833 </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)
BEGIN {}
PROCESS
{
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$status = ""
	$policy = "Current policy: "
	$recommendation = ""
	$Severity = "Unknown"
	try
	{							
		# Initialize objects.
		$piadminTrustsDisabled = $false
		$piadminMappingsDisabled = $false	
		$result = $true						
													
		# Check if piadmin is blocked globally for mappings or trusts
		$piadminIdentity = $(Get-PIIdentity -Connection $global:PIDataArchiveConnection -Name "piadmin")
		$piadminTrustsDisabled = -not($piadminIdentity.AllowTrusts)
		$piadminMappingsDisabled = -not($piadminIdentity.AllowMappings)
		
		# Evaluate if authentication policy allows trusts 
		$trustsGlobalDisabled = $(Get-PITuningParameter -Connection $global:PIDataArchiveConnection -Name "Server_AuthenticationPolicy" | Select-Object -ExpandProperty Value) -eq 51

		# Get PI Trusts with the piadmin user. 
		$noncompliantTrusts = Get-PITrust -Connection $global:PIDataArchiveConnection `
									| Where-Object {$_.Identity -EQ 'piadmin' -and $_.IsEnabled} `
									| ForEach-Object {$_.Name}
		# Get PI Mappings with the piadmin user.
		$noncompliantMappings = Get-PIMapping -Connection $global:PIDataArchiveConnection `
									| Where-Object {$_.Identity -EQ 'piadmin' -and $_.IsEnabled} `
									| ForEach-Object {$_.PrincipalName}
															
		# Iterate through the returned results (if any) and append ; delimiter for the output message. 
		if($noncompliantTrusts){
			$noncompliantTrusts = $noncompliantTrusts | ForEach-Object {$_ + ';'}			
			if($trustsGlobalDisabled -or $piadminTrustsDisabled)
			{ 
				$recommendation += "Consider removing or disabling the following trusts which are no longer in effect: " + $noncompliantTrusts	+ ".`n" 
			}
			else
			{
				$result = $false	
				$status += "Trust(s) in effect using piadmin: " + $noncompliantTrusts	+ ".`n"

				if($noncompliantTrusts.Trim(';') -eq "!Proxy_127!")
				{ $Severity = "Medium" }
				else 
				{ $Severity = "High" }
			}
		}
		if($noncompliantMappings){
			$noncompliantMappings =	$noncompliantMappings | ForEach-Object {$_ + ';'}	
			if($piadminTrustsDisabled)
			{ $recommendation += "  Consider removing or disabling the following mappings which are no longer used: " + $noncompliantMappings	+ ".`n" }	
			else
			{
				$result = $false	
				$status += "Mappings(s) in effect using piadmin: " + $noncompliantMappings																												
				$Severity = "High"
			}
		}

		if($result){
			$status += "No effective Trust(s) or Mapping(s) identified with piadmin.  "
			
			# Check if noncompliant objects are still allowed.
			if(-not($piadminMappingsDisabled))
			{
				$result = $false 
				$Severity = "Low"
			}
			if(-not($piadminTrustsDisabled -or $trustsGlobalDisabled))
			{ 
				$result = $false
				$Severity = "Medium"
			} 
		}	
		
		# Record policy in entry to inform the user.
		if($trustsGlobalDisabled)
		{ $policy += " blocks trust authentication;" }
		else
		{ $policy += " allows trust authentication;" }
		
		if($piadminTrustsDisabled)
		{ $policy += " blocks trusts to piadmin;" }
		else 
		{ $policy += " allows trusts to piadmin;" }
		if($piadminMappingsDisabled)
		{ $policy += " blocks mappings to piadmin;" }
		else
		{ $policy += " allows mappings to piadmin;" }	

		$msg += $status + " " + $policy.Trim(';') + ". " + $recommendation
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	#......................................
	# Define the results in the audit table	
	#......................................				
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20002" `
										-ain "PI Admin Usage" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity $Severity																		
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPIServerVersion
{
<#  
.SYNOPSIS
AU20003 - PI Data Archive Version
.DESCRIPTION
VALIDATION: verifies that the PI Data Archive is using the most recent release. <br/>  
COMPLIANCE: upgrade the PI Data Archive to the latest version, PI Data Archive 
2016 R2 (3.4.405.1198).  For more information, see the "Upgrade a PI Data Archive Server" 
section of the PI Data Archive Installation and Upgrade Guide, Live Library: <br/>
<a href="https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-0BDEB1F5-C72F-4865-91F7-F3D38A2975BD ">https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-0BDEB1F5-C72F-4865-91F7-F3D38A2975BD </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)
BEGIN {}
PROCESS
{
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$Severity = "Unknown"
	try
	{
		# Update these for subsequent releases
		$latestVersion = '3.4.405.1198'
		$readable = '2016 R2'

		$installationVersion = $global:PIDataArchiveConnection.ServerVersion.ToString()
		$versionInt = [int]($installationVersion -replace '\.', '')
		$latestInt = [int]($latestVersion -replace '\.', '')
		
		if($versionInt -lt $latestInt)
		{
			$result = $false
			$Severity = 'High'
			$msg = "Upgrading to PI Data Archive $readable ($latestVersion) is recommended."
		}
		else
		{
			$result = $true
			$Severity = 'High'
			$msg = "PI Data Archive version is compliant."
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}	
	
	# Define the results in the audit table
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20003" `
										-ain "PI Data Archive Version" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity $Severity									
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckEditDays
{
<#  
.SYNOPSIS
AU20004 - Check Edit Days
.DESCRIPTION
VALIDATION: verified that the Edit Days tuning parameter is set. <br/>
COMPLIANCE: set to a value greater than zero.  EditDays defines the number of past 
days where events can be modified in the Snapshot or Archive databases. A zero value means 
no time check is done.  For instructions to set EditDays, see "Modify the EditDays tuning 
parameter" section in the PI Data Archive System Management Guide:<br/>
<a href="https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-0865CC31-BF8C-4347-B717-15071ED51399 ">https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-0865CC31-BF8C-4347-B717-15071ED51399 </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)
BEGIN {}
PROCESS
{					
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$EditDays = $null
	try
	{

		$EditDays = Get-PITuningParameter -Connection $global:PIDataArchiveConnection -Name "EditDays" | Select-Object -ExpandProperty Value

		# The default value is set to 0 which is not compliant.
		if($null -eq $EditDays) 
		{ 
			$result = $false
			$msg = "EditDays not specified, using non-compliant default of 0."
		}
		else 
		{
			if($EditDays -eq 0) 
			{ 
				$result = $false 
				$msg = "EditDays using non-compliant value of 0."
			}
			else 
			{ 
				$result = $true 
				$msg = "EditDays specified as a non-zero value."
			}	
		}			
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
			
	# Define the results in the audit table												
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20004" `
										-ain "Edit Days" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity "High"												
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckAutoTrustConfig
{
<#  
.SYNOPSIS
AU20005 - Auto Trust Configuration
.DESCRIPTION
VALIDATION: verifies that the autotrustconfig tuning parameter is set to create 
either no trusts or a trust for the loopback automatically (127.0.0.1). <br/>
COMPLIANCE: set the autotrustconfig tuning parameter to a value of 0 (do not 
automatically create any PI Trust entries) or 1 (create the trust entry for the loopback 
IP address 127.0.0.1 only). 
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)
BEGIN {}
PROCESS
{					
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$AutoTrustConfig = $null
	try
	{
		$AutoTrustConfig = Get-PITuningParameter -Connection $global:PIDataArchiveConnection -Name "AutoTrustConfig" | Select-Object -ExpandProperty Value				
				
		# Defaults to 1 if not specified.
		if($null -eq $AutoTrustConfig)
		{ $AutoTrustConfig = 1 }
		
		# Values for AutoTrustConfig Tuning Parameter
		# 0 = NONE, 1 = Loopback, 2 = Localhost, 4 = IPaddr, 8 = Hostname, 16 = Fully Qualified Domain Name (FQDN)
		# 17 = LoopBack + FQDN
		# 127 = v3.4.370 Compatible, 255 = All

		if($AutoTrustConfig -eq 0) 
		{ $description = "Does not automatically create any PI Trust entries." }
		else
		{	
			$description = "Creates trust entries for: "
			switch ($AutoTrustConfig)
			{
				1   { $description += "127.0.0.1"; break; }
				2   { $description += "localhost"; break; }
				4   { $description += "IP address"; break; }
				8   { $description += "hostname"; break; }
				16  { $description += "FQDN"; break; }
				17  { $description += "127.0.0.1 and FQDN"; break; }
				127 { $description += "v3.4.370 Compatibility"; break; }
				255 { $description += "127.0.0.1, localhost, IP address, host and FQDN (All)"; break; }
			
				default {$description += "Unknown configuration" }
			}
		}

		if($AutoTrustConfig -le 1) 
		{ 
			$result = $true 
			$msg = "Tuning parameter compliant: {0}"
		}
		else 
		{ 
			$result = $false
			$msg = "Tuning parameter not compliant: {0}" 
		}		
		$msg = [string]::Format($msg, $description)									
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
			
	# Define the results in the audit table			
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20005" `
										-ain "Auto Trust Configuration" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" -Group3 "Authentication" `
										-Severity "High"	
										
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckExpensiveQueryProtection
{
<#  
.SYNOPSIS
AU20006 - Expensive Query Protection Check
.DESCRIPTION
VALIDATION: verify that the PI Data Archive has protection against expensive queries. <br/>
COMPLIANCE: set the archive_maxqueryexecutionsec tuning parameter to a value between 60 
and 300.  For more information on this parameter and other that can protect against expensive 
queries, see the knowledgebase article 3224OSI8 <br/>
<a href="https://techsupport.osisoft.com/Troubleshooting/KB/3224OSI8">https://techsupport.osisoft.com/Troubleshooting/KB/3224OSI8  </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)
BEGIN {}
PROCESS
{
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$Archive_MaxQueryExecutionSec = $null
	try
	{														
		
		# Validate rules
		
		# Example of output.
		# if the file is empty, it means it is configure to default value of 0 if the piarchss
		# is prior to (KB 3224OSI8) 3.4.390.x, otherwise it is set to 260.		
		# otherwise the file would contain Archive_MaxQueryExecutionSec,<value>
										
		# Get installation version
		$installationVersion = $global:PIDataArchiveConnection.ServerVersion.ToString()
		# Get tuning parameter value 
		$temp = Get-PITuningParameter -Connection $global:PIDataArchiveConnection -Name "Archive_MaxQueryExecutionSec" | Select-Object -ExpandProperty Value
		# Using temp because otherwise null (Default) will be coerced to 0 when int16 conversion is applied.
		if($null -ne $temp){[int16]$Archive_MaxQueryExecutionSec = $temp}
		
		$installVersionTokens = $installationVersion.Split(".")
		# Form an integer value with all the version tokens.
		[string]$temp = $InstallVersionTokens[0] + $installVersionTokens[1] + $installVersionTokens[2] + $installVersionTokens[3]
		$installVersionInt64 = [Convert]::ToInt64($temp)		
								
		# Default value for PI Data Archive prior to 3.4.390.16 was 0
		# Check if the timeout setting is between 60 and 300.
		if(($null -eq $Archive_MaxQueryExecutionSec) -and ($installVersionInt64 -lt 3439016)) 
		{ 
			$result = $false 
			$msg = "Using the non-compliant default of 0."
		}
		elseif(($null -eq $Archive_MaxQueryExecutionSec) -and ($installVersionInt64 -ge 3439016)) 
		{ 
			$result = $true 
			$msg = "Using the compliant default of 260."
		}				
		elseif(($null -ne $Archive_MaxQueryExecutionSec) -and ($Archive_MaxQueryExecutionSec -ge 60) -and ($Archive_MaxQueryExecutionSec -le 300)) 
		{ 
			$result = $true 
			$msg = "Using a compliant value of {0}."
			$msg = [string]::Format($msg, $Archive_MaxQueryExecutionSec)
		}
		else 
		{ 
			$result = $false 
			$msg = "Using a non-compliant value of {0}."
			$msg = [string]::Format($msg, $Archive_MaxQueryExecutionSec)
		}	
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	#......................................
	# Define the results in the audit table	
	#......................................				
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20006" `
										-ain "Expensive Query Protection" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" -Group3 "PI Archive Subsystem" `
										-Severity "High"																		
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckExplicitLoginDisabled
{
<#  
.SYNOPSIS
AU20007 - Check if the explicit login is disabled
.DESCRIPTION
VALIDATION: verifies that explicit login is disabled as an authentication protocol. <br/>  
COMPLIANCE: set the tuning parameter Server_AuthenticationPolicy to a value greater than 3.  
This is equivalent to the third notch, "Disable explicit login", or higher on the Security 
Settings plugin in PI SMT.  For more information, see "Security Best Practice #2" and "Security 
Best Practice #3" in KB00833. <br/>
<a href="https://techsupport.osisoft.com/Troubleshooting/KB/KB00833">https://techsupport.osisoft.com/Troubleshooting/KB/KB00833 </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$Severity = "Unknown"
	$piadminExplicitLoginDisabled = $false
	try
	{		
		
		$Server_AuthenticationPolicy = Get-PITuningParameter -Connection $global:PIDataArchiveConnection -Name "Server_AuthenticationPolicy" | Select-Object -ExpandProperty Value
		
		# A null Server_AuthenticationPolicy is treated the same as a value of 0.
		if($null -eq $Server_AuthenticationPolicy)
		{ $Server_AuthenticationPolicy = 0 }

		switch ($Server_AuthenticationPolicy)
				{
					0   { $description = "All authentication options enabled. "; break; }
					2   { $description = "Explicit logins for users with blank passwords disabled. "; break; }
					3   { $description = "Explicit logins disabled. "; break; }
					19   { $description = "Explicit logins and SDK Trusts disabled. "; break; }
					51   { $description = "All trusts and explicit login disabled. "; break; }
			
					default {$description = "Unrecognized configuration" }
				}
		
		$msgPolicy =""
		if($Server_AuthenticationPolicy -lt 3)
		{
			$result = $false
			$msgPolicy = "Using non-compliant policy:"
			$Severity = "High"
			
			$piadminExplicitLoginDisabled = -not($(Get-PIIdentity -Connection $global:PIDataArchiveConnection -Name "piadmin").AllowExplicitLogin)
			
			if($piadminExplicitLoginDisabled)
			{
				$description += "Explicit login disabled for piadmin."
				$Severity = "High"
			}
			else
			{
				$description += "Explicit login allowed for piadmin."
				$Severity = "High"
			}
		}
		else
		{
			$result = $true
			$msgPolicy = "Using compliant policy:"
		}
		$msg = [string]::Format("{0} {1}", $msgPolicy,$description)

	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20007" `
										-ain "Explicit login disabled" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity $Severity								
}

END {}
#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPISPN
{
<#  
.SYNOPSIS
AU20008 - Check PI Server SPN
.DESCRIPTION
VALIDATION: Checks PI Data Archive SPN assignment.<br/>
COMPLIANCE: PI Data Archive SPNs exist and are assigned to the account running pinetmgr. 
Presently only local system is supported.  Correct SPN assignment makes Kerberos 
Authentication possible.  For more information, see "PI and Kerberos authentication" in 
the PI Live Library. <br/>
<a href="https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-531FFEC4-9BBB-4CA0-9CE7-7434B21EA06D">https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v7/GUID-531FFEC4-9BBB-4CA0-9CE7-7434B21EA06D </a>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{		
		$serviceType = "piserver"
		$serviceName = "pinetmgr"

		$result = Invoke-PISysAudit_SPN -svctype $serviceType -svcname $serviceName -lc $LocalComputer -rcn $RemoteComputerName -dbgl $DBGLevel

		If ($result) 
		{ 
			$msg = "The Service Principal Name exists and it is assigned to the correct Service Account."
		} 
		Else 
		{ 
			$msg = "The Service Principal Name does NOT exist or is NOT assigned to the correct Service Account."
		}	
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20008" `
										-ain "PI Data Archive SPN Check" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive"`
										-Severity "Medium"								
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPICollective
{
<#  
.SYNOPSIS
AU20009 - PI Collective
.DESCRIPTION
VALIDATION: Checks if the PI Data Archive is a member of a High Availability Collective. <br/>
COMPLIANCE: Ensure that the PI Data Archive is a member of a PI Collective to allow for 
	High Availability. <br/>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{	
		$serviceType = $global:PIDataArchiveConnection.Service.Type.ToString()
		if ($serviceType.ToLower() -eq 'collective')
		{
			$result = $true
			$msg = "PI Data Archive is a member of PI Collective '{0}'"
			$msg = [string]::Format($msg, $global:PIDataArchiveConnection.Service.Name)
		}
		else
		{
			$msg = "PI Data Archive is not a member of a PI Collective"
			$result = $false
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20009" `
										-ain "PI Collective" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive"`
										-Severity "Medium"								
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckInstalledClientSoftware
{
<#  
.SYNOPSIS
AU20010 - No Client Software
.DESCRIPTION
VALIDATION: Checks if common client software is installed on the PI Data Archive machine. <br/>
COMPLIANCE: Ensure the PI Processbookt and Microsoft Office are not installed
	on the PI Data Archive machine, as these programs should be used on client
	machines only. <br/>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{		
		$installedPrograms = Get-PISysAudit_InstalledComponents -lc $LocalComputer -rcn $RemoteComputerName	-dbgl $DBGLevel
		$procBook = $installedPrograms | Where-Object DisplayName -Like 'PI Processbook*'
		$msOffice = $installedPrograms | Where-Object DisplayName -Like 'Microsoft Office*'
		if($procBook -and $msOffice)
		{
			$result = $false
			$msg = "PI Processbook and MS Office installed on PI Data Archive machine."
		}
		elseif($procBook)
		{
			$result = $false
			$msg = "PI Processbook installed on PI Data Archive machine."
		}
		elseif($msOffice)
		{
			$result = $false
			$msg = "Microsoft Office installed on PI Data Archive machine."
		}
		else
		{
			$result = $true
			$msg = "Did not detect client software on PI Data Archive machine."
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20010" `
										-ain "Client Software" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity "Medium"
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPIFirewall
{
<#  
.SYNOPSIS
AU20011 - PI Firewall Used
.DESCRIPTION
VALIDATION: Checks that PI Firewall is used. <br/>
COMPLIANCE: The default PI Firewall rule of "Allow *.*.*.*" should 
	be removed and replaced with specific IPs or subnets that may 
	connect to the PI Data Archive. For more information on PI Firewall,
	see <a href="https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v8/GUID-14FC1696-D64B-49B0-96ED-6EEF3CE92DCB ">https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v8/GUID-14FC1696-D64B-49B0-96ED-6EEF3CE92DCB </a> <br/>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{		
		$rules = Get-PIFirewall -Connection $global:PIDataArchiveConnection
		if($rules)
		{
			# Get-PIFirewall returns 'Unknown' if rule does not fit text "Allow" or "Disallow" 
			#    exactly, case-sensitive. Include these in our search since a rule of 
			#    "*.*.*.* Unknown" must be Allow or else all connections are being blocked.
			$allowRules = $rules | Where-Object { $_.Access -eq 'Allow' -or $_.Access -eq 'Unknown' }
			$defaultRule = $allowRules | Where-Object Hostmask -EQ '*.*.*.*'
			if($defaultRule)
			{
				$result = $false
				$msg = "Detected Allow rule for *.*.*.* in PI Firewall."
			}
			else
			{
				$result = $true
				$msg = "Allow rule for *.*.*.* has been removed in PI Firewall."
			}
		}
		else
		{
			$result = "N/A"
			$msg = "Unable to load PI Firewall or no rules returned."
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20011" `
										-ain "PI Firewall Used" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity "Medium"								
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckTransportSecurity
{
<#  
.SYNOPSIS
AU20012 - Transport Security Used
.DESCRIPTION
VALIDATION: All connections are using transport security.
COMPLIANCE: All connections should have transport security enabled. To
	accomplish this, the application must connect with WIS, the PI Data 
	Archive must be at PI Data Archive 2015 or later and the client 
	application must be of a supported version:
	+ PI API 2016 for Windows Integrated Security
	+ PI SDK 1.3.6 or higher
	+ PI AF SDK (all versions)
	For more information, see <a href="https://techsupport.osisoft.com/Troubleshooting/KB/KB01092">https://techsupport.osisoft.com/Troubleshooting/KB/KB01092</a> <br/>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$Severity = "Unknown"
	try
	{		
		# Check if the PI Data Archive version supports transport security before pulling connection stats.
		$version = $global:PIDataArchiveConnection.ServerVersion
		if($version.Major -ge 3 -and $version.Minor -ge 4 -and $version.Build -ge 395)
		{
			$rawPIConnectionStats = Get-PIConnectionStatistics -Connection $global:PIDataArchiveConnection
			$processedPIConnectionStats = Get-PISysAudit_ProcessedPIConnectionStatistics -PIDataArchiveConnection $global:PIDataArchiveConnection `
																					-PIConnectionStats $rawPIConnectionStats -ProtocolFilter Any `
																					-RemoteOnly $true -SuccessOnly $true -CheckTransportSecurity $true `
																					-DBGLevel $DBGLevel
			if($null -ne $processedPIConnectionStats)
			{
				$countSecured = $processedPIConnectionStats.SecureStatus | Where-Object { $_ -eq 'Secure' } | Measure-Object | Select-object -ExpandProperty count	
				if($countSecured -eq $processedPIConnectionStats.Count)	
				{
					$result = $true
					$msg = "All remote connections to the PI Data Archive leverage transport security."
				}
				else # Not all connections are using transport security, assess scope.
				{
					$result = $false
					$countWindows=0; $countTrust=0; $countExlplicitLogin=0

					$processedPIConnectionStats.AuthenticationProtocol | Foreach-Object {
																							switch($_)
																							{
																								'Windows' {$countWindows++;break}
																								'Trust' {$countTrust++;break}
																								'ExplicitLogin' {$countExlplicitLogin++;break}
																							} 
																						} 
					[float]$percentSecured = 100*($countSecured/$processedPIConnectionStats.Count)
					if($countWindows -eq $processedPIConnectionStats.Count)
					{
						$Severity = 'Medium'
						$msg = "Not all remote connections leveraging transport security {0:N1}.  All remote connections leveraging Windows authentication." -f $percentSecured
					}
					else
					{
						[float]$percentWindows = 100*($countWindows/$processedPIConnectionStats.Count)
						[float]$percentTrust = 100*($countTrust/$processedPIConnectionStats.Count)
						[float]$percentExplicitLogin = 100*($countExplicitLogin/$processedPIConnectionStats.Count)
						$Severity = 'High'
						$msg = "Legacy protocols in use.  Authentication protocol distribution: Windows ({0:N1} %), Trust ({1:N1} %), ExplicitLogin ({2:N1} %)" -f $percentWindows, $percentTrust, $percentExplicitLogin
					}
				}
			}
			else
			{
				$msg = "No remote connections were found."					
				Write-PISysAudit_LogMessage $msg "Warning" $fn								
				$result = "N/A"
			}
		}
		else
		{
			$result = $false
			$msg = 'PI Data Archive version does not support transport security.'
			$Severity = 'High'
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20012" `
										-ain "Transport Security Used" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity $Severity								
}

END {}

#***************************
#End of exported function
#***************************
}

function Get-PISysAudit_CheckPIBackup
{
<#  
.SYNOPSIS
AU20013 - PI Backup Configured
.DESCRIPTION
VALIDATION: Ensures that PI Backups are configured and current. <br/>
COMPLIANCE: Configure PI Backup to back up PI Data Archive configuration
	and data daily. It is best practice to back up to a local disk on the 
	PI Data Archive machine, then copy the backup to an off-machine location. 
	For more information, see <a href="https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v8/GUID-8F56FDA9-505C-4868-8483-E51435E80A61">https://livelibrary.osisoft.com/LiveLibrary/content/en/server-v8/GUID-8F56FDA9-505C-4868-8483-E51435E80A61</a><br/>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	$severity = 'N/A'
	try
	{		
		$con = $global:PIDataArchiveConnection
		$now = Get-Date
		$lastBackup = Get-PIBackupReport -Connection $con -LastReport -ErrorAction SilentlyContinue
		$archiveList = Get-PIArchiveFileInfo -Connection $con -ErrorAction SilentlyContinue

		# Check how recent the latest backup is
		if($null -ne $lastBackup)
		{
			$backupSummary = $lastBackup.Summary
			if($backupSummary.StatusMessage -eq '[0] Success')
			{
				if($backupSummary.BackupStart -gt $now.AddDays(-1))
				{
					# Good recent backup found, check file coverage
					if($null -ne $archiveList)
					{
						$arcsNotBackedUp = $archiveList | Where-Object { $null -eq $_.LastBackupTime }
						if($arcsNotBackedUp.Count -eq 0)
						{
							$result = $true
							$msg = "Good backup found, all archives backed up."
						}
						else
						{
							# Not all archives backed up, Medium warning
							$result = $false
							$msg = "Good backup found, but $($arcsNotBackedUp.Count) archive(s) not backed up."
							$severity = 'Medium'
						}
					}
					else
					{
						# Unable to get archive list, cannot fully assess severity. Default to Medium
						$result = $false
						$msg = "Good backup found, but could not confirm backup coverage of archive files."
						$severity = 'Medium'
					}
				}
				elseif($backupSummary.BackupStart -gt $now.AddDays(-7))
				{
					# Last backup older than a day but less than a week, Medium warning
					$result = $false
					$lastBackupTime = $backupSummary.BackupStart.ToString("dd-MMM-yyyy HH:mm:ss")
					$msg = "Last backup is more than a day ago, at $lastBackupTime"
					$severity = 'Medium'
				}
				else
				{
					# Last backup older than a week, High warning
					$result = $false
					$lastBackupTime = $backupSummary.BackupStart.ToString("dd-MMM-yyyy HH:mm:ss")
					$msg = "Last backup performed more than a week ago, at $lastBackupTime"
					$severity = 'High'
				}
			}
			else
			{
				# Last backup returned an error, High warning
				$result = $false
				$msg = "Last PI Backup returned error $($backupSummary.StatusMessage)"
				$severity = 'High'
			}

		}
		else
		{
			# No backup found, High warning
			$result = $false
			$msg = "No PI Backup configuration found."
			$severity = 'High'
		}
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU20013" `
										-ain "PI Backup Configured" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "PI System" -Group2 "PI Data Archive" `
										-Severity $severity
}

END {}

#***************************
#End of exported function
#***************************
}


# ........................................................................
# Add your cmdlet after this section. Don't forget to add an intruction
# to export them at the bottom of this script.
# ........................................................................
function Get-PISysAudit_TemplateAU2xxxx
{
<#  
.SYNOPSIS
AU2xxxx - <Name>
.DESCRIPTION
VALIDATION: <Enter what the verification checks>
COMPLIANCE: <Enter what it needs to be compliant>
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess=$false)]     
param(							
		[parameter(Mandatory=$true, Position=0, ParameterSetName = "Default")]
		[alias("at")]
		[System.Collections.HashTable]
		$AuditTable,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("lc")]
		[boolean]
		$LocalComputer = $true,
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("rcn")]
		[string]
		$RemoteComputerName = "",
		[parameter(Mandatory=$false, ParameterSetName = "Default")]
		[alias("dbgl")]
		[int]
		$DBGLevel = 0)		
BEGIN {}
PROCESS
{		
	# Get and store the function Name.
	$fn = GetFunctionName
	$msg = ""
	try
	{		
		# Enter routine.			
	}
	catch
	{
		# Return the error message.
		$msg = "A problem occurred during the processing of the validation check."					
		Write-PISysAudit_LogMessage $msg "Error" $fn -eo $_									
		$result = "N/A"
	}
	
	# Define the results in the audit table	
	$AuditTable = New-PISysAuditObject -lc $LocalComputer -rcn $RemoteComputerName `
										-at $AuditTable "AU2xxxx" `
										-ain "<Name>" -aiv $result `
										-aif $fn -msg $msg `
										-Group1 "<Category 1>" -Group2 "<Category 2>" -Group3 "<Category 3>" -Group4 "<Category 4>"`
										-Severity "<Severity>"								
}

END {}

#***************************
#End of exported function
#***************************
}

# ........................................................................
# Export Module Member
# ........................................................................
# <Do not remove>
Export-ModuleMember Get-PISysAudit_FunctionsFromLibrary2
Export-ModuleMember Get-PISysAudit_CheckPIServerDBSecurity_PIWorldReadAccess
Export-ModuleMember Get-PISysAudit_CheckPIAdminUsage
Export-ModuleMember Get-PISysAudit_CheckPIServerVersion
Export-ModuleMember Get-PISysAudit_CheckEditDays
Export-ModuleMember Get-PISysAudit_CheckAutoTrustConfig
Export-ModuleMember Get-PISysAudit_CheckExpensiveQueryProtection
Export-ModuleMember Get-PISysAudit_CheckExplicitLoginDisabled
Export-ModuleMember Get-PISysAudit_CheckPISPN
Export-ModuleMember Get-PISysAudit_CheckPICollective
Export-ModuleMember Get-PISysAudit_CheckInstalledClientSoftware
Export-ModuleMember Get-PISysAudit_CheckPIFirewall
Export-ModuleMember Get-PISysAudit_CheckTransportSecurity
Export-ModuleMember Get-PISysAudit_CheckPIBackup
# </Do not remove>

# ........................................................................
# Add your new Export-ModuleMember instruction after this section.
# Replace the Get-PISysAudit_TemplateAU2xxxx with the name of your
# function.
# ........................................................................
# Export-ModuleMember Get-PISysAudit_TemplateAU2xxxx