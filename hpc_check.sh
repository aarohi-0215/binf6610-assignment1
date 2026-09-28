#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# hpc_check.sh — can you actually use the cluster?
#
#   ssh <yourusername>@login.explorer.northeastern.edu
#   bash hpc_check.sh
#
# Run it ON EXPLORER, before week 2's session. It checks the seven things that
# have to be true before any of the week's work is possible, and it tells you
# which one is missing rather than leaving you to infer it from a failure an hour
# into a job.
#
# Modelled on week 1's setup_check.sh, and for the same reason: an environment
# problem found now is a message on the discussion board, and the same problem
# found the night before the deadline is a lost weekend.
#-----------------------------------------------------------------------------
set -uo pipefail        # NOT -e: every check must run even after one fails

COURSE_SHARED=${COURSE_SHARED:-/courses/BINF6610.202710}
REF_FA="${COURSE_SHARED}/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa"

pass=0 warn=0 fail=0
if [[ -t 1 ]]; then G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; D=$'\033[0;90m'; N=$'\033[0m'
else G='' Y='' R='' D='' N=''; fi

ok()   { pass=$(( pass + 1 )); printf '  %sOK  %s %-34s %s\n' "$G" "$N" "$1" "${2:-}"; }
bad()  { fail=$(( fail + 1 )); printf '  %sFAIL%s %-34s %s\n' "$R" "$N" "$1" "${2:-}"; }
soft() { warn=$(( warn + 1 )); printf '  %sWARN%s %-34s %s\n' "$Y" "$N" "$1" "${2:-}"; }
hint() { printf '       %s%s%s\n' "$D" "$1" "$N"; }

printf '\nBINF6610 week 2 — cluster pre-flight\n'
printf '%suser %s on %s%s\n\n' "$D" "${USER}" "$(hostname -s)" "$N"

# 1 -- am I even on the cluster? ---------------------------------------------
# The commonest way to "fail" this script is to run it on your laptop.
if command -v sbatch >/dev/null; then
    ok "on a Slurm cluster" "$(sbatch --version 2>/dev/null | head -1)"
else
    bad "on a Slurm cluster" "sbatch not found"
    hint 'You are running this on your laptop. ssh to Explorer first:'
    hint '  ssh <yourusername>@login.explorer.northeastern.edu'
    printf '\nNothing else can be checked from here.\n\n'
    exit 1
fi

# 2 -- can I submit? ----------------------------------------------------------
# The real question, and the only one that cannot be answered by reading
# documentation: does YOUR account have a usable Slurm association?
probe=$(sbatch --parsable -p short -t 00:00:30 --wrap "true" 2>&1)
if [[ "${probe}" =~ ^[0-9]+$ ]]; then
    ok "can submit jobs" "test job ${probe}"
    scancel "${probe}" 2>/dev/null
else
    bad "can submit jobs" "${probe:0:70}"
    hint 'This is the one problem you cannot fix yourself. Post the message above on the'
    hint 'discussion board — it is almost certainly a missing Slurm account association,'
    hint 'and it has to be fixed by Research Computing.'
fi

# 3 -- partitions -------------------------------------------------------------
if sinfo -h -p short -o "%P" >/dev/null 2>&1; then
    ok "partition 'short' exists" "$(sinfo -h -p short -o '%D nodes, %l limit')"
else
    bad "partition 'short' exists" "sinfo could not see it"
fi

# 4 -- the module system ------------------------------------------------------
if command -v module >/dev/null 2>&1 || [[ -n "${MODULESHOME:-}" ]]; then
    ok "module system available"
    for m in bwa samtools fastqc; do
        if module -t avail 2>&1 | grep -qi "^${m}/"; then
            ok "  module ${m}" "$(module -t avail 2>&1 | grep -i "^${m}/" | head -1)"
        else
            soft "  module ${m}" "not found — the conda env supplies it"
        fi
    done
else
    bad "module system available" "no 'module' command"
fi

# 5 -- the shared course data -------------------------------------------------
# Read-only and shared on purpose: an 8.9 GB reference copied by twenty students
# is 178 GB of the same bytes, and building the index yourself costs an hour.
if [[ -r "${COURSE_SHARED}/data" ]]; then
    ok "shared course directory" "${COURSE_SHARED}"
    for sub in data/refs/grch38-1000g data/fastq-variant; do
        if [[ -d "${COURSE_SHARED}/${sub}" ]]; then
            ok "  ${sub}" "$(du -sh "${COURSE_SHARED}/${sub}" 2>/dev/null | cut -f1)"
        else
            bad "  ${sub}" "missing"
        fi
    done
    if [[ -r "${REF_FA}" && -r "${REF_FA}.bwt" ]]; then
        ok "  reference + BWA index" "${REF_FA}"
    else
        bad "  reference + BWA index" "cannot read ${REF_FA} or its .bwt"
    fi
    # fastp, gatk and multiqc are not modules on Explorer; the course conda
    # environment is where every tool the pipeline calls comes from.
    ENV_DIR="${COURSE_SHARED}/shared/env/binf6610"
    if [[ -x "${ENV_DIR}/bin/gatk" && -x "${ENV_DIR}/bin/fastp" && -x "${ENV_DIR}/bin/multiqc" ]]; then
        ok "  course conda environment" "${ENV_DIR}"
    else
        bad "  course conda environment" "cannot run gatk, fastp or multiqc from ${ENV_DIR}"
    fi
else
    bad "shared course directory" "${COURSE_SHARED} not readable"
    hint 'Access comes from the course Unix group. Run  id -Gn  and look for BINF6610.202710;'
    hint 'if it is not there, post this output on the discussion board.'
fi

# 6 -- somewhere to write -----------------------------------------------------
# Never in home: quotas there are small, and a run directory is not small.
MYSCRATCH="/scratch/${USER}"
if [[ -d "${MYSCRATCH}" ]] && [[ -w "${MYSCRATCH}" ]]; then
    ok "your scratch space" "${MYSCRATCH}"
else
    bad "your scratch space" "${MYSCRATCH} missing or not writable"
    hint 'Run your pipeline here, not in your home directory.'
fi

# 7 -- conda ------------------------------------------------------------------
if module -t avail 2>&1 | grep -qi '^miniconda3/'; then
    ok "miniconda3 module" "$(module -t avail 2>&1 | grep -i '^miniconda3/' | tail -1)"
else
    soft "miniconda3 module" "not found — needed for gatk, fastp, hisat2, multiqc"
fi

printf '\n  %d ok' "${pass}"
(( warn )) && printf ', %d warnings' "${warn}"
(( fail )) && printf ', %s%d failures%s' "$R" "${fail}" "$N"
printf '\n\n'
if (( fail )); then
    printf 'Fix the failures before week 2. If you cannot, post the FULL output of this\n'
    printf 'script on the discussion board — it is enough to diagnose almost anything.\n\n'
    exit 1
fi
printf 'You are ready for week 2.\n\n'
