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
    """
    Parse the command line arguments provided as input.
    We do not let argparse fetch them itself.
    Returns an arparse structure.
    """
    parser = argparse.ArgumentParser(description="Uploading the TPL for MACOSX so they can be reused for GEOSX.")
    parser.add_argument("tpl_dir", metavar="TPL_DIR", help="Path to the TPL folder")
    parser.add_argument("service_account_file", metavar="CONFIG_JSON", help="Path to the service accoubt json file.")
    return parser.parse_args(arguments)


def tpl_name_builder():
    """
    Builds and returns the GCP blob name (mostly from environment variables).
    Before modifying this function, keep in mind that GEOSX uses this naming convention to download the tarball.
    Consider modifying GEOSX accordingly.
    """
    return "TPL/%s-%s-%s.tar" % (os.environ['TRAVIS_OS_NAME'], os.environ['TRAVIS_PULL_REQUEST'], os.environ['TRAVIS_BUILD_NUMBER'])


def old_tpl_in_pr_predicate(blob):
    """
    A predicate to check if the given CGP blob may be deleted from its bucket.
    For the moment we only delete the blobs coming from the same pull request
    because we can assume they cannot be used by client code.
    """
    try:
        return blob.metadata['TRAVIS_PULL_REQUEST'] == os.environ["TRAVIS_PULL_REQUEST"]
    except Exception:
        logging.warning('Could not retrieve metainformation for blob "%s" in bucket "%s".' % (blob.name, blob.bucket.name))
        return False


def build_credentials(service_account_file):
    """
    Builds and returns the GCP credentials from the JSON config file (decyphered by travis).
    """
    return service_account.Credentials.from_service_account_file(
               service_account_file, scopes=("https://www.googleapis.com/auth/devstorage.full_control",)
                                                                )


def build_storage_client(credentials):
    """
    Builds and returns the GCP storage client.
    This functions requires GCP credentials.
    """
    return storage.Client(project=credentials.project_id, credentials=credentials)


def upload_metadata(blob, tpl_dir, credentials):
    """
    Uploads the metadata of the blob. These metadata can be used to delete the old blobs
    (instead of relying on an implicit convention for the blob name).
    """
    metadata = {"metadata":{"TRAVIS_PULL_REQUEST": os.environ["TRAVIS_PULL_REQUEST"],
                            "TRAVIS_BUILD_NUMBER": os.environ["TRAVIS_BUILD_NUMBER"],
                            "TRAVIS_COMMIT": os.environ["TRAVIS_COMMIT"],
                            "GEOSX_TPL_DIR": tpl_dir}}
    authed_session = AuthorizedSession(credentials)
    url = "https://www.googleapis.com/storage/v1/b/%s/o/%s" % (quote(blob.bucket.name, safe=""), quote(blob.name, safe=""))
    req = authed_session.patch(url, json=metadata)
    if not req.ok:
        raise ValueError(req.reason)


def remove_old_blobs(storage_client, blob_filter, bucket_name=TPL_BUCKET_NAME):
    """
    Removes the olb GCP blobs from the GCP bucket `bucket_name`.
    This functions reliese on the predicate `blob_filter` to select the blocs to delete.
    """
    bucket = storage_client.get_bucket(bucket_name)
    for b in filter(blob_filter, bucket.list_blobs()):
        b.delete()
        logging.info('Removed blob "%s" from bucket "%s"' % (b.name, bucket.name))


def upload_tpl(fp, fp_size, destination_blob_name, storage_client, bucket_name=TPL_BUCKET_NAME):
    """
    Uploads the content of the file-like instance `fp` of size `fp_size (in bytes)`
    to the blob `destination_blob_name` into the `bucket_name` GCP bucket.
    No assumptiom on the `fp` position is done and it will me rewinded anyhow
    and `fp_size` bytes will be read.

    Returns the created blob instance.
    """
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(destination_blob_name)
    blob.upload_from_file(fp, size=fp_size, rewind=True)
    blob.make_public()
    return blob


def compress_tpl_dir(tpl_dir):
    """
    Tar (no compression for binaries) the `tpl_dir` file or direcory name.
    The resulting archive is returned in a 2-tuple as a file-like object alonside its size (in bytes). 
    """
    fp = BytesIO()
    with tarfile.open(mode="w|", fileobj=fp) as tar:
        # We don't want the archive to copy the whole path to the root folder
        archive_name = os.path.basename(os.path.normpath(tpl_dir))
        tar.add(tpl_dir, arcname=archive_name)
    size = fp.tell()
    return fp, size


def main(arguments):
    """
    Uploads the bucket and its metainformation, detetes some old blobs (but not all).
    The `arguments` are the command line arguments (excluding the program itself).
    Returns 0 in case of succes of throws.
    """
    logging.basicConfig(format='[%(asctime)s][%(levelname)s] %(message)s',
                        level=logging.INFO)
    args = parse_args(arguments)
    tpl_buff, tpl_size = compress_tpl_dir(args.tpl_dir)

    credentials = build_credentials(args.service_account_file)
    storage_client = build_storage_client(credentials)

    blob_name = tpl_name_builder()
    remove_old_blobs(storage_client, old_tpl_in_pr_predicate)
    blob = upload_tpl(tpl_buff, tpl_size, blob_name, storage_client)
    upload_metadata(blob, args.tpl_dir, credentials)
    logging.info('Uploaded blob "%s" to bucket "%s"' % (blob.name, blob.bucket.name))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        logging.error(repr(e))
        sys.exit(1)
