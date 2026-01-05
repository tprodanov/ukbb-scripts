#!/bin/bash

set -euo pipefail

rm -rf /output && mkdir -p /output && cd /output
ln -s /mnt/project/Ref Ref
ln -s "/mnt/project/Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]" WGS
cp /mnt/project/Timofey/Locityper/scripts/preprocess_one.sh .
chmod +x preprocess_one.sh

samples="$1"
outer_threads="$2"
inner_threads=1
genome="Ref/GRCh38/full/genome.fa"
counts="Ref/GRCh38/counts.jf"

cat "$samples" | \
    xargs -i -t -P "$outer_threads" ./preprocess_one.sh {} "$genome" "$counts" "$inner_threads" \
    |& tee xargs.log

rm Ref WGS preprocess_one.sh
