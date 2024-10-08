# gtakeout_backup

`get_takeout.sh` and `run_backup.sh` to assist downloading Google Takeout archives in parallel, and automate deduplication and backup of Google Takeout archives to local and remote targets.

## `get_takeout.sh`

Script to assist downloading Google Takeout archives in parallel.

You can watch a demo showing how to copy the Takeout archive cURL out of Google Chrome's developer tools, and use of the `get_takeout.sh` script, from [my YouTube video](https://youtu.be/CGAS24k1PQE).

In my experience using GNU curl from the Linux command line (which is called by the `get_takeout.sh` script) results in faster and more stable downloads than downloading with Google Chrome directly.

Notes:
1. You can only try to download each part 4 times before it is no longer valid.
2. You must copy the URL and start the download within 10 minutes before the authentication times out.
3. You must download all parts within 7 days before the archives are removed from Google Takeout.
4. While not completely necessary, it's best to configure Google Chrome to ask where to save each download. This way you can cancel the save prompt without starting a download. If you don't do this, you should go to the Chrome Downloads page (Ctrl/Cmd+J) and cancel the downloads there. Avoid conflicts if you are downloading to the same computer and directory with Chrome and the wrapper script.

Recommended number of parallel downloads:
* 100 Mbps download speed or less: 2
* 101-300 Mbps download speed: 3
* 301-500 Mbps download speed: 4
* 501 Mbps download speed or higher: 6

The speeds above are download speeds, not the speed of the connection to your Internet Service Provider. If your Internet Service Provider has insufficient peering with Google to support the speeds listed above, decrease the number of parallel downloads accordingly.

## `run_backup.sh`

Script to automate deduplication and backup of Google Takeout archives to remote cloud targets. Details and requirements are contained as comments in the script.
