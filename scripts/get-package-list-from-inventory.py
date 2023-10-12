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

import re
import json
import argparse

repos = {}


def parse_arguments():
    parser = argparse.ArgumentParser(description='RPM Inventory Generator.')
    parser.add_argument(
        '-p',
        '--path',
        type=str,
        required=True,
        dest="path",
        help='Path to the directory where inventory.json should be saved.'
    ),
    parser.add_argument(
        '-o',
        '--output',
        type=str,
        required=True,
        dest="output",
        help='Path to the directory where inventory.json should be saved.'
    ),
    parser.add_argument(
        '-e',
        '--explicit',
        action='store_true',
        dest="explicit",
        help='Generate a list of explicitly installed packages.'
    ),
    parser.add_argument(
        '-d',
        '--deps',
        action='store_true',
        dest='deps',
        help='Generate a list of dependencies.'
    )
    return parser.parse_args()


def read_base_file(path):
    with open(path) as file:
        data = json.load(file)

    return data


def filter_packages(packages, mode=None):
    to_print = {}
    if mode == 'explicit':
        regex_pattern = r'i\+'
    elif mode == 'deps':
        regex_pattern = r'i$'
    else:
        regex_pattern = r'.'
    regex = re.compile(regex_pattern)
    for package in packages:
        name = package.get('name')
        version = package.get('version')
        status = package.get('status')
        if regex.match(status):
            to_print[name] = version
    return to_print


def print_packages(path, file_name, packages):
    keys = packages.keys()
    with open(file_name, 'w') as file:
        for key in keys:
            file.write(f'{key}={packages[key]}\n')


def main():
    print("Generating rpm inventory.")
    parsed_args = parse_arguments()
    print("Removing packages already in {}".format(parsed_args.path))
    path = read_base_file(parsed_args.path)
    if parsed_args.explicit and parsed_args.deps:
        raise argparse.ArgumentParser(
            "explicit and deps are mutually exclusive!"
            )
    elif parsed_args.explicit:
        packages = filter_packages(path, "explicit")
    elif parsed_args.deps:
        packages = filter_packages(path, "deps")
    else:
        packages = filter_packages(path)
    print_packages(parsed_args.path, parsed_args.output, packages)
    print(
        "rpm inventory generation complete and written to {}".format(
            parsed_args.output
        )
    )


if __name__ == "__main__":
    main()
