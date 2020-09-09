import os
import os.path
import sys
import re
import logging
import hashlib
import argparse
from urllib.parse import urlparse

import yaml
import requests


def read_config_file(file_name):
    with open(file_name, 'r') as f:
        return yaml.load(f)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tpl", default="tpls.yaml")
    parser.add_argument("--dest", default="../tplMirror")
    return parser.parse_args()


def validate_hashcode(file_name, md5_reference):
    logging.info("Checking md5 sum for " + file_name)
    md5 = hashlib.md5()
    chunk_size = md5.block_size * 1024
    try:
        with open(file_name, "rb") as f:
            for chunk in iter( lambda: f.read(chunk_size), b'' ):
                md5.update(chunk)
        if md5.hexdigest() != md5_reference:
            error_msg = "md5 sum for %s is %s and does not match reference %s" % (file_name, md5.hexdigest(), md5_reference)
            logging.error(error_msg)
    except Exception as e:
        logging.error(e)


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
    url = tpl["url"]

    if not url:
        msg = 'No url provided for tpl "%s". Nothing done.' % tpl["name"]
        logging.warning(msg)
        return

    try:
        with requests.get(url, stream=True, allow_redirects=True) as response:
            response.raise_for_status()

            output_file_name = build_output_name(tpl, response, url)
            output = os.path.join(dest, output_file_name)
            logging.warning("Downloading (0) %s to %s" % (url, output))


            if os.path.exists(output):
                if overwrite:
                    msg = 'File "%s" already exists, overwriting.' % output
                    logging.warning(msg)
                else:
                    msg = 'File "%s" already exists, nothing done.' % output
                    logging.warning(msg)
                    return

            with open(output, "wb") as f:
                logging.warning("Downloading %s to %s" % (url, output))
                for chunk in response.iter_content(chunk_size=chunk_size):
                    f.write(chunk)

        if "md5" in tpl and tpl["md5"]:
            validate_hashcode(output, tpl["md5"])
    except Exception as e:
        logging.error(e)


def download_all_tpls(tpls, dest):
    if not os.path.isdir(dest):
        error_msg = "Destination folder \"%s\" does not exist or is not a directory." % dest
        logging.error(error_msg)
        sys.exit(1)

    for tpl in tpls:
        download_tpl(tpl, dest)


def main():
    args = parse_args()
    tpls = read_config_file(args.tpl)
    try:
        download_all_tpls(tpls["tpls"], args.dest)
        # download_all_tpls(tpls["tpls"], "/tmp/test")
    except Exception as e:
        logging.error(e)
        sys.exit(1)


if __name__ == "__main__":
    logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                        datefmt='%Y/%m/%d %H:%M:%S',
                        level=logging.DEBUG)
    main()

# NOTES
# adiak from github does not contain submodules
