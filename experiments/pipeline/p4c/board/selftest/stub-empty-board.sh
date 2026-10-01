#!/bin/bash
c="$1"
case "$c" in
  *"echo BID="*) printf 'BID=82c150fb-88f6-4e25-ba12-94ec04ae217c\r\nUP=1892\r\nPD=1\r\nFESVR=0\r\nLOCK=NO_LOCK\r\nLOCKOWNER=\r\nTOOLS=timeout,\r\nls: /root/xv6run: No such file or directory\r\nLISTED=NODIR\r\n';;
  *"re-read"*|"echo FESVR="*) printf 'FESVR=0\r\nLISTED=NODIR\r\n';;
  *"echo TMO="*) printf 'TMO=yes\r\n';;
  "cat /proc/sys/kernel/random/boot_id") printf '82c150fb-88f6-4e25-ba12-94ec04ae217c\r\n';;
  *) echo "STUB: unexpected command: $c" >&2; exit 1;;
esac
