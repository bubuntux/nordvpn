#!/bin/bash

if [[ "$1" == "-w"  ]]; then
    echo $2 | sed 's/=/ = /'
    exit 0
else
    exec /sbin/sysctl.orig $@
fi
