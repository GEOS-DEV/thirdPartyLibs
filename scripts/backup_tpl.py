import argparse
import logging
import os
import sys

import yaml

from google.oauth2 import service_account
from google.cloud import storage
from google.auth.transport.requests import AuthorizedSession

from requests.utils import quote


TPL_BUCKET_NAME = "geosx-tpl-mirror"


def parse_args(arguments):
    """
    Parse the command line arguments

    Returns:
        A structure with 3 attributes (`tpl`, `dest`, `overwrite`) definind respectively
        - the path to the tpl yaml description file,
        - the download destination folder
        - and whether we should overwrite a file if it already exists.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--tpl", default="scripts/tpls.yaml", help="Path to TPLs yaml description.")
    parser.add_argument("--from", default="tplMirror", help="TPL directory.", dest="from_dir")
    # parser.add_argument("service_account_file", metavar="CONFIG_JSON", help="Path to the service accoubt json file.")
    return parser.parse_args(arguments)

# TODO factor
def read_config_file(file_name):
    """
    Parses and returns the file describing the TPLs.

    Parameters
        file_name (str): The path to the file.

    Returns:
        The parsed yaml, used as a dict.
    """
    with open(file_name, 'r') as f:
        return yaml.load(f)
        # return yaml.load(f, Loader=yaml.FullLoader)

# TODO refactor
def build_credentials(service_account_file):
    """
    Builds and returns the GCP credentials from the JSON config file (decyphered by travis).
    """
    return service_account.Credentials.from_service_account_file(
               service_account_file, scopes=("https://www.googleapis.com/auth/devstorage.full_control",)
                                                                )


# TODO refactor
def build_storage_client(credentials):
    """
    Builds and returns the GCP storage client.
    This functions requires GCP credentials.
    """
    return storage.Client(project=credentials.project_id, credentials=credentials)


def build_name(output, md5):
    return quote( output + "/" + md5 )


def backup_tpls(bucket, tpls, from_dir):
    blobs_names = list(b.name for b in bucket.list_blobs())
    for output, md5 in ( ( tpl["output"], tpl["md5"] ) for tpl in tpls ):
        tpl_blob_name = build_name( output, md5 )
        if tpl_blob_name not in blobs_names:
            tpl_blob = bucket.blob(tpl_blob_name, chunk_size=8 * 1024 * 1024)
            from_file_name = os.path.join( from_dir, output )
            if not os.path.exists( from_file_name ):
                logging.warning(from_file_name + " does not exist")
                # FIXME Should become an error/assert
                continue
            with open( from_file_name, "rb" ) as f:
                logging.debug( "Uploading " + from_file_name )
                tpl_blob.upload_from_file( f )


def main(arguments):
    try:
        logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                datefmt='%Y/%m/%d %H:%M:%S',
                level=logging.DEBUG)

        args = parse_args(arguments)

        # credentials = build_credentials(args.service_account_file)
        credentials = build_credentials("/root/thirdPartyLibs/geosx-key.json")
        storage_client = build_storage_client(credentials)
        bucket = storage_client.get_bucket(TPL_BUCKET_NAME)

        tpls = read_config_file(args.tpl)
        return backup_tpls(bucket, tpls["tpls"], args.from_dir)
    except Exception as e:
        logging.error(e)
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:
        logging.error(repr(e))
        sys.exit(1)
