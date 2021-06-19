zfs-backup-snapshots
====================

This script will mount the latest snapshot of specified dataset into a directory so it can be backed up by a traditional backup system

```
$ zfs_backup_snapshots help
The following commands are supported:
     mount: Mounts latest snapshot of specified dataset to the backup directory
            Example: ./zfs_backup_snapshots.sh mount /tmp/test data/test
   cleanup: Unmounts everything from the backup directory
            Example: ./zfs_backup_snapshots.sh cleanup /tmp/test
      help: You're looking at it!
```
