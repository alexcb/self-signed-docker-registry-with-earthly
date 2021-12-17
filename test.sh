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

docker rm --force earthly-buildkitd || true

# I don't think this works as I thought it would
#earthly config global.tlsca "$(pwd)/public/SelfSigned_Root_CA.pem"

# start up earthly-buildkitd
earthly bootstrap

# update hosts in earthly container to point to host IP
docker exec -ti earthly-buildkitd sh -c "echo \"$HOST_IP selfsigned.example.com\" >> /etc/hosts"

docker cp public/SelfSigned_Root_CA.crt earthly-buildkitd:/usr/local/share/ca-certificates/
docker exec -ti earthly-buildkitd sh -c "update-ca-certificates"

# Sanity check that root ca cert works
docker exec -ti earthly-buildkitd sh -c "wget https://selfsigned.example.com:5000 -O - >/dev/null"

docker wait registry-test
