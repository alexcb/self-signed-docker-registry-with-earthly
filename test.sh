#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

tools=("docker" "curl")
for tool in "${tools[@]}"; do
    which "$tool" >/dev/null || (echo "$tool must be installed to use this script" && exit 1)
done

WORK_DIR="$(mktemp -d)"
cd "$WORK_DIR"
echo working out of $WORK_DIR

# deletes the temp directory
function cleanup {
  rm -rf "$WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

REGISTRY_HOST="selfsigned.example.com"

mkdir private public

# create a selfsigned CA
openssl genrsa -out private/selfsigned-ca.key 2048
openssl req -x509 -new -nodes -key private/selfsigned-ca.key -days 9999 -out public/SelfSigned_Root_CA.crt -subj "/CN=test-ca"

# typically a user would store SelfSigned_Root_CA.crt under /usr/local/share/ca-certificates/SelfSigned_Root_CA.crt
# and run update-ca-certificates to install that certificate on the user's system filepath rather than saving it 
# to a temporary/user location (like this test script does).
# instead we will run under the public directory, which will produce SelfSigned_Root_CA.pem and ca-certificates.crt
cd public; update-ca-certificates --fresh --certsdir . --localcertsdir . --hooksdir . --certsconf . --etccertsdir .; cd ..

# create an ssl cert
openssl genrsa -out private/selfsigned.key 2048

openssl req -new -key private/selfsigned.key -subj "/CN=$REGISTRY_HOST" -out public/selfsigned.csr
echo "== contents of public/selfsigned.csr =="
cat public/selfsigned.csr | openssl req -in - -text -noout

# Next create options for use during signing the csr with the root CA
echo "
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[req_ext]
subjectAltName = DNS:$REGISTRY_HOST
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
" > openssl.config

openssl x509 -req -in public/selfsigned.csr -CA public/SelfSigned_Root_CA.pem \
        -CAkey private/selfsigned-ca.key -CAcreateserial -out public/selfsigned.pem \
        -days 9999 -extensions v3_req \
        -extensions req_ext -extfile openssl.config

echo "== contents of public/selfsigned.pem =="
cat public/selfsigned.pem | openssl x509 -in - -ext req -text -noout

ls -la public
ls -la private

docker rm -f registry-test

docker run --network=host --name=registry-test --rm -d \
  -v $(pwd)/private:/keys/private \
  -v $(pwd)/public:/keys/public \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/keys/public/selfsigned.pem \
  -e REGISTRY_HTTP_TLS_KEY=/keys/private/selfsigned.key \
  registry:2

docker logs -f registry-test &

# wait for registry to start
while ! nc -z localhost 5000; do
  echo "waiting for registry to start"
  sleep 1
done

# buildkit runs in earthly-buildkitd; we must pass in an IP address pointing to the host.
HOST_IP=$(hostname --all-ip-addresses | awk '{print $1}')

curl --cacert public/ca-certificates.crt --resolve "$REGISTRY_HOST:5000:$HOST_IP" -vv "https://$REGISTRY_HOST:5000"

# reset_earthly_buildkit_and_load_certs clears the earthly cache and re-initializes the SSL cert and hosts entry for the selfsigned.example.com registry
function reset_earthly_buildkit_and_load_certs {
    docker rm --force earthly-buildkitd || true

    # start up earthly-buildkitd and prune/reset the cache
    earthly --buildkit-volume-name=selfhostedregistrytest prune --reset

    # a --reset removes all custom-certs/hosts, need to reload them

    # update hosts in earthly container to point to host IP
    docker exec -ti earthly-buildkitd sh -c "echo \"$HOST_IP selfsigned.example.com\" >> /etc/hosts"

    docker cp public/SelfSigned_Root_CA.crt earthly-buildkitd:/usr/local/share/ca-certificates/
    docker exec -ti earthly-buildkitd sh -c "update-ca-certificates"

    # Sanity check that root ca cert works after a prune --reset
    docker exec -ti earthly-buildkitd sh -c "wget https://selfsigned.example.com:5000/?this-is-a-sanity-check -O - >/dev/null"
}

reset_earthly_buildkit_and_load_certs

# Earthly should now be setup for use with our self-hosted, self-signed registry
# Continue with testing earthly remote cache behaviour


test_stage="Running earthly against an empty registry";
docker exec registry-test /bin/sh -c "echo == $test_stage == > /proc/1/fd/1"

earthly --buildkit-volume-name=selfhostedregistrytest --use-inline-cache "$SCRIPT_DIR/+test" 2>&1 | tee output.txt
if grep '*cached*' output.txt >/dev/null; then
    echo "ERROR: there should not be any cached items"
    exit 1
fi


test_stage="Earthly should push a cache item to the registry"
docker exec registry-test /bin/sh -c "echo == $test_stage == > /proc/1/fd/1"

# FIXME targets referenced by COPYs dont get saved to the regsitry cache
#    1) maybe a bug? should --save-inline-cache work when no --push is specified?
#        "earthly --save-inline-cache +euler-bin" doesn't push a cache item
#
#    2) cache items are pushed only for directly referenced targets:
#        "earthly --save-inline-cache --push +euler-bin" will produce a cache item for selfsigned.example.com:5000/myuser/testcache_euler_bin:mytag
#       however, if instead we call
#        "earthly --save-inline-cache --push +test"
#       this will not produce a cache item for selfsigned.example.com:5000/myuser/testcache_euler_bin:mytag or selfsigned.example.com:5000/myuser/testcache_calc_e:mytag
#       since these items are referenced by COPYs

# TL;DR: This should work but doesn't
#  earthly --buildkit-volume-name=selfhostedregistrytest --save-inline-cache --push "$SCRIPT_DIR/+test" 2>&1 | tee output.txt
# as a work-around, we need to call the individual targets when they are referenced via a COPY

earthly --buildkit-volume-name=selfhostedregistrytest --save-inline-cache --push "$SCRIPT_DIR/+euler-bin" 2>&1 | tee output.txt
if ! grep '*cached*' output.txt >/dev/null; then
    echo "ERROR: layers should have been cached from the previous build (but not registry)"
    exit 1
fi

# FIXME targets referenced by FROMs dont get saved to the regsitry cache
# calling +euler-bin includes a FROM +gcc-deps, but +gcc-deps is not being cached
# As a work-around, we need to call +gcc-deps directly in order to have it pushed
earthly --buildkit-volume-name=selfhostedregistrytest --save-inline-cache --push "$SCRIPT_DIR/+gcc-deps" 2>&1 | tee output.txt

# Next clear the cache and then build the pi-bin (which shares the same deps as euler-bin)
test_stage="Earthly should pull in cached gcc-deps and push cache for pi-bin "
docker exec registry-test /bin/sh -c "echo == $test_stage == > /proc/1/fd/1"
reset_earthly_buildkit_and_load_certs
earthly --buildkit-volume-name=selfhostedregistrytest --use-inline-cache --save-inline-cache --push "$SCRIPT_DIR/+pi-bin" 2>&1 | tee output.txt
if ! grep '*cached*' output.txt >/dev/null; then
    echo "ERROR: +gcc-deps should have been cached from the self hosted registry, but weren't"
    exit 1
fi

# tests that no items are cached when --use-inline-cache is not set
#test_stage="run earthly without inline cache"
#docker exec registry-test /bin/sh -c "echo == $test_stage == > /proc/1/fd/1"
#reset_earthly_buildkit_and_load_certs
#earthly --buildkit-volume-name=selfhostedregistrytest "$SCRIPT_DIR/+test" 2>&1 | tee output.txt
#if grep '*cached*' output.txt >/dev/null; then
#    echo "ERROR: there should not be any cached items"
#    exit 1
#fi


# tests that at least one layer is pulled in from the cache
test_stage="run earthly with inline cache"
docker exec registry-test /bin/sh -c "echo == $test_stage == > /proc/1/fd/1"
reset_earthly_buildkit_and_load_certs
earthly --buildkit-volume-name=selfhostedregistrytest --use-inline-cache "$SCRIPT_DIR/+test" 2>&1 | tee output.txt
if ! grep '*cached*' output.txt >/dev/null; then
    echo "ERROR: layers should have been cached from the self hosted registry, but weren't"
    exit 1
fi


echo " == self-hosted, self-signed docker registry caching test passed =="
docker rm -f registry-test >/dev/null
