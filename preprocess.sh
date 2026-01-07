#!/usr/bin/zsh

set -euo pipefail

mkdir wdir Ref
# Copy reference genome and k-mer counts.
cp /mnt/project/Ref/GRCh38/{full/genome.fa,full/genome.fa.fai,counts.jf} Ref

# File with sample ids.
samples_file="$1"
outer_threads="$2"
inner_threads=1

cp /mnt/project/Timofey/Locityper/scripts/preprocess_one.sh .
chmod +x preprocess_one.sh

cp "$samples_file" samples.txt
log_prefix="$(basename "$samples_file" .txt)"
cat samples.txt | xargs -i -P "$outer_threads" \
    ./preprocess_one.sh {} "$inner_threads" | \
    sed 's/s,/,/g' | tee "${log_prefix}.time"

rm -r Ref wdir
rm preprocess_one.sh samples.txt
