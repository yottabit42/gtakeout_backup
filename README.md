# gtakeout_backup

`get_takeout.sh` and `run_backup.sh` to assist downloading Google Takeout archives in parallel, and automate deduplication and backup of Google Takeout archives to local and remote targets.

## `get_takeout.sh`

Script to assist downloading Google Takeout archives in parallel.

You can watch a demo showing how to copy the Takeout archive cURL out of Google Chrome's developer tools, and use of the `get_takeout.sh` script, from [my YouTube video](https://youtu.be/CGAS24k1PQE). Both Google Chrome (*Copy as cURL (bash)*) and Mozilla Firefox (*Copy as cURL (POSIX)*) are supported.

In my experience using GNU curl from the Linux command line (which is called by the `get_takeout.sh` script) results in faster and more stable downloads than downloading with Google Chrome or Mozilla Firefox directly.

Requirements: `bash`, `curl`, `pv`, and `tar` (with Google Takeout archives exported in `.tgz` format).

Behavior on failed or suspect downloads:
* Passes `--no-clobber` (when supported by `curl`) so duplicate server-supplied filenames are renamed instead of overwritten, and protects pre-existing files in the working directory from deletion.
* Tracks each parallel transfer's `curl` exit code, HTTP status, and `Content-Type` (catching HTTP `4xx`/`5xx` errors and expired-session `text/html` login redirects in addition to network/stream errors) without scanning healthy archives.
* Runs `pv -- <file> | tar tvz > /dev/null` on each suspect/failed download after the parallel `curl` batch finishes:
  * If `tar tvz` **passes**, the archive is kept and noted as salvaged (saving one of your 4 Takeout download attempts).
  * If `tar tvz` **fails**, the corrupt/incomplete file is deleted and the script reports which 1-based download sequence numbers failed in paste order (e.g., `download 1, download 4`), lists remaining files (`ls -lh`), and exits non-zero.

Notes:
1. You can only try to download each part 4 times before it is no longer valid.
2. You must copy the URL and start the download within 10 minutes before the authentication times out.
3. You must download all parts within 7 days before the archives are removed from Google Takeout.
4. While not completely necessary, it's best to configure your browser (e.g., Google Chrome or Mozilla Firefox) to ask where to save each download. This way you can cancel the save prompt without starting a download. If you don't do this, you should go to your browser's Downloads page (Ctrl/Cmd+J) and cancel the downloads there. Avoid conflicts if you are downloading to the same computer and directory with your browser and the wrapper script.

Recommended number of parallel downloads:
* 100 Mbps download speed or less: 2
* 101-300 Mbps download speed: 3
* 301-500 Mbps download speed: 4
* 501 Mbps download speed or higher: 6

The speeds above are download speeds, not the speed of the connection to your Internet Service Provider. If your Internet Service Provider has insufficient peering with Google to support the speeds listed above, decrease the number of parallel downloads accordingly.

## `run_backup.sh`

Script to automate deduplication and backup of Google Takeout archives to remote cloud targets. Details and requirements are contained as comments in the script.

Deterministic deduplication behavior:
* Uses `canonical_dir_patterns` (default: `("Photos from *")`) with `jdupes -O` (`--param-order`) and `-R` (`--recurse:`) to build a strictly disjoint, deterministically sorted directory list for both hardlinking (`dedupe_with_hardlinks`) and pre-upload duplicate hardlink removal (`delete_dupe_hardlinks`).
* Canonical year folders (e.g., `Photos from YYYY`) are always prioritized ahead of album folders regardless of album names, preventing cloud sync tools (`gsutil rsync` / `rclone sync`) from deleting and re-uploading existing photos when a new alphabetically-earlier album containing the same photos is added in a future Takeout export.
* Ancestor directories are scanned non-recursively (before `-R`) so loose files remain covered without parent/child path overlap, and datasets without matching canonical directories fall back cleanly to recursive deduplication of the mount root.
