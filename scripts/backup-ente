#!/bin/bash

LOCAL_BACKEUP="/mnt/ente/Ente Photos/"
DRIVE_BACKUP="/mnt/externalEnte/Ente Photos/"

rsync -az --dry-run --delete --itemize-changes "${LOCAL_BACKEUP}" "${DRIVE_BACKUP}" | awk '
  BEGIN {
    add = 0
    del = 0
  }
  /^>/ {add++}
  /^\*deleting/ {del++}
  END {
    print add " files to add"
    print del " files to delete"
  }
'

rsync -az --info=progress2 --delete "${LOCAL_BACKEUP}" "${DRIVE_BACKUP}"

rsync -az --dry-run --delete --itemize-changes "${LOCAL_BACKEUP}" "${DRIVE_BACKUP}" | awk '
  BEGIN {
    add = 0
    del = 0
  }
  /^>/ {add++}
  /^\*deleting/ {del++}
  END {
    print add " files to add"
    print del " files to delete"
  }
'

