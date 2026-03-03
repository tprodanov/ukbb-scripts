#!/usr/bin/zsh

set -euo pipefail

# genotype.sh SAMPLES DB OUTER_THREADS[,INNER_THREADS] :: EXTRA_ARGS

samples="samples/$1"
db_dir="$2"

# If contains "," then has two numbers, otherwise one
if [[ "$3" =~ , ]]; then
    IFS=, read outer_threads inner_threads <<< "$3"
else
    outer_threads="$3"
    inner_threads=1
fi

if [[ $# -ge 4 ]]; then
    [[ $4 = :: ]] || (echo "Next argument must be ::" >&2; exit 1)
    args=("${@:5}")
else
    args=()
fi

samples_tar="/mnt/project/Timofey/samples.tar.gz"
tar xvf "$samples_tar" "$samples"
out_prefix="$(basename "$samples" .txt)"

mkdir wdir ref out
# Copy reference genome and k-mer counts.
cp /mnt/project/Ref/GRCh38/{full/genome.fa,full/genome.fa.fai,counts.jf} ref

# Avoid copying multiple files by providing one tar file.
if [[ "$db_dir" =~ .tar ]]; then
    cp /mnt/project/"$db_dir" db.tar
    tar xf db.tar
    mv $(tar tf db.tar | head -n 1) db
    rm db.tar
else
    cp -r /mnt/project/"$db_dir" db
fi

cp /mnt/project/Timofey/Locityper/scripts/genotype_one.sh .
chmod +x genotype_one.sh

mkdir bg
# Take first two characters from each sample
cut -c-2 "$samples" | sort -u | xargs -i -P "$outer_threads" \
    tar -C bg -xf /mnt/project/Timofey/Locityper/bg/{}.tar.gz

# Allow 15 hours per sample
(cat "$samples" | xargs -i -P "$outer_threads" \
    timeout 54000 ./genotype_one.sh {} "$inner_threads" :: "${args[@]}" | \
    sed --unbuffered 's/s,/,/g' | tee "${out_prefix}.time") || true

# Create a TAR file combining all output files
tar cf "${out_prefix}.tar" -C out .

rm -r samples wdir ref db bg out \
    genotype_one.sh
