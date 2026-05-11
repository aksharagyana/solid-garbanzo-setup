graphify_setup(){
    export GRAPHIFY_NO_VIZ=1
    graphify codex install
    graphify copilot install
    graphify cursor install
    graphify antigravity install
    graphify update . --mode deep
}