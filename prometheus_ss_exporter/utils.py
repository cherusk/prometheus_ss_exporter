# MIT License
#  prometheus_ss_exporter
# Copyright (c) 2018 Matthias Tafelmeier
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import os


def which(executable, fail=False):
    def is_executable(filename):
        return (os.path.isfile(filename) and
                os.access(filename, os.X_OK))

    pathname, filename = os.path.split(executable)
    if pathname:
        if is_executable(executable):
            return executable
    else:
        for path in [i.strip('""')
                     for i in
                     os.environ["PATH"].split(os.pathsep)]:
            filename = os.path.join(path, executable)
            if is_executable(filename):
                return filename

    if fail:
        raise RuntimeError("No %s binary found in PATH." % executable)
