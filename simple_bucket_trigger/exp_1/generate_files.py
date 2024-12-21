"""Generate random file to check uploading."""

import pandas as pd
import argparse
from tqdm import tqdm
import numpy as np
from pathlib import Path
import uuid
import subprocess


def generate_files(*, output_dir: Path, n_files: int, f_size: int) -> int:
    """Generate n_files of size f_size for testing with."""
    # Roughly this is how large the file needed to be for there to be a single
    # mb, this is obviously dependent on how the data is generated below.
    one_mb = 28_500
    rng = np.random.default_rng(1)
    for _ in tqdm(range(n_files)):
        file_id = str(uuid.uuid4()).replace("-", "")
        file = output_dir / f"file__{file_id}.csv"
        df = pd.DataFrame({"value": rng.integers(1, 1000, one_mb * f_size)}).assign(
            data_id=file_id
        )
        df.to_csv(file, index=False)
    return 0


def upload_files(output_dir: Path) -> None:
    """Upload files using gcloud command."""
    # Can upload in parallel with -m, but seemed a bit off on mac.
    upload_cmd = f"gcloud storage cp {output_dir}/* gs://upload-gcs-bucket/ --quiet"
    print(upload_cmd)
    subprocess.run(
        upload_cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def main(n_files: int, f_size: int) -> int:
    output_dir = Path(__file__).parent / "data_output"
    output_dir.mkdir(exist_ok=True, parents=True)
    generate_files(output_dir=output_dir, n_files=n_files, f_size=f_size)
    upload_files(output_dir=output_dir)

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate some synth data")

    parser.add_argument(
        "--n-files",
        type=int,
        required=True,
        help="Number of files to generate",
    )

    parser.add_argument(
        "--f-size",
        type=int,
        required=True,
        help="Size (ish) of files to generate.",
    )

    args = parser.parse_args()

    raise SystemExit(main(n_files=args.n_files, f_size=args.f_size))
