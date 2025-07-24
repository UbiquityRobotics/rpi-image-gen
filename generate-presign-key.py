# generate_presigned_url.py
import boto3
import sys

BUCKET = 'ubiquity-pi-image'
REGION = 'sfo2'
ENDPOINT_URL = 'https://sfo2.digitaloceanspaces.com'

filename = sys.argv[1]
session = boto3.session.Session()
client = session.client(
    's3',
    region_name=REGION,
    endpoint_url=ENDPOINT_URL,
    aws_access_key_id=S3_ACCESS_KEY,
    aws_secret_access_key=S3_SECRET_KEY
)
url = client.generate_presigned_url(
    'put_object',
    Params={'Bucket': BUCKET, 'Key': filename},
    ExpiresIn=3600
)
print(url)

