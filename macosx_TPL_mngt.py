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


def old_tpl_in_pr_predicate(blob):
    try:
        return blob.metadata['TRAVIS_PULL_REQUEST'] == os.environ["TRAVIS_PULL_REQUEST"]
    except Exception:
        logging.warning('Could not retrieve metainformation for blob "%s" in bucket ""%s.' % (blob.name, blob.bucket.name))
        return False


def build_credentials(service_account_file):
    return service_account.Credentials.from_service_account_file(
               service_account_file, scopes=("https://www.googleapis.com/auth/devstorage.read_write",)
                                                                )


def build_storage_client(credentials):
    return storage.Client(project=credentials.project_id, credentials=credentials)


def upload_metadata(blob, credentials):
    metadata = {"metadata":{"TRAVIS_PULL_REQUEST": "876"}}
    authed_session = AuthorizedSession(credentials)
    url = "https://www.googleapis.com/storage/v1/b/%s/o/%s" % (quote(blob.bucket.name, safe=""), quote(blob.name, safe=""))
    req = authed_session.patch(url, json=metadata)
    if not req.ok:
        raise ValueError(req.reason)


def remove_old_blobs(storage_client, blob_filter, bucket_name=TPL_BUCKET_NAME):
    bucket = storage_client.get_bucket(bucket_name)
    for b in filter(blob_filter, bucket.list_blobs()):
        logging.info('Removing blob "%s" from bucket "%s"' % (b.name, bucket.name))
        # b.delete()

def upload_tpl(fp, fp_size, destination_blob_name, storage_client, bucket_name=TPL_BUCKET_NAME):
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

    credentials = build_credentials(args.service_account_file)
    storage_client = build_storage_client(credentials)

    remove_old_blobs(storage_client, old_tpl_in_pr_predicate)
    blob = upload_tpl(tpl_buff, tpl_size, tpl_name_builder(), storage_client)
    upload_metadata(blob, credentials)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        logging.error(repr(e))
        raise e
        sys.exit(1)
