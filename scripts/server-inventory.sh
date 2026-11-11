#!/bin/sh
# Read only; never prints container environments or credentials.
set -eu
hostname
lsblk --json -o NAME,MODEL,SERIAL,SIZE,FSTYPE,UUID,MOUNTPOINTS
findmnt -rn -t ext4,xfs,btrfs,exfat -o TARGET,SOURCE,FSTYPE,UUID
docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'
docker inspect mycloud-minio-1 --format '{{range .Mounts}}{{.Type}} {{.Name}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
free -h
