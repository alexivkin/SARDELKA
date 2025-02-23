# SARDELKA

_**S**uper **A**wesome **R**sync **D**eduplicating **E**ncrypting and **L**in**K**ing **A**utomation_

A complete backup solution using nothing, but Bash and Rsync. The main features are the **synthetic full backups** and **end-to-end encryption**.

A _synthetic full backup_ is a full backup that only the uses the disk space of an incremental backup, similar to the copy-on-write technology of the time-machine and btrfs. 
It does so by using hardlinks for any files that did not change, and only copying what did change. You get the best of both worlds: a full backup, always identical to the source at the time when it was taken, 
and only using the space required for the an incremental backup, i.e changes since the last backup.

The _end to end encryption_ is done via just-in-time mounting of remote LUKS encrypted file stores. The backup server never sees the encryption keys. Even if the file stores are leaked there is no way to get the original backup data from them.

Other awesome features:

* Backup of a local system or a remote system through ssh/rsync/nfs to a local folder or a remote ssh/rsync/nfs server.
* Backup **scheduling and monitoring** to ensure they run on the scheduled time. Alert on backup failure, including remote backups that did not come in when they were expected
* **Rotating** backups - keep the last n days, or n copies of the backups
* **Shipping out** backups to the secondary storage 
* Keeping track of how many files and bytes changed in the backup, and are unique to this backup in the set of backups, to make intelligent calls about old backup cleanup
* Running as a **docker container**
* Support for backing up to a remote Tivoli Storage Management server

Types of the backup supported:

* **Incremental full backup** - aka synthetic full backup, keep full copies hardlinked to each other.
* **Full backup** - a full rsync copy. There is an option to use secondary folder to move all replaced/deleted files for longer storage.
* **Folder backup** - tar.gz  time-stamped copies of a folder
* **Configuration backup** - a system configuration backup - firewall config, installed packages and file/folder lists

## Commands

* **backup** - does the actual backup. It uses configuration from `backup.config` and `backup.schedule`
* **backup-setup** - configures your client to perform the backup, particularly the end-to-end backup.
* **backup-analyzer** - reviews existing backups for the files that take the most space. It understands hardlinks and synthetic backups. Questions that it will help you answer:
    * What backup takes the most space? (space in unique backups, i.e. files that are not hardlinked in other backups)
	* What backups have no new information? (all files in the backup are hardlinked somewhere else)
	* What files take the most space in each backup? (what are the N biggest unique files in a backup)
	* What files may not have important information? (what are the most frequently changed files across backups. If a file changes often and is backed up often, it may be less important to keep around all the versions of)
    * As a feature the analyzer lookes across all backups, irrespective of the time they were taken, since it counts hardlinks. This means that files that were new to a give backup, but then showed up in later backups will NOT contribute to the uniquieness of that backup-set, unless/until you remove all other backups/hardlinks to these files.
* **backup-cleaner** - removes full synthetic backups intelligently. For example
	* Remove the partial and zero entropy backups
	* Remove all folders older than the number of days indicated as the parameter
	* Remove all but the last N backups
	* Remove all folders with exclusivity less than or equal to a given percentage
	* Remove a given list of backups, showing progress
* **backup-mounter** - mount and unmount end-to-end encrypted backups. Saves the hassle of running the mount commands manually. Also necessary before running the `restore`
* **backup-monitor** - Verify that all scheduled backups completed successfully within the proper timeframe, alert via email if not.
* **backup-ship-out** - Move full synthetic backups to another folder or filesystem for longer storage, hardlinking all identical files in the new folder/filesystem.
* **backup-functions** - not a script, but a bash library, containing Bash code for all backup functions invoked by the scripts above
* **restore** - does backups, but in reverse

## Running

### Running the backup scripts natively

* If you are planning to backup remotely, not on the local disk, then configure your backup server per instructions in the sections below. 
* Copy `backup.config.sample` and `backup.schedule.sample` to `backup.config` and `backup.schedule` respectively. Edit both files to configure your backups. 
* Run `backup-setup`. It will do the following for you:
  * Set up a way to connect to the backup server. An ssh user with the private/public key set up on the backup server for SSHFS or NFS exported share for NFS.
  * For the end-to-end encrypted backups: 
    * Create a storage file on the backup server containing the encrypted filesystem, which will later be mounted with cryptsetup. 
    * Create a local LUKs key to decrypt the remote file containing the encrypted filesystem. This key never leaves the client to ensure true e2e encryption.
  * Schedule the backup for periodic runs using systemd timers
* Run `backup` or `sudo systemd start backup` or wait for the systemd timer to kick it off.

If you are doing E2EE backups, do not forget to backup your encryption key files somewhere separately, otherwise the backups will be useless in event of a failure. 
It may also be usefull to add a passphrase to the LUKS headers as a manual recovery alternative to the key files.

### Running as a docker container

* Copy `backup.config.sample` and `backup.schedule.sample` to `backup.config` and `backup.schedule` respectively. Edit both files to configure your backups.
* Run `docker-compose up`.  The container will verify that the backup is necessary, do the backup and stop. Althernatively you can run the backup without the docker compose with this monstrocity:

`docker run --rm --name backup -v "$(pwd)/backup.config":/sardelka/backup.config -v "$(pwd)/backup.schedule":/sardelka/backup.schedule -v $(pwd)/logs:/sardelka/logs -v "$(pwd)/backup.status":/sardelka/backup.status -v "/my/source/folder":/source -v "/my/backup/folder":/backups alexivkin/sardelka`

##  Backup server setup

There are three supported ways to do remote backups: rsync, SSH or NFS. SSH is the only one that provides full traffic encryption, for the other two use VPN over untrusted networks, or stunnel over more trusted ones.

1. Fix the IP for the backup server. Set the following in `/etc/network/interfaces.d/eth0`

```
auto eth0
iface eth0 inet static
address 192.168.<your IP here>
netmask 255.255.255.0
gateway 192.168.1.1
dns-nameservers 192.168.1.2
```
1. Designate a big enough disk for the backups. HDD is fine to use, instead of SSD since the network throughpout is likely going to be bottleneck. Format it with the ext4 file system and mount it.
If you are planning to use it for the end-to-end encrypted backups use `mkfs.ext4 -m0 -T largefile4 /dev/mapper/$E2EE_FILE`.
All the linux filesystems (XFS/BRTFS etc) are all more or less the same for this use, since it's just a small number of very large files. Using the largefile4 option reduces the space wasted on the inodes.
1. Follow the instruction in the appropriate section below.

### Rsync backup server setup

Install rsync. That's it.

### NFS backup server setup

To configure NFS export do the following:

```
sudo apt-get -y install nfs-kernel-server
sudo systemctl start nfs-kernel-server.service
sudo ufw allow from <client subnet> to any port nfs
disk=backups
subnet=192.168.1.1/24
echo "/media/$disk $subnet(rw, async, no_subtree_check)" | tee -a /etc/exports
sudo exportfs -a
```

Open up the backup folder for everyone
```
sudo chmod 777 /media/$disk
touch /media/$disk/status
chown o+rw /media/$disk/status
```

### SSH backup server setup

To configure the SSH connection you need to:

1. Create the ssh user key on the system you are backing up (client) with something like `ssh-keygen -t ed25519 -f ~/.ssh/backupserver_backupuser`.
2. Create the user on the backup server with no password like this `sudo useradd -m -s /bin/bash backupuser`. Not setting the password would limit the login to only the SSH key
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
5. Test SSH login from the client via `ssh e2eebackup` to ensure the server is known to the local ssh.

## Restoring

1. Clone this repo
1. Restore the e2ee keys, configure the ssh keys
1. if using nfs, install the nfs client, e.g `sudo apt install nfs-common`
1. `mkdir /media/backups`
1. If you are using e2ee, run `backup-mounter <system-name>`
1. Edit `./restore` and run it

## Monitoring and maintaining backups

If you want your backups to be monitored, schedule `backup-monitor` to run every day using the same methods outlined above for the `backup` command.

`backup.status` log shows the status of all past backups. For backups to a remote system the remote `backup.status` is authoritative, when deciding whether a new backup is needed or not. The local backup.status is just a convinient copy.

It's recommended to run `backup-analyzer` periodically as well, so you do not have to wait for it to recalculate everything before `backup-cleanup` can be used. Recalculating a big backup may take long time. To schedule it add a symlink to /etc/cron.daily.

## How end-to-end encrypted backups work

End-to-end encryption uses EXT4 fs stored inside a LUKS encrypted file. This allows backup scripts to treat end-to-end encrypted backup as local backups, except for the mounting and unmounting the file systems.
The mounting can be done with or without transport level encryption.The first one uses SSH, but is slower and prone to hangups, the second one uses NFS, but does not encrypt metadata about the connection. The data itself is encrypted either way.
Note that although is possible to encrypt NFS traffic metadata with `stunnel`, it's not currently implemented. An alternative to `stunnel` is using a VPN, e.g. `wireguard` to encrypt the NFS traffic.

## Requirements

* It's full of Bashisms (the best kind of -isms) and needs a bash 4.2 or above.
* Synthetic Full Backups work only on file systems that support proper hardlinks (hint, not NTFS)
* backup-setup assumes a debian based distro, i.e. the deb package manager.

## Rarely asked questions

* Why Bash?

Because less dependencies. Also because it grew up from a 5 line bash script kicking off rsync.
