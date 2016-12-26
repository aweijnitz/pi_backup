#!/bin/bash
# Script for timestamping lines

while read x; do
    echo -n `date +%Y-%m-%d\ %H:%M:%S`;
    echo -n " ";
    echo $x;
done