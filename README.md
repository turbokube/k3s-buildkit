# k3s-buildkit

Evaluating AI agents for cluster level development,
we need a truly sandboxed environment
- basically virtual machines with access only to public internet.

In our experience [k3s](https://k3s.io/), unlike Minikube and Kind,
is a pretty good canary for a production environment.
Stuff that works in k3s tends to work in production too.

Backend devloops must be able to build container images.
Classic Docker workflows fail to get your images into the kubernetes cluster.
It's notoriously slow and impractical to use an external registry for devloops.
At the very least you need a local registry, but then TLS is an issue.

[k3d image import](https://k3d.io/v5.0.3/usage/commands/k3d_image_import/) works
but workflows must be tweaked for it.

## custom k3d image

The first deliverable of this repo is a custom [k3d](https://k3d.io/) image
that can be used with port mapping so that [buildkit](https://github.com/moby/buildkit) builds
to local containerd.

The limitation is that you must build on every node,
but that's practical as long as a single-node cluster is sufficient.

See [./test-k3d.sh](./test-k3d.sh) for example usage with [buildctl](https://github.com/moby/buildkit/blob/master/docs/reference/buildctl.md).

Assuming you run k3d in Docker you probably have the buildx tool already.

```
docker buildx create \
  --name k3d \
  --driver remote \
  tcp://localhost:8547
docker buildx build --builder k3d --output type=image,name=example.net/test/myimage:k3s-buildkit-test /tmp/mycontext
CLUSTER=$(k3d cluster list --no-headers | head -n1 | cut -d' ' -f1)
docker exec k3d-${CLUSTER}-server-0 crictl images | grep -E "^(IMAGE|example)"
```

Note: Always specify tag when building this way, otherwise containerd might not list your images with name. There's no default `:latest`.

## digests, names and tags

We're yet to find out how images built this way can be referenced by digest.
