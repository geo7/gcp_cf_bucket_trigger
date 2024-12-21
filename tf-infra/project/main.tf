# Setup project for working in - don't expect this to be altered as much,
# though might activate some API's from within here.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "terraform-state-gcs-bucket"
    prefix = "gcp-project-id--project"
  }
}

# Billing account id is needed in order to activate services.
data "google_secret_manager_secret_version" "billing_account" {
  secret = "projects/bill-proj-293754/secrets/billing-acc-id"
}

resource "google_project" "project" {
  # TODO: I'd like to parameterise this as well so that the project name to
  # create can be from a variable.
  name       = "gcp-project-id"
  project_id = "gcp-project-id"
  # TODO: I'll need to parameterise this when I want to publish this on public
  # internet, don't want to release org-id. Should probably add a bootstrap
  # project for this as well.
  org_id = "548790850976"
  # want to be able to delete this project.
  deletion_policy = "DELETE"
  billing_account = data.google_secret_manager_secret_version.billing_account.secret_data
}

output "project_id" {
  value = google_project.project.project_id
}
