#!/usr/bin/env python3
"""
High-Speed Parallel Multipart Uploader for S3 / DigitalOcean Spaces.
Optimized for AWS EC2 Graviton (t4g.xlarge) to DigitalOcean Spaces cross-region transfers.
Uses boto3 TransferConfig with 16 parallel threads and 25MB chunks.
"""
import sys
import os
import time

try:
    import boto3
    from boto3.s3.transfer import TransferConfig
    from botocore.config import Config
except ImportError:
    print("[WARN] boto3 is not installed in Python environment.", file=sys.stderr)
    sys.exit(2)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file_to_upload> [s3_key]", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    if not os.path.isfile(file_path):
        print(f"[ERROR] File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    key = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(file_path)

    bucket = os.environ.get("SPACES_BUCKET", "ubiquity-pi-image")
    region = os.environ.get("SPACES_REGION", "sfo2")
    endpoint = os.environ.get("SPACES_ENDPOINT", f"{region}.digitaloceanspaces.com")
    access_key = os.environ.get("S3_ACCESS_KEY")
    secret_key = os.environ.get("S3_SECRET_KEY")

    if not access_key or not secret_key:
        print("[ERROR] S3_ACCESS_KEY and S3_SECRET_KEY environment variables are required.", file=sys.stderr)
        sys.exit(1)

    file_size = os.path.getsize(file_path)
    file_size_mb = file_size / (1024 * 1024)
    file_size_gb = file_size / (1024 * 1024 * 1024)

    print("==========================================================")
    print("  HIGH-SPEED PARALLEL SPACES UPLOADER (boto3 / 16 threads)")
    print("==========================================================")
    print(f"  Source File : {file_path}")
    print(f"  File Size   : {file_size_gb:.2f} GB ({file_size_mb:.1f} MB)")
    print(f"  Destination : s3://{bucket}/{key}")
    print(f"  Endpoint    : https://{endpoint} (Region: {region})")
    print("==========================================================")

    session = boto3.session.Session()
    client = session.client(
        "s3",
        region_name=region,
        endpoint_url=f"https://{endpoint}",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(s3={"addressing_style": "virtual"}, retries={"max_attempts": 5, "mode": "adaptive"})
    )

    class UploadProgress:
        def __init__(self, total_bytes):
            self.total_bytes = total_bytes
            self.uploaded_bytes = 0
            self.start_time = time.time()
            self.last_report = 0

        def __call__(self, bytes_transferred):
            self.uploaded_bytes += bytes_transferred
            now = time.time()
            if now - self.last_report >= 2.0 or self.uploaded_bytes >= self.total_bytes:
                elapsed = max(now - self.start_time, 0.001)
                pct = (self.uploaded_bytes / self.total_bytes) * 100.0
                mb_uploaded = self.uploaded_bytes / (1024 * 1024)
                mb_total = self.total_bytes / (1024 * 1024)
                speed_mb_s = mb_uploaded / elapsed
                eta_s = (self.total_bytes - self.uploaded_bytes) / (speed_mb_s * 1024 * 1024) if speed_mb_s > 0 else 0
                print(f"  Progress: {pct:5.1f}% [{mb_uploaded:6.1f} / {mb_total:6.1f} MB] @ {speed_mb_s:5.1f} MB/s (ETA: {eta_s:.0f}s)", flush=True)
                self.last_report = now

    # Transfer configuration: 16 concurrent threads, 25MB part size
    transfer_config = TransferConfig(
        multipart_threshold=25 * 1024 * 1024,
        max_concurrency=16,
        multipart_chunksize=25 * 1024 * 1024,
        use_threads=True
    )

    t0 = time.time()
    progress_callback = UploadProgress(file_size)
    client.upload_file(
        Filename=file_path,
        Bucket=bucket,
        Key=key,
        ExtraArgs={"ACL": "public-read"},
        Config=transfer_config,
        Callback=progress_callback
    )
    total_time = max(time.time() - t0, 0.001)
    avg_speed = file_size_mb / total_time

    print("==========================================================")
    print("  UPLOAD COMPLETE!")
    print(f"  Duration    : {total_time:.1f} seconds ({total_time/60:.2f} minutes)")
    print(f"  Avg Speed   : {avg_speed:.2f} MB/s")
    print(f"  Public URL  : https://{bucket}.{endpoint}/{key}")
    print("==========================================================")

if __name__ == "__main__":
    main()
