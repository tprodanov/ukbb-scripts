#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

function help_message { cat <<HELP
Usage: $SCRIPT_NAME -s FILE -d FILE -@ INT [-- locityper-args]

Genotype a group of samples on UK Biobank.

Available options:
    -S, --samples-tar  FILE  Path to a tarball containing various sample subsets [${samples_tar}].
    -s, --samples      FILE  Basename of the sample subset.
                             No extension is necessary, but only one file must match the prefix.
    -d, --database     FILE  Path to a tar with Locityper database.
    -p, --preproc      DIR   Folder with preprocessed tar.gz files, groupped
                             by first two characters (DIR/XX.tar.gz) [${preproc_dir}].
    -r, --reference    FILE  Reference FASTA file (must contain .fai index) [${reference}].
    -w, --wgs          DIR   WGS data location and infix [default: UKB specific].
        --wgs-infix    STR   CRAM infix, files will be located at
                             DIR/XX/SAMPLE\$INFIX.cram [default: UKB specific].
    -@, --threads      INT   Number of Locityper instances, executed at the same time.
        --gt-threads   INT   Run Locityper with this number of threads [${gt_threads}].
        --debug              Run inner function with -x flag.
        --save-log           Save Locityper logs.
        --save-json          Save JSON files. By default, only genotypes are saved.
        --timeout      NUM   Timeout in hours [${timeout_hs}].
    -h, --help               Print this help and exit.

All paths should be relative to the mount point /mnt/project.

Pass additional Locityper arguments after --
HELP
}

function cleanup {
    trap - INT TERM ERR EXIT
    rm -rf wdir
}
trap cleanup INT TERM ERR EXIT

function setup_colors {
    readonly RED="\e[31m"
    readonly ENDCOLOR="\e[0m"
}

function msg {
    echo -e "$*" >&2
}

function err {
    msg "${RED}[ERROR]${ENDCOLOR} $*"
}

function panic {
    err "$1"
    exit "${2-1}" # Return 1 by default.
}

function parse_params {
    samples_tar="Timofey/samples.tar.gz"
    preproc_dir="Timofey/Locityper/bg"
    reference="Ref/GRCh38/full/genome.fa"
    wgs_dir="Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
    cram_infix="_23372_0_0"
    gt_threads=1
    debug=n
    save_log=n
    save_json=n
    timeout_hs=10

    long1="samples-tar:,samples:,database:,preproc:,reference:,wgs:,wgs-infix:,"
    long2="threads:,gt-threads:,debug,save-log,save-json,timeout:,help"
    ARGS="$(getopt -o S:s:d:p:r:w:@:h --long "${long1}${long2}" --name "$SCRIPT_NAME" -- "$@")"
    eval set -- "$ARGS"
    while :; do
        case "$1" in
            -S | --samples-tar)
                samples_tar="$2"; shift 2 ;;
            -s | --samples)
                samples="$2";     shift 2 ;;
            -d | --database)
                database="$2";    shift 2 ;;
            -p | --preproc)
                preproc_dir="$2"; shift 2 ;;
            -r | --reference)
                reference="$2";   shift 2 ;;
            -w | --wgs)
                wgs_dir="$2";     shift 2 ;;
            --wgs-infix)
                cram_infix="$2";  shift 2 ;;
            -@ | --threads)
                threads="$2";     shift 2 ;;
            --gt-threads)
                gt_threads="$2";  shift 2 ;;
            --debug)
                debug=y;      shift ;;
            --save-log)
                save_log=y;   shift ;;
            --save-json)
                save_json=y;  shift ;;
            --timeout)
                timeout_hs="$2"; shift 2 ;;
            -h | --help)
                help_message; exit 0;
                ;;
            -- ) shift; break ;;
            * )  panic "Unexpected argument $1" ;;
        esac
    done

    gt_args=( "$@" )
    [[ ! -z "${samples-}" ]] || panic "Missing required parameter: samples"
    [[ ! -z "${database-}" ]] || panic "Missing required parameter: database"
    [[ ! -z "${threads-}" ]] || panic "Missing required parameter: threads"
    timeout="$(awk "BEGIN { print int(${timeout_hs} * 60 * 60) }")"
    [[ "$debug" = n ]] && debug_arg="" || debug_arg="-x"
}

function prepare_folders {
    fs=/mnt/project
    mkdir -p wdir out
    ln -s "${fs}/${wgs_dir}" wdir/wgs
}

function extract_samples {
    mkdir samples-tmp
    cp "${fs}/${samples_tar}" samples-tmp/samples.tar

    local filenames
    readarray -t filenames < <(tar tf samples-tmp/samples.tar | grep -P "(^|/)${samples}")
    [[ ${#filenames[@]} -eq 1 ]] || panic "${#filenames[@]} files match prefix ${samples}"
    local filename
    filename="${filenames[0]}"

    tar -C samples-tmp -xf samples-tmp/samples.tar "$filename"
    mv "samples-tmp/$filename" wdir/samples.txt
    rm -r samples-tmp

    out_prefix="$(basename "$samples" .txt)"
}

function extract_database {
    mkdir db_tmp
    cp "${fs}/$database" db_tmp/db.tar
    tar -C db_tmp -xf "db_tmp/db.tar"
    rm "db_tmp/db.tar"

    local db_dir
    db_dir="$(ls db_tmp | head -n1)"
    mv "db_tmp/$db_dir" wdir/db
    rm -rf db_tmp
}

function extract_preproc {
    mkdir wdir/bg
    cut -c-2 wdir/samples.txt | sort -u | \
        xargs -i -P "$threads" \
        tar -C wdir/bg -xf "${fs}/${preproc_dir}/{}.tar.gz"
}

function copy_reference {
    cp "${fs}/${reference}" wdir/genome.fa
    cp "${fs}/${reference}.fai" wdir/genome.fa.fai
}

function genotype_one {
    # Need exported variables $gt_threads, $debug_arg, $save_log, $save_json, $cram_infix, $timeout.
    # debug_arg without quotes because it can be empty and skipped.
    set $debug_arg -euo pipefail

    local sample gt_args prefix cram log cmd runtime n
    # First proper argument: sample, all rest: additional locityper arguments.
    sample="$1"
    gt_args="${@:2}"

    cd wdir
    # First two letters.
    prefix="${sample:0:2}"
    cram="wgs/$prefix/${sample}${cram_infix}.cram"
    # Copy index and stream CRAM file.
    ln -s "$cram" "${sample}.cram"
    cp "${cram}.crai" "${sample}.cram.crai"

    [[ "$save_log" = y ]] && log="../out/${sample}.log" || log=/dev/null

    cmd=( time locityper genotype \
        -a "${sample}.cram" -d db -p "bg/${prefix}/${sample}.gz" \
        -r genome.fa -o "$sample" -O 0 -@ "$gt_threads" "${gt_args[@]}" \
        "&>" "$log" )
    # TIMEFMT: User time, system time, elapsed time, peak memory
    runtime="$( TIMEFMT="%U,%S,%E,%M" timeout "$timeout" zsh -c "${cmd[*]}" 2>&1 )"

    zgrep -m1 genotype "$sample/loci"/*/res.json.gz | \
        awk -F'[/"]' -v sample="$sample" 'BEGIN{OFS="\t"} { print sample,$3,$7 }' > "../out/${sample}.csv"
    if [[ "$save_json" = y ]]; then
        cp --parents "$sample/loci"/*/res.json.gz ../out
    fi

    n="$(< "../out/${sample}.csv" wc -l)"
    echo "${sample},${n},${runtime//s}"

    rm -r "$sample"*
    cd ..
}

function export_variables {
    export gt_threads
    export debug_arg
    export save_log
    export save_json
    export cram_infix
    export timeout
    export -f genotype_one
}

function run_genotyping {
    (
        cat wdir/samples.txt | \
        xargs -i -P "$threads" bash -c "genotype_one {} ${gt_args[*]}" | \
        tee "${out_prefix}.time"
    ) || true
}

function collect_output {
    # Add || true so that we save output even if something is missing
    cat out/*.csv | gzip -9 > "${out_prefix}.csv.gz" || true
    if [[ "$save_json" = y ]]; then
        ( cd out; tar cf "../${out_prefix}.jsons.tar" */loci/*/res.json.gz ) || true
    fi
    if [[ "$save_log" = y ]]; then
        ( cd out; tar czf "../${out_prefix}.logs.tar.gz" *.log ) || true
    fi
    rm -rf out
}

setup_colors
parse_params "$@"

prepare_folders
# Extracts samples from        $fs/$samples_tar/.../$samples  into  wdir/samples.txt
extract_samples
# Extract Locityper database from $fs/$database               into  wdir/db
extract_database
# Extract preprocessed data from  $fs/$preproc_dir/XX.tar.gz  into  wdir/bg
extract_preproc
# Copy reference genome from      $fs/$ref_dir/genome.fa*     into  wdir/
copy_reference

export_variables
run_genotyping
collect_output
cleanup
