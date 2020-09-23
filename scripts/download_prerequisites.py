import os
import os.path
import enum
import sys
import re
import logging
import hashlib
import argparse
from urllib.parse import urlparse

import yaml
import requests
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry


class ErrorCode(enum.Enum):
    Success = 0
    Error = 1


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


def parse_args( arguments ):
    """
    Parse the command line arguments

    Returns:
        A structure with 3 attributes (`tpl`, `dest`, `overwrite`) definind respectively
        - the path to the tpl yaml description file,
        - the download destination folder
        - and whether we should overwrite a file if it already exists.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument( "--tpl", default="tpls.yaml", help="Path to TPLs yaml description." )
    parser.add_argument( "--dest", default="../tplMirror", help="Download directory." )
    parser.add_argument( '--overwrite', default=False, action='store_true', help="Override existing files." )
    return parser.parse_args( arguments )


def validate_hashcode(file_name, md5_reference):
    """
    Computes the md5 checksum for given file and validate against reference.

    Arguments:
        file_name (str): Path to the file to be analyzed.
        md5_reference (str): Hexdigest provided as refence as a 32 characters [0-9a-f]

    Returns:
        ErrorCode.Success if check matches. ErrorCode.Error in any other case.
    
    Raises:
        Does not raise.
    """
    md5 = hashlib.md5()
    chunk_size = md5.block_size * 1024
    try:
        with open(file_name, "rb") as f:
            for chunk in iter(lambda: f.read(chunk_size), b''):
                md5.update(chunk)

        if md5.hexdigest() != md5_reference:
            error_msg = "md5 sum for %s is %s and does not match reference %s" % (file_name, md5.hexdigest(), md5_reference)
            logging.error(error_msg)
            return ErrorCode.Error
        else:
            logging.info("Checksum for %s matches reference." % file_name)

        return ErrorCode.Success
    except Exception as e:
        logging.exception( e )
        return ErrorCode.Error


def build_output_name(tpl, response, url):
    """
    Builds and returns the downloaded file name.

    Arguments:
        tpl (dict like): May contain the name in the `output` key to define a potential output file name.
        response (http request answer): May contain a name in its header.
        url (str): The download link.

    Returns:
        The download file name as a str.
    """
    # If a name is provided by the user
    if "output" in tpl:
        return tpl["output"]
    # If the name is defined in the HTTP headers
    m = re.search("filename=(.+)", response.headers.get('content-disposition', ''))
    if m:
        return m.group(1)
    # Default is to build the basename from the URL
    parsed_url = urlparse(url)
    return os.path.basename(parsed_url.path)


def download_tpl(tpl, dest, overwrite, chunk_size=1024 * 1024):
    """
    Downloads the third partylib from `tpl`.
    Validate against md5 checksums if provided.

    Arguments:
        tpl (dict like): Contains keys `url` that defines where to download from, 
            `output` that defines where to download and potentially `md5` that contains a checksum reference and
        dest (str): Download file name.
        overwrite (bool): Shall we overwrite any file that already exists.
        chunk_size (int): Size of the chunk to write when downloading the stream.
            Technical argument, shoud not be needed to modify.
    
    Returns:
        ErrorCode.Success if download and check are OK. ErrorCode.Error in any other case.
    
    Raises:
        Does not raise.
    """
    url = tpl.get("url")

    if not url:
        msg = 'No url provided for tpl "%s". Nothing done.' % tpl["output"]
        # When all the urls are fulfilled, this should become an error (logging.error + return ErrorCode.Error)
        logging.warning(msg)
        return ErrorCode.Success

    try:
        with requests.Session() as session:
            # Allow for some retries if a download fails on potentially recoverable or temporary errors.
            retry = Retry(total=2, backoff_factor=5, method_whitelist=False,
                          status_forcelist=(408, 429, 500, 502, 503, 504))
            adapter = HTTPAdapter(max_retries=retry)
            session.mount("https://", adapter)
            session.mount("http://", adapter)
            session.mount("ftp://", adapter)

            response = session.get(url, stream=True)
            response.raise_for_status()

            output_file_name = build_output_name(tpl, response, url)
            output = os.path.join(dest, output_file_name)

            # Overwrite part
            if os.path.exists(output):
                if overwrite:
                    msg = 'File "%s" already exists, overwriting.' % output
                    logging.warning(msg)
                else:
                    msg = 'File "%s" already exists, nothing done.' % output
                    logging.warning(msg)
                    return ErrorCode.Success

            # Actual downloading part
            with open(output, "wb") as f:
                logging.info("Downloading %s to %s" % (url, output))
                for chunk in response.iter_content(chunk_size=chunk_size):
                    f.write(chunk)

        if "md5" in tpl and tpl["md5"]:
            return validate_hashcode(output, tpl["md5"])

        return ErrorCode.Success
    except Exception as e:
        logging.exception( e )
        return ErrorCode.Error


def download_all_tpls(tpls, dest, overwrite):
    """
    Downloads all the third partylib from `tpls`.

    Arguments:
        tpls (iterable): Description of all the third party libraries. See `download_tpl` documentation.
        dest (str): Download file name.
        overwrite (bool): Shall we overwrite any file that already exists.
    
    Returns:
        ErrorCode.Success if everything went OK for all tpls. ErrorCode.Error in any other case.
    
    Raises:
        Does not raise.
    """
    if not os.path.isdir(dest):
        error_msg = "Destination folder \"%s\" does not exist or is not a directory." % dest
        logging.error(error_msg)
        return ErrorCode.Error

    # I convert into list to be sure that the whole iteration goes through before going to the error check.
    error_codes = list(map(lambda tpl: download_tpl(tpl, dest, overwrite), tpls))
    return ErrorCode.Success if all( ec == ErrorCode.Success for ec in error_codes ) else ErrorCode.Error


def main( arguments ):
    logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                        datefmt='%Y/%m/%d %H:%M:%S',
                        level=logging.INFO)
    try:
        args = parse_args( arguments )
        tpls = read_config_file(args.tpl) 
        return download_all_tpls(tpls["tpls"], args.dest, args.overwrite)
    except Exception as e:
        logging.error(e)
        return ErrorCode.Error


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        sys.exit( main( arguments ).value )
    except Exception as e:
        logging.exception( e )
        sys.exit( ErrorCode.Error.value )
