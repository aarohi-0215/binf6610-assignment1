process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict
    val  region

    output:
    path 'cohort.vcf.gz',     emit: vcf
    path 'cohort.vcf.gz.tbi', emit: tbi

    script:
    """
    joint_genotype.sh ${ref} ${region} ${task.cpus} ${gvcfs}
    """
}
