#!/bin/bash
# Only tested with Debian 11 (TrueNAS SCALE)
# This script will mount the latest snapshot for each zfs filesytem currently mounted on the system into the below directory
backupDirectory="/tmp/zfs_backup_snapshots"
mkdir -p $backupDirectory

# requirements
# =============================================
# check for GNU version of find
type -P find &>/dev/null || { echo "We require the GNU version of find to be installed and aliased as 'find'. Aborting script."; exit 1; }

# check to make sure backupDirectory exists
stat "${backupDirectory}" &>/dev/null
if [[ $? == 1 ]]; then
        echo "The backup directory specified does not exist. Please create and try again: ${backupDirectory}"
        exit 1
fi


# functions
# =============================================

# umounts and cleans up the backup directory
# usage: zfs_backup_cleanup backupDirectory
function zfs_backup_cleanup() {
        # get all filesystems mounted within the backup directory
        fs=( $(tac /etc/mtab | cut -d " " -f 2 | grep "${1}") )

        # umount said filesystems
        for i in ${fs[@]}; do
                umount "$i"
        done

        # delete empty directories from within the backup directory
        find "${1}" -type d -empty -delete
}

# gets the name of the newest snapshot given a zfs filesystem
# usage: get_latest_snap filesystem
function zfs_latest_snap() {
                snapshot=$(zfs list -H -t snapshot -o name -S creation -d1 "${1}" | head -1 | cut -d '@' -f 2)
                if [[ -z $snapshot ]]; then
                                # if there's no snapshot then let's ignore it
                                return 1
                fi
                echo "$snapshot"
}


# gets the path of a snapshot given a zfs filesystem and a snapshot name
# usage zfs_snapshot_mountpoint filesystem snapshot
function zfs_snapshot_mountpoint() {
        # get mountpoint for filesystem
        mountpoint=$(zfs list -H -o mountpoint "${1}")

        # exit if filesystem doesn't exist
        if [[ $? == 1 ]]; then
                return 1
        fi

        # build out path
        path="${mountpoint}/.zfs/snapshot/${2}"

        # check to make sure path exists
        if stat "${path}" &> /dev/null; then
                echo "${path}"
                return 0
        else
                return 1
        fi
}

# mounts latest snapshot in directory
# usage: mount_latest_snap filesystem backupdirectory
function mount_latest_snap() {
        backupDirectory="${2}"
        fs="${1}"

        # get name of latest snapshot
        snapshot=$(zfs_latest_snap "${fs}")

        # if there's no snapshot then let's ignore it
        if [[ $? == 1 ]]; then
                echo "No snapshot exists for ${fs}, it will not be backed up."
                return 1
        fi

        sourcepath=$(zfs_snapshot_mountpoint "${fs}" "${snapshot}")
        # if the filesystem is not mounted/path doesn't exist then let's ignore as well
        if [[ $? == 1 ]]; then
                echo "Cannot find snapshot ${snapshot} for ${fs}, perhaps it's not mounted? Anyways, it will not be backed up."
                return 1
        fi

        # mountpath may be inside a previously mounted snapshot
        mountpath=${backupDirectory}/${fs}

        # mount to backup directory using a bind filesystem
        mkdir -p "${mountpath}"
        echo "mount ${sourcepath} => ${mountpath}"
        mount --bind --read-only "${sourcepath}" "${mountpath}"
        return 0
}


function usage() {
        echo "The following commands are supported:
   cleanup: Unmounts everything from the backup directory
     mount: Mounts the latest snapshot for every ZFS filesystem to the backup directory
      help: You're looking at it!"
        return 0
}

function cleanup() {
        zfs_backup_cleanup "${backupDirectory}"
        return 0
}


function mountOthers() {
        # get list of all non-root zfs filesystems on the box not including the ROOT since that has duplicate mountpoints
        # on TrueNAS SCALE the root pool is at boot-pool/ROOT, ensure egrep matches also in this case
        # order by shallowest mountpoint first (determined by number of slashes)
        # TODO: perhaps filter here, exclude if mountpoint doesn't contain "/" (like "none" or "legacy")
        filesystems=( $(zfs list -H -o name,mountpoint | awk '{print gsub("/","/", $2), $1}' | sort -n | cut -d' ' -f2- | egrep -v "(^boot-pool\/ROOT.*)|(^rpool\/ROOT.*)") )

        for fs in "${filesystems[@]}"; do
                mount_latest_snap "${fs}" "${backupDirectory}"
        done
        return 0
}

# ==========================================
# arguments parsing

if [[ $1 == "cleanup" ]]; then
        cleanup
        exit $?
elif [[ $1 == "mount" ]]; then
        mountOthers
        exit $?
elif [[ $1 == "help" ]]; then
        usage
        exit $?
else
        echo "missing command"
        usage
        exit 1
fi
