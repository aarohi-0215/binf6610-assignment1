process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    """
    align.sh ${meta.id} ${ref} ${task.cpus} ${reads}
    """
}
