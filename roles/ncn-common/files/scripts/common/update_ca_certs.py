#!/usr/bin/env python3
#
# MIT License
#
# (C) Copyright 2020, 2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
"""A cloud-init 'like' module to update-ca certs. Expects ~ cPython 3.6+."""

import io
import os
import json
import subprocess as subp
import sys

import logging
from cryptography import x509
from cryptography.hazmat.backends import default_backend

UPDATE_CA_CMD = ["update-ca-certificates"]
CRAYSYS_META_CMD = ["craysys", "metadata", "get", "ca-certs"]

# SLES CA Path
# https://www.suse.com/support/kb/doc/?id=000019003
CA_CERT_PATH_SLES = "/etc/pki/trust/anchors/"

# use different path from upstream cloud-init ca module
CA_CERT_FILENAME = "platform-ca-certs.crt"
CA_CERT_FULLPATH = os.path.join(CA_CERT_PATH_SLES, CA_CERT_FILENAME)

logging.basicConfig(
    format='%(asctime)s %(levelname)s:%(filename)s(%(lineno)d) %(message)s',
    level=logging.DEBUG
)


def get_ca_meta():
    """
    Try to retrieve cert-related cloud-init metadata.

    Returns ca_certs data structure on success, None otherwise.
    """

    try:
        p = subp.run(
            CRAYSYS_META_CMD,
            stdout=subp.PIPE,
            stderr=subp.PIPE,
            check=True,
            )
        return json.loads(p.stdout)
    except subp.CalledProcessError as e:
        logging.error(f"Exec failed {CRAYSYS_META_CMD}, rc = {e.returncode}")
        logging.error(f"stdout: \n{e.stdout}")
        logging.error(f"stderr: \n{e.stderr}")
    except FileNotFoundError:
        logging.error(f"Exec failed, file not found {CRAYSYS_META_CMD}")
    except (ValueError, KeyError):
        logging.error(f"Failed to load metadata, raw input:\n {p.stdout}")

    return None


def add_ca_certs(certs):
    """
    Adds certificates to PKI trust anchor location.
    @param certs: list of single string, pem encoded, certificates, with
    embedded '\n' newlines.

    Returns True on success, False otherwise.
    """

    if os.path.exists(CA_CERT_FULLPATH):
        logging.info("bundle file exists at {}".format(CA_CERT_FULLPATH))

    if not len(certs):
        logging.info("List of certificates is empty,"
                     f" removing (if exists) {CA_CERT_FULLPATH}")

        try:
            if os.path.isfile(CA_CERT_FULLPATH):
                os.unlink(CA_CERT_FULLPATH)
        except OSError as e:
            logging.error(f"Unable to unlink file, received: {e.strerror}")

        return True

    logging.info(f"Found {len(certs)} certificates")

    sbuff = io.StringIO()

    for cert in certs:
        try:
            cert = cert.strip()
            # sanity check, attempt to parse cert
            try:
                raw = bytes(cert, "utf-8")
                x509.load_pem_x509_certificate(raw, default_backend())
            except Exception as e:
                logging.error(f'Failed to parse certificate: {e}')

            # guard against 'empty' lines
            # that could cause pem parsing failures
            # on system.
            for line in cert.split('\n'):
                if len(line.strip()):
                    sbuff.write(line + '\n')
        except (ValueError, TypeError):  # primarily for x509.load...
            logging.error(f"Cannot load cert into x509 format:\n{cert}")
            return False

    try:
        if len(sbuff.getvalue()):
            with open(CA_CERT_FULLPATH, 'w') as f:
                f.write(sbuff.getvalue())
    except IOError:
        logging.error("Error writing PEM files")
        return False

    return True


def update_ca_certs():
    """
    Updates system cache of trusted CA certificates.

    Returns True on success, False otherwise.
    """

    try:
        subp.run(UPDATE_CA_CMD, check=True, stdout=subp.PIPE, stderr=subp.PIPE)
    except subp.CalledProcessError as e:
        logging.error(f"Unable to exec {UPDATE_CA_CMD}, rc = {e.returncode}")
        logging.error(f"stdout: \n{e.stdout}")
        logging.error(f"stderr: \n{e.stderr}")
        return False
    except FileNotFoundError:
        logging.error(f"Exec failed, file not found {UPDATE_CA_CMD}")
        return False

    return True


def main():

    logging.info("start")

    # Try to load meta, if no meta found, take no action

    # get cert meta
    cert_meta = get_ca_meta()
    if cert_meta is None:
        logging.error("Unable to load ca-certs metadata")
        sys.exit(1)

    logging.info("loaded ca-certs metadata")

    if 'trusted' not in cert_meta.keys():
        logging.error("'trusted' ca certificates key not in metadata")
        sys.exit(2)

    # Replace certs provisioned by this tool, an empty
    # array will remove CAs installed by this tool, if
    # they exist.

    if not add_ca_certs(cert_meta['trusted']):
        logging.error("unable to add/remove ca certificates")
        sys.exit(3)

    logging.info(f"Updated certificate bundle at {CA_CERT_FULLPATH}")

    if not update_ca_certs():
        logging.error("unable to update ca certificate cache")
        sys.exit(4)

    logging.info("Updated certificate cache on system")

    logging.info("stop")


if __name__ == "__main__":
    main()

# vi: ts=4 expandtab
