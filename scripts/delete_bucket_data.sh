# Simple script to delete both upload and processed data from buckets.

# TODO: parameterise these buckets, buckets are global so I would rather not display that information.

# delete all files in the processed bucket
PROCESSED_BUCKET='processed-gcs-bucket'
gsutil -m -q rm -r "gs://${PROCESSED_BUCKET}/**"
gsutil ls gs://$PROCESSED_BUCKET

# delete all files in the upload bucket
UPLOAD_BUCKET='upload-gcs-bucket'
gsutil -m -q rm -r "gs://${UPLOAD_BUCKET}/**"
gsutil ls gs://$UPLOAD_BUCKET
