# View roles assigned to particular service account, clunky approach but
# I never use jq, pretty nice

# TODO: parameterise these roles.
PROJECT_ID=gcp-project-id
SA=github-actions-sa@gcp-project-id.iam.gserviceaccount.com

gcloud projects get-iam-policy $PROJECT_ID --format=json > iam_policy.json
jq -r "
  .bindings[]
  | select(.members[] | contains(\"serviceAccount:${SA}\"))
  | .role
" iam_policy.json > update.json
echo ""
echo "Roles for service account : ${SA}"
echo ""
cat update.json
rm update.json iam_policy.json
