#!/bin/bash
# Nautilus script to sync specified folder to another destination via rsync.
# Put this to ~/.gnome2/nautilus-scripts
# Written by Anton Keks

paths_file=$(readlink -f $0).paths
locations=`cat $paths_file`
sources=`cat $paths_file | awk -F'|' '{print $1}'`

if [ "$1" ]; then
  source=$1 
else
  # add current directory also to the list
  sources=`echo -e "$sources\\n$PWD" | sort -u`
  # ask user to chose one of the sources
  source=`zenity --list --title="Sync source" --text="No source was specified. Please choose what do you want to sync" --column=Source "$sources" Other...` || exit 1
  if [ "$source" = Other... ]; then
    source=`zenity --entry --title="Sync source" --text="Please enter the source path on local computer" --entry-text="$PWD"` || exit 1
  fi
fi

# normalize and remove trailing /
source=`readlink -f "$source"`
source=${source%/}

if [ ! -d "$source" ]; then
  zenity --error --text="$source is not a directory"; exit 2
fi

if [ $2 ]; then
  # TODO: support multiple sources
  zenity --warning --text="Only one directory can be synched, using $source"
fi

# find matching destinations from stored ones
destinations=""
for s in $sources; do
  if echo "$source" | fgrep $s; then
    dest=`fgrep "$s" $paths_file | awk -F'|' '{print $2}'`
    suffix=${source#$s}
    suffix=${suffix%/*}
    destinations="$destinations $dest$suffix" 
  fi
done

# ask user to chose one of the matching destinations of enter a new one
dest=`zenity --list --title="Sync destination" --text="Choose where to sync $source" --column=Destination $destinations New...` || exit 3
if [ $dest = New... ]; then
  basename=`basename "$source"`
  dest=`zenity --entry --title="Sync destination" --text="Please enter the destination (either local path or rsync's remote descriptor), omitting $basename" --entry-text="user@host:$(dirname $source)"` || exit 3
  echo "$source|$dest" >> $paths_file
fi

# check if user is not trying to do something wrong with rsync
if [ `basename "$source"` = `basename "$dest"` ]; then
  # sync contents of source to dest
  source="$source/"
fi

log_file=/tmp/Sync.log
rsync_opts=-rltEorzh
echo -e "The following changes will be performed by rsync (see man rsync for info on itemize-changes):\\n$source -> $dest\\n" > $log_file
( echo x; rsync -ni $rsync_opts --delete "$source" "$dest" 2>&1 >> $log_file ) | zenity --progress --pulsate --auto-close --width=350 --title="Retrieving sync information" 

if [ $? -ne 0 ]; then
  zenity --error --title="Sync" --text="Rsync failed: `cat $log_file`"; exit 4
fi

num_files=`cat $log_file | wc -l`
num_files=$((num_files-3))

if [ $num_files -le 0 ]; then
  zenity --info --title="Sync" --text="All files are up to date on $dest"; exit
fi

zenity --text-info --title="Sync review ($num_files changes)" --filename=$log_file --width=500 --height=500 || exit 4

num_deleted=$(grep '^\*deleting ' $log_file | wc -l)
if [ $num_deleted -ge 100 ]; then
  zenity --question --title="Sync" --text="$num_deleted files are going to be deleted from $dest, do you still want to continue?" --ok-label="Continue" || exit 4
fi

rsync_progress_awk="{	
	if (\$0 ~ /to-check/) {
		last_speed=\$(NF-3)
	}
	else {
		print \"#\" \$0 \" - \" files \"/\" $num_files \" - \" last_speed;
		files++;
		print files/$num_files*100 \"%\";
	}
	fflush();
}
END {
	print \"#Done, \" files \" changes, \" last_speed
}"

# note: delete-delay below means that any files will be deleted only as a last step
rsync $rsync_opts --delete-delay --progress "$source" "$dest" | awk "$rsync_progress_awk" | zenity --progress --width=350 --title="Synchronizing $source" || exit 4

