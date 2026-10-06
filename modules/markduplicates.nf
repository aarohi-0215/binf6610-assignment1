process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.markdup.bam"), path("${meta.id}.markdup.bam.bai"), emit: bam
    path "${meta.id}.markdup.metrics.txt",                                               emit: metrics

    script:
    """
    gatk MarkDuplicates \\
        -I ${bam} \\
        -O ${meta.id}.markdup.bam \\
        -M ${meta.id}.markdup.metrics.txt
    samtools index ${meta.id}.markdup.bam
    reads=\$(samtools view -c ${meta.id}.markdup.bam)
    (( reads > 0 )) || { echo "markduplicates: ${meta.id} has no reads" >&2; exit 1; }
    """
}
