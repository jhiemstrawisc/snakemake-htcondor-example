#!/bin/bash

# Run the "Snakemake Long" script, which submits
# the Snakemake manager as a separate "local universe"
# job to HTCondor. This lets you close your laptop
# without jobs being descheduled by HTCondor.
#
# The command below can be run directly in your terminal,
# but it's provided here for ease of use.

./snakemake_long.py --htcondor-jobdir logs --profile profile --conda-env snakemake-env --use-mamba
