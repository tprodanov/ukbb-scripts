#!/bin/bash

set -euo pipefail

rm -rf wdir && mkdir -p wdir

# Copy reference genome and k-mer counts.
mkdir Ref
cp /mnt/project/Ref/GRCh38/{full/genome.fa,full/genome.fa.fai,counts.jf} Ref

# File with sample ids.
samples_file="$1"
outer_threads="$2"
inner_threads=1

cp /mnt/project/Timofey/Locityper/scripts/preprocess_one.sh .
chmod +x preprocess_one.sh

cp "$samples_file" samples.txt
cat samples.txt | xargs -i -t -P "$outer_threads" \
    ./preprocess_one.sh {} "$inner_threads"

rm -r Ref wdir
rm preprocess_one.sh samples.txt
