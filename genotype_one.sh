#!/usr/bin/zsh

set -euo pipefail

sample="$1"
threads="$2"

if [[ $# -ge 3 ]]; then
    [[ $3 = :: ]] || (echo "Next argument must be ::" >&2; exit 1)
    args=("${@:4}")
else
    args=()
fi

cd wdir

# First two letters.
prefix="${sample:0:2}"
wgs="/mnt/project/Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
cram="$wgs/$prefix/${sample}_23372_0_0.cram"
# Copy index and stream CRAM file.
ln -s "$cram" "${sample}.cram"
cp "${cram}.crai" "${sample}.cram.crai"

# TIMEFMT: User time, system time, elapsed time, peak memory
runtime=$( TIMEFMT="%U,%S,%E,%M";
    { time locityper genotype \
        -a "${sample}.cram" \
        -d ../db \
        -p "../bg/${prefix}/${sample}.gz" \
        -r "../ref/genome.fa" \
        -o "$sample" \
        -O 0 \
        -@ "$threads" \
        "${args[@]}" \
        &> /dev/null;
    } 2>&1 )

n="$(cp --parents -v "$sample/loci/"*/res.json.gz ../out | grep -cF .json.gz)"
echo "${sample},${n},${runtime}"

rm -r "$sample"*
