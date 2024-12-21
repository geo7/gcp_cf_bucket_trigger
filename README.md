# GCP Cloud function and related IAC

Python project containing a simple Cloud Function triggered by Google Cloud Storage events. The function processes CSV files uploaded to a specific bucket and writes the processed data to another bucket. Main motivation of this project is to provide a template/starting point.

## Functionality

* File Upload: Users upload CSV files to the designated storage bucket (`upload-gcs-bucket`).   
* Cloud Function Trigger: The Cloud Function (`gcp-cloud-function`) is triggered whenever a new file is finalized in the upload bucket.
* Data Processing: The function validates / processes received data.
* Output: Processed data is written as a CSV file to the output bucket (`processed-gcs-bucket`).
* Cleanup: Original uploaded file is deleted from the upload bucket.

## Project Structure

* `cloud_function`: Contains the Cloud Function code (main.py).
* `scripts`: Utility scripts for workflows.
* `simple_bucket_trigger/exp_1`: Sub dir with some basic experiments.
* `tests`: Contains test scripts.
* `tf-infra`: Terraform configuration files for infrastructure deployment.

## Deployment

Terraform is used to deploy the required infrastructure components (storage buckets, Cloud Function, etc.). Terraform configuration files are located in the `tf-infra/`.   

## Motivation

Motivation for this project is to serve as a reasonable starting point for:

* cloud function that acts on storage events.
* semantic versioning run in CI.
* terraform deployed via actions following tagged commits.

It _should_ be relatively straightforward to update from what's here.

## Failing actions

Any actions failing here should be ignored :), public repository is just for reference.
