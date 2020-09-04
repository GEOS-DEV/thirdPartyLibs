# from __future__ import (absolute_import, division, print_function, unicode_literals)
# from builtins import *

import os
import os.path
import sys
import logging
import json
import hashlib
import argparse
from urllib.parse import urlparse

import requests


def read_config_file(file_name):
    with open(file_name, 'r') as f:
        return json.load(f)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tpl", default="tpls.json")
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


def download_tpl(tpl, dest, overwrite=False, chunk_size=1024):
    url = tpl["url"]
    try:
        with requests.get(url, stream=True) as response:
            response.raise_for_status()

            parsed_url = urlparse(url)
            output = os.path.basename(parsed_url.path)
            output_file_name = os.path.join(dest, output)

            if os.path.exists(output_file_name):
                if overwrite:
                    msg = "File \"%s\" already exists, overwriting." % output_file_name
                    logging.warning(msg)
                else:
                    msg = "File \"%s\" already exists, nothing done." % output_file_name
                    logging.warning(msg)
                    return

            with open(output_file_name, "wb") as f:
                logging.info("Downloading " + url)
                for chunk in response.iter_content(chunk_size=chunk_size):
                    f.write(chunk)

        if "md5" in tpl:
            validate_hashcode(output_file_name, tpl["md5"])
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
        download_all_tpls(tpls["tpls"], tpls["dest"])
        # download_all_tpls(tpls["tpls"], "/tmp/test")
    except Exception as e:
        logging.error(e)
        sys.exit(1)


if __name__ == "__main__":
    logging.basicConfig(format='[%(asctime)s][%(levelname)8s] %(message)s',
                        datefmt='%Y/%m/%d %H:%M:%S',
                        level=logging.INFO)
    main()
