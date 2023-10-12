#
#  MIT License
#
#  (C) Copyright 2023 Hewlett Packard Enterprise Development LP
#
#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included
#  in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
#  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
#  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
#  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#  OTHER DEALINGS IN THE SOFTWARE.
#

import os
import re
import xml.etree.ElementTree as ET
import json
import argparse

repos = {}
packages = []


def parse_arguments():
    parser = argparse.ArgumentParser(description='RPM Inventory Generator.')
    parser.add_argument(
        '-p',
        '--path',
        type=dir_path,
        required=True,
        dest="path",
        help='Path to the directory where inventory.json should be saved.'
    )
    parser.add_argument(
        '-f',
        '--file_name',
        type=str,
        required=False,
        dest="file_name",
        default="inventory.json",
        help='Filename for inventory. Defaults to inventory.json'
    )
    parser.add_argument(
        '-b',
        '--base',
        type=file_path,
        required=False,
        dest='base',
        help='If set the generated inventory.json will have the base '
             'packages in this file removed.'
    )
    return parser.parse_args()


def dir_path(path):
    if os.path.isdir(path):
        return path
    else:
        raise argparse.ArgumentTypeError(
            f"readable_dir:{path} is not a valid path"
        )


def file_path(path):
    if os.path.isfile(path):
        return path
    else:
        raise argparse.ArgumentTypeError(
            f"readable_file:{path} is not a valid file path"
        )


def get_repos():
    stream = os.popen('zypper --terse --non-interactive --xmlout lr --details')
    xml = stream.read()
    root = ET.fromstring(xml)

    for repo_element in root.findall(".//repo"):
        repo = {
            'alias': repo_element.attrib['alias'],
            'name': repo_element.attrib['name'],
            'url': repo_element.find('url').text
        }

        repos[repo['name']] = repo


def get_repo_url(repo):
    if repo in repos.keys():
        return repos[repo]['url']
    else:
        return "Unknown"


def get_packages():
    # Does not use the --xmlout option because the XML does not include
    # information about whether a package was user installed, or installed
    # as a dependency of another package.
    # i = installed as a dependency by zypper
    # i+ = installed explicitly by the user
    lines = os.popen(
        'zypper --terse --non-interactive search --type package '
        '--installed-only --details'
    ).readlines()
    pattern = re.compile(r"^i(\+|\s)+(|).+$")
    for line in lines:
        line = line.strip()
        if pattern.match(line):
            fields = line.split('|')
            try:
                package = {
                    'status': fields[0].strip(),
                    'name': fields[1].strip(),
                    'version': fields[3].strip(),
                    'arch': fields[4].strip(),
                    'repo': fields[5].strip(),
                    'repo_url': get_repo_url(fields[5].strip())
                }
            except KeyError as e:
                raise KeyError(
                    "A KeyError occurred while attempting to parse a line of "
                    "zypper package output.\n\n{}".format(
                        line
                    )
                ) from e
            except:
                raise Exception(
                    "An unknown error occurred while attempting to parse a "
                    "line of zypper package output.\n\n{}".format(
                        line
                    )
                ) from e
            packages.append(package)


def remove_base_packages(base):
    global packages
    packages = [package for package in packages if not any(
        base_package['name'] == package['name'] and base_package['version'] ==
        package['version'] for base_package in base
    )]


def write_output(path, file_name):
    with open("{}/{}".format(path, file_name), 'w') as file:
        file.write(json.dumps(packages, indent=2))


def read_base_file(path):
    with open(path) as file:
        data = json.load(file)

    return data


def main():
    print("Generating rpm inventory.")
    parsed_args = parse_arguments()
    get_repos()
    try:
        get_packages()

        if parsed_args.base:
            print("Removing packages already in {}".format(parsed_args.base))
            base = read_base_file(parsed_args.base)
            remove_base_packages(base)

    except KeyError as e:
        print(
            e.args[0]
        )  # prints newlines which KeyError normally does not process
        # correctly
        raise e
    except:
        print(e)
        raise e

    write_output(parsed_args.path, parse_arguments().file_name)
    print(
        "rpm inventory generation complete and written to {}".format(
            parsed_args.path
        )
    )


if __name__ == "__main__":
    main()
