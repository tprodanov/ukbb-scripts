#!/usr/bin/zsh

set -euo pipefail

# File with sample ids.
samples="samples/$1"
if [[ "$2" =~ , ]]; then
    IFS=, read outer_threads inner_threads <<< "$2"
else
    outer_threads="$2"
    inner_threads=1
fi

samples_tar="/mnt/project/Timofey/samples.tar.gz"
tar xvf "$samples_tar" "$samples"

mkdir wdir ref
# Copy reference genome and k-mer counts.
cp /mnt/project/Ref/GRCh38/{full/genome.fa,full/genome.fa.fai,counts.jf} ref

cp /mnt/project/Timofey/Locityper/scripts/preprocess_one.sh .
chmod +x preprocess_one.sh

log_prefix="$(basename "$samples" .txt)"
(cat "$samples" | xargs -i -P "$outer_threads" \
    ./preprocess_one.sh {} "$inner_threads" | \
    sed --unbuffered 's/s,/,/g' | tee "${log_prefix}.time") || true

rm -r samples wdir ref preprocess_one.sh
