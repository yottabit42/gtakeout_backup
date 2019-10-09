#!/bin/bash
# Revision 191008a by Jacob McDonald <jacob@mcawesome.org>.

# Exit on any failure. Print every command. Require set variables.
set -euxo pipefail

archive_path="/mnt/jacob.mcdonald/Junk"
dataset="vol0/google_photos_backup"
extract_path="/mnt/google_photos_backup/"
gcs_bucket=""
host_id="root@172.16.42.25"
unix_seconds=$(date +%s)
ram_buffer="4G"

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
# 6. TODO: Amazon S3.
# 7. Rollback the snapshot to the (hardlink-)deduped state.
#
# The reason for #3 and #4 above is to cost-optimize the remote storage by not
# uploading duplicate data, which is not deduplicated on the remote. #7 reverts
# the snapshot to restore the hardlink steady-state.
#
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
#  8. Passwordless SSH key to operate remote ZFS commands as root, if you want
#     to maximize automation.
#  9. Google Takeout archive(s) must be in tgz (tar) format.
# 10. All tgz archives in the path will be used, so you probably want to place
#     them in a unique subdir.
###

echo "Started at $(date)."

for f in $(find "${archive_path}" -iname "*.tgz"); do \
  time mbuffer -i "${f}" -o - -m "${ram_buffer}" | \
    unpigz -c | \
      tar xOC "${extract_path}" -f - > /dev/null
done

time jdupes -LNr "${extract_path}"

time ssh "${host_id}" zfs snapshot "${dataset}@${unix_seconds}"

time jdupes -dHNr "${extract_path}"

# 5. TODO.

# 6. TODO.

time ssh "${host_id}" zfs rollback "${dataset}@${unix_seconds}"

echo "Completed successfully at $(date)."
