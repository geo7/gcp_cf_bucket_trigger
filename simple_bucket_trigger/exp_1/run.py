"""Simple load test.

Simple test of cloud function with a particular amount of files, not the best,
but gives a rough idea.

Process:

- Generate N files size M mb to local directory
- Upload all N files to upload bucket via gsutil -m
- Monitor how long it takes to process all files from upload -> procesed, and
  whether any are dropped.
"""

import google.api_core.exceptions as google_exceptions
import tempfile
import datetime as dt
from pathlib import Path
import json
from simple_bucket_trigger.exp_1 import generate_files
import argparse
import subprocess
from loguru import logger as log

from google.cloud import storage


def parse_args():
    """CLI."""
    parser = argparse.ArgumentParser(description="Experiment cli.")

    parser.add_argument(
        "--experiment",
        type=str,
        required=True,
        help="Run experiment, gen files and upload.",
        choices=["yes", "no", "y", "n"],
    )

    parser.add_argument(
        "--n-files",
        type=int,
        required=False,
        help="Number of files to generate",
    )

    parser.add_argument(
        "--f-size",
        type=int,
        required=False,
        help="Size (ish) of files to generate.",
    )

    args = parser.parse_args()

    if (args.experiment in ["yes", "y"]) and not (args.n_files and args.f_size):
        parser.error("If running --experiment --n-files and --f-size must be passed.")

    return args


def wipe_bucket(bucket_name):
    client = storage.Client()
    bucket = client.get_bucket(bucket_name)
    blobs = bucket.list_blobs()
    for blob in blobs:
        log.debug(f"deleting blob: {blob.name} from {bucket_name}")
        try:
            blob.delete()
        except google_exceptions.NotFound as ex:
            # If trying to delete from a bucket that the cloud function has
            # already deleted from.
            log.warning(str(ex))
            pass


def wipe_buckets():
    """Wipe all files from specified buckets."""
    buckets = ["upload-gcs-bucket", "processed-gcs-bucket"]
    for bucket_name in buckets:
        wipe_bucket(bucket_name)
    print("All files deleted from specified buckets.")


def max_instance_count() -> int:
    """Get the max instance count from the cloud function"""
    cmd = """
        gcloud functions describe gcp-cloud-function --region=europe-west2 --v2 --format="json" | jq '.serviceConfig.maxInstanceCount'
    """.strip()
    max_instances = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return int(max_instances)


def run_experiment(
    *,
    n_files: int,
    f_size: int,
):
    with tempfile.TemporaryDirectory() as tmp_dir_generated_files:
        dir_generated_files = Path(tmp_dir_generated_files)
        log.debug("Running experiment.")
        wipe_buckets()
        # Want to know when the experiment started in order to filter the logs to
        # this experiment, it'll be the most recent thing run so can just filter >=
        # this start time.
        experiment_config = {
            "experiment_start_time": dt.datetime.now(tz=dt.UTC).isoformat(),
            "n_files": n_files,
            "f_size": f_size,
            "max_instances": max_instance_count(),
        }
        with open(Path(__file__).parent / "experiment_config.json", "w") as f:
            log.debug("Writing experiment config.")
            json.dump(experiment_config, f, indent=4)
        # Run the experiment - generate files locally and upload them to the
        # storage bucket.
        log.debug("Generating files locally and uploading to storgage.")
        generate_files.generate_files(
            output_dir=dir_generated_files,
            n_files=n_files,
            f_size=f_size,
        )
        generate_files.upload_files(output_dir=dir_generated_files)


def main() -> int:
    """Run experiment."""
    args = parse_args()
    if args.experiment in ["yes", "y"]:
        run_experiment(
            n_files=args.n_files,
            f_size=args.f_size,
        )
    log.debug("Experiment finished")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
