#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"

function help_message { cat <<HELP
Usage: $SCRIPT_NAME -s FILE -@ INT [-- locityper-args]

Run Locityper preprocessing for multiple samples.

Available options:
    -S, --samples-tar  FILE  Path to a tarball containing various sample subsets [${samples_tar}].
    -s, --samples      FILE  Basename of the sample subset.
                             No extension is necessary, but only one file must match the prefix.
    -r, --reference    FILE  Reference FASTA file (must contain .fai index) [${reference}].
    -j, --jf-counts    FILE  Jellyfish genomic k-mer counts [${jf_counts}].
    -w, --wgs          DIR   WGS data location and infix [default: UKB specific].
        --wgs-infix    STR   CRAM infix, files will be located at
                             DIR/XX/SAMPLE\$INFIX.cram [default: UKB specific].
    -@, --threads      INT   Number of Locityper instances, executed at the same time.
        --debug              Run inner function with -x flag.
        --save-log           Save Locityper logs.
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
    reference="Ref/GRCh38/full/genome.fa"
    jf_counts="Ref/GRCh38/counts.jf"
    wgs_dir="Bulk/GATK and GraphTyper WGS/Whole genome GATK CRAM files and indices [500k release]"
    cram_infix="_23372_0_0"
    debug=n
    save_log=n

    long="samples-tar:,samples:,reference:,jf-counts:,wgs:,wgs-infix:,threads:,debug,save-log,help"
    ARGS="$(getopt -o S:s:d:r:j:w:@:h --long "$long" --name "$SCRIPT_NAME" -- "$@")"
    eval set -- "$ARGS"
    while :; do
        case "$1" in
            -S | --samples-tar)
                samples_tar="$2"; shift 2 ;;
            -s | --samples)
                samples="$2";     shift 2 ;;
            -r | --reference)
                reference="$2";   shift 2 ;;
            -j | --jf-counts)
                jf_counts="$2";   shift 2 ;;
            -w | --wgs)
                wgs_dir="$2";     shift 2 ;;
            --wgs-infix)
                cram_infix="$2";  shift 2 ;;
            -@ | --threads)
                threads="$2";     shift 2 ;;
            --debug)
                debug=y;      shift ;;
            --save-log)
                save_log=y;   shift ;;
            -h | --help)
                help_message; exit 0;
                ;;
            -- ) shift; break ;;
            * )  panic "Unexpected argument $1" ;;
        esac
    done

    extra_args=( "$@" )
    [[ ! -z "${samples-}" ]] || panic "Missing required parameter: samples"
    [[ ! -z "${threads-}" ]] || panic "Missing required parameter: threads"
    [[ "$debug" = n ]] && debug_arg="" || debug_arg="-x"
}

function prepare_folders {
    fs=/mnt/project
    mkdir -p wdir
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
}

function copy_reference {
    cp "${fs}/${reference}" wdir/genome.fa
    cp "${fs}/${reference}.fai" wdir/genome.fa.fai
    cp "${fs}/${jf_counts}" wdir/counts.jf
}

function preprocess_one {
    # Need exported variables $debug_arg, $save_log, $cram_infix.
    # debug_arg without quotes because it can be empty and skipped.
    set $debug_arg -euo pipefail

    local sample extra_args prefix cram log cmd runtime status
    # First proper argument: sample, all rest: additional locityper arguments.
    sample="$1"
    extra_args="${@:2}"

    cd wdir
    # First two letters.
    prefix="${sample:0:2}"
    cram="wgs/$prefix/${sample}${cram_infix}.cram"
    # Copy index and stream CRAM file.
    ln -s "$cram" "${sample}.cram"
    cp "${cram}.crai" "${sample}.cram.crai"

    [[ "$save_log" = y ]] && log="../${prefix}/${sample}.log" || log=/dev/null

    cmd=( time locityper preproc \
        -a "${sample}.cram" -o "$sample" \
        -r "genome.fa" -j "counts.jf" \
        -@ 1 "${extra_args[@]}" \
        "&>" "$log" )
    # TIMEFMT: User time, system time, elapsed time, peak memory
    runtime="$( TIMEFMT="%U,%S,%E,%M" zsh -c "${cmd[*]}" 2>&1 )"

    if [[ -f "${sample}/success" ]]; then
        status=+
        mv "${sample}/distr.gz" "../${prefix}/${sample}.gz"
    else
        status=-
    fi
    echo "${sample},${status},${runtime//s}"

    rm -r "$sample"*
    cd ..
}

function export_variables {
    export debug_arg
    export save_log
    export cram_infix
    export -f preprocess_one
}

function run_preprocessing {
    cut -c-2 wdir/samples.txt | sort -u | xargs -i -P1 mkdir {}

    time_log="$(basename "$samples" .txt).time"
    (
        cat wdir/samples.txt | \
        xargs -i -P "$threads" bash -c "preprocess_one {} ${extra_args[*]}" | \
        tee "$time_log"
    ) || true
}

setup_colors
parse_params "$@"

prepare_folders
# Extracts samples from        $fs/$samples_tar/.../$samples  into  wdir/samples.txt
extract_samples
# Copy reference genome from      $fs/$ref_dir/genome.fa*     into  wdir/
copy_reference

export_variables
run_preprocessing
cleanup
