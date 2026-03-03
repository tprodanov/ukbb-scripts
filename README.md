# Scripts for running Locityper on UK Biobank

Scripts `preprocess_one.sh` and `genotype_one.sh` process one sample on UKB and have two required arguments:
sample ID and the number of threads (usually 1).
In addition, `genotype_one.sh` allows for additional arguments after `::` that are passed directly into `locityper genotype`.

Both scripts copy CRAI index and soft-link the CRAM file, located at
```sh
wgs="/mnt/project/Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
# First two letters.
prefix="${sample:0:2}"
cram="$wgs/$prefix/${sample}_23372_0_0.cram"
```

Optimally, both scripts should be executed in `zsh` due to its better built-in `time` command, capable of recording memory usage.

## Preprocessing

Main preprocessing script `preprocess.sh` has two arguments: filename with the list of sample IDs
and number of threads `OUTER_THREADS[,INNER_THREADS]`.
Samples are split into multiple batches and are stored in a `tar.gz` file, its location is hardcoded to be
`/mnt/project/Timofey/samples.tar.gz`.

We then extract file `samples/${SAMPLES}.txt` from this TAR file, for example `samples/batch1000.txt` for `SAMPLES=batch1000`.

Additionally, the scripts expects reference genome at
`/mnt/project/Ref/GRCh38/full/genome.fa[.fai]` and corresponding k-mer counts at `/mnt/project/Ref/GRCh38/counts.jf`;
as well as the inner preprocessing script at `/mnt/project/Timofey/Locityper/scripts/preprocess_one.sh`.

## Genotyping

In addition to the sample files, reference genome and inner scripts, genotyping pipeline relies on preprocessed data.
After running preprocessing scripts, we organized it into `/mnt/project/Timofey/Locityper/bg/{}.tar.gz`
files, where `{}` encodes first two digits of the sample ID.

Such procedure can be done with
```sh
cut -c-2 ../samples/samples.txt | sort -u | parallel -P8 \
    mkdir {} '&&' cp ../bg0/{}"*" {}
cut -c-2 ../samples/samples.txt | sort -u | parallel -P8 --progress \
    tar cf - {} '|' gzip -9 '>' {}.tar.gz
```

The genotyping script is executed using `genotype.sh SAMPLES DB OUTER_THREADS[,INNER_THREADS] :: EXTRA_ARGS`
where `DB` is a TAR file with the Locityper target database, located in `/mnt/project`.

## Job submission

On UKB, to submit a job with have to use [Swiss-Army-Knife](https://community.ukbiobank.ac.uk/hc/en-gb/articles/29899902876829-Running-Docker-images-with-the-Swiss-Army-Knife-GUI-on-the-UKB-RAP) applet, with submission command looking something like:
```sh
DB=mucins-a
SUBSET=by_256/2e8:AAAAA1
INSTANCE=mem2_ssd1_v2_x32
PRIORITY=low
dx run swiss-army-knife \
    --instance-type=${INSTANCE} \
    --priority=${PRIORITY} \
    --destination=/Timofey/Locityper/gt/${DB} \
    -iimage_file=/Timofey/Locityper/locityper."*".tar.xz \
    -icmd='
        md5sum /mnt/project/Timofey/Locityper/scripts/genotype*.sh;
        zsh -x /mnt/project/Timofey/Locityper/scripts/genotype.sh \
            '$SUBSET' Timofey/Locityper/dbs/'$DB'.tar.gz '${INSTANCE##*x}' \
            :: --recr-bed ~~GRCh38 --recr-alt-len 0
    '
```
