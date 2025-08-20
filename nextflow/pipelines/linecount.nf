#!/usr/bin/env nextflow

process countLines {
    input:
      path inputFile from file('example.fastq')
    output:
      file 'linecount.txt'

    script:
    """
    echo "Counting lines in \$inputFile"
    wc -l \$inputFile > linecount.txt
    """
}

workflow {
    countLines()
}