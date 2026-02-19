Function Perform-VMFSUnmap {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory=$true)]
            [String[]]$Datastore,
            [String]$ESXiHost
        )
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -Scope Session -Confirm:$false
    $ESXHost = Get-VMHost $ESXiHost
    $DatastoreName = Get-Datastore $Datastore
    Write-Host "Using ESXCLI and connecting to $ESXiHost" -ForegroundColor Green
    $esxcli = Get-EsxCli -VMHost $ESXHost -V2
    Write-Host "Unmapping $Datastore on $ESXiHost" -ForegroundColor Green
    $args = @{
        #reclaimunit = 42; #Native internal page size. Not sure if unmap follows alignment, let's see after some testing.
        volumelabel = $DatastoreName.Name
    }
$esxcli.storage.vmfs.unmap.invoke($args)
}
#https://github.com/tquizzle/PowerCLI/blob/master/DatastoreFunctions.ps1
Function Get-DatastoreMountInfo {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)]
		$Datastore
	)
	Process {
		$AllInfo = @()
		if (-not $Datastore) {
			$Datastore = Get-Datastore
		}
		Foreach ($ds in $Datastore) {  
			if ($ds.ExtensionData.info.Vmfs) {
				$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].diskname
				if ($ds.ExtensionData.Host) {
					$attachedHosts = $ds.ExtensionData.Host
					Foreach ($VMHost in $attachedHosts) {
						$hostview = Get-View $VMHost.Key
						$hostviewDSState = $VMHost.MountInfo.Mounted
						$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
						$devices = $StorageSys.StorageDeviceInfo.ScsiLun
						Foreach ($device in $devices) {
							$Info = "" | Select Datastore, VMHost, Lun, Mounted, State
							if ($device.canonicalName -eq $hostviewDSDiskName) {
								$hostviewDSAttachState = ""
								if ($device.operationalState[0] -eq "ok") {
									$hostviewDSAttachState = "Attached"							
								} elseif ($device.operationalState[0] -eq "off") {
									$hostviewDSAttachState = "Detached"							
								} else {
									$hostviewDSAttachState = $device.operationalstate[0]
								}
								$Info.Datastore = $ds.Name
								$Info.Lun = $hostviewDSDiskName
								$Info.VMHost = $hostview.Name
								$Info.Mounted = $HostViewDSState
								$Info.State = $hostviewDSAttachState
								$AllInfo += $Info
							}
						}
						
					}
				}
			}
		}
		$AllInfo
	}
}


Import-Module VMware.PowerCLI > $nul
Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -Scope Session -InvalidCertificateAction Ignore -Confirm:$false > $nul

. "$PSScriptRoot\Config.ps1"
$vCenterPass = ConvertTo-SecureString -String $vCenterPassPT -AsPlainText -Force
$vCenterCred = New-Object System.Management.Automation.PSCredential ($vCenterUser, $vCenterPass)

Connect-VIServer -Server $vCenterHost -Credential $vCenterCred  > $nul

#Valid datastores. VMFS only
$Datastores = Get-Datastore | Where-Object -FilterScript {$_.Type -eq 'VMFS' -and $_.ExtensionData.host.count -gt 1}
#Get hosts, where datastore is mounted
$DatastoreMounts = $Datastores | Get-DatastoreMountInfo | Where-Object -FilterScript {$_.Mounted -eq $true} | Group-Object -Property Datastore | Sort-Object -Property Name

#Run one UNMAP per day. Dividing with modulus day number (of year) by number of datastore gives a nice dynamic loop. Should number of datastores ever change, loop also changes.
#Array of datastore and result of modulus are both 0-based
$DatastoreIndex = (Get-Date).DayOfYear % $DatastoreMounts.Length
$DatastoreMounts = $DatastoreMounts[$DatastoreIndex]

Foreach ($Datastore in $DatastoreMounts) {
    $Executionhost = $Datastore.Group.VMhost | % {Get-VMHost -Name $_} | Where-Object -FilterScript {$_.ConnectionState -eq 'Connected'} | Get-Random | Select -First 1
    Write-Host ('Starting UNMAP. Datastore: ' + $Datastore.name + ' Host: ' + $Executionhost.Name)
    $Time = Measure-Command -Expression {
        Perform-VMFSUnmap -Datastore $Datastore.Name -ESXiHost $Executionhost
    }
    Write-Host ('Completed UNMAP. Datastore: ' + $Datastore.name + ' Host: ' + $Executionhost.Name + ' Time: ' + $Time.TotalSeconds +' seconds')
}