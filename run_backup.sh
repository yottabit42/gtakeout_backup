#!/usr/bin/env bash
# Revision 200801a by Jacob McDonald <jacob@mcawesome.org>.

# Exit on any failure. Require set variables.
set -euo pipefail

# Debug by echoing all commands.
#set -x

###
# tl;dr: unpacks Google Takeout archive, dedupes, creates ZFS snapshot, pushes
# backup to Google Cloud Storage and/or arbitrary rclone remote. Full details are
# contained below, before the variable definitions block.
#
# TODO: use ${gcs_bucket} and ${rclone_remote} to optionally run these services.
###

###
# This script performs the following actions:
#
# 1. Extract the tgz archive(s) defined as ${archive}, over top of the
#    ${extract_path} subdir.
# 2. Run jdupes to replace all duplicate files with hardlinks against all paths
#    defined in the ${dataset_mounts} array.
# 3. Create a snapshot of the datasets defined in the ${datasets} array, with
#    the name defined as ${unix_seconds}.
# 4. Run jdupes to delete all duplicate hardlinks against all paths defined in
#    the ${dataset_mounts} array.
# 5. Run gsutil rsync to push new and changed files from ${backup_root} to the
     # storage bucket defined as ${gcs_bucket} in Google Cloud Storage.
# 6. Run rclone to push new and changed files from ${backup_root} to the remote
#    defined as ${rclone_remote}.
# 7. Rollback the snapshots to the (hardlink-)deduped state.
#
# The reason for #3 and #4 above is to cost-optimize the remote storage by not
# uploading duplicate data, which is not deduplicated on the remote. #7 rolls
# back the snapshot to restore the hardlink steady-state.
#
# Requirements:
#
#  1. bash: preferred shell compatible with this script.
#  2. parallel: optimize the speed of extract, especially on systems with a lot
#     of CPU threads and fast disks/SSD.
#  3. pigz: optimize the speed of extract, especially on systems with a lot of
#     CPU threads.
#  4. find: enumerate the archives for the extract loop.
#  5. tar: required for extraction of the data.
#  6. gsutil: required to push new and changed data to GCS.
#  7. Persistent authentication key for GCS.
#  8. rclone: required to push to other remotes, such as Amazon S3 or Glacier.
#  9. Persistent authentication key for rclone remote, e.g., AWS.
# 10. Passwordless SSH key to operate remote ZFS commands as root, if you want
#     to maximize automation. Can also use explicit passwordless definitions in
#     sudoers file to allow ZFS commands as non-root.
# 11. Google Takeout archive(s) must be in tgz (tar) format.
# 12. All tgz archives in the path will be used, so you probably want to place
#     them in a unique subdir.
###

###
# Define or change variables below.
###
# This is where you place the tgz Takeout archives.
archive_path=""  # e.g.: "/mnt/takeout_archives"
# These are the ZFS dataset names used for the dedupe.
datasets=("")  # e.g.: ("tank/dataset1" "tank/dataset2")
# These are the mountpoint s used for the dedupe.
dataset_mounts=("")  # e.g.: ("/mnt/dataset1" "/mnt/dataset2")
# This is the source for the backup push to cloud.
backup_root=""  # e.g.: "/mnt/cloud_push"
# This is where you want the Takeout archive extracted.
extract_path=""  # e.g.: "/mnt/takeout_backup"
# This is the name of your GCS bucket for backup push.
gcs_bucket=""  # e.g.: "gs://my-bucket-name"
# This is the rclone remote target, e.g., AWS S3 Vault ARN.
rclone_remote=""  # e.g.: "glacier:my-bucket-name"
# This sets the number of simultaneous upload streams for rclone.
rclone_streams="4"  # e.g.: "10"
# This is the SSH login of the ZFS host. See README.
host_id=""  # e.g.: "root@192.168.1.10"
# This uses the current unix seconds as a timestamp for the ZFS snapshot.
unix_seconds=$(date +%s)
# This sets the number of archives to unpack in parallel. See 'man parallel'.
parallelism="3"  # e.g.: "2" or "+4" or "-4" or "50%"
###

# gsutil needs UTF-8 set as the default encoding or it fails to understand
# UTF-8-encoded filenames.
export LANG="en_US.UTF-8"
export LC_COLLATE="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export LC_MESSAGES="en_US.UTF-8"
export LC_MONETARY="en_US.UTF-8"
export LC_NUMERIC="en_US.UTF-8"
export LC_TIME="en_US.UTF-8"
export LC_ALL=

extract() {
  echo "Starting archive extract."
  find "${archive_path}" -iname "*.tgz" | \
    parallel --bar --eta --env extract_path -j ${parallelism} -n 1 \
      --will-cite "unpigz -c {} | tar xC "${extract_path}" -f - > /dev/null"
  echo "Finished archive extract."
  echo; echo --; echo
}

dedupe_with_hardlinks() {
  for f in ${dataset_mounts[@]}; do
    echo "Replacing duplicates with hardlinks: ${f}."
    time jdupes -LNr "${f}"
    echo "Finished replacing duplicates with hardlinks."
    echo; echo --; echo
  done
}

snapshot() {
  for f in ${datasets[@]}; do
    echo "Creating ZFS snapshot ${f}@${unix_seconds}."
    time ssh "${host_id}" zfs snapshot "${f}@${unix_seconds}"
    echo "Finished creating ZFS snapshot."
    echo; echo --; echo
  done
}

delete_dupe_hardlinks() {
  for f in ${dataset_mounts[@]}; do
    echo "Deleting duplicate hardlinks: ${f}."
    time jdupes -dHNr "${f}"
    echo "Finished deleting duplicate hardlinks."
    echo; echo --; echo
  done
}

gcs_dryrun() {
  echo "Dry-run pushing to GCS because mistakes cost money."
  time /usr/local/bin/gsutil -m rsync -Cdnr "${backup_root}" "${gcs_bucket}"
  echo "Finished dry-run pushing to GCS."
  echo; echo --; echo
}

gcs_run() {
  echo "Pushing to GCS."
  time /usr/local/bin/gsutil -m rsync -Cdr "${backup_root}" "${gcs_bucket}"
  echo "Finished pushing to GCS."
  echo echo; echo --; echo
}

rclone_dryrun() {
  echo "Dry-run pushing to rclone remote target because mistakes cost money."
  time rclone sync -Pc --check-first --dry-run \
    "${backup_root}" "${rclone_remote}"
  echo "Finished pushing to rclone remote target."
  echo; echo --; echo
}

rclone_run() {
  echo "Pushing to rclone remote target."
  time rclone sync -Pc --check-first --transfers ${rclone_streams} \
    "${backup_root}" "${rclone_remote}"
  echo "Finished pushing to rclone remote target."
  echo; echo --; echo
}

rollback_snapshot() {
  for f in ${datasets[@]}; do
    echo "Rolling back ZFS snapshot ${f}@${unix_seconds}."
    time ssh "${host_id}" zfs rollback "${f}@${unix_seconds}"
    echo "Finished rolling back ZFS snapshot."
    echo; echo --; echo
  done
}

echo "Started at $(date)."
extract
dedupe_with_hardlinks
snapshot
delete_dupe_hardlinks
gcs_dryrun
#gcs_run
rclone_dryrun
#rclone_run
rollback_snapshot
echo "Completed successfully at $(date)."
