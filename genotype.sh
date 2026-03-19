#!/usr/bin/zsh

set -euo pipefail

# genotype.sh SAMPLES DB OUTER_THREADS[,INNER_THREADS] :: EXTRA_ARGS
# Also, reads exported variables `DEBUG` (run inner scripts with -x) and `SAVE_LOG`
# (both variables should hold true/false).

samples="samples/${1}.txt"
db_tar="$2"

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

# Extract Locityper database
mkdir db_tmp
cp "/mnt/project/$db_tar" db_tmp
tar -C db_tmp -xf db_tmp/$(basename $db_tar)
rm db_tmp/$(basename $db_tar)
db_dir="$(ls db_tmp | head -n1)"
mv "db_tmp/$db_dir" db
rm -rf db_tmp

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
