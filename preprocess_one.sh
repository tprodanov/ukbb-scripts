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

runtime=$( TIMEFMT="%U,%S,%E,%M";
    { time locityper preproc \
        -a "wdir/${sample}.cram" \
        -o "wdir/$sample" \
        -r "Ref/genome.fa" \
        -j "Ref/counts.jf" \
        -@ "$threads" &> "wdir/${sample}.log";
    } 2>&1 )

if [[ -f "wdir/${sample}/success" ]]; then
    res=OK
    mv "wdir/${sample}/distr.gz" "${sample}.gz"
else
    res=ERR
    mv "wdir/${sample}.log" "${sample}.log"
fi
rm -r "wdir/$sample"*

echo "${sample},${res},${runtime}"
