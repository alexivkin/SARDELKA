# SARDELKA

_**S**uper **A**wesome **R**sync **DE**duplicating **L**in**K**ing **A**uthority_

File integrity monitoring and backup with data deduplication. Intrusion detection system and Incremental backup all in one.

The main feature is that they allow you to take a **Synthetic Full Backups** with Rsync. Synthetic Full Backup is a full backup that only takes space required for an incremental backup.
It does so by using hardlinks for any information that does not change. Essentially you get the best of both worlds: a full backup, always identical to the source at the time when it was taken, and a backup that consumes only the space required for the changes since the last backup.

Other awesome features:

* Backup of
	* a local system (duh)
	* a remote system through ssh
* Backup to
	* a remote rsync server
	* a remote CrashPlan server
	* a remote Tivoli Storage Management system
* Monitoring backups to ensure they run on the scheduled time
* Alert on backup failure, including remote backups that did not come in when expected
* Full backup - a single full rsync copy. There is an option to use secondary folder to move all replaced/deleted files for longer storage.
* Folder backup - tar.gz copy of a folder
* Configuration backup - system configuration (firewall, package and file lists), tarred

## Scripts

* backup - does the actual backups. It uses backup.config and backup.schedule for the backup configuration
* backup-analyzer - List size of unique content of all rolling backup directories aka synthetic full backups, taking hardlinking into account. Questions that it will help you answer:
    * What backup takes the most space? (space in unique backups, i.e. files that are not hardlinked in other backups)
	* What backups have no new information? (all files in the backup are hardlinked somewhere else)
	* What files take the most space in each backup? (what are the N biggest unique files in a backup)
	* What files may not have important information? (what are the most frequently changed files across backups. If a file changes often and is backed up often, it may be less important to keep around all the versions of)
* backup-cleaner - Remove full synthetic backups inteligently
	* Remove the partial and zero entropy backups
	* Remove all folders older than the number of days indicated as the parameter
	* Remove remove all folders with exclusivity less than or equal to a given percentage
	* Remove a given list of backups, showing progress
* backup-monitor - Verify that all scheduled backups completed successfully within the proper timeframe, alert via email if not.
* backup-ship-out - Move full synthetic backups to another folder or filesystem for longer storage, hardlinking all identical files in the new folder/filesystem.
* backup-functions - not a script, but a library, containing code for all backup functions invoked by the scripts above

## Installation

* Clone the repo
* Rename backup.config.sample and backup.schedule.sample to backup.config and backup.schedule respectively
* Edit both files to configure your backups
* Create .exclude file for each backup, even if it's empty. You can use the included samples for reference
* Schedule 'backup' to run every day - either plop a symlink into /etc/cron.daily/ or your crontab with crontab -e
* If you want your backups to be monitored too, schedule backup-monitor to run every day as well

Note: if scheduling as root to backup a user folder, you might need to re-launch backup as a user, e.g.

`sudo -u user -H /home/user/sardelka/backup`

## Notes

backup.status shows the status of all past backups. For backups to a remote system the remote backup.status is authoritative, when deciding whether a backup needs to run or not. In that case the local backup.status is just a convinient copy.

## Limitations

* It's full of Bashisms (the best kind of -isms) and needs a bash 4.2 or above.
* Synthetic Full Backups work only on file systems that support proper hardlinks (hint, not NTFS - Windows is out)

## Rarely asked questions

* Why Bash?
Because KISS and less dependencies. You only need bash and rsync on your device to get it going. Also because it grew up from a 5 line bash script kicking off rsync

* Windows?
No.
