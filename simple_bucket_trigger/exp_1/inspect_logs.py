"""Query logs generated from experiment."""

from google.cloud import bigquery

import pandas as pd
import datetime as dt
from pathlib import Path
import json
from loguru import logger as log

from google.cloud import storage


def count_objects(client) -> int:
    """Count number of objects in processed bucket."""
    client = storage.Client()
    bucket = client.bucket("processed-gcs-bucket")
    return len(list(bucket.list_blobs()))


def logs(client: bigquery.client.Client, tbl: str) -> pd.DataFrame:
    """Get logs for particular output.

    Have the following available from root 'run_googleapis_com_requests_20241122':

    - run_googleapis_com_requests_<date>
    - run_googleapis_com_stderr_<date>
    - run_googleapis_com_stdout_<date>
    - run_googleapis_com_varlog_system_<date>

    Where <date> is the date eg: '..._requests_20241122'
    """
    query = f"SELECT * FROM `{tbl}`"
    rows = list(client.query_and_wait(query))
    return pd.DataFrame([dict(r) for r in rows]).sort_values(["trace", "timestamp"])


def process_logs(
    df_log: pd.DataFrame,
    experiment_start_time: dt.datetime,
) -> pd.DataFrame:
    """Process logs for experiment.

    Get logs relevant to experiment only, where relevant is considered to be
    the most recently ran experiment. Pivot those so we have columns start/end
    for each file, can then generate some summary stats (average run time /
    total run time etc).
    """
    df = df_log.copy()
    df = df.loc[:, ["resource", "httpRequest", "labels"]]
    df_log = df_log.loc[
        df_log["textPayload"].str.contains("Start")
        | df_log["textPayload"].str.contains("Finished"),
        [
            "timestamp",
            "receiveTimestamp",
            "textPayload",
            "trace",
        ],
    ].assign(
        file_name=lambda x: x["textPayload"].str.extract(r"(file__[^ ]+\.csv)"),
        action=lambda x: x["textPayload"].str.split(" ").str[0].str.strip().str.lower(),
    )
    # Assuming that we want all logs _since_ the experiment was run. If it's a
    # _particular_ experiment (say we've run 5 and we want the second) this
    # isn't a suitable approach.
    df_log = df_log.loc[df_log["timestamp"].ge(experiment_start_time)]
    if df_log.empty:
        log.warning("No log values to process")
        return

    # Simple check, should only have a single start/finish per trace.
    assert (
        df_log[["trace", "action"]]
        .groupby("trace")["action"]
        .value_counts()
        .eq(1)
        .all()
    ), "Some actions (start/finish) have values other than 1."
    # Get dataframe that'll make some of the calculations a bit easier:
    #
    #                                  file_name                         finished                            start
    # file__0049a7923c0a416ab2b15dc767290947.csv 2024-11-22 20:02:23.208685+00:00 2024-11-22 20:02:22.760196+00:00
    # file__00647df6ddd4458c95e0f88c749b4d21.csv 2024-11-22 19:52:07.525857+00:00 2024-11-22 19:52:07.019301+00:00
    df_pivot = (
        df_log.pivot_table(
            index="file_name",
            columns="action",
            values="timestamp",
            aggfunc="first",
        )
        .reset_index()
        .assign(duration=lambda x: x["finished"] - x["start"])
    )
    return df_pivot


def main() -> int:
    client = bigquery.Client(project="gcp-project-id")
    with open(Path(__file__).parent / "experiment_config.json", "r") as f:
        experiment_config = json.load(f)

    experiment_start_time = dt.datetime.fromisoformat(
        experiment_config["experiment_start_time"]
    )
    df_log = logs(
        client=client,
        tbl=(
            "gcp-project-id.cloud_function_logs."
            f"run_googleapis_com_stdout_{dt.datetime.now(tz=dt.UTC).strftime('%Y%m%d')}"
        ),
    )
    df_pivot = process_logs(
        df_log=df_log,
        experiment_start_time=experiment_start_time,
    )
    # df_pivot will be a dataframe like:
    #
    # (Pdb++) df_pivot.head(3)
    # action                                   file_name                         finished                            start               duration
    # 0       file__0881e99fd5154ed0a9a601d09f95fcef.csv 2024-12-09 00:03:49.393369+00:00 2024-12-09 00:03:48.891106+00:00 0 days 00:00:00.502263
    # 1       file__0ca6dc07ec434677ad468802194a47b7.csv 2024-12-09 00:03:40.837169+00:00 2024-12-09 00:03:40.346884+00:00 0 days 00:00:00.490285
    # 2       file__1b6d062afd574897a28eb570ba407b88.csv 2024-12-09 00:03:48.052625+00:00 2024-12-09 00:03:47.552716+00:00 0 days 00:00:00.499909
    log.debug(f"df_pivot.shape {df_pivot.shape}")  # just to shutup the linter.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
