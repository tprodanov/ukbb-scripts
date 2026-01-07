#!/usr/bin/zsh

set -euo pipefail

sample="$1"
threads="$2"

# First two letters.
prefix="${sample:0:2}"
wgs="/mnt/project/Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
cram="$wgs/$prefix/${sample}_23372_0_0.cram"
# Copy index and stream CRAM file.
ln -s "$cram" "wdir/${sample}.cram"
cp "${cram}.crai" "wdir/${sample}.cram.crai"

cp "/mnt/project/Timofey/Locityper/bg/${sample}.gz" "wdir/${sample}.bg.gz"

runtime=$( TIMEFMT="%U,%S,%E,%M";
    { time locityper genotype \
        -a "wdir/${sample}.cram" \
        -d db \
        -p "wdir/${sample}.bg.gz" \
        -r "ref/genome.fa" \
        -o "wdir/$sample" \
        -O 0 \
        -@ "$threads" &> "${sample}.log"
    } 2>&1 )

cat "${sample}.log"

cd wdir
n="$(cp --parents -v "$sample/loci/*/res.json.gz" ../out | grep -cF .json.gz)"

rm -r "$sample"*

echo "${sample},${n},${runtime}"
