#!/bin/bash
# Only tested with Debian 11 (TrueNAS SCALE)
# This script will mount the latest snapshot of specified dataset to the backup directory
BACKUP_DIRECTORY=$2
ZFS_DATASET=$3

# requirements
# =============================================
# check for GNU version of find
type -P find &>/dev/null || { echo "We require the GNU version of find to be installed and aliased as 'find'. Aborting script."; exit 1; }

# functions
# =============================================

function usage() {
        echo "The following commands are supported:
     mount: Mounts latest snapshot of specified dataset to the backup directory
            Example: $0 mount /tmp/test data/test
   cleanup: Unmounts everything from the backup directory
            Example: $0 cleanup /tmp/test
      help: You're looking at it!"
        return 0
}

# umounts and cleans up the backup directory
# usage: zfs_backup_cleanup BACKUP_DIRECTORY
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
# usage: mount_latest_snap filesystem BACKUP_DIRECTORY
function mount_latest_snap() {
        BACKUP_DIRECTORY="${2}"
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
        mountpath=${BACKUP_DIRECTORY}/${fs}

        # mount to backup directory using a bind filesystem
        mkdir -p "${mountpath}"
        echo "mount ${sourcepath} => ${mountpath}"
        mount --bind --read-only "${sourcepath}" "${mountpath}"
        return 0
}

function cleanup() {
        zfs_backup_cleanup "${BACKUP_DIRECTORY}"
        return 0
}


function mount_dataset() {
        # ensure BACKUP_DIRECTORY exists
        mkdir -p $BACKUP_DIRECTORY
        # get list of all zfs filesystems under $ZFS_DATASET
        # exclude if mountpoint "legacy" and "none" mountpoint
        # order by shallowest mountpoint first (determined by number of slashes)
        filesystems=( $(zfs list $ZFS_DATASET -r -H -o name,mountpoint | egrep -v "(legacy)$|(none)$" | awk '{print gsub("/","/", $2), $1}' | sort -n | cut -d' ' -f2-) )

        for fs in "${filesystems[@]}"; do
                mount_latest_snap "${fs}" "${BACKUP_DIRECTORY}"
        done
        return 0
}

# ==========================================
# arguments parsing

if [[ $1 == "cleanup" && -n $BACKUP_DIRECTORY ]]; then
        cleanup
        exit $?
elif [[ $1 == "mount" && -n $BACKUP_DIRECTORY && -n $ZFS_DATASET ]]; then
        mount_dataset
        exit $?
elif [[ $1 == "help" ]]; then
        usage
        exit $?
else
        echo "missing command"
        usage
        exit 1
fi
