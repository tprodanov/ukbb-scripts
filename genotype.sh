#!/usr/bin/zsh

set -euo pipefail

# File with sample ids.
samples_file="$1"
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

cp "/mnt/project/$samples_file" samples.txt
out_prefix="$(basename "$samples_file" .txt)"
# Allow 15 hours per sample
(cat samples.txt | xargs -i -P "$outer_threads" \
    timeout 54000 ./genotype_one.sh {} "$inner_threads" :: "${args[@]}" | \
    sed --unbuffered 's/s,/,/g' | tee "${out_prefix}.time") || true

# Create a TAR file combining all output files
tar cf "${out_prefix}.tar" -C out .

rm -r wdir ref db out
rm genotype_one.sh samples.txt
