# SARDELKA

_**S**uper **A**wesome **R**sync **D**eduplicating **E**ncrypting and **L**in**K**ing **A**utomation_

Backup solution for incremental full backups (snapshots) with data de-duplication using nothing but Bash and Rsync.

The main features are the **synthetic full backups** with Rsync and *end-to-end encryption*. A _synthetic full backup_ is a full backup that only the uses the disk space of an incremental backup. It's a snapshot created with minimal size, similar to a copy-on-write tech of the time-machine and btrfs.
It does so by using hardlinks for any information that did not change, and only copying what did change. Essentially you get the best of both worlds: a full backup, always identical to the source at the time when it was taken, but only consuming the space required for the changes since the last backup.

The _end to end encryption_ is done via just-in-time mounting of remote LUKS encrypted volumes over SSH. The remote system can only stores a sparse encrypted file, never the encryption keys. Even if these files are leaked there is no way to get the original backup data.

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
* **Configuration backup** - system configuration backup - firewall, package and file/folder lists

## Commands

* **backup** - does the actual backups. It uses backup.config and backup.schedule for the backup configuration
* **backup-analyzer** - List size of unique content of all rolling backup directories aka synthetic full backups, taking hardlinking into account. Questions that it will help you answer:
    * What backup takes the most space? (space in unique backups, i.e. files that are not hardlinked in other backups)
	* What backups have no new information? (all files in the backup are hardlinked somewhere else)
	* What files take the most space in each backup? (what are the N biggest unique files in a backup)
	* What files may not have important information? (what are the most frequently changed files across backups. If a file changes often and is backed up often, it may be less important to keep around all the versions of)
    * As a feature the analyzer lookes across all backups, irrespective of the time they were taken, since it counts hardlinks. This means that files that were new to a give backup, but then showed up in later backups will NOT contribute to the uniquieness of that backup-set, unless/until you remove all other backups/hardlinks to these files.
* **backup-cleaner** - Remove full synthetic backups intelligently
	* Remove the partial and zero entropy backups
	* Remove all folders older than the number of days indicated as the parameter,
	* Remove all but the last N backups
	* Remove all folders with exclusivity less than or equal to a given percentage
	* Remove a given list of backups, showing progress
* **backup-mounter** - mount and unmount end-to-end encrypted backups. Saves the hassle of running the mount commands manually. Also necessary before running `restore`
* **backup-monitor** - Verify that all scheduled backups completed successfully within the proper timeframe, alert via email if not.
* **backup-ship-out** - Move full synthetic backups to another folder or filesystem for longer storage, hardlinking all identical files in the new folder/filesystem.
* **backup-functions** - not a script, but a bash library, containing Bash code for all backup functions invoked by the scripts above
* **restore** - does something related to backups, but in reverse ;)

### How to set up End-to-End encryption

The backup scripts treat end-to-end encrypted backup as local backups, except for the mounting and unmounting the file systems.
There are two ways to do this - with or without transport level encryption. The first one uses SSH, the second one uses NFS. The first one is slower and prone to hangups, the second one should only be used on semi-trusted networks, as metadata about the connection is not encrypted.

    NOTE: it is possible to encrypt NFS metadata traffic with `stunnel` but it's not currently implemented

You need to setup three things for the mounting:

* A way to connect - an ssh user with the private/public key set up on the backup server, which will be used to mount the remote disk over sshfs OR an NFS export share.
* a (sparse) file on the backup server containing the encrypted filesystem, which will later be mounted with cryptsetup
* a local LUKs key to decrypt the remote file containing the encrypted filesystem. This key never leaves the client ensuring e2e encryption

#### Setting up the SSH

1. Give your local user an ability to run LUKS and mount commands without requiring password. Running `sudo visudo` and add `<user here> ALL = (root) NOPASSWD:  /usr/sbin/cryptsetup,/usr/bin/umount,/usr/bin/rsync,/usr/sbin/ufw,/usr/bin/mount`
1. Create the ssh user key on the system you are backing up with something like `ssh-keygen -t ed25519 -f ~/.ssh/backupserver_backupuser`.
2. Create the user on the backup server with no password like this `sudo useradd -m -s /bin/bash backupuser`
3. Create the required folders, copy the public ssh key to `/.ssh/authorized_keys` and set proper access rights
```
sudo mkdir ~backupuser/.ssh
sudo vi ~backupuser/.ssh/authorized_keys
sudo chown -R backupuser:backupuser ~backupio/.ssh/
sudo chmod 700 ~backupuser/.ssh/
sudo chmod 600 ~backupuser/.ssh/authorized_keys
```
4. Create an entry on the system you are backing up in the `~/.ssh/config` like the following
```
Host backupserver
	User backupuser
	PubkeyAuthentication yes
	IdentityFile ~/.ssh/backupserver_backupuser
```
5. Login via `ssh e2eebackup` to ensure the server is known to the local ssh

#### Setting up NFS

Make sure you have the NFS client on the client: `sudo apt install nfs-common`

On the server

	sudo apt-get install nfs-kernel-server
	sudo systemctl start nfs-kernel-server.service
	sudo ufw allow from <client subnet> to any port nfs

vi /etc/export

	/media/disk <client subnet>(rw, async, no_subtree_check)

apply the config:

	sudo exportfs -a

### Setting up the encrypted storage

To create the encrypted file do the following on the system you want to backup. Do not do it directly on the remote backup server, unless its you really trust it.

1. Configure FUSE to allow root to operate on user mounts. This is needed because cryptsetup has to run as root to create /dev/mapper devices. To do this uncomment `user_allow_other` in `/etc/fuse.conf`
2. Mount the remote server destination over SSHFS to the local server: `sshfs -o reconnect,ConnectTimeout=10,ServerAliveInterval=10,allow_root e2eebackup:/media/disk/ /tmp/plain`
3. Create a sparse file of the size you'd like it to grow to eventually `truncate -s 2T /tmp/plain/file.bak`. Set its ownership to the `backupuser:backupuser` and `chmod 600`
4. Create an encryption key in the location specified by `KEY_FILES` in `backup.config` (defaults to `/root/.keyfiles`). The key file should be named exactly the same as the file you just created (e.g. "file.bak").
```
sudo mkdir /root/.keyfiles/
sudo dd if=/dev/urandom of=/root/.keyfiles/file.bak bs=4096 count=1
sudo chmod 400 /root/.keyfiles/file.bak
```
5. Format it for LUKS `cryptsetup luksFormat /tmp/plain/file.bak` setting up a recovery password and add your key `cryptsetup luksAddKey /tmp/plain/file.bak /root/.keyfiles/file.bak`, or just go all in with `cryptsetup luksFormat ~/tmp/plain/file.bak --key-file /root/.keyfiles/luks_remote_backups`
6. Mount and create the filesystem inside it:
```
sudo cryptsetup luksOpen /tmp/plain/file.bak --key-file /root/.keyfiles/file.bak backup-partition
sudo mkfs.ext4 -m0 -E lazy_itable_init=0,lazy_journal_init=0 /dev/mapper/backup-partition
sudo mount /dev/mapper/backup-partition /media/backups
```
7. Edit `backup.schedule` and specify which server to use and what file to mount like this: `e2ee://[sshalias]/[folder/file]`

* `sshalias` is the host alias in the `~/.ssh/config` file that specifies which user and key to use to connect to which server for the backup
* folder/file is the location of the encrypted file on the backup server

8. Prepare the folders. Pre-create folders for all backup sets.

```
sudo chown o+rw /tmp/plain/status
sudo chown user:user /media/backups
mkdir /media/backups/backupset && chmod 700 /media/backups/backupset
mkdir /media/backups/backupset2 && chmod 700 /media/backups/backupset2
```

9. Unmount everything with `backup-mounter <backupset> -u` so it does not block the actual backups.

Do not forget to backup your keyfile somewhere separately, otherwise the backups will be useless if they are stored a filesystem you are backing up and that filesystem is corrupted.

## Running

### As a docker container

Create the backup.schedule that can can contain only one line: `docker syntheticFullBackup 1 /source,/backups`. This names backups "docker" and sets a one per day frequency.

Create the backup.config file with, at the very least, these settings:
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
* Allow non-password sudo for required commands. `sudo visudo` or edit the /etc/sudoers file and add `<userhere> ALL = (root) NOPASSWD:  /usr/sbin/cryptsetup,/usr/bin/umount,/usr/bin/rsync,/usr/sbin/ufw,/usr/bin/mount`. Make sure it comes after all other staatement that may apply to your user, as the last statement takes precidence for sudo.
* Allow non-root sshfs users to mount as root. `sudo vi /etc/fuse.conf` and uncomment `user_allow_other`
* Rename backup.config.sample and backup.schedule.sample to backup.config and backup.schedule respectively
* Edit both files to configure your backups
* For GUI notifications install libnotify with `apt install libnotify-bin`
* Create .exclude file for each backup, even if it's empty. You can use the included samples for reference

## Scheduling periodic backups

The `backup` script checks the schedule and the backup server availability before it runs backups. You can use anacron or cron to run it as often as you want, or you can run it whenever your devices connects to a network.

* For scheduled runs create a symlink into /etc/cron.daily/ or add it to your crontab with crontab -e. If scheduling as root to backup a user folder, you might need to create a script to re-launch backup as a user, e.g.

```
echo "sudo -u user -H /home/user/bin/backupTools/backup" > /home/alex/bin/backupTools/backup-launcher-as-user
sudo ln -s /home/alex/bin/backupTools/backup-launcher-as-user /etc/cron.daily
```

* To trigger backups when connected to the right network create a script to launch `backup` as yourself by NetworkManager, e.g. `/etc/NetworkManager/dispatcher.d/55BackupLauncher.sh`


```
echo "sudo -u user -H /home/user/bin/backupTools/backup" | sudo tee /etc/NetworkManager/dispatcher.d/55BackupLauncher.sh
chmod 755 /etc/NetworkManager/dispatcher.d/55BackupLauncher.sh
sudo service network-manager restart
```

Verify that the proper network is specified in `backup.config`  or IF, ROUTERIP and ROUTERMAC variables and restart the network manager


## Restoring

1. Clone this repo
1. Restore the e2ee keys, configure the ssh keys
1. if using nfs, install the nfs client, e.g `apt install nfs-common`
1. `mkdir /media/backups`
1. If you are using e2ee, run `backup-mounter <system-name>`
1. Edit `./restore` and run it

## Monitoring and maintaining backups

If you want your backups to be monitored, schedule `backup-monitor` to run every day using the same methods outlined above for the `backup` command.

`backup.status` log shows the status of all past backups. For backups to a remote system the remote `backup.status` is authoritative, when deciding whether a new backup is needed or not. The local backup.status is just a convinient copy.

It's recommended to run `backup-analyzer` periodically as well, so you do not have to wait for it to recalculate everything before `backup-cleanup` can be used. Recalculating a big backup may take long time. To schedule it add a symlink to /etc/cron.daily.

## Requirements

* It's full of Bashisms (the best kind of -isms) and needs a bash 4.2 or above.
* Synthetic Full Backups work only on file systems that support proper hardlinks (hint, not NTFS)

## Rarely asked questions

* Why Bash?

Because less dependencies. Also because it grew up from a 5 line bash script kicking off rsync.

* Windows?

No. But maybe with WLS.
