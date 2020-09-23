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

# TODO factor
def read_config_file( file_name ):
    """
    Parses and returns the file describing the TPLs.

    Parameters
        file_name (str): The path to the file.

    Returns:
        The parsed yaml, used as a dict.
    """
    with open( file_name, 'r' ) as f:
        return yaml.load( f )
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
def build_storage_client( credentials ):
    """
    Builds and returns the GCP storage client.
    This functions requires GCP credentials.
    """
    return storage.Client(project=credentials.project_id, credentials=credentials)


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
    # We do not want to upload something that already exists,
    # so we need to know what's already in the bucket.
    # We rely on naming convention here.
    # If you break this, tarballs will therefore be saved twice.
    blobs_names = list( b.name for b in bucket.list_blobs() )

    for output, md5 in ( ( tpl["output"], tpl["md5"] ) for tpl in tpls ):
        tpl_blob_name = build_blob_name( output, md5 )

        # Nothing to do if the blob already exists.
        if tpl_blob_name in blobs_names:
            msg = "%s already in bucket %s" % (tpl_blob_name, bucket.name)
            logging.info( msg )
            continue

        # The timeout seems based on the chunk size, so I put a chunck of 4MB for 60 seconds.
        tpl_blob = bucket.blob( tpl_blob_name, chunk_size=4 * 1024 * 1024 )
        src_file_name = os.path.join( from_dir, output )
        # We check that the file has been previously downloaded in `from_dir`
        # From the workflow we are using, this should not happen so this should be an error.
        # But we are currently migrating, this is still acceptable
        if not os.path.exists( src_file_name ):
            # FIXME Should become an error/assert
            logging.warning( src_file_name + " does not exist" )
            continue

        # The upload part
        with open( src_file_name, "rb" ) as f:
            msg = "Uploading %s to blob bucket %s" % ( src_file_name, tpl_blob.name )
            logging.info( msg )
            logging.debug( "Uploading " + src_file_name )
            tpl_blob.upload_from_file( f )


def main( arguments) :
    try:
        logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                datefmt='%Y/%m/%d %H:%M:%S',
                level=logging.DEBUG)

        args = parse_args(arguments)

        credentials = build_credentials(args.service_account_file)
        # credentials = build_credentials("/root/thirdPartyLibs/geosx-key.json")
        storage_client = build_storage_client(credentials)
        bucket = storage_client.get_bucket(TPL_BUCKET_NAME)

        tpls = read_config_file(args.tpl)
        return backup_tpls(bucket, tpls["tpls"], args.from_dir)
    except Exception as e:
        logging.error( e, exc_info=e )
        return 1


if __name__ == "__main__":
    try:
        sys.exit( main( sys.argv[1:] ) )
    except Exception as e:
        logging.error( e, exc_info=e )
        sys.exit( 1 )
