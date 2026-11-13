#!/bin/bash

# Runs the checker of one of the Go providers over every provider's
# artifacts_certs_r5.zip and writes ./output/certs/<provider>_<verifier>.csv.
#
# Usage: ./src/test_certs_r5_go.sh <verifier>
#   <verifier>  go-crypto | okwuosa
#
# Needs the Go toolchain named in providers/<verifier>/src/go.mod.
# What each row means is described in providers/<verifier>/README.md.

if [ $# -lt 1 ]; then
    echo "Error: must provide the name of the verifier to use (go-crypto or okwuosa)."
    exit 255
fi

verifier=$1
case "$verifier" in
  go-crypto|okwuosa)
    echo "Running with verifier $verifier."
    ;;
  *)
    echo "ERROR: verifier \"$verifier\" not supported"
    exit 255
    ;;
esac

certszip="artifacts_certs_r5.zip"
inputdir="./providers"
outputdir="./output/certs"
logfile=$outputdir/${verifier}_certs.log
srcdir=$inputdir/$verifier/src

mkdir -p $outputdir
printf "Build time: %s\n\n" "$(date)" > $logfile

# The checker's dependencies must be the ones recorded in go.sum.
(cd $srcdir && go mod verify) 2>&1 | tee -a $logfile
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: the dependencies of the $verifier checker do not match go.sum" | tee -a $logfile
    exit 1
fi

# Build the checker once; it reads the zips directly, so nothing is unzipped.
builddir=$(mktemp -d)
trap 'rm -rf "$builddir"' EXIT
checker="$builddir/check$(go env GOEXE)"
if ! (cd $srcdir && go build -buildvcs=false -o "$checker" ./cmd/check); then
    echo "ERROR: could not build the $verifier checker" | tee -a $logfile
    exit 1
fi
go version | tee -a $logfile

for providerdir in $(ls -d $inputdir/*/); do
    provider=$(basename $providerdir)
    zip=${providerdir}$certszip
    resultsfile=${outputdir}/${provider}_${verifier}.csv

    if [ ! -f $zip ]; then
        continue
    fi

    printf "\nTesting %s\n" $zip | tee -a $logfile

    # The checker writes the CSV (header row included) and prints its
    # findings as JSON lines on stderr. A finding is not an error: the exit
    # status is non-zero only if the zip could not be read or the CSV could
    # not be written.
    "$checker" -zip $zip -generator $provider -out $resultsfile 2>&1 | tee -a $logfile
    status=${PIPESTATUS[0]}

    if [ $status -ne 0 ]; then
        printf "ERROR: the %s checker failed on %s (exit status %s)\n" $verifier $zip $status | tee -a $logfile
        continue
    fi

    printf "Rows: %s Y, %s N\n" $(grep -c ',Y$' $resultsfile) $(grep -c ',N$' $resultsfile) | tee -a $logfile
done
