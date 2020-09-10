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


class ErrorCode(enum.Enum):
    Success = 0
    Error = 1


def read_config_file(file_name):
    with open(file_name, 'r') as f:
        return yaml.load(f)
        # return yaml.load(f, Loader=yaml.FullLoader)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tpl", default="tpls.yaml")
    parser.add_argument("--dest", default="../tplMirror")
    return parser.parse_args()


def validate_hashcode(file_name, md5_reference):
    md5 = hashlib.md5()
    chunk_size = md5.block_size * 1024
    try:
        with open(file_name, "rb") as f:
            for chunk in iter( lambda: f.read(chunk_size), b'' ):
                md5.update(chunk)

        if md5.hexdigest() != md5_reference:
            error_msg = "md5 sum for %s is %s and does not match reference %s" % (file_name, md5.hexdigest(), md5_reference)
            logging.error(error_msg)
            return ErrorCode.Error
        else:
            logging.info("Checksum for %s matches reference." % file_name)

        return ErrorCode.Success
    except Exception as e:
        logging.error(e)
        return ErrorCode.Error


def build_output_name(tpl, response, url):
    """
    Builds and returns the downloaded file name.
    tpl: dict like - may contain the name in the `output` key.
    response: http request answer - my contain a name in its header.
    url: string - download link.
    """
    # If a name is provided by the user
    # FIXME one could use the `name` field instead.
    if "output" in tpl:
        return tpl["output"]
    # If the name is defined in the HTTP headers
    m = re.search("filename=(.+)", response.headers.get('content-disposition', ''))
    if m:
        return m.group(1)
    # Default is to build the basename from the URL
    parsed_url = urlparse(url)
    return os.path.basename(parsed_url.path)


def download_tpl(tpl, dest, overwrite=False, chunk_size=1024):
    url = tpl.get("url")

    if not url:
        msg = 'No url provided for tpl "%s". Nothing done.' % tpl["output"]
        logging.error(msg)
        return ErrorCode.Error

    try:
        with requests.get(url, stream=True) as response:
            response.raise_for_status()

            output_file_name = build_output_name(tpl, response, url)
            output = os.path.join(dest, output_file_name)

            if os.path.exists(output):
                if overwrite:
                    msg = 'File "%s" already exists, overwriting.' % output
                    logging.warning(msg)
                else:
                    msg = 'File "%s" already exists, nothing done.' % output
                    logging.warning(msg)
                    return ErrorCode.Success

            with open(output, "wb") as f:
                logging.info("Downloading %s to %s" % (url, output))
                for chunk in response.iter_content(chunk_size=chunk_size):
                    f.write(chunk)

        if "md5" in tpl and tpl["md5"]:
            return validate_hashcode(output, tpl["md5"])

        return ErrorCode.Success
    except Exception as e:
        logging.error(e)
        return ErrorCode.Error


def download_all_tpls(tpls, dest):
    if not os.path.isdir(dest):
        error_msg = "Destination folder \"%s\" does not exist or is not a directory." % dest
        logging.error(error_msg)
        sys.exit(ErrorCode.Error)

    # I convert into list to be sure that the whole iteration goes through before going to the error check.
    error_codes = list(map(lambda tpl: download_tpl(tpl, dest), tpls))
    return ErrorCode.Success if all( ec == ErrorCode.Success for ec in error_codes ) else ErrorCode.Error


def main():
    args = parse_args()
    tpls = read_config_file(args.tpl)
    try:
        # return download_all_tpls(tpls["tpls"], "/tmp/test")
        return download_all_tpls(tpls["tpls"], args.dest)
    except Exception as e:
        logging.error(e)
        return ErrorCode.Error


if __name__ == "__main__":
    logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                        datefmt='%Y/%m/%d %H:%M:%S',
                        level=logging.INFO)
    # sys.exit(main().value)
    main()
