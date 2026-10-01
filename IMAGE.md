## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

Also pinned, to match the course environment beyond the seven tools: htslib=1.24 openjdk=23.0.1 python=3.10.21.

## The pushed image
docker.io/aarohi1234/variant-call@sha256:c4ee9c11f966e7c01523620bb5a3abd6776cd457396a574fe4b7522a2eebdf19

To rerun this in a year, the one thing needed is the pushed image's digest, under **The pushed image**: `apptainer pull variant-call.sif docker://docker.io/aarohi1234/variant-call@sha256:c4ee9c11f966e7c01523620bb5a3abd6776cd457396a574fe4b7522a2eebdf19` returns exactly the software this run used, whatever has happened to the tag `1.0` since. Together with the pipeline code at the commit the manifest records (`40eeb125f2fe08df05b68f1e23568369af0cb3ba`, in `cluster-run-container/manifest.json`), the same samplesheet and the same reference, that reproduces the run: this image's run gave variant records identical to last week's conda run (`cluster-run-container/records-sha256.txt`). The recipe alone is not enough. Rebuilding `containers/Dockerfile` from the base image under **Base image**, with the versions under **Versions pinned**, gives the same seven tools but not byte-for-byte the same image, because every package the recipe does not pin is resolved again on build day. The rebuild is the fallback only if the pushed image is ever deleted from Docker Hub.
