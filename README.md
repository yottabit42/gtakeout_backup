# gtakeout_backup

## `get_takeout.sh`

Script to assist downloading Google Takeout archives in parallel.

You can watch a demo showing how to copy the Takeout archive URL out of Google Chrome's developer tools, and use of the `get_takeout.sh` script, from [my YouTube video](https://youtu.be/h5idAEJorIc).

In my experience using GNU wget from the Linux command line (which is called by the `get_takeout.sh` script) results in more stable and faster downloads than downloading with Google Chrome directly.

Notes:
1. For this to work, the computer you're using to copy the URL, and the console you're using to download the URL, must come from the same public IP address (typical for home networks using NAT).
2. You can only try to download each part four times before it is no longer valid.
3. You must copy the URL and start the download within 10 minutes before the authentication times out.
4. While not completely necessary, it's best to configure Google Chrome to ask where to save each download. This way you can cancel the save prompt, but still obtain the URL without saving the file through Chrome. If you don't do this, you should go to the Chrome Downloads page (Ctrl/Cmd+J) and cancel the downloads there. Avoid conflicts if you are downloading to the same computer and directory with Chrome and the wrapper script.

Recommended number of parallel downloads:
* 100 Mbps download speed or less: 2
* 101-300 Mbps download speed: 3
* 301-500 Mbps download speed: 4
* 501 Mbps download speed or higher: 6

If your Internet Service Provider has insufficient peering with Google to support the speeds listed above, decrease the number of parallel downloads accordingly.

## `run_backup.sh`

Script to automate deduplication and backup of Google Takeout archives to remote cloud targets. Details and requires are contained as comments in the script.
