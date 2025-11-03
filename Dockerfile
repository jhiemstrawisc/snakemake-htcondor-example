# A minimal Dockerfile that can be used as a container environment at Execution Points
# for jobs that run Snakemake workflows.

# This Dockerfile should be modified to contain _all_ dependencies your job will need to
# run successfully at the EP, including Snakemake itself, any additional Snakemake
# plugins, and any software your workflow requires.

# Note that this container does not install the HTCondor Snakemake executor itself because
# the executor is run by the Access Point, whereas this is used to bundle dependencies for
# jobs that are executed remotely by the Execution Point.

# Pick a base image that includes Python.
FROM python:3.12-slim

# Install a compatible version of Snakemake.
RUN pip install --no-cache-dir snakemake==9.6.2
