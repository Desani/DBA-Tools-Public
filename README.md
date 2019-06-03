# DBA-Tools-Public

This repository will contain tools that leverage PowerShell and SQL Modules to help automate some tasks that need to be performed by DBA's on the Microsoft SQL Server platform.

Currently the only available tool is Backup-SQLDatabse.ps1

Backup-SQLDatabase:

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

EXAMPLES:

.\Backup-SQLDatabases.ps1 -Full -Path G:\Backup

Create a Full backup for all User Databases on the local server to G:\Backup

.\Backup-SQLDatabase.ps1 -Full -CopyOnly -Path G:\Backup -Database "foglightdb,dbadmin,master" -SystemDB -AlwaysOn -SQLCredential sysdba

Create a Full Copy-Only backup for only the Databases dbadmin, foglightdb and master on the local SQL Server to G:\Backup. Runs the backup using the sysdba SQL Account.
-SystemDB and -AlwaysOn must be used to make sure the databases supplied are eligble for a backup as master is a SystemDB and
foglightdb is an AlwaysOn database in this example. -AlwaysOn only needs to be supplied when running the backup on a secondary AlwaysOn server.

.\Backup-SQLDatabase.ps1 -Diff -Path "\\NetworkLocation\sharedfolder" -Database -SystemDB -NoUserDB -ConnectionString "Servername,InstancePort" -Retention 14

Create a Diff backup of only the System Databases for a remote SQL Server Instance and attempts to remove backup files older than 14 days. 
This will resuly in no database backups as DIFF is not supported for System Databases.

.\Backup-SQLDatabase.ps1 -Log -Path G:\Backup -SelectDB -CheckSum -Verify -Compression
 
 Create a log backup of all the databses selected in the Gridview generated from a list of all databases with compression on and calculate a checksum and verify all backups created.
