
#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

ROOT="$(cd "$(dirname $0)"; pwd -P)"
export KUBECONFIG="$ROOT/.kubeconfig"

cleanup() {
  k3d cluster delete test-k3s-buildkit
}

# echo "=> Building custom k3s image"
TAG=latest
IMAGE=example.net/turbokube/k3s-buildkit:$TAG
docker buildx build -t $IMAGE --progress=plain $ROOT

# loadbalancer ports aren't strictly necessary, but validate that we can develop something useful with the sandobx
HTTP_PORT=80
HTTPS_PORT=443
BUILDKIT_TCP_PORT=8547

echo "=> Starting single-node k3d cluster using $IMAGE"
k3d cluster create test-k3s-buildkit \
  --k3s-arg "--disable=traefik@server:*" \
  --k3s-arg "--disable=traefik@agent:*" \
  --port $HTTP_PORT:$HTTP_PORT@loadbalancer \
  --port $HTTPS_PORT:$HTTPS_PORT@loadbalancer \
  --image $IMAGE \
  --port $BUILDKIT_TCP_PORT:$BUILDKIT_TCP_PORT@server:0
until kubectl get pods 2>/dev/null; do
  echo "=> Waiting for cluster to respond ..."
  sleep 1
done
until kubectl get serviceaccount default 2>/dev/null; do
  echo "=> Waiting for the default service account to exist ..."
  sleep 1
done
SERVER=k3d-test-k3s-buildkit-server-0

echo "=> Container $SERVER running, KUBECONFIG=$KUBECONFIG"

echo "=> Test image build from within container (no port mapping required)"
RUNID="$(date -u +%s)"
# from now on be specific about kubeconfig to facilitate ad-hoc testing
export KUBECONFIG=""

# remove untagged images, helps while we try to set repoTags and/or pinned=true
docker exec -i $SERVER sh -ce 'crictl images -o yaml' | yq '.images.[] | select(.repoTags | length == 0) | .id' | xargs docker exec -i $SERVER crictl rmi

TESTPOD=k3s-buildkit-test-$RUNID
docker exec -e TESTPOD=$TESTPOD -i $SERVER sh -ex << 'EOF'
mkdir -p /tmp/build
cd /tmp/build
echo "FROM busybox:1" > Dockerfile
echo "RUN echo '$(date -Is)' > /tmp/date" >> Dockerfile
echo 'ENTRYPOINT [ "cat", "/tmp/date" ]' >> Dockerfile
# you _can_ build without tag but then the image will only be available by digest (and quite possibly not the digest you'd expect)
IMAGE=example.net/g5y/test-build-in-k3d:$TESTPOD
# with unpack=true the digest in the metadata file doesn't match that of `ctr image inspect`
UNPACK=false
# can't use rewrite-timestamp=true because of https://github.com/moby/buildkit/issues/4230
BUILDKIT_HOST=tcp://0.0.0.0:8547 SOURCE_DATE_EPOCH=0 buildctl build \
  --frontend=dockerfile.v0 --local context=. --local dockerfile=. \
  --output type=image,name=$IMAGE,push=false,unpack=false,store=true,oci-mediatypes=true \
  --progress=plain \
  --metadata-file /tmp/testbuild.json

DIGEST=$(cat /tmp/testbuild.json | grep '"containerimage.digest":' | cut -d '"' -f4)
BUILDKIT_IMAGE=$(cat /tmp/testbuild.json | grep '"image.name":' | cut -d '"' -f4)
[ "$IMAGE" = "$BUILDKIT_IMAGE" ] || (echo "Image mismatch arg/buildkit $IMAGE/$BUILDKIT_IMAGE" && exit 1)
CONFIG_DIGEST=$(cat /tmp/testbuild.json | grep 'containerimage.config.digest' | cut -d '"' -f4)
ctr images inspect $IMAGE
ctr images inspect $IMAGE | grep $DIGEST
ctr images inspect $IMAGE | grep $CONFIG_DIGEST

kubectl run $TESTPOD --image=$DIGEST --restart=Never
kubectl run $TESTPOD-config --image=$CONFIG_DIGEST --restart=Never
EOF

# We get ErrImagePull for any use of digest except the config digest (not manifest) with no name
ORG_TESTPOD=$TESTPOD
TESTPOD=$TESTPOD-config
KUBECONFIG=$(pwd)/.kubeconfig kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/$TESTPOD --timeout=10s
KUBECONFIG=$(pwd)/.kubeconfig kubectl logs pod/$TESTPOD
CONTAINER=$(KUBECONFIG=$(pwd)/.kubeconfig kubectl get pod $TESTPOD -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|containerd://||')
DIGEST=$(KUBECONFIG=$(pwd)/.kubeconfig kubectl get pod $TESTPOD -o jsonpath='{.status.containerStatuses[0].imageID}')
TESTPOD=$ORG_TESTPOD
echo "=> Digest from running pod: $DIGEST"

# INVESTIGATING image tagging
set -x
# the image name is avaiable here even if addressed by digest only
docker exec $SERVER ctr containers info $CONTAINER | grep '"Image"
'
docker exec $SERVER ctr images inspect example.net/g5y/test-build-in-k3d:$TESTPOD
MANIFEST_DIGEST=$(docker exec $SERVER cat /tmp/testbuild.json | grep '"containerimage.digest":' | cut -d '"' -f4)

# but can we run with that image name?
KUBECONFIG=$(pwd)/.kubeconfig kubectl run $TESTPOD-2 --image=example.net/g5y/test-build-in-k3d:$TESTPOD --image-pull-policy=Never --restart=Never
KUBECONFIG=$(pwd)/.kubeconfig kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/$TESTPOD-2 --timeout=5s

# Note that unlike digest only or tag only we need IfNotPresent to run with digest AND tag, otherwise we get ErrImageNeverPull
# BUT it doesn't seem to work with our locally built image regardless
KUBECONFIG=$(pwd)/.kubeconfig kubectl run busybox-digest-$RUNID --image=busybox@sha256:f85340bf132ae937d2c2a763b8335c9bab35d6e8293f70f606b9c6178d84f42b --image-pull-policy=IfNotPresent --restart=Never -- date
KUBECONFIG=$(pwd)/.kubeconfig kubectl run busybox-tagdigest-$RUNID --image=busybox:1@sha256:f85340bf132ae937d2c2a763b8335c9bab35d6e8293f70f606b9c6178d84f42b --image-pull-policy=IfNotPresent --restart=Never -- date
KUBECONFIG=$(pwd)/.kubeconfig kubectl run $TESTPOD-3 --image=example.net/g5y/test-build-in-k3d:$TESTPOD@$MANIFEST_DIGEST --image-pull-policy=IfNotPresent --restart=Never
# KUBECONFIG=$(pwd)/.kubeconfig kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/$TESTPOD-3 --timeout=5s
# ^ support for tag+digest is not required
#KUBECONFIG=$(pwd)/.kubeconfig kubectl get pod -o 'custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image,IMAGE_ID:.status.containerStatuses[*].imageID,CONTAINER_ID:.status.containerStatuses[*].containerID'
sleep 5
KUBECONFIG=$(pwd)/.kubeconfig kubectl get pod -o 'custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[*].image'

# docker exec -i $SERVER sh -ce 'crictl images'
# docker exec -i $SERVER crictl inspecti $DIGEST
