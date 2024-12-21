"""Cloud function to process files uploaded to storage bucket.

Simple example - when files are uploaded to storage bucket they're processed by
the cloud function, and the processed data written to a different bucket.

# Example event/context data:

event :
>>> {
>>>     'kind': 'storage#object',
>>>     'id': 'upload-gcs-bucket/ysoduifsdoifjhdsejsd9Us09dufDQDe.txt/928375923874932',
>>>     'selfLink': 'https://www.googleapis.com/storage/v1/b/upload-gcs-bucket/o/ysoduifsdoifjhdsejsd9Us09dufDQDe.txt',
>>>     'name': 'ysoduifsdoifjhdsejsd9Us09dufDQDe.txt',
>>>     'bucket': 'upload-gcs-bucket',
>>>     'generation': '928375923874932',
>>>     'metageneration': '1',
>>>     'contentType': 'text/plain',
>>>     'timeCreated': '2024-11-17T12:52:34.344Z',
>>>     'updated': '2024-11-17T12:52:34.344Z',
>>>     'storageClass': 'STANDARD',
>>>     'timeStorageClassUpdated': '2024-11-17T12:52:34.344Z',
>>>     'size': '33',
>>>     'md5Hash': '+2izvQSlLNCSLDKIMFOSLI==',
>>>     'mediaLink': 'https://storage.googleapis.com/download/storage/v1/b/upload-gcs-bucket/o/ysoduifsdoifjhdsejsd9Us09dufDQDe.txt?generation=928375923874932&alt=media',
>>>     'contentLanguage': 'en',
>>>     'crc32c': 'lsIOcQ==',
>>>     'etag': 'CJa1/rsdoismdfE='
>>> }

context :
>>> {
>>>     event_id: 18291928192831982,
>>>     timestamp: 2024-11-17T12:52:34.344511Z,
>>>     event_type: google.storage.object.finalize,
>>>     resource: {
>>>         'name': 'projects/_/buckets/upload-gcs-bucket/objects/ysoduifsdoifjhdsejsd9Us09dufDQDe.txt',
>>>         'service': 'storage.googleapis.com',
>>>         'type': 'storage#object'
>>>         }
>>> }
"""

from typing import Self
from google.cloud import storage
import logging
import io
import pandas as pd
import google.cloud.logging as cloud_logging

log_client = cloud_logging.Client()
log_client.setup_logging()

log = logging.getLogger(__name__)
logging.basicConfig(format="%(asctime)s %(name)s %(message)s", level=logging.DEBUG)


class ValidateFile:
    """Methods for validation."""

    def __init__(
        self,
        bucket: storage.bucket.Bucket,
        name: str,
        # Assume we're getting reasonably small csvs, this is just
        # validating the file rather than the content though.
        file_size_limit_mb: int = 5,
        # https://datatracker.ietf.org/doc/html/rfc7231#section-3.1.1.5
        content_type: str = "text/csv",
    ):
        self.blob = bucket.get_blob(name)
        self.name = name
        self.file_size_limit_mb = file_size_limit_mb
        self.expected_content_type = content_type

    def file_size(self) -> Self:
        """Ensure file size is within expected range."""
        # Avoiding someone being able to dump a bunch of 20GB video files when
        # you're expecting 2mb csv's.
        blob_size = self.blob.size / 1_000_000
        if (blob_size) > self.file_size_limit_mb:
            raise ValueError(
                (
                    f"File {self.name} with size {blob_size} mb exceeds "
                    f"size limit of {self.file_size_limit_mb}"
                )
            )
        return self

    def content(self) -> Self:
        if self.blob.content_type != self.expected_content_type:
            raise ValueError(
                (
                    f"Content type {self.blob.content_type} for {self.name} "
                    f"is not the expected {self.expected_content_type}."
                )
            )
        return self

    def process(self) -> Self:
        """Validate file."""
        self.file_size().content()
        return self


def load(byte_data) -> pd.DataFrame:
    """load data from storage bucket."""
    df = pd.read_csv(io.BytesIO(byte_data))
    return df


def validate_data(*, data: pd.DataFrame) -> None:
    """Validate data before processing."""
    # Very simple validation example, just checking the schema is as expected.
    expected_columns = sorted(["value", "data_id"])
    if expected_columns != sorted(data.columns):
        raise ValueError(
            (
                f"Unexpected columns, have {sorted(data.columns)}"
                f"expected {expected_columns}"
            )
        )


def process(*, data: pd.DataFrame) -> pd.DataFrame:
    """Process data."""
    # Silly little enrichment!
    return data.assign(processed=True)


def write(*, data: pd.DataFrame, storage_blob) -> None:
    storage_blob.upload_from_string(data.to_csv(index=False), "text/csv")


def run(
    event: dict[str, str],
    _context: dict[str, str | dict[str, str]],
) -> None:
    """Entry point for cloud function."""

    log.info("Start processing %s", event["name"])

    storage_client = storage.Client()
    input_bucket = storage_client.get_bucket(event["bucket"])
    output_bucket = storage_client.get_bucket("processed-gcs-bucket")

    ValidateFile(bucket=input_bucket, name=event["name"]).process()

    # Will download file content here.
    input_blob = input_bucket.blob(event["name"])
    output_bucket.blob(event["name"])
    output_blob = output_bucket.blob(event["name"])

    try:
        df = load(byte_data=input_blob.download_as_bytes())
    except Exception as ex:
        log.exception(ex)
        return None

    validate_data(data=df)
    write(data=df, storage_blob=output_blob)

    # Could move elsewhere / leave / etc - for this the uploaded blob is
    # deleted once uploaded.
    input_blob.delete()

    log.info("Finished processing %s", event["name"])
    return None
