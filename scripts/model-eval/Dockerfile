FROM ghcr.io/xtool-org/xtool:1.21.0@sha256:032d20a18c8015e49fa99fddfc4ba236795731fd8543d69971ff76d388e8430f
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cmake build-essential ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["/bin/bash"]
