#!/usr/bin/zsh

set -euo pipefail

sample="$1"
threads="$2"

cd wdir

# First two letters.
prefix="${sample:0:2}"
wgs="/mnt/project/Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
cram="$wgs/$prefix/${sample}_23372_0_0.cram"
# Copy index and stream CRAM file.
ln -s "$cram" "${sample}.cram"
cp "${cram}.crai" "${sample}.cram.crai"

cp "/mnt/project/Timofey/Locityper/bg/${sample}.gz" "${sample}.bg.gz"

runtime=NULL
runtime=$( TIMEFMT="%U,%S,%E,%M";
    { time locityper genotype \
        -a "${sample}.cram" \
        -d ../db \
        -p "${sample}.bg.gz" \
        -r "../ref/genome.fa" \
        -o "$sample" \
        -O 0 \
        -@ "$threads" &> /dev/null;
    } 2>&1 )

n="$(cp --parents -v "$sample/loci/"*/res.json.gz ../out | grep -cF .json.gz)"
echo "${sample},${n},${runtime}"

rm -r "$sample"*
