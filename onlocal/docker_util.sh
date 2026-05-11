gchr_login(){
    echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
}

dev_go(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${GO_IMAGE}" bash
}

dev_python(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${PYTHON_IMAGE}" bash
}

dev_node(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -p 3000:3000 -p 7007:7007 -p 5173:5173  -v /var/run/docker.sock:/var/run/docker.sock -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${DEBIAN_IMAGE}" bash
}

dev_debian(){
    docker run -it --pull=always --env-file "${DOCKER_ENV_FILE}" -v "${CODE_ON_MAC}":"${CODE_ON_CONT}" -v "${UTILS_ON_MAC}":"${UTILS_ON_CONT}" "${DEBIAN_IMAGE}" bash
}

docker_cleanup(){
    echo -e "\nStopping all running containers..."
    docker stop $(docker ps -q) 2>/dev/null || true

    echo "Removing all containers (including stopped ones)..."
    docker rm -f $(docker ps -a -q) 2>/dev/null || true

    echo "Removing all images..."
    docker rmi -f $(docker images -q) 2>/dev/null || true

    echo "Removing all volumes..."
    docker volume rm -f $(docker volume ls -q) 2>/dev/null || true

    echo "Removing all custom networks..."
    docker network rm $(docker network ls --filter "type=custom" -q) 2>/dev/null || true

    echo "Clearing build cache and remaining system resources..."
    docker builder prune -a -f
    docker system prune -a --volumes -f

    echo -e "\n=== DOCKER NUCLEAR CLEANUP COMPLETED at $(date) ==="

    echo "Final disk usage:"
    docker system df -v || echo "Docker info not available (everything cleaned)."

    echo -e "\nAll Docker resources have been aggressively deleted."
}
