# Scripts for running Locityper on UK Biobank

Genotyping script has been updated to encorporate proper argument parsing,
while preprocessing is still being updated.
Both scripts assume file system is mounted into `/mnt/project`, all paths point there.

## Arguments and data structure

- `-r` : reference FASTA file with required FAI index,
- `-j` : jellyfish *k*-mer counts (necessary only for preprocessing),
- `-S` : TAR file containing multiple text files with sample subsets.
- `-s` : basename (possibly without suffix) of one of these text files.
- `-d` : TAR with Locityper database.
- `-p` : directory with preprocessed data. Data is structured in the following way:
    tar files `DIR/XX.tar.gz` contain files `XX/SAMPLE.gz`, where `XX` is two-letter prefix of the sample name,
    and `SAMPLE.gz` is preprocessed Locityper data (`distr.gz`).
- `-w` and `--wgs-infix` : path to WGS files and file infix. Files are located in `WGS_DIR/XX/SAMPLE${INFIX}.cram`.

Additional Locityper arguments can be passed after `--`, for example we used `--recr-alt-len 0` and possibly
`--recr-bed PATH`.

## Job submission

On UKB, to submit a job with have to use [Swiss-Army-Knife](https://community.ukbiobank.ac.uk/hc/en-gb/articles/29899902876829-Running-Docker-images-with-the-Swiss-Army-Knife-GUI-on-the-UKB-RAP) applet,
with submission command looking something like:
```sh
DB=database_name
SUBSET=subset_name
INSTANCE=mem2_ssd1_v2_x32
PRIORITY=low
dx run swiss-army-knife \
    --instance-type="$INSTANCE" \
    --priority="$PRIORITY" \
    --destination=/Timofey/Locityper/gt/"$DB" \
    -iimage_file=/Timofey/Locityper/locityper."*".tar.xz \
    -icmd='
        bash -x /mnt/project/Timofey/Locityper/scripts/genotype.sh \
            -s '$SUBSET' \
            -d Timofey/Locityper/dbs/'$DB'.tar.gz \
            -@ '${INSTANCE##*x}' \
            -- --recr-alt-len 0
    '
```
