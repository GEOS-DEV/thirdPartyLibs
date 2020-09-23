import argparse
import logging
import os
import sys

import yaml

from google.oauth2 import service_account
from google.cloud import storage
from google.auth.transport.requests import AuthorizedSession

from requests.utils import quote

from download_prerequisites import read_config_file
from macosx_TPL_mngt import build_credentials, build_storage_client


def parse_args( arguments ):
    """
    Parse the command line arguments

    Returns:
        A structure with 3 attributes (`tpl`, `from_dir`, `service_account_file`) definind respectively
        - the path to the tpl yaml description file,
        - the source folder
        - the path to the service account file used for GCP bucket connection.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument( "--tpl", default="scripts/tpls.yaml", help="Path to TPLs yaml description." )
    parser.add_argument( "--from", default="tplMirror", help="TPL directory.", dest="from_dir" )
    parser.add_argument( "service_account_file", metavar="CONFIG_JSON", help="Path to the service accoubt json file." )
    return parser.parse_args( arguments )


def build_blob_name( output, md5 ):
    """
    Builds the blob backup name.
    We rely on this to check if the file is already saved in the bucket.
    If the name is not found in the bucket, then we'll backup again.
    """
    return quote( output + "/" + md5 )


def backup_tpls( bucket, tpls, from_dir ):
    """
    Build all the tpl tarballs defined in `tpls` and located in `from_dir` into GCP's `bucket`.

    Parameters
        bucket (google.cloud.storage.bucket.Bucket): The GCP storage bucket to upload to.
        tpls (iterable): Description of all the third party libraries.
                         "output" key contains the file name to find in `from_dir` and to be uploaded to `bucket`.
        from_dir (str): The directory where to find the tarball (should be the "output" field )

    Returns:
        None

    Raises:
        Raises in case of error.
    """
    for output, md5 in ( ( tpl["output"], tpl["md5"] ) for tpl in tpls ):
        tpl_blob_name = build_blob_name( output, md5 )
        # The timeout seems based on the chunk size, so I put a chunck of 4MB for 60 seconds.
        tpl_blob = bucket.blob( tpl_blob_name, chunk_size=4 * 1024 * 1024 )

        # We do not want to upload something that already exists,
        # so we need to know if the blobs are already in the bucket.
        # We rely on naming convention here.
        # If you break this, tarballs will therefore be saved twice.
        if tpl_blob.exists():
            msg = "%s already in bucket %s" % (tpl_blob_name, bucket.name)
            logging.info( msg )
            continue

        # We check that the source file has been previously downloaded in `from_dir`.
        # In our workflow, this should not happen so this should be an error.
        # But we are currently migrating, this is still acceptable
        src_file_name = os.path.join( from_dir, output )
        if not os.path.exists( src_file_name ):
            # FIXME Should become an error/assert
            logging.warning( src_file_name + " does not exist" )
            continue

        # Last, the upload part
        with open( src_file_name, "rb" ) as f:
            msg = "Uploading %s to blob %s" % ( src_file_name, os.path.joint( bucket.name, tpl_blob.name ) )
            logging.info( msg )
            tpl_blob.upload_from_file( f )


def main( arguments ):
    try:
        logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                datefmt='%Y/%m/%d %H:%M:%S',
                level=logging.INFO)

        args = parse_args(arguments)

        credentials = build_credentials(args.service_account_file)
        storage_client = build_storage_client(credentials)
        bucket = storage_client.get_bucket( "geosx-tpl-mirror" )

        tpls = read_config_file(args.tpl)
        backup_tpls( bucket, tpls["tpls"], args.from_dir )
        return 0
    except Exception as e:
        logging.exception( e )
        return 1


if __name__ == "__main__":
    sys.exit( main( sys.argv[1:] ) )
