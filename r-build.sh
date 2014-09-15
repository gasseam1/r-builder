#! /bin/bash

set -e
set -x

export PATH=/usr/local/bin:$PATH
export CRAN=cran.rstudio.com
export roptions=""

# Detect OS
export OS=linux
if uname -a | grep -q Darwin; then
    export OS=osx
    roptions=--with-tcl-config=/usr/local/opt/tcl-tk/lib/tclConfig.sh \
	    --with-tk-config=/usr/local/opt/tcl-tk/lib/tkConfig.sh \
	    ${roptions}
fi

## TODO: Detect CI
export CI="semaphore"

export tag=${CI}-${version}

GetGFortran() {
    curl -O http://cran.rstudio.com/bin/macosx/tools/gfortran-4.2.3.pkg
    sudo installer -pkg gfortran-4.2.3.pkg -target /
}

GetDeps() {
    if [ $OS == "osx" ]; then
	GetGFortran
    elif [ $OS == "linux" ]; then
	Retry sudo apt-get update
	Retry sudo apt-get -y build-dep r-base
	Retry sudo apt-get -y install subversion ccache texlive \
	      texlive-fonts-extra texlive-latex-extra
    fi
}

GetSource() {
    rm -rf R-${version} R-${version}.tar.gz
    major=$(echo $version | sed 's/\..*$//')
    url="http://${CRAN}/src/base/R-${major}/R-${version}.tar.gz"
    curl -O "$url"
    tar xzf "R-${version}.tar.gz"
    cd R-${version}
}

GetDevelSource() {
    # TODO
    true
}

GetRecommended() {
    Retry tools/rsync-recommended
}

CreateInstDir() {
    sudo mkdir -p /opt/R/R-${version}
    sudo chown -R $(id -un):$(id -gn) /opt/R
}

Configure() {
    R_PAPERSIZE=letter                                       \
    R_BATCHSAVE="--no-save --no-restore"                     \
    PERL=/usr/bin/perl                                       \
    R_UNZIPCMD=/usr/bin/unzip                                \
    R_ZIPCMD=/usr/bin/zip                                    \
    R_PRINTCMD=/usr/bin/lpr                                  \
    AWK=/usr/bin/awk                                         \
    CFLAGS="-std=gnu99 -Wall -pedantic"                      \
    CXXFLAGS="-Wall -pedantic"                               \
    ./configure                                              \
    --prefix=/opt/R/R-${version}
    ${roptions}
}

Make() {
    make
}

Install() {
    make install
}

Deploy() {
    git config --global user.name "Gabor Csardi"
    git config --global user.email "csardi.gabor@gmail.com"
    git config --global push.default matching

    git remote set-url origin https://github.com/gaborcsardi/r-builder
    git config credential.helper "store --file=.git/credentials"
    python -c 'import os; print "https://" + os.environ["GH_TOKEN"] + ":@github.com"' > .git/credentials

    git fetch -q origin ${CI}
    git checkout ${CI}

    cp -r /opr/R/R-${version} .
    git add -A .

    git commit -q --allow-empty -m "Building R ${version} on ${CI}"
    git tag -d ${tag} || true
    git push origin :refs/tags/${tag}

    git tag ${tag}
    git push -q
    git push -q --tags
}

Retry() {
    if "$@"; then
        return 0
    fi
    for wait_time in 5 20 30 60; do
        echo "Command failed, retrying in ${wait_time} ..."
        sleep ${wait_time}
        if "$@"; then
            return 0
        fi
    done
    echo "Failed all retries!"
    exit 1
}

BuildVersion() {
    GetDeps
    GetSource
    CreateInstDir
    Configure
    Make
    Install
    Deploy
}

BuildDevel() {
    GetDevelSource
    GetRecommended
    CreateInstDir
    Configure
    Make
    Install
    Deploy
}

if [ "$version" == "devel" ]; then
    BuildDevel
elif [ "$version" == "" ]; then
    echo 'version is not set, doing nothing'
    exit 0
else
    BuildVersion
fi
