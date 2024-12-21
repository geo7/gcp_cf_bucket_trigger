################################################################################
# SECTION: VARIABLES
################################################################################

variable "release_version" {
  type = string
  description = "Semantic release version tag (e.g., v3.23.1)"
}
variable "billing_project_id" {
  description = <<EOT
Project that contains billing account ID, enables other projects to be
created dynamically.
EOT
}
variable "billing_account_secret" {
  description = "Secret name within billing project that contains billing account."
}
variable "terraform_state_project_id" {
  description = <<EOT
Project which stores terraform state, stored within a separate project
so that all dynamically created projects can use this bucket for their
state.
EOT
}
variable "terraform_state_bucket_name" {
  description = <<EOT
Bucket within project which stores terraform state, stored within a separate
project so that all dynamically created projects can use this bucket for
their state.
EOT
}
variable "terraform_state_bucket_prefix" {
  description = "Prefix to use within terraform state bucket for this application."
}
variable "gcp_region" {
  description = "Default gcp region to use."
}
variable "gcp_multi_region" {
  description = "Default gcp multi-region to use."
}
variable "bucket_name_upload" {
  description = "Bucket to which data is initially uploaded."
}
variable "bucket_name_processed" {
  description = "Bucket the cloud function writes to."
}
variable "environment" {
  description = "Production / staging environments."
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Invalid environment, must be one of staging, production"
  }
}
variable "compute_service_account" {
  description = "Default compute service account ID for this project."
}

################################################################################
# SECTION: STATE AND REMOTE CONFIGURATION
################################################################################

# Setup project for working in - don't expect this to be altered as much,
# though might activate some API's from within here.
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  # NOTE: still can't param backend unfortunately :(
  # https://github.com/hashicorp/terraform/issues/13022
  backend "gcs" {
    bucket = "terraform-state-gcs-bucket"
    prefix = "gcp-project-id--app"
  }
}
# Access state file for project name, which seems a little bit daft given we
# have the name hard-coded in here anyway
data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket = var.terraform_state_bucket_name
    prefix = var.terraform_state_bucket_prefix
  }
}
# Billing account id is needed in order to activate services.
data "google_secret_manager_secret_version" "billing_account" {
  secret = "projects/${var.billing_project_id}/secrets/${var.billing_account_secret}"
}

################################################################################
# SECTION: PROJECT APIS - ACTIVATE APIS FOR PROJECT USE
################################################################################

variable "apis_to_enable" {
  type = list(string)
  default = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}
resource "google_project_service" "project_services" {
  for_each                   = toset(var.apis_to_enable)
  project                    = data.terraform_remote_state.project.outputs.project_id
  service                    = each.key
  disable_on_destroy         = true
  disable_dependent_services = true
}

################################################################################
# SECTION: STORAGE BUCKETS
################################################################################

# Bucket that will receive files that need processing by the cloud function.
resource "google_storage_bucket" "upload" {
  name                        = var.bucket_name_upload
  location                    = var.gcp_region
  project                     = data.terraform_remote_state.project.outputs.project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}
# Bucket that the cloud function will write processed files to.
resource "google_storage_bucket" "processed" {
  name                        = var.bucket_name_processed
  location                    = var.gcp_multi_region
  project                     = data.terraform_remote_state.project.outputs.project_id
  uniform_bucket_level_access = true
}

#####################################################################################
# SECTION: GITHUB ACTIONS SERVICE ACCOUNT.
#####################################################################################

# By default service account key creation was off by default:
# gcloud org-policies describe constraints/iam.disableServiceAccountKeyCreation --project='...'
#
# Going to :
# https://console.cloud.google.com/iam-admin/iam?inv=1&invt=AbjaDA&organizationId=...
# And adding the role: "Organisation Policy Administrator" (at org level, not
# project) was needed.
#
# References:
# https://www.googlecloudcommunity.com/gc/Infrastructure-Compute-Storage/Cant-assign-Organization-Policy-Administrator-role-to-myself/td-p/728748
# https://www.reddit.com/r/googleworkspace/comments/1biw03d/comment/kvqcj14
resource "google_service_account" "github_actions" {
  project      = data.terraform_remote_state.project.outputs.project_id
  account_id   = "github-actions-sa"
  display_name = "Github actions service account"
}
# This is most likely overpowered by a fair amount.
locals {
  iam_roles_github_account = [
    "roles/artifactregistry.admin",
    "roles/bigquery.metadataViewer",
    "roles/cloudbuild.builds.editor",
    "roles/cloudfunctions.admin",
    "roles/eventarc.eventReceiver",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.serviceAccountViewer",
    "roles/logging.viewer",
    "roles/pubsub.admin",
    "roles/pubsub.publisher",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/securitycenter.admin",
    "roles/storage.admin",
  ]
}
# Adding roles - almost certainly overpowered.
resource "google_project_iam_member" "project_iam_github_account" {
  for_each = toset(local.iam_roles_github_account)
  project  = data.terraform_remote_state.project.outputs.project_id
  role     = each.key
  member   = google_service_account.github_actions.member
}
resource "google_project_iam_member" "tf_state_project_iam_github_account" {
  for_each = toset(local.iam_roles_github_account)
  project  = var.terraform_state_project_id
  role     = each.key
  member   = google_service_account.github_actions.member
}
resource "google_project_iam_member" "billing_project_iam_github_account" {
  for_each = toset(local.iam_roles_github_account)
  project  = var.billing_project_id
  role     = each.key
  member   = google_service_account.github_actions.member
}
# Save service account key as a secret - we'll want to copy this from here into
# Github to allow actions to apply terraform. Moving from gcp -> github is
# manual with this, which makes rotation a bit annoying. Workload identities
# were giving some annoying errors so I resorted to using sa keys :/
resource "google_service_account_key" "github_actions_key" {
  service_account_id = google_service_account.github_actions.name
  keepers = {
    # This ensures a new key is created if the project or account changes
    project = google_service_account.github_actions.project
  }
}
resource "google_secret_manager_secret" "github_actions_key" {
  secret_id = "github-actions-key"
  project   = data.terraform_remote_state.project.outputs.project_id
  replication {
    # From:
    # Expected setting here to be 'automatic = true', but thread here:
    # https://github.com/hashicorp/terraform-provider-google/issues/15926
    # states it should just be auto as used.
    auto {}
  }
}
resource "google_secret_manager_secret_version" "github_actions_key_version" {
  secret      = google_secret_manager_secret.github_actions_key.id
  secret_data = google_service_account_key.github_actions_key.private_key
}

#####################################################################################
# SECTION: SERVICE ACCOUNT FOR GLOUD FUNCTION.
#####################################################################################

resource "google_service_account" "account" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account"
  project      = data.terraform_remote_state.project.outputs.project_id
  description  = "Service account for managing cloud functions"
}
locals {
  iam_roles = [
    "roles/artifactregistry.admin",
    "roles/cloudbuild.builds.editor",
    "roles/cloudfunctions.admin",
    "roles/eventarc.eventReceiver",
    "roles/pubsub.admin",
    "roles/pubsub.publisher",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/storage.admin",
  ]
}
# adding roles found here:
# https://registry.terraform.io/modules/GoogleCloudPlatform/cloud-functions/google/latest
resource "google_project_iam_member" "project_iam" {
  for_each = toset(local.iam_roles)
  project = data.terraform_remote_state.project.outputs.project_id
  role    = each.key
  member  = google_service_account.account.member
}
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "../../cloud_function/"
  output_path = "../../function-source-${var.release_version}.zip"
}
resource "google_storage_bucket" "bucket" {
  name                        = "${data.terraform_remote_state.project.outputs.project_id}-gcf-source"
  location                    = var.gcp_multi_region
  uniform_bucket_level_access = true
  project                     = data.terraform_remote_state.project.outputs.project_id
}
resource "google_storage_bucket_object" "object" {
  source       = data.archive_file.source.output_path
  content_type = "application/zip"
  name         = "function-source-${var.release_version}.zip"
  bucket       = google_storage_bucket.bucket.name
}
# To fix error:
# > The service account running this build
# > projects/gcp-project-id/serviceAccounts/825723592735-compute@developer.gserviceaccount.com
# > does not have permission to write logs to Cloud Logging. To fix this, grant
# > the Logs Writer (roles/logging.logWriter) role to the service account.
resource "google_project_iam_member" "service_account_log_writer" {
  project = data.terraform_remote_state.project.outputs.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.compute_service_account}"
}
# following this link:
# https://cloud.google.com/functions/docs/troubleshooting#build-service-account
resource "google_project_iam_member" "service_account_cloud_build_builder" {
  project = data.terraform_remote_state.project.outputs.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${var.compute_service_account}"
}
resource "google_project_iam_member" "service_account_compute_eventarc_receive" {
  project = data.terraform_remote_state.project.outputs.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${var.compute_service_account}"
}
# Following through this
# https://cloud.google.com/eventarc/standard/docs/run/create-trigger-storage-gcloud#before-you-begin
# TODO: Do i need this? I think i'm not using pubsub... it's just a direct
# trigger from the cloud function?
resource "google_project_iam_member" "service_account_gcs_sa_pubsub_publisher" {
  project = data.terraform_remote_state.project.outputs.project_id
  role    = "roles/pubsub.publisher"
  # TODO: should this account be parameterised some how?
  # TODO: what is this service account? What's it called? It's not the 'compute' sevice account so ?
  member = "serviceAccount:service-825723592735@gs-project-accounts.iam.gserviceaccount.com"
}

################################################################################
# SECTION: CLOUD FUNCTION
################################################################################

resource "google_cloudfunctions2_function" "function" {
  name        = "gcp-cloud-function"
  location    = var.gcp_region
  description = "Process data from upload bucket into processed bucket."
  project     = data.terraform_remote_state.project.outputs.project_id
  build_config {
    runtime     = "python312"
    entry_point = "run"
    environment_variables = {
      # Lot of stderr output from fork(), didn't go particularly deep into it
      # for this. Ended up just using pandas, but left this for reference.
      # https://github.com/pola-rs/polars/blob/414d88387f1c0f07d82a1f4185c6e44ddd1c4293/py-polars/polars/__init__.py#L439C1-L448C1
      POLARS_MAX_THREADS = 1
      RELEASE_VERSION = "${var.release_version}"
    }
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }
  service_config {
    max_instance_count               = 2
    min_instance_count               = 1
    available_memory                 = "1Gi"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    service_account_email            = google_service_account.account.email
  }
  event_trigger {
    event_type = "google.cloud.storage.object.v1.finalized"
    # Depends on the nature of the function, it might make sense to retry, or
    # it might make sense to accept failure and just inspect relevant logs.
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = google_service_account.account.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.upload.name
    }
  }
}

################################################################################
# SECTION: BIGQUERY LOGGING
################################################################################

resource "google_bigquery_dataset" "dataset" {
  dataset_id  = "cloud_function_logs"
  project     = data.terraform_remote_state.project.outputs.project_id
  description = "Dataset for storing cloud function logs."
  location    = var.gcp_region
  labels = {
    deploy = "terraform"
  }
}
# Want to be able to analyse the service logs
resource "google_logging_project_sink" "function-sink" {
  name    = "gcp-function-sink-2"
  project = data.terraform_remote_state.project.outputs.project_id
  # Can export to pubsub, cloud storage, bigquery, log bucket, or another project
  # eg: destination = "pubsub.googleapis.com/projects/my-project/topics/instance-activity"
  # eg: destination = "bigquery.googleapis.com/projects/[PROJECT]/datasets/[DATASET]"
  destination = "bigquery.googleapis.com/${google_bigquery_dataset.dataset.id}"
  description = "Sink to store gcp-cloud-function results in bigquery table."
  # Log all WARN or higher severity messages relating to instances
  filter = "resource.type = cloud_function OR resource.type = cloud_run_revision"
  # Use a unique writer (creates a unique service account used for writing)
  unique_writer_identity = true
  bigquery_options {
    use_partitioned_tables = false
  }
}
# From:
# https://github.com/GoogleCloudPlatform/gke-logging-sinks-demo/blob/fcb2d3309d87d05d6a39d9206e1c145002b8fae1/terraform/main.tf#L134C1-L140C2
resource "google_project_iam_binding" "log-writer-bigquery" {
  role    = "roles/bigquery.dataEditor"
  project = data.terraform_remote_state.project.outputs.project_id
  members = [
    google_logging_project_sink.function-sink.writer_identity,
  ]
}

#####################################################################################
# SECTION: OUTPUTS
#####################################################################################

output "app_project_id" {
  value = data.terraform_remote_state.project.outputs.project_id
}
output "sink_destination" {
  value = google_logging_project_sink.function-sink.destination
}
output "bq_dataset_id" {
  value = google_bigquery_dataset.dataset.id
}
output "upload_bucket_name" {
  value = google_storage_bucket.upload.name
}
output "processed_bucket_name" {
  value = google_storage_bucket.processed.name
}
output "github_actions_sa" {
  value = google_service_account.github_actions.email
}
output "release_version" {
  value = var.release_version
}
output "cloud_function_storage_object_source" {
  value = google_storage_bucket_object.object.name
}
