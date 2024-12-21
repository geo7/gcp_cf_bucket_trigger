set -euo pipefail

# Deploy cloud function locally.

# Run formatting - don't want to deploy something that fails this.
make format

# generate requirement files
poetry export --without-hashes --output ./cloud_function/requirements.txt

# run terraform
APP_DIR='./tf-infra/app'
terraform -chdir=$APP_DIR init
terraform -chdir=$APP_DIR fmt
terraform -chdir=$APP_DIR validate
terraform -chdir=$APP_DIR plan -out="tf.plan"
terraform -chdir=$APP_DIR apply tf.plan
