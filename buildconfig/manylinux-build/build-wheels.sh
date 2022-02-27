#!/bin/bash
set -e -x

# don't make pyversion >= 3.9 wheels on manylinux1 
export SUPPORTED_PYTHONS="cp36-cp36m cp37-cp37m cp38-cp38"
if [[ "$1" != "manylinux1" ]]; then
    export SUPPORTED_PYTHONS="$SUPPORTED_PYTHONS cp39-cp39 cp310-cp310"
fi

if [[ "$1" == "buildpypy" ]]; then
    export SUPPORTED_PYTHONS="$SUPPORTED_PYTHONS pp37-pypy37_pp75 pp38-pypy38_pp75 pp39-pypy39_pp75"
fi

export PORTMIDI_INC_PORTTIME=1

# To 'solve' this issue:
#   >>> process 338: D-Bus library appears to be incorrectly set up; failed to read
#   machine uuid: Failed to open "/var/lib/dbus/machine-id": No such file or directory
if [ ! -f /var/lib/dbus/machine-id ]; then
    dbus-uuidgen > /var/lib/dbus/machine-id
fi


# -msse4 is required by old gcc in centos, for the SSE4.2 used in image.c
# -g0 removes debugging symbols reducing file size greatly.
# -03 is full optimization on.
export CFLAGS="-g0 -O3"

ls -la /io
ls -la /opt/python/

# Compile wheels
for PYVER in $SUPPORTED_PYTHONS; do
    PYBIN="/opt/python/${PYVER}/bin"
    PYTHON="${PYBIN}/python"
    if [ ! -f ${PYTHON} ]; then
        PYTHON="${PYBIN}/pypy"
    fi

    ${PYTHON} -m pip install Sphinx
    cd io
    ${PYTHON} setup.py docs
    cd ..
    ${PYTHON} -m pip wheel --global-option="build_ext" --global-option="-j4" -vvv /io/ -w wheelhouse/
done

# Bundle external shared libraries into the wheels
for whl in wheelhouse/*.whl; do
    auditwheel repair $whl -w /io/buildconfig/manylinux-build/wheelhouse/
done

# Dummy options for headless testing
export SDL_AUDIODRIVER=disk
export SDL_VIDEODRIVER=dummy

# Install packages and test
for PYVER in $SUPPORTED_PYTHONS; do
    PYBIN="/opt/python/${PYVER}/bin"
    PYTHON="${PYBIN}/python"
    if [ ! -f ${PYTHON} ]; then
        PYTHON="${PYBIN}/pypy"
    fi

    ${PYTHON} -m pip install pygame --no-index -f /io/buildconfig/manylinux-build/wheelhouse
    (cd $HOME; ${PYTHON} -m pygame.tests -vv --exclude opengl,music,timing)
done
