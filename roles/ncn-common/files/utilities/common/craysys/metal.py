#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
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
import json
import subprocess
import sys

class Metal:

    def execute(self, cmd):
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (result, error) = process.communicate()
        rc = process.wait()
        if rc != 0:
            print("Error: failed to execute cmd:", cmd, error)
        return json.loads(result)

    def get_metadata(self, key, level='system'):
        try:
            #
            # cloud-init converts dashes, so we'll do the same
            #
            key = key.replace('-', '_')
            resp = self.execute("cloud-init query -a")
            if level == 'node':
                return resp['ds']['meta_data'][key]
            else:
                return resp['ds']['meta_data']['Global'][key]
        except Exception as e:
            sys.exit('Error getting metadata value: {}'.format(e))
