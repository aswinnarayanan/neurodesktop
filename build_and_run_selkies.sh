#!/bin/bash
# Build and run the Selkies PoC image.
#
# Ports exposed:
#   8888        JupyterLab
#   3478        TURN server (TCP + UDP)
#   49152-49252 TURN relay range (UDP)
#
# Usage:
#   ./build_and_run_selkies.sh                  # default (port-forwarding mode)
#   ./build_and_run_selkies.sh --host-network   # host networking (simpler, no TURN needed)
set -e

IMAGE_NAME="neurodesktop-selkies"
TAG="poc"

echo "Building ${IMAGE_NAME}:${TAG}..."
docker build -f Dockerfile.selkies -t "${IMAGE_NAME}:${TAG}" .

if [ "$1" = "--host-network" ]; then
    HOST_IP="${SELKIES_TURN_HOST:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')}"
    echo ""
    echo "Starting with host networking..."
    echo "  JupyterLab:  http://localhost:8888"
    echo "  TURN server: ${HOST_IP}:3478 (shared host stack)"
    echo ""
    docker run --rm -it \
        --network host \
        --shm-size=256m \
        -e SELKIES_TURN_HOST="${HOST_IP}" \
        "${IMAGE_NAME}:${TAG}"
else
    # Detect host IP for TURN server (browser needs to reach this)
    HOST_IP="${SELKIES_TURN_HOST:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')}"

    echo ""
    echo "Starting with port forwarding..."
    echo "  JupyterLab:  http://localhost:8888"
    echo "  TURN server: ${HOST_IP}:3478"
    echo ""
    docker run --rm -it \
        -p 8888:8888 \
        -p 3478:3478 \
        -p 3478:3478/udp \
        -p 49152-49252:49152-49252/udp \
        --shm-size=256m \
        -e SELKIES_TURN_HOST="${HOST_IP}" \
        "${IMAGE_NAME}:${TAG}"
fi
