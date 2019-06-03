#########################################################
#               Backup Database Creation              #
#########################################################
#Requires -Version 4
#Requires -Modules SQLPS

# If running this from a machine without SQLPS module installed, install the SqlServer Module using the command: Install-Module -Name SqlServer
# https://docs.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-2017
# Then erase or update the Requires line to say: Requires -Modules SqlServer

<#
    Written by: Nathan Peterman

.SYNOPSIS
Supply a remote SQL Server instance or use the default setting of the local SQL instance to backup all User/System Database files to a remote location or local location.
Command line arguments can be supplied to determine the type of backup used and which databases are selected for backup.

.PARAMETER ConnectionString
Calling Syntax: -ConnectionString "Servername\Instance" or -ConnectionString "Servername,Port"

Parameter Description: When supplied, a connection will be attempted to backup databases on remote SQL Server Instance. When used, 
a Network UNC path must be supplied with the -Path Parameter so that the remote server is able to access the backup location

.PARAMETER Path
Calling Syntax: -Path "X:\BackupLocation" or "\\Servername\Sharename"

Parameter Description: This is a required parameter. This is the location that the Databases Backups and backup log will be stored. A new folder will be created under SERVERNAME for organization.

.PARAMETER Full
Calling Syntax: -Full

Parameter Description: Full Backup Selection. This will be the type of backup used and it is required to supply one of the three backup types.

.PARAMETER Diff
Calling Syntax: -Diff

Parameter Description: Differential Backup Selection. This will be the type of backup used and it is required to supply one of the three backup types.

.PARAMETER Log
Calling Syntax: -Log

Parameter Description: Log Backup Selection. This will be the type of backup used and it is required to supply one of the three backup types.

.PARAMETER Retention
Calling Syntax: -Retention 7

Parameter Description: Running PowerShell as admin is required for this command. This will attempt to delete database backups that are older than the supplied time in days. The default value is 0 which will keep all backup files.

.PARAMETER SystemDB
Calling Syntax: -SystemDB

Parameter Description: When supplied system databases will be included in the backup.

.PARAMETER NoUserDB
Calling Syntax: -NoUserDB

Parameter Description: When supplied user databases files will be skipped.

.PARAMETER AlwaysOn
Calling Syntax: -AlwaysOn

Parameter Description: When supplied backups for databases that are a joined to an AlwaysOn group and with a server that is in the Secondary role will be included in the databases to be backed up. 
For databases that fall into this scope, when used with the -Full backup type, a COPY-ONLY backup will be taken.

.PARAMETER Database
Calling Syntax: -Database "database" or -Database "database1,database2"

Parameter Description: This parameter accepts one or more database names separated by a comma. When used, backups will only be attempted on the databases that are supplied. 
When including the names of a system or AlwaysOn secondary databases, the proper parameters need to be supplied to confirm that they are included. I.E. -SystemDB or -AlwaysOn

.PARAMETER CopyOnly
Calling Syntax: -CopyOnly

Parameter Description: When supplied all full backups will be taken with the Copy Only backup mode.

.PARAMETER SelectDB
Calling Syntax: -SelectDB

Parameter Description: Opens up a GridView window for manual database selection for backup

.PARAMETER Compression
Calling Syntax: -Compression

Parameter Description: Turns the compression option on for SQL Backups if the server is not set to use compression by default

.PARAMETER Script
Calling Syntax: -Script

Parameter Description: Outputs the TSQL Backup commands into a text file stored in the backup directory for manual execution. When this option is used, it will not backup the databases,
it will only export the TSQL commands.

.PARAMETER WhatIf
Calling Syntax: -WhatIf

Parameter Description: Shows what would happen if the cmdlet runs. When this option is used, it will not backup the databases.

.PARAMETER CheckSum
Calling Syntax: -CheckSum

Parameter Description: When supplied, the server will calculate a checksum for the backup file when creating a backup. When performing a verification restore, it is used to check data 
structure and reliability in a SQL Server backup.

.PARAMETER Verify
Calling Syntax: -Verify

Parameter Description: When supplied, will attempt to restore the backup file using the VerifyOnly option to check whether a SQL database backup can be read and restored properly. 
Recommended to use in conjunction with -CheckSum.

.PARAMETER SQLCredential
Calling Syntax: -SQLCredential sa

Parameter Description: When used, supplies a SQL Server Account to use when connecting to the database to perform backups. The username for the SQL Server account must be supplied

.PARAMETER CSVFile
Calling Syntax: -CSVFile ".\ServerList.csv"

Parameter Description: Accepts a text or csv file with each server connection string on a new line. Will attempt to connect to each server using the connection string a backup according
to the command line arguments supplied.

File Contents Example:
SERVERNAMEDB01,57109
SERVERNAMEDB02\INSTANCENAME


.EXAMPLE
.\Backup-SQLDatabases.ps1 -Full -Path G:\Backup
    Create a Full backup for all User Databases on the local server to G:\Backup

.\Backup-SQLDatabase.ps1 -Full -CopyOnly -Path G:\Backup -Database "foglightdb,dbadmin,master" -SystemDB -AlwaysOn -SQLCredential sysdba
    Create a Full Copy-Only backup for only the Databases dbadmin, foglightdb and master on the local SQL Server to G:\Backup. Runs the backup
    using the sysdba SQL Account.
    -SystemDB and -AlwaysOn must be used to make sure the databases supplied are eligble for a backup as master is a SystemDB and
    foglightdb is an AlwaysOn database. -AlwaysOn only needs to be supplied when running the backup on a secondary AlwaysOn server.

.\Backup-SQLDatabase.ps1 -Diff -Path "\\NetworkLocation\sharedfolder" -Database -SystemDB -NoUserDB -ConnectionString "Servername,InstancePort" -Retention 14
    Create a Diff backup of only the System Databases for a remote SQL Server Instance and attempts to remove backup files older than 14 days. 
    This will resuly in no database backups as DIFF is not supported for System Databases.

.\Backup-SQLDatabase.ps1 -Log -Path G:\Backup -SelectDB -CheckSum -Verify -Compression
    Create a log backup of all the databases selected in the Gridview generated from a list of all databases with compression on and calculate a checksum and verify all backups created.

.NOTES
Version History
    0.1 - Initial Creation
    0.2 - Added in seperate backup mode functionality
    0.3 - Added in -AlwaysON, -Database, -CopyOnly functionality. Bug fixes.
    0.4 - Added in the SelectDB Gridview
    0.5 - Added the collection of more database details to the log
    0.6 - Added in the option to supply a SQL Server Account to be used when connecting to the database
    0.7 - Re-Wrote Backup-SQLDatabase parameters into a Hash Table for building the query on the fly
    0.8 - Added in CheckSum and Verify for verification of a successful backup
    1.0 - Added in the functionality to read a server list from a CSV file and execute against each one.
    1.1 - Corrected issues with saving backups to multiple locations provided by the CSVFile
    1.2 - Refactored Server info into a funtion to return a server object and gather instance info for file organization
#>

Param (
    [String]$ConnectionString = $null, # Connection String for remote database backups
    [Switch]$Full,
    [Switch]$Diff, # One of the options Full, Diff  or Log must be selected for backup type
    [Switch]$Log,
    [Parameter(Mandatory=$true)]
    [String]$Path = $null, # Path where backups will be stored
    [Int]$Retention = 0, # Will delete backup files older than this number of days. 0 keeps all files by default
    [Switch]$SystemDB, # Switch to include the System Databases
    [Switch]$NoUserDB, # Switch to not backup any User Databases
    [Switch]$AlwaysOn, # Switch to backup read only databases on AlwaysOn Secondaries
    [String]$Database, # If a database name is supplied will only attempt a backup of that database
    [Switch]$CopyOnly, # Forces a Copy-Only backup of the databases
    [Switch]$SelectDB, # Opens a dialog to allow for the selection of databases to backup
    [Switch]$Compression, # Allows for the explict setting of compression on databases if the Instance is not setup to compress backups
    [Switch]$Script, # Writes out the backup TSQL to a query text file
    [Switch]$WhatIf, # Shows what would happen if the cmdlet runs
    [Switch]$CheckSum, # Calculates a CHeckSum when creating a backup
    [Switch]$Verify, # Tests the restore of the database after creation of the backup
    [PSCredential]$SQLCredential, # Will prompt for SQL Account Credentials if supplied with a username
    [String]$CSVFile # If providing a CSV or Text file, will execute against each server listed
)

$ScriptVersion = 1.2
$Date = "$((Get-Date).ToString('yyyyMMdd-hhmmss'))"
$Instance = ""
$CurrentDBA = $env:USERDOMAIN + "\" + $env:USERNAME

Clear-Host

# Function to write the output to a log file and places it in the backup folder
#**************************************************************
Function LogWrite
#**************************************************************
{
   Param (
       [String]$logstring,
       [String]$Colour,
       [switch]$log)

    If (!($log)) {
        If ($Colour) {
            Write-Host "$(Get-Date): $logstring" -ForegroundColor $Colour
        } Else {
            Write-Host "$(Get-Date): $logstring"
        } 
    }
    Add-content $LogFile -value "$(Get-Date): $logstring" -Force
}

# Function to return a server object from a string.
#**************************************************************
Function Get-ServerObject
#**************************************************************
{
    Param (
        [String]$ServerString
    )

    $pos = $ServerString.IndexOf("\")
    If ($pos -gt 0) {
        $ComputerName = $ServerString.Substring(0, $pos)
        $Instance = $ServerString.Substring($pos + 1)
        $Port = $null
    } Else {
        $pos = $ServerString.IndexOf(",")
        If ($pos -gt 0) {
            $ComputerName = $ServerString.Substring(0, $pos)
            $Instance = $null
            $Port = $ServerString.Substring($pos + 1)
        } Else {
            $ComputerName = $ServerString
            $Instance = $null
            $Port = $null
        }
    }

    $ComputerName = $ComputerName.ToUpper()

    $ServerObject = [PSCustomObject]@{
        Name = $ComputerName
        Instance = $Instance
        Port = $Port
        ConnectionString = $ServerString
    }

    Return $ServerObject
}

If ($Retention -gt 0) {
    # Check to see if the powershell was lauched as Admin
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        Write-Warning "You do not have Administrator rights to remove old database backup files!`nPlease re-run this script as an Administrator or remove the -Retention Flag"
        Break
    }
}

If (($CSVFile) -and ($ConnectionString -ne '')) {
    Write-Warning "You cannot supply the ConnectionString parameter and the CSVFile parameter at the same time."
    Exit 10
}

If ($CSVFile) {
    If (Test-Path $CSVFile) {
        [string[]]$InstanceArray = Get-Content -Path $CSVFile
    } Else {
        Write-Warning "There was an issue reading from the supplied CSVFile : $CSVFile"
        Write-Warning "Please check the file location and attempt to run the script again"
        Exit 10
    }
}

# Split out the Name of the Server and the Instance name from the supplied connection strings
If (($ConnectionString -eq '') -and ($null -eq $InstanceArray)) {
    $Server = Get-ServerObject $env:COMPUTERNAME
} ElseIf ($InstanceArray){
    $Server = Get-ServerObject $InstanceArray[0]
} Else {
    $Server = Get-ServerObject $ConnectionString
}

# Check to make sure that the path is a network path if the backup is a remote server
If ($Server.Name -ne $env:COMPUTERNAME.ToUpper()) {
    If (!($Path.StartsWith("\\"))) {
        Write-Warning "The path supplied should be a UNC path for remote database backups"
        Exit 10
    }
}

# Check the path to make sure it is accessible
If(!(test-path $Path))
{
    Write-Warning "The path supplied does not exist or is not reachable by this client: $Path"
    Exit 10
}

# Check to make sure one of the backup options is selected
$Count = 0
If ($Full) {
    $Count++
}
If ($Diff) {
    $Count++
}
If ($Log) {
    $Count++
}
If ($Count -ne 1) {
    Write-Warning "One backup type must be selected. Use -Full , -Diff or -Log in the calling syntax"
    Exit 10
}

# Default to a full backup and change it if another one is selected
$BackupType = "FULL"
If ($Diff) {
    $BackupType = "DIFF"
} ElseIf ($Log) {
    $BackupType = "LOG"
}

$BackupPath = Join-Path -path $Path -ChildPath $Server.Name
$LogFile = Join-Path -Path $BackupPath -ChildPath "Backup_Log-$Date.log"
$QueryFile = Join-Path -Path $BackupPath -ChildPath "BackupQueries.txt"

If ($CSVFile) {
    $LogFile = Join-Path -Path $Path -ChildPath "Backup_Log-$Date.log"
}

# Create the backup directory
If(!(test-path $BackupPath))
{
    Try {
        New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null
    } Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Error "There was an issue creating the backup directory"
        Write-Error $ErrorMessage
        Exit 10
    }
}

# Create the log file remove old log files from the backup location
Try {
    $LogLocation = Join-Path -Path $BackupPath -ChildPath "Backup_Log*.log"
    Get-ChildItem -Path $LogLocation | Sort-Object -Descending -Property LastWriteTime | Select-Object -Skip 14 | Remove-Item
    New-Item -ItemType File -Force -Path $LogFile | Out-Null
} Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Error "There was an issue creating the backup log file"
    Write-Error $ErrorMessage
    Exit 10
}

$LogObject = Get-Item -Path $Logfile

If (Test-Path $QueryFile) {
    Try {
        Remove-Item -Force -Path $QueryFile -ErrorAction Stop
    } Catch {
        LogWrite "Error: There was an issue removing the query file: $QueryFile" -Colour "Red"
        LogWrite "Please manually remove this file and re-run script."
        $ErrorMessage = $_.Exception.Message
        LogWrite -log $ErrorMessage
        Exit 10
    }
}

Try {
    New-Item -ItemType File -Force -Path $QueryFile | Out-Null
} Catch {
    LogWrite "Error: There was an issue creating the query file: $QueryFile"
    $ErrorMessage = $_.Exception.Message
    LogWrite -log $ErrorMessage
}

$ErrorCount = 0
$DatabaseCount = 0
$VerifyCount = 0
$ConnectionSuccess = 0
$ConnectionError = 0
If ($CSVFile) {
    $LastConnection = $Server.Name
}
$BackupLocationList = New-Object System.Collections.ArrayList

LogWrite "Starting script $($MyInvocation.MyCommand.Name)"
LogWrite "Script Version: $ScriptVersion"
LogWrite "Account initiating backup: $CurrentDBA "
LogWrite "Server name determined: $($Server.Name)" -Colour "Cyan"
LogWrite "Backing up SQL Databases to: $BackupPath"
LogWrite "Backup Type: $BackupType" -Colour "Cyan"
LogWrite "System Databases included: $SystemDB"
LogWrite "Current Log File: $LogFile"

If ($CSVFile) {
    LogWrite "Total number of SQL Instances found in CSVFile: $($InstanceArray.Count)"
}

If ($null -eq $SQLCredential.username -or $SQLCredential.username -eq '') {
    LogWrite "SQL User used for connecting to the instance: $($env:USERDOMAIN)\$($env:USERNAME)"
} Else {
    LogWrite "SQL User used for connecting to the instance: $($SQLCredential.username)"
}

# Split the databases that could be supplied through the -Database parameter
$DbArray = $Database.Split(",")

# Get all the instances installed on the server
If (($ConnectionString -eq '') -and ($null -eq $InstanceArray)) {
    $inst = (get-itemproperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server").InstalledInstances
} Elseif ($InstanceArray) {
    $inst = $InstanceArray
} Elseif ($ConnectionString) {
    $inst = $Server.ConnectionString
}

# For each instance found in the Registry or supplied through the -ConnectionString parameter
foreach ($i in $inst)
{
    # If there is an array of SQL Servers, Change the backup path depending on the server connection
    If ($InstanceArray) {

        $Server = Get-ServerObject $i

        # If the instance that is being targeted is not been setup, setup some folders and basic values
        If ($Server.Name -ne $LastConnection) {

            $BackupPath = Join-Path -path $Path -ChildPath $Server.Name
            $QueryFile = Join-Path -Path $BackupPath -ChildPath "BackupQueries.txt"

            # Create the backup directory
            If(!(test-path $BackupPath))
            {
                Try {
                    New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null
                } Catch {
                    $ErrorMessage = $_.Exception.Message
                    LogWrite "Error: There was an issue creating the backup directory" -Colour "Red"
                    LogWrite -log $ErrorMessage
                    Exit 10
                }
            }

            If (Test-Path $QueryFile) {
                Try {
                    Remove-Item -Force -Path $QueryFile -ErrorAction Stop
                } Catch {
                    LogWrite "Error: There was an issue removing the query file: $QueryFile" -Colour "Red"
                    LogWrite "Please manually remove this file and re-run script."
                    $ErrorMessage = $_.Exception.Message
                    LogWrite -log $ErrorMessage
                }
            }
            
            Try {
                New-Item -ItemType File -Force -Path $QueryFile | Out-Null
            } Catch {
                LogWrite "Error: There was an issue creating the query file: $QueryFile"
                $ErrorMessage = $_.Exception.Message
                LogWrite -log $ErrorMessage
            }

            LogWrite "Server name determined: $($Server.Name)" -Colour "Cyan"
            LogWrite "Backing up SQL Databases to: $BackupPath"
        }
    } Else {
        If ($ConnectionString -eq ''){
            $Server.Instance = $i
            $Server.ConnectionString = $Server.Name + "\" + $Server.Instance
        }
    }

    LogWrite "Connection String: $($Server.ConnectionString)"

    # Add the new log location to a collection so that the it can be copied there once the script has completed
    $LogLocation = Join-Path -Path $BackupPath -ChildPath $LogObject.Name
    $BackupLocationList.Add($LogLocation) | Out-Null

    # List all of the databases on an SQL Instance
    Try {
        If ($SelectDB){
            $UserDBs = Get-SqlDatabase -ServerInstance $Server.ConnectionString -ErrorAction Stop -Credential $SQLCredential | Out-GridView -PassThru -Title "Select Database for Backup"
            $LastConnection = $Server.Name
            $ConnectionSuccess++
        } Else {
            $UserDBs = Get-SqlDatabase -ServerInstance $Server.ConnectionString -ErrorAction Stop -Credential $SQLCredential
            $LastConnection = $Server.Name
            $ConnectionSuccess++
        }
        If ($null -eq $Server.Instance) {
            $SQLServerName = Invoke-SqlCmd -ServerInstance $Server.ConnectionString -Database "master" -Query 'select @@ServerName AS ServerName' -QueryTimeout 5 -ErrorAction Stop
            $ServerTemp = Get-ServerObject $SQLServerName.ServerName
            If ($null -eq $ServerTemp.Instance) {
                $Server.Instance = "MSSQLSERVER"
            } Else {
                $Server.Instance = $ServerTemp.Instance
            }
        }
    } Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Warning "Unable to determine available databases on the SQL Instance: $ConnectionString."
        LogWrite -log "Error: Unable to determine available databases on the SQL Instance: $ConnectionString."
        LogWrite -log $ErrorMessage
        $ConnectionError++
    }

    # Setup the folder structure for backups in this instance
    $InstancePath = Join-Path -Path $BackupPath -ChildPath $Server.Instance

    # Create the Instance Backup Directory
    If(!(test-path $InstancePath))
    {
        New-Item -ItemType Directory -Force -Path $InstancePath | Out-Null
    }

    # For every database found when connecting to the instance
    ForEach ($DB in $UserDBs)
    {
        # If the supplied database name using the -Database param has a value, check it with the current database name to make sure it is selected or else continue
        If (($Database -ne "" -and $DbArray -match $DB.Name) -or ($Database -eq "")) {

            # Checks the current database to make sure it is of normal status and it is not a snapshot before proceeding to backup
            If (($DB.Status -match "Normal*" -and $DB.IsDatabaseSnapshot -ne "True") -and ($DB.Name -ne "TempDB")) {

                # If the database is apart of an availability group check to make sure it is accessable or else continue
                If (($DB.AvailabilityGroupName -eq "") -or ($DB.IsAccessible -eq "True") -or ($AlwaysOn)) {

                    # If the database is a System DB check to see if the -SystemDB switch is set to continue
                    If ($SystemDB -or ($DB.ID -gt 4)) {

                        # Check to make sure that User Databases aren't being skipped with the -NoUserDB switch
                        If (!($NoUserDB -and ($DB.ID -gt 4))) {

                            LogWrite "Database Name: $($DB.Name)" -Colour "Cyan"
                            LogWrite "Database Recovery Mode: $($DB.RecoveryModel)"
                            LogWrite -log "Database Compatibility Level: $($DB.CompatibilityLevel)"
                            LogWrite -log "Database Owner: $($DB.Owner)"
                            LogWrite "Database Size on Disk: $(($DB.DataSpaceUsage / 1000).ToString('N2')) MB "

                            $BackupParams = @{
                                ServerInstance = $Server.ConnectionString
                                Database = $DB.Name
                                ErrorAction = "Stop"
                            }

                            If ($SQLCredential){
                                $BackupParams.Credential = $SQLCredential
                            }

                            If ($Compression) {
                                LogWrite "Compression has been enabled for this backup"
                                $BackupParams.CompressionOption = "On"
                            }

                            If ($CheckSum) {
                                LogWrite "CheckSum has been enabled for this backup"
                                $BackupParams.CheckSum = $true
                            }

                            If ($WhatIf) {
                                LogWrite "The Whatif Option has been enabled"
                                $BackupParams.WhatIf  = $true
                            }
                            
                            If ($Script) {
                                LogWrite "The Script Option has been enabled"
                                $BackupParams.Script = $true
                            }

                            # Create database directory for backups
                            If (!(Test-Path "$InstancePath\$($DB.Name)")) { 
                                New-Item -Path "$InstancePath\$($DB.Name)" -ItemType Directory | Out-Null 
                            }
                            
                            # If the -Full backup mode is selected continue with the Full backup methods
                            If ($BackupType -eq "FULL") {
                                $BackupFile = "$InstancePath\$($DB.Name)\$($DB.Name).FULL-$Date.bak"
                                LogWrite "Backup Location: $BackupFile"
                                $BackupParams.BackupFile = $BackupFile
                                Try {
                                    # If the database targeted by the full backup is a member of an AlwaysOn Availibliy group as a secondary or if -CopyOnly is selected, proceed with a Copyonly backup
                                    If (($CopyOnly) -or (($AlwaysOn) -and ($DB.AvailabilityGroupName -ne ""))) {
                                        LogWrite "Taking a COPY-ONLY backup of $($DB.Name)" -Colour "Magenta"
                                        $BackupParams.CopyOnly = $true
                                    # Create a Full Database backup
                                    } Else {
                                        LogWrite "Taking a FULL backup of $($DB.Name)" -Colour "Magenta"
                                    }

                                    $Duration = Measure-Command { Backup-SqlDatabase @BackupParams | Out-File -Append -FilePath $QueryFile }
                                    If ($Output) {
                                        LogWrite $Output
                                    }
                                    LogWrite "Success: Backup Completed in: $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Colour "Green"
                                    $BackupCompleted = $true
                                    $DatabaseCount++
                                } Catch {
                                    $ErrorMessage = $_.Exception.Message
                                    $ErrorCount++
                                    $BackupCompleted = $false
                                    LogWrite "Error: There was an issue backing up the database: $($DB.Name). If this database is on an AlwaysOn Secondary, supply the -AlwaysOn flag when backing up. Please check the log for details" -Colour "Red"
                                    LogWrite -log "Error: $ErrorMessage"
                                }
                            # If the -Diff backup mode is selected continue with the Diff backup methods
                            } ElseIf ($BackupType -eq "DIFF") {
                                If ((($DB.AvailabilityGroupName -ne "") -and ($DB.IsUpdateable -ne "TRUE")) -or ($DB.ID -lt 5)) {
                                    LogWrite "Skipping DIFF Backup for $($DB.Name) on server $($Server.ConnectionString). DIFF backup for AlwaysOn Read-Only or System databases are not supported" -Colour "Gray"
                                } Else {
                                    $BackupFile = "$InstancePath\$($DB.Name)\$($DB.Name).DIFF-$Date.bak"
                                    LogWrite "Backup Location: $BackupFile"
                                    $BackupParams.BackupFile = $BackupFile
                                    $BackupParams.Incremental = $true
                                    Try {
                                        LogWrite "Taking a DIFF backup of $($DB.Name)" -Colour "Magenta"
                                        $Duration = Measure-Command { Backup-SqlDatabase @BackupParams | Out-File -Append -FilePath $QueryFile }
                                        LogWrite "Success: Backup Completed in: $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Colour "Green"
                                        $BackupCompleted = $true
                                        $DatabaseCount++
                                    } Catch {
                                        $ErrorMessage = $_.Exception.Message
                                        $ErrorCount++
                                        $BackupCompleted = $false
                                        LogWrite "Error: There was an issue backing up the database: $($DB.Name). Please check the log for details" -Colour "Red"
                                        LogWrite -log "Error: $ErrorMessage"
                                    }
                                }
                            # If the -Log backup mode is selected continue with the Log backup methods
                            } ElseIf ($BackupType -eq "LOG") {
                                If (!($DB.RecoveryModel -eq "Simple")) {
                                    $BackupFile = "$InstancePath\$($DB.Name)\$($DB.Name).LOG-$Date.trn"
                                    LogWrite "Backup Location: $BackupFile"
                                    $BackupParams.BackupFile = $BackupFile
                                    $BackupParams.BackupAction = "Log"
                                    Try {
                                        LogWrite "Taking a LOG backup of $($DB.Name)"
                                        $Duration = Measure-Command { Backup-SqlDatabase @BackupParams | Out-File -Append -FilePath $QueryFile }
                                        LogWrite "Success: Backup Completed in: $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Colour "Green"
                                        $BackupCompleted = $true
                                        $DatabaseCount++
                                    } Catch {
                                        $ErrorMessage = $_.Exception.Message
                                        $ErrorCount++
                                        $BackupCompleted = $false
                                        LogWrite "Error: There was an issue backing up the database: $($DB.Name). Please check the log for details" -Colour "Red"
                                        LogWrite -log "Error: $ErrorMessage"
                                    }
                                } Else {
                                    LogWrite "Skipping Log Backup for $($DB.Name) on server $($Server.ConnectionString). Log backup for SIMPLE recovery model not supported" -Colour "Cyan"
                                }
                            }
                            If ($Verify) {
                                If ($WhatIf -or $Script) {
                                    LogWrite "Skipping verification phase" -Colour "Gray"
                                } Else {
                                    If ($BackupCompleted -eq $true) {
                                        If ($CheckSum) {
                                            $Query = "RESTORE VERIFYONLY FROM DISK = '$BackupFile' WITH CHECKSUM, STATS = 25"
                                        } Else {
                                            $Query = "RESTORE VERIFYONLY FROM DISK = '$BackupFile' WITH STATS = 25"
                                        }
                                        Try {
                                            Logwrite "Verifing the backup: $BackupFile" -Colour "Cyan"
                                            $Duration = Measure-Command { Invoke-SqlCmd -ServerInstance $Server.ConnectionString -Database "master" -Query $Query -QueryTimeout 0 -ErrorAction Stop -Verbose }
                                            LogWrite "Success: Verification Completed in: $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Colour "Green"
                                            $RestoredResult = $true
                                            $VerifyCount++
                                        } Catch {
                                            $ErrorMessage = $_.Exception.Message
                                            $ErrorCount++
                                            $RestoredResult = $false
                                            LogWrite "There was an issue testing the restore for the database: $($DB.Name). Please check the log for details" -Colour "Red"
                                            LogWrite -log "Error: $ErrorMessage"
                                        }
                                    } Else {
                                        LogWrite "Skipping the testing of the restore on an unsuccessful backup" -Colour "Gray"
                                    }
                                }
                            }
                            If ($Retention -gt 0) {
                                # If Verify has been selected, confirm that the backup has been verified before removing older backups
                                If (($Verify -and ($RestoredResult -eq $true)) -or ($Verify -eq $false)) {
                                    LogWrite "Deleting files older than $Retention Days" -Colour "Cyan"
                                    If ((Get-ChildItem -Path "$InstancePath\$($DB.Name)" -File -Force).count -gt 2) { # Make sure to leave at least 2 Backup Copies in the folder
                                        $RemoveMe = (Get-ChildItem -Path "$InstancePath\$($DB.Name)" -File -Force) |
                                            Where-Object { ($_.CreationTime -lt (Get-Date).AddDays(-$Retention)) } 
                                        If ($RemoveMe) { 
                                            LogWrite "Deleting old backup files $($RemoveMe.Name)"
                                            Try {
                                                $RemoveMe | Remove-Item -Force
                                            } Catch {
                                                $ErrorMessage = $_.Exception.Message
                                                $ErrorCount++
                                                LogWrite "Error: There was an issue removing old backup files. Please check the log for details" -Colour "Red"
                                                LogWrite -log "Error: $ErrorMessage"
                                            }
                                        }
                                    }
                                }
                            }
                        } Else {
                            LogWrite "Skipping User Database $($DB.Name) on server $($Server.ConnectionString). User Datbases not selected for Backup" -Colour "Gray"
                        }    
                    } Else {
                        LogWrite "Skipping System Database $($DB.Name) on server $($Server.ConnectionString). System Databases not selected for Backup" -Colour "Gray"
                    }
                } Else {
                    LogWrite "Skipping AlwaysOn $($DB.Name) on server $($Server.ConnectionString). AlwaysOn Databases not selected for Backup or Database is not accessable" -Colour "Gray"
                }
            } Else {
                LogWrite "$($DB.Name) on server $($Server.ConnectionString) is not eligible for Backup" -Colour "Gray"
            }
        } 
    }
}

If ($Script) {
    Write-Warning "No backups have been completed"
    LogWrite -log "No backups have been completed"
    LogWrite "The T-SQL Backup Scripts have been saved to: $QueryFile" -Colour "Green"
} ElseIf ($WhatIf) {
    LogWrite -log "Whatif command has been used. No backups have been taken."
    Write-Warning "Whatif command has been used. No backups have been taken."
} Else {
    LogWrite "Number of SQL Servers successfully established a connection: $ConnectionSuccess " -Colour "Green"
    LogWrite "Number of Databases successfully backed up: $DatabaseCount" -Colour "Green"
    If ($Verify) {
        LogWrite "Number of Databases successfully verified: $VerifyCount" -Colour "Green"
    }
}

If ($ConnectionError -gt 0) {
    LogWrite -log "Error: There were errors while connecting to one or more SQL Instances"
    LogWrite -Log "Number of Connection Errors: $ConnectionError"
    Write-Warning "There were errors while connecting to one or more SQL Instances. Please check the log for details"
}

If ($ErrorCount -gt 0) {
    LogWrite -log "Error: There were errors while backing up one or more databases"
    LogWrite -Log "Number of Errors: $ErrorCount"
    Write-Warning "There were errors while backing up or verifing one or more databases. Please check the log for details"
}

LogWrite "$($MyInvocation.MyCommand.Name) Completed Successfully"

If ($CSVFile) {
    ForEach ($i in $BackupLocationList)
    {
        LogWrite "Copying Log file to: $i"
        Copy-Item -Path $LogFile -Destination $i
    }
    Remove-Item -Path $LogFile
}

If (($ConnectionError -gt 0) -or ($ErrorCount -gt 0)) {
    Exit 15
}

Exit 0