#!/usr/bin/zsh

set -euo pipefail

# File with sample ids.
samples_file="$1"
if [[ "$2" =~ , ]]; then
    IFS=, read outer_threads inner_threads <<< "$2"
else
    outer_threads="$2"
    inner_threads=1
fi

mkdir wdir ref
# Copy reference genome and k-mer counts.
cp /mnt/project/Ref/GRCh38/{full/genome.fa,full/genome.fa.fai,counts.jf} ref

cp /mnt/project/Timofey/Locityper/scripts/preprocess_one.sh .
chmod +x preprocess_one.sh

cp "/mnt/project/$samples_file" samples.txt
log_prefix="$(basename "$samples_file" .txt)"
cat samples.txt | xargs -i -P "$outer_threads" \
    ./preprocess_one.sh {} "$inner_threads" | \
    sed --unbuffered 's/s,/,/g' | tee "${log_prefix}.time"

rm -r wdir ref
rm preprocess_one.sh samples.txt
