process FILTER {
    container params.containers.gatk

    input:
    path vcf
    path tbi
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'variants.tsv',           emit: table

    script:
    """
    gatk VariantFiltration \\
        -R ${ref} \\
        -V ${vcf} \\
        --filter-expression "QD < 2.0"  --filter-name "QD2" \\
        --filter-expression "FS > 60.0" --filter-name "FS60" \\
        --filter-expression "MQ < 40.0" --filter-name "MQ40" \\
        --filter-expression "SOR > 3.0" --filter-name "SOR3" \\
        -O cohort.filtered.vcf.gz
    variants_table.sh cohort.filtered.vcf.gz
    """
}
