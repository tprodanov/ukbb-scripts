#!/bin/bash

set -euo pipefail

sample="$1"
genome="$2"
counts="$3"
threads="$4"

prefix="${sample:0:2}"
cram="WGS/$prefix/${sample}_23372_0_0.cram"

time locityper preproc \
    -a "$cram" \
    -o "$sample" \
    -r "$genome" \
    -j "$counts" \
    -@ "$threads" &> "${sample}.log"

([[ -f "${sample}/success" ]] && mv "${sample}/distr.gz" "${sample}.gz") || touch "${sample}.err"
rm -r "$sample"
