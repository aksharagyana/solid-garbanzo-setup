precommit_install(){
    pre-commit clean
    pre-commit install --install-hooks
    pre-commit install --hook-type commit-msg
}

precommit_run(){
    pre-commit run --all-files
}
