#!/bin/bash

# Run a basic Snakemake workflow with HTCondor
# This runs Snakemake tied to your terminal session
#
# The command below can be run directly in your terminal,
# but it's provided here for ease of use.

snakemake --profile profile --htcondor-jobdir logs
