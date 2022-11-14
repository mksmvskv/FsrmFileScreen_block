function Get-WorkServers {
    $servers = @()
    $ReplicationGroups = Get-DfsReplicationGroup | Where-Object { $_.GroupName -match '^domain\.com\\some\\' }
    foreach ( $ReplicationGroup in $ReplicationGroups ) {
        $stats = Get-DfsnFolderTarget -Path $ReplicationGroup.GroupName
        foreach ($stat in $stats){
            if ($stat.State -eq 'Online') {
                $servers += $stat.TargetPath -replace '\\\\([^\\|\.]+)[\\|\.].*', '$1'
            }
        }
    }
    $servers = $servers.ToLower() | Sort-Object | Get-Unique
return $servers
}

function Set-LockFile ($workserver) {
    $result = Invoke-Command -ComputerName $workserver -ScriptBlock {
        $servername = $env:computername + "@domain.com"
        $disk = Get-WMIObject Win32_LogicalDisk -filter "DriveType=3 `
        and DeviceID!='H:' `
        and DeviceID!='L:' `
        and DeviceID!='T:' `
        and DeviceID!='C:' `
        and VolumeName!='SomeName'"
        Set-FsrmSetting -FromEmailAddress $servername -AdminEmailAddress "admin@domain.com" -SmtpServer "smtp.domain.com"
        foreach ($disk in $disk.DeviceID) {
            $diskname = $disk + "\"
            New-FsrmFileGroup -Name "PST" -IncludePattern @("*.pst")
            $Notification = New-FsrmAction `
            -Type Email `
            -MailTo "[Admin Email]" `
            -Subject "An unauthorized file from the following file group has been detected: [Violated File Group]" `
            -Body "User [Source Io Owner] tried to save the file [Source File Path] in folder [File Screen Path] on server [Server]. This file belongs to the file group [Violated File Group], which is not allowed on the server." `
            -RunLimitInterval 120
            New-FsrmFileScreenTemplate -Name "block_PST" -IncludeGroup "PST" -Notification $Notification -Active
            New-FsrmFileScreen -Path $diskname -Template "block_PST"
        }
    }
return $result
}

$servers = Get-WorkServers
foreach ($server in $servers){
    Set-LockFile -workserver $server
}
