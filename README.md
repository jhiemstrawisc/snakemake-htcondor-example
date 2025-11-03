# Snakemake+HTCondor Hello-world Example
This repo contains a basic "hello-world" tutorial for running a simple Snakemake workflow from an HTCondor Access Point (AP) at CHTC.
It's meant to give users a feel for what it takes to run these workflows with an HTCondor executor, and as such is based on a very simple script that appends words to a slice of input files.
Once you understand the basics of running Snakemake workflows with a backend executor, you can build on top of these workflows to fit your needs.

The repo contains self-contained examples, so if you have an AP account, you should be able to `git clone` this repo into your AP home directory and start running right away.

## Background Information
### Snakemake
Snakemake is a popular Python workflow management tool that uses a "Make"-like approach for building/managing Directed Acyclic Graphs (DAGs) of computational work.
Its goals are to simplify running large, chained workflows and to make your science easier to verify/repeat by both you and your scientific peers.

The basic unit of work in Snakemake is called a "rule", and rules are typically made of three sections:
- Inputs -- the collection of files needed by the rule to begin execution
- Outputs -- the collection of files the rule is expected to generate as output
- Run -- the actual work that's done on the inputs to produce the outputs

Viewed holistically, this can be seen as another framing of `f(x) = y`, where `f` is some function or `Run` executable that takes input data `x` to produce output data `y`.

Snakemake generates a DAG of rules by examining the interdependencies of `inputs` and `outputs`.
That is, Snakemake can determine the order different rules must run in by seeing that one rule's output is the input to another rule.
When two rules are independent (i.e. their input/output chains are disconnected), Snakemake is able to run these rules in parallel.

### CHTC & HTCondor
High-throughput computing (HTC) is a type of computing that aims to support workflows where many independent "jobs" can be run in parallel.
This is particularly useful when those jobs do not have interdependencies (i.e., job1 doesn't need to communicate with job2 while both are running).
In this paradigm, unlike High-Performance Computing (HPC), per-job latency is often traded for the ability to run many tasks simultaneously.
HTC is ideal for scenarios where the goal is to maximize the number of tasks completed over a period of time, rather than minimizing the time to complete a single task.

The Center for High Throughput Computing (CHTC) is a research center at the University of Wisconsin-Madison that aims to bring the power of High Throughput Computing to all fields of research.
CHTC provides the infrastructure and expertise needed to leverage HTC for a wide range of scientific and engineering applications.
By enabling researchers to run large numbers of independent jobs in parallel, CHTC helps accelerate the pace of discovery and innovation across diverse disciplines.

The primary software CHTC uses to accomplish this approach to computing is called [HTCondor](https://htcondor.org/), a high-throughput scheduling tool that glues together many independent, federated servers in a way that democratizes their access by providing a unified interface for job placement, monitoring, and management.
HTCondor allows users to place jobs to a central queue, which then distributes these jobs to available resources across the network.
This ensures efficient utilization of computational resources and enables researchers to run large-scale workflows without worrying about the underlying infrastructure.

### HTCondor + Snakemake
The [Snakemake Executor for HTCondor](https://github.com/htcondor/snakemake-executor-plugin-htcondor) lets you treat HTCondor as the backend for running many independent "steps" in a Snakemake workflow.

At a basic level, the HTCondor Snakemake Executor brings together these two software stacks by translating between Snakemake "steps" and HTCondor "jobs"; when Snakemake starts running a step, it creates an HTCondor submit description and places the rule/job in the cluster's scheduler for execution.

While Snakemake is managing the HTCondor jobs, it will periodically poll the [HTCondor SchedD](https://htcondor.readthedocs.io/en/latest/apis/python-bindings/tutorials/HTCondor-Introduction.html#Schedd), HTCondor's scheduler daemon, to see rule/job status.
When jobs complete, Snakemake will verify that any outputs now exist in their expected locations.
If the output of a job doesn't exist after the job finishes, Snakemake will view the step as having failed and may re-place it with HTCondor.

A major challenge in integrating these two tools is that Snakemake is designed for shared filesystems, whereas HTCondor assumes a distributed environment without one.
In particular, this means both pieces of software have specific requirements for referencing things like input/output files, where Snakemake often assumes things like absolute paths and HTCondor typically assumes that files are transferred with jobs and appear to the job as flattened files. 
Because jobs running on HTCondor Execution Points (EP) in CHTC only share some common filesystem paths (e.g. `/staging` or `/projects`), the executor must explicitly manage the transfer of any files that don't exist under these paths.

> **NOTE:** The workflow examples below assume _all_ input/output files come from the directory where the work is submitted and not a shared filesystem mounted into the HTCondor cluster.
> Examples for how to place jobs with files that come from a mix of local and shared filesystems are under development.

## Running the Hello World Example

### Workflow Overview
The example provided here is very simple -- it operates on a set of input files located in `inputs/`, and appends new words in a sequence of steps for each of those files.
This is all coded by the `Snakefile` located in this directory, which is the definition of work Snakemake will undertake.

Here's a basic overview of the `Snakefile` and how it works:
1. Start by defining a directory with input files -- in this case, `inputs/`.
2. A special Snakemake rule called "all" tells Snakemake about all the files that should exist at the end of the workflow. In this case, there will be one output that is derived for each of the input samples.
3. The two other rules, `make_intermediary` and `make_output` tell Snakemake how to take an input file and turn it into an output file. In this example, Snakemake will append words to the input and produce a new file for the output. Notice that the files are _not_ updated in place -- it's crucial for Snakemake workflows that each rule produces a new file!

For example, these are the workflow steps to turn `inputs/sample1.txt` into `outputs/output_sample1.txt`:
1. Load `inputs/sample1.txt` and make a new file called `outputs/intermediary_sample1.txt` by appending the word "foo" in a newline.
2. Load `outputs/intermediary_sample1.txt` and make a new file called `outputs/output_sample1.txt` by appending the word "bar" in a newline.

Snakefiles can be far more complex than this because they are written in Python -- just about anything you can do in Python, you can do in a Snakefile!

There are a few steps for running this hello world example:
1. Clone this repo onto the AP with `git clone https://github.com/jhiemstrawisc/snakemake-htcondor-example.git` and `cd` into the new directory
2. Build an environment at the AP that contains some of the software needed to invoke Snakemake (notably, Snakemake and the HTCondor+Snakemake executor plugin)
3. Build a container image (you can use either Docker or Apptainer) that will be transferred by HTCondor along with the job and act as the execution environment for your remote executable
4. If using Docker in step 3, push your image to a public repository like Dockerhub. If using Apptainer, build the `.sif` image and place it in your submit directory
5. Modify the configuration "profile" located at `profile/config.yaml` to indicate which container image to use along with any other requirements needed by your job
6. Run Snakemake

Each of these steps is discussed in more detail below.

### Building Environments
When you run this example workflow, you're using Snakemake at the AP to place jobs with HTCondor's scheduler.
After those jobs are scheduled to execute, Snakemake will start doing work at a remote Execution Point (EP).

For both ends of this process to function, you need to build an appropriate and self-contained software environment for each, one for the AP and one for the EP.

#### Building the AP Environment
Running your Snakemake command at the AP requires that you have snakemake and the HTCondor Snakemake Executor installed.
These have been bundled into a conda/mamba environment file called `env.yaml`, and running the commands below assumes you've installed one of these tools.
For help setting up conda/mamba on the AP, see [this page](https://chtc.cs.wisc.edu/uw-research-computing/conda-installation) for guidance.

To build the environment called 'snakemake-env' (assuming you've installed mamba), run:
```bash
mamba env create -f env.yaml
```

Then to activate:
```bash
mamba activate snakemake-env
```

Alternatively, you can use `conda` to the same effect, but `conda` is often much slower at resolving software dependencies:
```bash
conda env create -f env.yaml
```
Then to activate:
```bash
conda activate snakemake-env
```

After running these commands, your shell prompt should indicate you're using the new environment by telling you which is active in parantheses, e.g.:
```bash
(snakemake-env) [jhiemstra@ap2002 ~]$
```

#### Building the EP's Container Image
Container images are often used in distributed computing as a self-contained, transportable way to bundle all the dependencies and configuration needed to run a piece of software.
The most popular container technology is called Docker.
In some cases, CHTC users will instead use a technology called Apptainer for building container images.
Deciding which to use is outside the scope of this tutorial, and if you need help deciding you should contact a CHTC Research Computing Facilitator.

The easiest way for you to get started setting up a container image for this example is to use a pre-built image rather than building your own.
To assist with that, a usable image has already been configured for the example (`jhiemstra/snakemake-dev-image:v1`), which was built using the Dockerfile in this repo.
If you're using your own image, you'll need to change which image this example points to (discussed later).

To build your own Docker image you can either install Docker on your local machine and push it to Dockerhub or you can follow [this guide](https://chtc.cs.wisc.edu/uw-research-computing/apptainer-htc) for building apptainer images at CHTC.

To build the Docker image, navigate to the directory that contains it and run:
```
docker build -t <name of image here>:<some unique version tag, e.g. 'v1'> .
```
> **WARNING:** If you're using Docker on a modern Mac that uses "Apple Silicon", you'll also need to specify the correct computer architecture to run at CHTC.
> Do this by prepending `DOCKER_DEFAULT_PLATFORM=linux/amd64` to your command, e.g.
> ```
> DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build -t <name of image here>:<some unique version tag, e.g. 'v1'> .
> ```

Assuming you already have an account with `https://hub.docker.com`, this Docker image can then be pushed to Dockerhub with:
```
docker push <the name you chose>:<the tag you chose>
```
You may be asked to login first.

Whenever you need to use a custom image, modify `profile/config.yaml` so that the `container_image` key points at your own image (either a local `.sif` or an image in a remote repository like Dockerhub).
> **NOTE:** If you edit `profile/config.yaml` to point at your custom image, be aware of the quote requirements; for an image called `my-image:latest`, you must double outer quotes and single inner quotes, i.e. `"'my-image:latest'"`

> **WARNING:** Whenever you create new custom images for use with HTCondor, it's _very_ important you give them unique tag values for every change you push to Dockerhub.
> This is because HTCondor caches these images whenever you run workflows with them, and changing the image without changing its name makes it hard for HTCondor to know which image should be used.

### Example Workflows
There are two options in this repo for running Snakemake.

The first invokes Snakemake directly in your terminal.
This is good for some of your first experiments with Snakemake, but doesn't scale to large workflows because the Snakemake process gets killed whenever you terminate your SSH session.
For example, if you close your laptop lid, all your Snakemake jobs will be removed from HTCondor and your workflow will stop.

To persist Snakemake's ability to run in the background, you'll need to run a "Snakemake Long" job, which is the second option discussed below.

#### Running Snakemake Directly
The `run_basic.sh` script invokes Snakemake directly in a way that ties it to your terminal session.
This is typically not the way you want to do things for real, but is useful when you're just getting started with Snakemake+HTCondor because it's more interactive.
The downside is that Snakemake will only stay running as long as your terminal session is active, meaning your work will stop running if you close your computer or exit the AP.

Before running the Snakemake command, try inspecting the run file to see how it works -- the two arguments passed to Snakemake are:
- `--profile profile`: tell Snakemake to use the configuration defined in `profile/config.yaml`
- `--htcondor-jobdir logs`: tell the HTCondor Snakemake executor that HTCondor logs should be placed in the directory called `logs`.
> **WARNING:** Your logs directory should exist before running the job! Create the log directory ahead of time with `mkdir -p <name of log dir>`

You could run the command from the file directly, or you can do:
```bash
./run_basic.sh
```
if you want to avoid typing it all out.

When you run Snakemake in this mode, you should immediately start to see it telling you about the jobs that are running.
In a separate terminal, you can watch the jobs' progress from HTCondor's point of view by running:
```bash
condor_watch_q
```
This should display each HTCondor job and where it is in its lifetime (e.g. waiting idle, transferring input data, running, transferring output data, etc.)
> **NOTE:** The `condor_watch_q` command only knows about jobs that are already placed with HTCondor.
> Try refreshing periodically to see new jobs that have been placed.

As Snakemake progresses and individual jobs start to finish, you should see new files start filling a new directory called `outputs/`.

To stop Snakemake, you can `ctrl-c`.
Snakemake should de-schedule any jobs that are in HTCondor's queue, but will leave running jobs to finish.

To monitor the logs for the workflow, peek into `logs/`, or whichever directory you specified for the workflow.
You should see lots of numbered files with `.out`, `.err` and `.log` file extensions.
These are the log files provided by HTCondor, and the number represents the "job ID" from HTCondor's perspective.
Try checking a few of them out -- typically, any logging produced by Snakemake or your Snakefile will live in the `.err` and `.out` files, while information produced by HTCondor will live in the `.log` files.

To correlate information between a Snakemake "step" and an HTCondor "job", review your Snakemake output -- it will tell you something along the lines of "Job 4 submitted to HTCondor Cluster ID 4560949" where "job 4" is the ID of a Snakemake step and the "HTCondor Cluster ID" is the ID of the job inside HTCondor.
You can use this mapping to inspect log files produced by HTCondor and correlate them back with the Snakemake step that was responsible for generating them.

You can also use the Cluster ID to inspect jobs directly with HTCondor:
```
condor_q <insert a job Cluster ID>
```

#### Run Snakemake Management Jobs
The previous example walked through how to run the Snakemake workflow by invoking Snakemake directly.
However, this approach doesn't scale well for large, long-running workflows because of the limitations discussed in the previous section.

To work around this, you'll need to run a "Snakemake Long" job, which lets HTCondor manage the Snakemake workflow much like it manages each of the individual steps in the workflow.

**NOTE:** Running the `run_long.sh` script assumes you have `mamba` installed and built the AP environment it. To use `conda` instead, remove the `--use-mamba` argument from the command.

The command to do this is set up in the `run_long.sh` script.
It's very similar to the `run_basic.sh` script, except that we tell the Snakemake Long tool which AP environment it should use with the `--conda-env snakemake-env --use-mamba` arguments.

The code for this Snakemake long job is located in the file named `snakemake_long.py`.
If you're building on top of this example, be aware that you may need to edit the python script to fit all your needs.
That being said, CHTC plans to develop a first-class way to submit these jobs by introducing a new HTCondor command in the future.

Unlike the previous example, running `./run_long.sh` will not immediately tell you what's happening with each of the Snakemake jobs.
Instead, Snakemake's output is being treated like a set of logs from another HTCondor job.

These logs are located at:
- `logs/snakemake.err`: Snakemake's standard error, which has most of the Snakemake information you saw running the `run_basic.sh` script, like which steps have already been submitted as HTCondor jobs and how far through the workflow you are
- `logs/snakemake.out`: Usually empty unless your Snakefile prints anything to standard out
- `logs/snakemake.log`: Contains information HTCondor provides about the job, like how much memory/CPU it uses, which servers it ran on, etc.

To watch Snakemake's progress from Snakemake's perspective, try running:
```bash
tail -f logs/snakemake.err
```
(use `ctrl-c` to quit watching the log)

Similar to the last example, you can also run `condor_watch_q` to see how far along the Snakemake jobs are, but this time you'll also notice an HTCondor job called 'sm-manager-process-<some timestamp>` -- this is the Snakemake Long job that's running all of the other Snakemake steps.
It's the process responsible for producing the `logs/snakemake.{out,err,log}` files discussed earlier.

#### Rerunning the Example
Snakemake uses what's called a "dataflow" or "declarative" model for deciding how to run work, as opposed to an "imperative" model.
This means that it watches for which input/output files have been created to decide where it is in a workflow, and is part of how Snakemake is capable of resuming failed steps where it left off.

For you, this means that once you've run this workflow in whole or in part -- anything that produces files in the `outputs/` directory -- you'll need to delete this directory before you can re-run the workflow.
Otherwise, Snakemake will think it's already done generating the intermediary/output files and won't run again.
