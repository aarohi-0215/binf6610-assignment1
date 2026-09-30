#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o pull-%j.out
set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers
apptainer pull /scratch/${USER}/containers/variant-call.sif \
    docker://aarohi1234/variant-call@sha256:c4ee9c11f966e7c01523620bb5a3abd6776cd457396a574fe4b7522a2eebdf19
