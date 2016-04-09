#!/usr/bin/env bash

#!/bin/bash
## Based on https://github.com/aalto-ics-kepaco/fswatch-rsync
################################################################################

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
reset=$(tput sgr0)

# Rsync details at https://www.samba.org/ftp/rsync/rsync.html
FSWATCH_PATH="fswatch"

# Sync latency / speed in seconds
LATENCY="3"

if [[ "$1" = "" || "$2" = "" ]]; then
  echo  "Usage: [WATCH=] sync.sh src_path dest_path"
  echo  " targetserver entry must exit in ssh config, which default to .ssh/config or else an SSH env var can be used for full SSH command control"
  echo  "e.g  WATCH= sync.sh . slcdev:tess/kubernetes"
  echo   "  will watch over the current directory and syncs to tess/kuberentes of slscdev (a host configured in ~/.ssh/config) "
  exit 1
else
  SRC="$1"
  TARGET=$2
fi

: ${SSH:='/usr/bin/ssh -F ~/.ssh/config'}

IGNORE_PATHS=(
    'Godeps/_workspace/pkg'
    '_output'
    '.git'
    '*.a'
)

rsync_excludes=""
for path in ${IGNORE_PATHS[@]}; do
    rsync_excludes="${rsync_excludes} --exclude $path"
done

#RSYNC="rsync -avzr ${DRY+-n} --delete --force --exclude 'Godeps/_workspace/pkg' --exclude '_output' --exclude '.git' --exclude '*.a'  $SRC $TARGET"
RSYNC="rsync -avzr ${DRY+-n} --delete --force ${rsync_excludes}  $SRC $TARGET"
echo -e "will run the following \n$RSYNC"

# Perform initial complete sync
read -n1 -r -p "press any key to continue (or abort with ctrl-C). Note that ${red}--delete${reset} option deletes missing file at the target " key
echo "synchronizing... "
eval "$RSYNC"
echo "${green}done${reset}"

# when using remote as source no WATCH support, otherwise flip using env WATCH
[[ -z ${WATCH+x} || $SRC == *":" ]] && exit 0

#http://stackoverflow.com/questions/3685970/check-if-an-array-contains-a-value
containsElement () {
  local e
  for e in "${@:2}"; do [[ "$1" =~ "$e" ]] && return 0; done
  return 1
}

fswatch_excludes=""
for path in ${IGNORE_PATHS[@]}; do
    fswatch_excludes="${fswatch_excludes} --exclude=$PWD/$path"
done

# Watch for changes and sync (exclude hidden files)
echo "watching for changes. quit anytime with ctrl-C."
echo "excluding $fswatch_excludes"
${FSWATCH_PATH} -0 -r -l $LATENCY $SRC --exclude="/\.[^/]*$" "${fswatch_excludes}" \
| while read -d "" event
  do
    # check to see if the relative path is ignored; not foolproof, but helps aovid unncessarily rysncing
    if ! containsElement "${event#$PWD/}" "${IGNORE_PATHS[@]}" ; then
        echo "${green}change in file $event ${reset}"
        eval "$RSYNC"
    fi
  done
