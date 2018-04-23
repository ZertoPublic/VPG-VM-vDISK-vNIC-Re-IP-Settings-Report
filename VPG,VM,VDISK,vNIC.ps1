#requires -Version 5
#requires -RunAsAdministrator
<#
.SYNOPSIS
   This script automates the collection of settings configured for VMs within a VPG. 
.DESCRIPTION

.EXAMPLE
   Examples of script execution
.VERSION 
   Applicable versions of Zerto Products script has been tested on.  Unless specified, all scripts in repository will be 5.0u3 and later.  If you have tested the script on multiple
   versions of the Zerto product, specify them here.  If this script is for a specific version or previous version of a Zerto product, note that here and specify that version 
   in the script filename.  If possible, note the changes required for that specific version.  
.LEGAL
   Legal Disclaimer:

----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
#>
#------------------------------------------------------------------------------#
# Declare variables
#------------------------------------------------------------------------------#
#Examples of variables:

##########################################################################################################################
#Any section containing a "GOES HERE" should be replaced and populated with your site information for the script to work.#  
##########################################################################################################################

################################################
################################################
# Configure the variables below
################################################
$ExportDataDir = "EnterExportDirectory"
$ZertoServer = "Enter ZVM IP"
$ZertoPort = "9669"
$ZertoUser = "Enter ZVM User"
$ZertoPassword = "Enter ZVM Password"
########################################################################################################################
# Nothing to configure below this line - Starting the main function of the script
########################################################################################################################
################################################
# Setting certificate exception to prevent authentication issues to the ZVM
################################################
add-type @"
 using System.Net;
 using System.Security.Cryptography.X509Certificates;
 public class TrustAllCertsPolicy : ICertificatePolicy {
 public bool CheckValidationResult(
 ServicePoint srvPoint, X509Certificate certificate,
 WebRequest request, int certificateProblem) {
 return true;
 }
 }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
################################################
# Building Zerto API string and invoking API
################################################
$baseURL = "https://" + $ZertoServer + ":"+$ZertoPort+"/v1/"
# Authenticating with Zerto APIs
$xZertoSessionURL = $baseURL + "session/add"
$authInfo = ("{0}:{1}" -f $ZertoUser,$ZertoPassword)
$authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
$authInfo = [System.Convert]::ToBase64String($authInfo)
$headers = @{Authorization=("Basic {0}" -f $authInfo)}
$sessionBody = '{"AuthenticationMethod": "1"}'
$TypeJSON = "application/json"
$TypeXML = "application/xml"
Try
{
$xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURL -Headers $headers -Method POST -Body $sessionBody -ContentType $TypeJSON
}
Catch {
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
# Extracting x-zerto-session from the response, and adding it to the actual API
$xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
$zertoSessionHeader_json = @{"Accept"="application/json"
"x-zerto-session"=$xZertoSession}

$zertoSessionHeader_xml = @{"Accept"="application/xml"
"x-zerto-session"=$xZertoSession}


################################################
# Creating Arrays for populating ZVM info from the API
################################################
$VPGArray = @()
$VMArray = @()
$VMVolumeArray = @()
$VMNICArray = @()
################################################
# Creating VPGArray, VMArray, VMVolumeArray, VMNICArray
################################################
# URL to create VPG settings
$CreateVPGURL = $baseURL+"vpgSettings"
# Build List of VPGs
$vpgListApiUrl = $baseURL+"vpgs"
$vpgList = Invoke-RestMethod -Uri $vpgListApiUrl -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
# Build List of VMs
$vmListApiUrl = $baseURL+"vms"
$vmList = Invoke-RestMethod -Uri $vmListApiUrl -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
# Select IDs from the API array
$zertoprotectiongrouparray = $vpgList.ArrayOfVpgApi.VpgApi | Select-Object OrganizationName,vpgname,vmscount,vpgidentifier
$vmListarray = $vmList.ArrayOfVmApi.VmApi | select-object *
################################################
# Starting for each VPG action of collecting ZVM VPG data
################################################
foreach ($VPGLine in $zertoprotectiongrouparray)
{
$VPGidentifier = $VPGLine.vpgidentifier
$VPGOrganization = $VPGLine.OrganizationName
$VPGVMCount = $VPGLine.VmsCount
$JSON =
"{
""VpgIdentifier"":""$VPGidentifier""
}"
################################################
# Posting the VPG JSON Request to the API
################################################
Try
{
$VPGSettingsIdentifier = Invoke-RestMethod -Method Post -Uri $CreateVPGURL -Body $JSON -ContentType $TypeJSON -Headers $zertoSessionHeader_json
$ValidVPGSettingsIdentifier = $true
}
Catch {
$ValidVPGSettingsIdentifier = $false
}
################################################
# Getting VPG settings from API
################################################
# Skipping if unable to obtain valid VPG setting identifier
if ($ValidVPGSettingsIdentifier -eq $true)
{
$VPGSettingsURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier
$VPGSettings = Invoke-RestMethod -Uri $VPGSettingsURL -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting recovery site ID (needed anyway for network settings)
$VPGRecoverySiteIdentifier = $VPGSettings.Basic.RecoverySiteIdentifier
# Getting site info
$VISitesURL = $baseURL+"virtualizationsites"
$VISitesCMD = Invoke-RestMethod -Uri $VISitesURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting network info
$VINetworksURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/networks"
$VINetworksCMD = Invoke-RestMethod -Uri $VINetworksURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting datastore info
$VIDatastoresURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/datastores"
$VIDatastoresCMD = Invoke-RestMethod -Uri $VIDatastoresURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting datastore cluster info
$VIDatastoreClustersURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/datastoreclusters"
$VIDatastoreClustersCMD = Invoke-RestMethod -Uri $VIDatastoreClustersURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting folder info
$VIFoldersURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/folders"
$VIFoldersCMD = Invoke-RestMethod -Uri $VIFoldersURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON_json
# Getting cluster info
$VIClustersURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/hostclusters"
$VIClustersCMD = Invoke-RestMethod -Uri $VIClustersURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting host info
$VIHostsURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/hosts"
$VIHostsCMD = Invoke-RestMethod -Uri $VIHostsURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting resource pool info
$VIResourcePoolsURL = $baseURL+"virtualizationsites/$VPGRecoverySiteIdentifier/resourcepools"
$VIResourcePoolsCMD = Invoke-RestMethod -Uri $VIResourcePoolsURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting all VPG Settings
$VPGJournalHistoryInHours = $VPGSettings.Basic.JournalHistoryInHours
$VPGName = $VPGSettings.Basic.Name
$VPGPriortiy = $VPGSettings.Basic.Priority
$VPGProtectedSiteIdentifier = $VPGSettings.Basic.ProtectedSiteIdentifier
$VPGRpoInSeconds = $VPGSettings.Basic.RpoInSeconds
$VPGServiceProfileIdentifier = $VPGSettings.Basic.ServiceProfileIdentifier
$VPGTestIntervalInMinutes = $VPGSettings.Basic.TestIntervalInMinutes
$VPGUseWanCompression = $VPGSettings.Basic.UseWanCompression
$VPGZorgIdentifier = $VPGSettings.Basic.ZorgIdentifier
# Getting Boot Group IDs
$VPGBootGroups = $VPGSettings.BootGroups.BootGroups
$VPGBootGroupCount = $VPGSettings.BootGroups.BootGroups.Count
$VPGBootGroupNames = $VPGSettings.BootGroups.BootGroups.Name
$VPGBootGroupDelays = $VPGSettings.BootGroups.BootGroups.BootDelayInSeconds
$VPGBootGroupIdentifiers = $VPGSettings.BootGroups.BootGroups.BootGroupIdentifier
# Getting Journal info
$VPGJournalDatastoreClusterIdentifier = $VPGSettings.Journal.DatastoreClusterIdentifier
$VPGJournalDatastoreIdentifier = $VPGSettings.Journal.DatastoreIdentifier
$VPGJournalHardLimitInMB = $VPGSettings.Journal.Limitation.HardLimitInMB
$VPGJournalHardLimitInPercent = $VPGSettings.Journal.Limitation.HardLimitInPercent
$VPGJournalWarningThresholdInMB = $VPGSettings.Journal.Limitation.WarningThresholdInMB
$VPGJournalWarningThresholdInPercent = $VPGSettings.Journal.Limitation.WarningThresholdInPercent
# Getting Network IDs
$VPGFailoverNetworkID = $VPGSettings.Networks.Failover.Hypervisor.DefaultNetworkIdentifier
$VPGFailoverTestNetworkID = $VPGSettings.Networks.FailoverTest.Hypervisor.DefaultNetworkIdentifier
# Getting recovery info
$VPGDefaultDatastoreIdentifier = $VPGSettings.Recovery.DefaultDatastoreIdentifier
$VPGDefaultFolderIdentifier = $VPGSettings.Recovery.DefaultFolderIdentifier
$VPGDefaultHostClusterIdentifier = $VPGSettings.Recovery.DefaultHostClusterIdentifier
$VPGDefaultHostIdentifier = $VPGSettings.Recovery.DefaultHostIdentifier
$VPGResourcePoolIdentifier = $VPGSettings.Recovery.ResourcePoolIdentifier
# Getting scripting info
$VPGScriptingPreRecovery = $VPGSettings.Scripting.PreRecovery
$VPGScriptingPostRecovery = $VPGSettings.Scripting.PostRecovery
# Getting VM IDs in VPG
$VPGVMIdentifiers = $VPGSettings.VMs.VmIdentifier
################################################
# Translating Zerto IDs from VPG settings to friendly vSphere names
################################################
# Getting site names
$VPGProtectedSiteName = $VISitesCMD | Where-Object {$_.SiteIdentifier -eq $VPGProtectedSiteIdentifier} | select -ExpandProperty VirtualizationSiteName
$VPGRecoverySiteName = $VISitesCMD | Where-Object {$_.SiteIdentifier -eq $VPGRecoverySiteIdentifier} | select -ExpandProperty VirtualizationSiteName
# Getting network names
$VPGFailoverNetworkName = $VINetworksCMD | Where-Object {$_.NetworkIdentifier -eq $VPGFailoverNetworkID} | Select -ExpandProperty VirtualizationNetworkName
$VPGFailoverTestNetworkName = $VINetworksCMD | Where-Object {$_.NetworkIdentifier -eq $VPGFailoverTestNetworkID} | Select -ExpandProperty VirtualizationNetworkName
# Getting datastore cluster name
$VPGJournalDatastoreClusterName = $VIDatastoreClustersCMD | Where-Object {$_.DatastoreClusterIdentifier -eq $VPGJournalDatastoreClusterIdentifier} | select -ExpandProperty DatastoreClusterName
# Getting datastore names
$VPGDefaultDatastoreName = $VIDatastoresCMD | Where-Object {$_.DatastoreIdentifier -eq $VPGDefaultDatastoreIdentifier} | select -ExpandProperty DatastoreName
$VPGJournalDatastoreName = $VIDatastoresCMD | Where-Object {$_.DatastoreIdentifier -eq $VPGJournalDatastoreIdentifier} | select -ExpandProperty DatastoreName
# Getting folder name
$VPGDefaultFolderName = $VIFoldersCMD | Where-Object {$_.FolderIdentifier -eq $VPGDefaultFolderIdentifier} | select -ExpandProperty FolderName
# Getting cluster name
$VPGDefaultHostClusterName = $VIClustersCMD | Where-Object {$_.ClusterIdentifier -eq $VPGDefaultHostClusterIdentifier} | select -ExpandProperty VirtualizationClusterName
# Getting host name
$VPGDefaultHostName = $VIHostsCMD | Where-Object {$_.HostIdentifier -eq $VPGDefaultHostIdentifier} | select -ExpandProperty VirtualizationHostName
# Getting resource pool name
$VPGResourcePoolName = $VIResourcePoolsCMD | Where-Object {$_.ResourcePoolIdentifier -eq $VPGResourcePoolIdentifier} | select -ExpandProperty ResourcepoolName
################################################
# Adding all VPG setting info to $VPGArray
################################################
$VPGArrayLine = new-object PSObject
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $VPGName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGidentifier" -Value $VPGidentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGOrganization" -Value $VPGOrganization
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGVMCount" -Value $VPGVMCount
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGPriortiy" -Value $VPGPriortiy
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGProtectedSiteName" -Value $VPGProtectedSiteName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGProtectedSiteIdentifier" -Value $VPGProtectedSiteIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGRecoverySiteName" -Value $VPGRecoverySiteName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGRecoverySiteIdentifier" -Value $VPGRecoverySiteIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGRpoInSeconds" -Value $VPGRpoInSeconds
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGServiceProfileIdentifier" -Value $VPGServiceProfileIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGTestIntervalInMinutes" -Value $VPGTestIntervalInMinutes
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGUseWanCompression" -Value $VPGUseWanCompression
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGZorgIdentifier" -Value $VPGZorgIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGBootGroupCount" -Value $VPGBootGroupCount
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGBootGroupNames" -Value $VPGBootGroupNames
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGBootGroupDelays" -Value $VPGBootGroupDelays
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGBootGroupIdentifiers" -Value $VPGBootGroupIdentifiers
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalHistoryInHours" -Value $VPGJournalHistoryInHours
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalDatastoreClusterName" -Value $VPGJournalDatastoreClusterName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalDatastoreClusterIdentifier" -Value $VPGJournalDatastoreClusterIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalDatastoreName" -Value $VPGJournalDatastoreName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalDatastoreIdentifier" -Value $VPGJournalDatastoreIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalHardLimitInMB" -Value $VPGJournalHardLimitInMB
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalHardLimitInPercent" -Value $VPGJournalHardLimitInPercent
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalWarningThresholdInMB" -Value $VPGJournalWarningThresholdInMB
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGJournalWarningThresholdInPercent" -Value $VPGJournalWarningThresholdInPercent
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGFailoverNetworkName" -Value $VPGFailoverNetworkName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGFailoverNetworkID" -Value $VPGFailoverNetworkID
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGFailoverTestNetworkName" -Value $VPGFailoverTestNetworkName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGFailoverTestNetworkID" -Value $VPGFailoverTestNetworkID
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultDatastoreName" -Value $VPGDefaultDatastoreName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultDatastoreIdentifier" -Value $VPGDefaultDatastoreIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultFolderName" -Value $VPGDefaultFolderName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultFolderIdentifier" -Value $VPGDefaultFolderIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultHostClusterName" -Value $VPGDefaultHostClusterName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultHostClusterIdentifier" -Value $VPGDefaultHostClusterIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultHostName" -Value $VPGDefaultHostName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGDefaultHostIdentifier" -Value $VPGDefaultHostIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGResourcePoolName" -Value $VPGResourcePoolName
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGResourcePoolIdentifier" -Value $VPGResourcePoolIdentifier
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGScriptingPreRecovery" -Value $VPGScriptingPreRecovery
$VPGArrayLine | Add-Member -MemberType NoteProperty -Name "VPGScriptingPostRecovery" -Value $VPGScriptingPostRecovery
$VPGArray += $VPGArrayLine
################################################
# Starting for each VM ID action for collecting ZVM VM data
################################################
foreach ($_ in $VPGVMIdentifiers)
{
$VMIdentifier = $_
# Get VMs settings
$GetVMSettingsURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier+"/vms/"+$VMIdentifier
$GetVMSettings = Invoke-RestMethod -Method Get -Uri $GetVMSettingsURL -TimeoutSec 100 -Headers $zertoSessionHeader_json -ContentType $TypeJSON
# Getting the VM name and disk usage
$VMNameArray = $vmListarray | where-object {$_.VmIdentifier -eq $VMIdentifier} | Select-Object *
$VMName = $VMNameArray.VmName
$VMProvisionedStorageInMB = $VMNameArray.ProvisionedStorageInMB
$VMUsedStorageInMB = $VMNameArray.UsedStorageInMB
# Setting variables from the API
$VMVolumeCount = $GetVMSettings.Volumes.Count
$VMNICCount = $GetVMSettings.Nics.Count
$VMBootGroupIdentifier = $GetVMSettings.BootGroupIdentifier
$VMJournalDatastoreClusterIdentifier = $GetVMSettings.Journal.DatastoreClusterIdentifier
$VMJournalDatastoreIdentifier = $GetVMSettings.Journal.DatastoreIdentifier
$VMJournalHardLimitInMB = $GetVMSettings.Journal.Limitation.HardLimitInMB
$VMJournalHardLimitInPercent = $GetVMSettings.Journal.Limitation.HardLimitInPercent
$VMJournalWarningThresholdInMB = $GetVMSettings.Journal.Limitation.WarningThresholdInMB
$VMJournalWarningThresholdInPercent = $GetVMSettings.Journal.Limitation.WarningThresholdInPercent
$VMDatastoreClusterIdentifier = $GetVMSettings.Recovery.DatastoreClusterIdentifier
$VMDatastoreIdentifier = $GetVMSettings.Recovery.DatastoreIdentifier
$VMFolderIdentifier = $GetVMSettings.Recovery.FolderIdentifier
$VMHostClusterIdentifier = $GetVMSettings.Recovery.HostClusterIdentifier
$VMHostIdentifier = $GetVMSettings.Recovery.HostIdentifier
$VMResourcePoolIdentifier = $GetVMSettings.Recovery.ResourcePoolIdentifier
################################################
# Translating Zerto IDs from VM settings to friendly vSphere names
################################################
# Getting boot group
$VMBootGroupName = $VPGBootGroups | Where-Object {$_.BootGroupIdentifier -eq $VMBootGroupIdentifier} | select -ExpandProperty Name
$VMBootGroupDelay = $VPGBootGroups | Where-Object {$_.BootGroupIdentifier -eq $VMBootGroupIdentifier} | select -ExpandProperty BootDelayInSeconds
# Getting datastore cluster name
$VMJournalDatastoreClusterName = $VIDatastoreClustersCMD | Where-Object {$_.DatastoreClusterIdentifier -eq $VMJournalDatastoreClusterIdentifier} | select -ExpandProperty DatastoreClusterName
$VMDatastoreClusterName = $VIDatastoreClustersCMD | Where-Object {$_.DatastoreClusterIdentifier -eq $VMDatastoreClusterIdentifier} | select -ExpandProperty DatastoreClusterName
# Getting datastore name
$VMJournalDatastoreName = $VIDatastoresCMD | Where-Object {$_.DatastoreIdentifier -eq $VMJournalDatastoreIdentifier} | select -ExpandProperty DatastoreName
$VMDatastoreName = $VIDatastoresCMD | Where-Object {$_.DatastoreIdentifier -eq $VMDatastoreIdentifier} | select -ExpandProperty DatastoreName
# Getting folder name
$VMFolderName = $VIFoldersCMD | Where-Object {$_.FolderIdentifier -eq $VMFolderIdentifier} | select -ExpandProperty FolderName
# Getting cluster name
$VMHostClusterName = $VIClustersCMD | Where-Object {$_.ClusterIdentifier -eq $VMHostClusterIdentifier} | select -ExpandProperty VirtualizationClusterName
# Getting host name
$VMHostName = $VIHostsCMD | Where-Object {$_.HostIdentifier -eq $VMHostIdentifier} | select -ExpandProperty VirtualizationHostName
# Getting resource pool name
$VMResourcePoolName = $VIResourcePoolsCMD | Where-Object {$_.ResourcePoolIdentifier -eq $VMResourcePoolIdentifier} | select -ExpandProperty ResourcepoolName
################################################
# Adding all VM setting info to $VMArray
################################################
$VMArrayLine = new-object PSObject
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $VPGName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VPGidentifier" -Value $VPGidentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMName" -Value $VMName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMIdentifier" -Value $VMIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICCount" -Value $VMNICCount
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeCount" -Value $VMVolumeCount
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMProvisionedStorageInMB" -Value $VMProvisionedStorageInMB
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMUsedStorageInMB" -Value $VMUsedStorageInMB
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMBootGroupName" -Value $VMBootGroupName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMBootGroupDelay" -Value $VMBootGroupDelay
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMBootGroupIdentifier" -Value $VMBootGroupIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalDatastoreClusterName" -Value $VMJournalDatastoreClusterName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalDatastoreClusterIdentifier" -Value $VMJournalDatastoreClusterIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalDatastoreName" -Value $VMJournalDatastoreName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalDatastoreIdentifier" -Value $VMJournalDatastoreIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalHardLimitInMB" -Value $VMJournalHardLimitInMB
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMJournalHardLimitInPercent" -Value $VMJournalHardLimitInPercent
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMDatastoreClusterName" -Value $VMDatastoreClusterName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMDatastoreClusterIdentifier" -Value $VMDatastoreClusterIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMDatastoreName" -Value $VMDatastoreName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMDatastoreIdentifier" -Value $VMDatastoreIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMFolderName" -Value $VMFolderName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMFolderIdentifier" -Value $VMFolderIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMHostClusterName" -Value $VMHostClusterName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMHostClusterIdentifier" -Value $VMHostClusterIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMHostName" -Value $VMHostName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMHostIdentifier" -Value $VMHostIdentifier
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMResourcePoolName" -Value $VMResourcePoolName
$VMArrayLine | Add-Member -MemberType NoteProperty -Name "VMResourcePoolIdentifier" -Value $VMResourcePoolIdentifier
$VMArray += $VMArrayLine
################################################
# Get VM Volume settings for the current VPG
################################################
$GetVMSettingVolumesURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier+"/vms/"+$VMIdentifier+"/volumes"
$GetVMSettingVolumes = Invoke-RestMethod -Method Get -Uri $GetVMSettingVolumesURL -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
$GetVMSettingVolumeIDs = $GetVMSettingVolumes.ArrayOfVpgSettingsVmVolumeApi.VpgSettingsVmVolumeApi | select-object VolumeIdentifier -ExpandProperty VolumeIdentifier
################################################
# Starting for each VM Volume ID action for collecting ZVM VM Volume data
################################################
foreach ($_ in $GetVMSettingVolumeIDs)
{
$VMVolumeID = $_
# Getting API data for volume
$GetVMSettingVolumeURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier+"/vms/"+$VMIdentifier+"/volumes/"+$VMVolumeID
$GetVMSettingVolume = Invoke-RestMethod -Method Get -Uri $GetVMSettingVolumeURL -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
# Setting values
$VMVolumeDatastoreClusterIdentifier = $GetVMSettingVolume.VpgSettingsVmVolumeApi.Datastore.DatastoreClusterIdentifier
$VMVolumeDatastoreIdentifier = $GetVMSettingVolume.VpgSettingsVmVolumeApi.Datastore.DatastoreIdentifier
$VMVolumeIsSWAP = $GetVMSettingVolume.VpgSettingsVmVolumeApi.IsSwap
$VMVolumeIsThin = $GetVMSettingVolume.VpgSettingsVmVolumeApi.Datastore.IsThin
# Getting datastore cluster name
$VMVolumeDatastoreClusterName = $VIDatastoreClustersCMD | Where-Object {$_.DatastoreClusterIdentifier -eq $VMVolumeDatastoreClusterIdentifier} | select -ExpandProperty DatastoreClusterName
# Getting datastore name
$VMVolumeDatastoreName = $VIDatastoresCMD | Where-Object {$_.DatastoreIdentifier -eq $VMVolumeDatastoreIdentifier} | select -ExpandProperty DatastoreName
################################################
# Adding all VM Volume setting info to $VMVolumeArray
################################################
$VMVolumeArrayLine = new-object PSObject
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $VPGName
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VPGidentifier" -Value $VPGidentifier
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMName" -Value $VMName
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMIdentifier" -Value $VMIdentifier
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeID" -Value $VMVolumeID
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeIsSWAP" -Value $VMVolumeIsSWAP
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeIsThin" -Value $VMVolumeIsThin
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeDatastoreClusterName" -Value $VMVolumeDatastoreClusterName
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeDatastoreClusterIdentifier" -Value $VMVolumeDatastoreClusterIdentifier
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeDatastoreName" -Value $VMVolumeDatastoreName
$VMVolumeArrayLine | Add-Member -MemberType NoteProperty -Name "VMVolumeDatastoreIdentifier" -Value $VMVolumeDatastoreIdentifier
$VMVolumeArray += $VMVolumeArrayLine
}
################################################
# Get VM Nic settings for the current VPG
################################################
$GetVMSettingNICsURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier+"/vms/"+$VMIdentifier+"/nics"
$GetVMSettingNICs = Invoke-RestMethod -Method Get -Uri $GetVMSettingNICsURL -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
$VMNICIDs = $GetVMSettingNICs.ArrayOfVpgSettingsVmNicApi.VpgSettingsVmNicApi | select-object NicIdentifier -ExpandProperty NicIdentifier
################################################
# Starting for each VM NIC ID action for collecting ZVM VM NIC data
################################################
foreach ($_ in $VMNICIDs)
{
$VMNICIdentifier = $_
$GetVMSettingNICURL = $baseURL+"vpgSettings/"+$VPGSettingsIdentifier+"/vms/"+$VMIdentifier+"/nics/"+$VMNICIdentifier
$GetVMSettingNIC = Invoke-RestMethod -Method Get -Uri $GetVMSettingNICURL -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
# Building arrays
$VMSettingNICIDArray1 = $GetVMSettingNIC.VpgSettingsVmNicApi.Failover.Hypervisor
$VMSettingNICIDArray2 = $GetVMSettingNIC.VpgSettingsVmNicApi.Failover.Hypervisor.IpConfig
$VMSettingNICIDArray3 = $GetVMSettingNIC.VpgSettingsVmNicApi.FailoverTest.Hypervisor
$VMSettingNICIDArray4 = $GetVMSettingNIC.VpgSettingsVmNicApi.FailoverTest.Hypervisor.IpConfig
# Setting failover values
$VMNICFailoverDNSSuffix = $VMSettingNICIDArray1.DnsSuffix
$VMNICFailoverNetworkIdentifier = $VMSettingNICIDArray1.NetworkIdentifier
$VMNICFailoverShouldReplaceMacAddress = $VMSettingNICIDArray1.ShouldReplaceMacAddress
$VMNICFailoverGateway = $VMSettingNICIDArray2.Gateway
$VMNIsFailoverDHCP = $VMSettingNICIDArray2.IsDhcp
$VMNICFailoverPrimaryDns = $VMSettingNICIDArray2.PrimaryDns
$VMNICFailoverSecondaryDns = $VMSettingNICIDArray2.SecondaryDns
$VMNICFailoverStaticIp = $VMSettingNICIDArray2.StaticIp
$VMNICFailoverSubnetMask = $VMSettingNICIDArray2.SubnetMask
# Nulling blank content
if ($VMNICFailoverDNSSuffix.nil -eq $true){$VMNICFailoverDNSSuffix = $null}
if ($VMNICFailoverGateway.nil -eq $true){$VMNICFailoverGateway = $null}
if ($VMNICFailoverPrimaryDns.nil -eq $true){$VMNICFailoverPrimaryDns = $null}
if ($VMNICFailoverSecondaryDns.nil -eq $true){$VMNICFailoverSecondaryDns = $null}
if ($VMNICFailoverStaticIp.nil -eq $true){$VMNICFailoverStaticIp = $null}
if ($VMNICFailoverSubnetMask.nil -eq $true){$VMNICFailoverSubnetMask = $null}
# Setting failover test values
$VMNICFailoverTestDNSSuffix = $VMSettingNICIDArray3.DnsSuffix
$VMNICFailoverTestNetworkIdentifier = $VMSettingNICIDArray3.NetworkIdentifier
$VMNICFailoverTestShouldReplaceMacAddress = $VMSettingNICIDArray3.ShouldReplaceMacAddress
$VMNICFailoverTestGateway = $VMSettingNICIDArray4.Gateway
$VMNIsFailoverTestDHCP = $VMSettingNICIDArray4.IsDhcp
$VMNICFailoverTestPrimaryDns = $VMSettingNICIDArray4.PrimaryDns
$VMNICFailoverTestSecondaryDns = $VMSettingNICIDArray4.SecondaryDns
$VMNICFailoverTestStaticIp = $VMSettingNICIDArray4.StaticIp
$VMNICFailoverTestSubnetMask = $VMSettingNICIDArray4.SubnetMask
# Nulling blank content
if ($VMNICFailoverTestDNSSuffix.nil -eq $true){$VMNICFailoverTestDNSSuffix = $null}
if ($VMNICFailoverTestGateway.nil -eq $true){$VMNICFailoverTestGateway = $null}
if ($VMNICFailoverTestPrimaryDns.nil -eq $true){$VMNICFailoverTestPrimaryDns = $null}
if ($VMNICFailoverTestSecondaryDns.nil -eq $true){$VMNICFailoverTestSecondaryDns = $null}
if ($VMNICFailoverTestStaticIp.nil -eq $true){$VMNICFailoverTestStaticIp = $null}
if ($VMNICFailoverTestSubnetMask.nil -eq $true){$VMNICFailoverTestSubnetMask = $null}
# Mapping Network IDs to Names
$VMNICFailoverNetworkName = $VINetworksCMD | Where-Object {$_.NetworkIdentifier -eq $VMNICFailoverNetworkIdentifier} | Select VirtualizationNetworkName -ExpandProperty VirtualizationNetworkName
$VMNICFailoverTestNetworkName = $VINetworksCMD | Where-Object {$_.NetworkIdentifier -eq $VMNICFailoverTestNetworkIdentifier} | Select VirtualizationNetworkName -ExpandProperty VirtualizationNetworkName
################################################
# Adding all VM NIC setting info to $VMNICArray
################################################
$VMNICArrayLine = new-object PSObject
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $VPGName
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VPGidentifier" -Value $VPGidentifier
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMName" -Value $VMName
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMIdentifier" -Value $VMIdentifier
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICIdentifier" -Value $VMNICIdentifier
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverNetworkName" -Value $VMNICFailoverNetworkName
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverNetworkIdentifier" -Value $VMNICFailoverNetworkIdentifier
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverDNSSuffix" -Value $VMNICFailoverDNSSuffix
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverShouldReplaceMacAddress" -Value $VMNICFailoverShouldReplaceMacAddress
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverGateway" -Value $VMNICFailoverGateway
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverDHCP" -Value $VMNIsFailoverDHCP
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverPrimaryDns" -Value $VMNICFailoverPrimaryDns
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverSecondaryDns" -Value $VMNICFailoverSecondaryDns
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverStaticIp" -Value $VMNICFailoverStaticIp
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverSubnetMask" -Value $VMNICFailoverSubnetMask
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestNetworkName" -Value $VMNICFailoverTestNetworkName
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestNetworkIdentifier" -Value $VMNICFailoverTestNetworkIdentifier
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestDNSSuffix" -Value $VMNICFailoverTestDNSSuffix
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestShouldReplaceMacAddress" -Value $VMNICFailoverTestShouldReplaceMacAddress
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestGateway" -Value $VMNICFailoverTestGateway
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestDHCP" -Value $VMNIsFailoverTestDHCP
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestPrimaryDns" -Value $VMNICFailoverTestPrimaryDns
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestSecondaryDns" -Value $VMNICFailoverTestSecondaryDns
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestStaticIp" -Value $VMNICFailoverTestStaticIp
$VMNICArrayLine | Add-Member -MemberType NoteProperty -Name "VMNICFailoverTestSubnetMask" -Value $VMNICFailoverTestSubnetMask
$VMNICArray += $VMNICArrayLine
# End of per VM NIC actions below
}
# End of per VM NIC actions above
#
# End of per VM actions below
}
# End of per VM actions above
################################################
# Deleting VPG edit settings ID (same as closing the edit screen on a VPG in the ZVM without making any changes)
################################################
Try
{
Invoke-RestMethod -Method Delete -Uri $VPGSettingsURL -TimeoutSec 100 -Headers $zertoSessionHeader_xml -ContentType $TypeXML
}
Catch [system.exception]
{
}
#
# End of check for valid VPG settings ID below
}
# End of check for valid VPG settings ID above
#
# End of per VPG actions below
}
# End of per VPG actions above
#
################################################
# Showing Results - edit here for export commands etc
################################################
write-host "VPG Array:"
$VPGArray | fl
write-host "VM Array:"
$VMArray | fl
write-host "VM VOlume Array:"
$VMVolumeArray | fl
write-host "VM NIC Array:"
$VMNICArray | fl
# Exporting results
# Exporting arrays to CSV
$VPGArray | export-csv $ExportDataDir"VPGArray.csv" -NoTypeInformation
$VMArray | export-csv $ExportDataDir"VMArray.csv" -NoTypeInformation
$VMVolumeArray | export-csv $ExportDataDir"VMVolumeArray.csv" -NoTypeInformation
$VMNICArray | export-csv $ExportDataDir"VMNICArray.csv" -NoTypeInformation 