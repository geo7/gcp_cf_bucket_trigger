# upload file to upload bucket - check that it's processed to processed bucket
# Simple script to delete both upload and processed data from buckets.

# delete all files in the processed bucket
PROCESSED_BUCKET='processed-gcs-bucket'
UPLOAD_BUCKET='upload-gcs-bucket'
FILE_NAME="check.csv"

echo "Contents of : ${UPLOAD_BUCKET}"
gsutil ls gs://$UPLOAD_BUCKET
echo "Contents of : ${PROCESSED_BUCKET}"
gsutil ls gs://$PROCESSED_BUCKET
