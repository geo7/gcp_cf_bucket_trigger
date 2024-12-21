# Simple sanity check whilst writing to see that:
#
# * when (valid) file upload to upload bucket.
# * cloud function processes file and writes to processed bucket.
################################################################################

PROCESSED_BUCKET='processed-gcs-bucket'
UPLOAD_BUCKET='upload-gcs-bucket'
FILE_NAME="check.csv"

# Ofc this is a nuke just for use whilst creating.
bash ./delete_bucket_data.sh || true

# Want a simple file that will pass the cloud function validation rules.
echo "creating test data"
echo "data_id,value" > $FILE_NAME
echo "1,2" >> $FILE_NAME

echo "Uploading test data to ${UPLOAD_BUCKET}"
gcloud storage cp ./check.csv gs://"${UPLOAD_BUCKET}"/

echo "Delete local test data file."
rm $FILE_NAME

sleep 1
# Should be output for processed bucket only (relevant to the created file at least).
bash ./list_buckets.sh
