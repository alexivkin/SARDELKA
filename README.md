# SARDELKA

_**S**uper **A**wesome **R**sync **DE**duplicating and **L**in**K**ing **A**utomation_

Backup solution for incremental full backups with data de-duplication using nothing but Bash and Rsync.

The main feature is the **synthetic full backups** with Rsync. A _synthetic full backup_ is a full backup that takes only the space required for an incremental backup.
It does so by using hardlinks for any information that did not change. Essentially you get the best of both worlds: a full backup, always identical to the source at the time when it was taken, and a backup that consumes only the space required for the changes since the last backup.

Other awesome features:

* Backup of a local system or a remote system through ssh, to a a local folder, a remote rsync server or a remote Tivoli Storage Management system
* Backup **scheduling and monitoring** to ensure they run on the scheduled time. Alert on backup failure, including remote backups that did not come in when they were expected
* **Rotating** backups - keep the last n days, or n copies of the backups
* **Shipping out** backups to the secondary storage
* Keeping track of how many files and bytes changed in the backup, and are unique to this backup in the set of backups, to make intelligent calls about old backup cleanup

Types of the backup supported

* **Incremental full backup** - aka synthetic full backup, keep full copies hardlinked to each other
* **Full backup** - a full rsync copy. There is an option to use secondary folder to move all replaced/deleted files for longer storage
* **Folder backup** - tar.gz copies of a folder
* **Configuration backup** - system configuration backup - firewall, package and file lists

## Commands

* **backup** - does the actual backups. It uses backup.config and backup.schedule for the backup configuration
* **backup-analyzer** - List size of unique content of all rolling backup directories aka synthetic full backups, taking hardlinking into account. Questions that it will help you answer:
    * What backup takes the most space? (space in unique backups, i.e. files that are not hardlinked in other backups)
	* What backups have no new information? (all files in the backup are hardlinked somewhere else)
	* What files take the most space in each backup? (what are the N biggest unique files in a backup)
	* What files may not have important information? (what are the most frequently changed files across backups. If a file changes often and is backed up often, it may be less important to keep around all the versions of)
* **backup-cleaner** - Remove full synthetic backups intelligently
	* Remove the partial and zero entropy backups
	* Remove all folders older than the number of days indicated as the parameter,
	* Remove all but the last N backups
	* Remove all folders with exclusivity less than or equal to a given percentage
	* Remove a given list of backups, showing progress
* **backup-monitor** - Verify that all scheduled backups completed successfully within the proper timeframe, alert via email if not.
* **backup-ship-out** - Move full synthetic backups to another folder or filesystem for longer storage, hardlinking all identical files in the new folder/filesystem.
* **backup-functions** - not a script, but a bash library, containing code for all backup functions invoked by the scripts above

## Running

### As a docker container

Create the backup.schedule that can can contain only one line: `docker syntheticFullBackup 1 /source,/backups`. This names backups "docker" and sets a one per day frequency.

Create the backup.config file that needs to have, at the very least:
```
DIR=/sardelka				# dir where all the scripts and configs are
BACKUPDESTDIR=/backups 			# backup destination
STATUSLOG=$DIR/backup.status 		# common log where status for all backups is kept
MINSPACE=10000 				# minimum free space before aborting a backup, in megabytes
```

Then run `docker-compose up`

The container will, verify that the backup is necessary, do the backup and stop.

If you want to monitor and persist the status of the backups, do `touch backup.status` and mount it to the container `-v "$(pwd)/backup.status":/sardelka/backup.status`

To do the backup without the docker compose run this monstrocity:

`docker run --rm --name backup -v "$(pwd)/backup.config":/sardelka/backup.config -v "$(pwd)/backup.schedule":/sardelka/backup.schedule -v "$(pwd)/backup.status":/sardelka/backup.status -v "/my/source/folder":/source -v "/my/backup/folder":/backups alexivkin/sardelka

Optionally you can expose the logs as `-v /log/folder:/sardelka/logs`

### Running natively

* Clone the repo
* Rename backup.config.sample and backup.schedule.sample to backup.config and backup.schedule respectively
* Edit both files to configure your backups
* Create .exclude file for each backup, even if it's empty. You can use the included samples for reference

## Scheduling periodic backups

To schedule `backup` to run every day either plop a symlink into /etc/cron.daily/ or add it to your crontab with crontab -e. If scheduling as root to backup a user folder, you might need to re-launch backup as a user, e.g.

Note that even though cron or anacron will start your script every day, it will not guarantee daily backups for laptops that you carry with you. Instead you might want to trigger backups when connected to the right network.
To do that create a script to launch `backup` as yourself by NetworkManager, e.g. `/etc/NetworkManager/dispatcher.d/55BackupLauncher.sh`

`sudo -u user -H /home/user/sardelka/backup`

Then

`chmod 755 /etc/NetworkManager/dispatcher.d/55BackupLauncher.sh`

Verify that the proper network is specified in `backup.config` IF, ROUTERIP and ROUTERMAC variables and restart the network manager

`sudo service network-manager restart`

## Monitoring and maintaining backups

If you want your backups to be monitored, schedule `backup-monitor` to run every day using the same methods outlined above for the `backup` command.

`backup.status` log shows the status of all past backups. For backups to a remote system the remote `backup.status` is authoritative, when deciding whether a new backup is needed or not. The local backup.status is just a convinient copy.

It's recommended to run `backup-analyzer` periodically as well, so you do not have to wait for it to recalculate everything before `backup-cleanup` can be used. Recalculating a big backup may take long time. To schedule it add a symlink to /etc/cron.daily.

## Requirements

* It's full of Bashisms (the best kind of -isms) and needs a bash 4.2 or above.
* Synthetic Full Backups work only on file systems that support proper hardlinks (hint, not NTFS)

## Rarely asked questions

* Why Bash?

Because KISS and less dependencies. Also because it grew up from a 5 line bash script kicking off rsync

* Windows?

No.
