ARG k3s_tag=v1.33.1-k3s1
ARG k3s_image=rancher/k3s:${k3s_tag}
ARG buildkit_release=0.22.0

FROM curlimages/curl:8.13.0@sha256:d43bdb28bae0be0998f3be83199bfb2b81e0a30b034b6d7586ce7e05de34c3fd
ARG TARGETARCH
ARG k3s_tag
ARG buildkit_release

RUN set -ex; \
  mkdir -p "/tmp/k3s-agent-images/images/"; \
  ARCH=$TARGETARCH; \
  K3S_TAG=$k3s_tag; \
  K3S_RELEASE="$(echo $K3S_TAG | sed 's/-/%2B/')"; \
  K3S_IMAGES_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_RELEASE}/k3s-airgap-images-${ARCH}.tar.zst"; \
  curl -sLS --fail --show-error \
    -o "/tmp/k3s-agent-images/images/k3s-airgap-images-${ARCH}.tar.zst" \
    ${K3S_IMAGES_URL};

RUN set -ex; \
  ARCH=$TARGETARCH; \
  BUILDKIT_URL="https://github.com/moby/buildkit/releases/download/v${buildkit_release}/buildkit-v${buildkit_release}.linux-${ARCH}.tar.gz"; \
  curl -sLS --fail --show-error \
    -o "/tmp/buildkit.tar.gz" \
    ${BUILDKIT_URL};

RUN set -ex; \
  mkdir -p /tmp/buildkit; \
  tar -xzf /tmp/buildkit.tar.gz -C /tmp/buildkit; \
  ls -la /tmp/buildkit/bin;

FROM ${k3s_image}
ARG TARGETARCH
ARG k3s_tag

COPY --from=0 /tmp/k3s-agent-images/images /var/lib/rancher/k3s/agent/images

COPY --from=0 /tmp/buildkit/bin /usr/local/bin

ADD buildkitd.toml /etc/buildkit/buildkitd.toml

ADD k3s-buildkit-start-background.sh /usr/local/bin/k3s-buildkit-start-background.sh
ADD default-entrypoint.sh /default-entrypoint.sh
ADD k3d-entrypoint-buildkitd.sh /bin/k3d-entrypoint-buildkitd.sh
ENTRYPOINT ["/default-entrypoint.sh"]

# EXPOSE 6443 8080 8547
