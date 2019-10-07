from __future__ import print_function
from __future__ import division
from __future__ import unicode_literals

import os
import sys
import logging
import argparse
from io import BytesIO
import tarfile

from google.oauth2 import service_account
from google.cloud import storage
from google.auth.transport.requests import AuthorizedSession

from requests.utils import quote

TPL_BUCKET_NAME = "geosx"


def parse_args(arguments):
    parser = argparse.ArgumentParser(description="Uploading the TPL for MACOSX so they can be reused for GEOSX.")
    parser.add_argument("tpl_dir", metavar="TPL_DIR", help="Path to the TPL folder")
    parser.add_argument("service_account_file", metavar="CONFIG_JSON", help="Path to the service accoubt json file.")
    return parser.parse_args(arguments)


def tpl_name_builder():
    return "TPL/%s-%s.tar" % (os.environ['TRAVIS_OS_NAME'], os.environ['TRAVIS_JOB_NUMBER'])


def upload_metadata(blob, service_account_file):
    metadata = {"metadata":{"TRAVIS_PULL_REQUEST": os.environ["TRAVIS_PULL_REQUEST"]}}
    credentials = service_account.Credentials.from_service_account_file(service_account_file, scopes=("https://www.googleapis.com/auth/devstorage.full_control",))
    authed_session = AuthorizedSession(credentials)
    url = "https://www.googleapis.com/storage/v1/b/%s/o/%s" % (quote(blob.bucket.name, safe=""), quote(blob.name, safe=""))
    req = authed_session.patch(url, json=metadata)
    if not req.ok:
        raise ValueError(req.reason)


def upload_tpl(fp, fp_size, destination_blob_name, service_account_file, bucket_name=TPL_BUCKET_NAME):
    credentials = service_account.Credentials.from_service_account_file(service_account_file)
    storage_client = storage.Client(project=credentials.project_id, credentials=credentials)
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(destination_blob_name)
    blob.upload_from_file(fp, size=fp_size, rewind=True)
    return blob


def compress_tpl_dir(tpl_dir):
    fp = BytesIO()
    with tarfile.open(mode="w|", fileobj=fp) as tar:
        tar.add(tpl_dir)
    size = fp.tell()
    return fp, size


def main(arguments):
    logging.basicConfig(format='[%(asctime)s][%(levelname)s] %(message)s',
                        level=logging.DEBUG)
    args = parse_args(arguments)
    tpl_buff, tpl_size = compress_tpl_dir(args.tpl_dir)
    blob=upload_tpl(tpl_buff, tpl_size, tpl_name_builder(), args.service_account_file)
    upload_metadata(blob, args.service_account_file)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        logging.error(e)
        sys.exit(1)
