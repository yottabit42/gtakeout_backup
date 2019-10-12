#!/usr/bin/env bash
# Revision 191011a by Jacob McDonald <jacob@mcawesome.org>.

# Exit on any failure. Print every command. Require set variables.
set -euo pipefail

# Debug by echoing all commands.
#set -x

# TODO: use ${gcs_bucket} and ${rclone_remote} to optionally run these services.

###
# tl;dr: unpacks Google Takeout archive, dedupes, creates ZFS snapshot, pushes
# backup to Google Cloud Storage and/or arbitrary rclone remote. Full details are
# contained below the variable definitions block.
###

###
# Define empty variables below.
###

# This is where you place the tgz Takeout archives.
archive_path=""  # e.g.: "/mnt/takeout"

# This is the name of the ZFS dataset used for the backup.
dataset=""  # e.g.: "tank/google_photos_backup"

# This is where you want the Take archive extracted.
extract_path=""  # e.g.: "/mnt/google_photos_backup"

# This is the name of your GCS bucket for backup push.
gcs_bucket=""  # e.g.: "gs://my-bucket-name"

# This is the name of your rclone remote definition for backup push.
rclone_remote=""  # e.g.: "glacier:my-bucket-name"

# This is the SSH login of the ZFS host. See README.
host_id=""  # e.g.: "root@192.168.1.10"

# This uses the current unix seconds as a timestamp for the ZFS snapshot.
unix_seconds=$(date +%s)

# This sets the RAM allocation for mbuffer. Default is 1G.
ram_buffer="1G"  # e.g.: "1G"
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

###
# This script performs the following actions:
#
# 1. Extract the tgz archive(s) defined as ${archive}, over top of the
#    ${extract_path} subdir.
# 2. Run jdupes to replace all duplicate files with hardlinks.
# 3. Create a snapshot of the dataset defined as ${dataset} with the name defined
#    as ${unix_seconds}.
# 4. Run jdupes to delete all duplicate hardlinks.
# 5. Run gsutil rsync to push new and changed files to the storage bucket
#    defined as ${gcs_bucket} in Google Cloud Storage.
# 6. Run rclone to push new and changed files to the remote defined as
#    ${rclone_remote}.
# 7. Rollback the snapshot to the (hardlink-)deduped state.
#
# The reason for #3 and #4 above is to cost-optimize the remote storage by not
# uploading duplicate data, which is not deduplicated on the remote. #7 rolls
# back the snapshot to restore the hardlink steady-state.
###

###
# Requirements:
#
#  1. bash: preferred shell compatible with this script.
#  2. mbuffer: optimize the speed of extract, especially on systems with a lot
#     of RAM and slow disks.
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

echo "Started at $(date)."

echo "Starting archive extract."
for f in $(find "${archive_path}" -iname "*.tgz"); do \
  time mbuffer -i "${f}" -o - -m "${ram_buffer}" | \
    unpigz -c | \
      tar xOC "${extract_path}" -f - > /dev/null
done
echo "Finished archive extract."

echo "Replacing duplicates with hardlinks."
time jdupes -LNr "${extract_path}"
echo "Finished replacing duplicates with hardlinks."

echo "Creating ZFS snapshot ${dataset}@${unix_seconds}."
time ssh "${host_id}" zfs snapshot "${dataset}@${unix_seconds}"
echo "Finished creating ZFS snapshot."

echo "Delete duplicate hardlinks."
time jdupes -dHNr "${extract_path}"
echo "Finished deleting duplicate hardlinks."

# Comment out this block when testing is complete.
echo "Dry-run pushing to GCS because mistakes cost money."
time /usr/local/bin/gsutil -m rsync -rCdnx "gsutil_rsync\.log" \
  "${extract_path}" "${gcs_backup}"
echo "Finished dry-run pushing to GCS."

# Uncomment this block when testing is complete.
#echo "Pushing to GCS."
#time /usr/local/bin/gsutil -m rsync -rCdx "gsutil_rsync\.log" \
#  "${extract_path}" "${gcs_bucket}"
#echo "Finished pushing to GCS."

# Comment out this block when testing is complete.
#echo "Pushing to rclone remote."
time rclone sync -P --dry-run "${extract_path}" "${rclone_remote}"
#echo "Finished pushing to rclone remote."

# Uncomment this block when testing is complete.
#echo "Pushing to rclone remote."
#time rclone sync -P "${extract_path}" "${rclone_remote}"
#echo "Finished pushing to rclone remote."

echo "Rolling back ZFS snapshot ${dataset}@${unix_seconds}."
time ssh "${host_id}" zfs rollback "${dataset}@${unix_seconds}"
echo "Finished rolling back ZFS snapshot."

echo "Completed successfully at $(date)."
