# staeiou/vllm-unsloth-aio

An all-in-one Docker container CUDA 12.9 runtime image, designed for interactive use in NRP. Contains:

- CUDA 12.9 base, Ubuntu 22.04, Python 3.10 (FROM nvidia/cuda:12.9.1-runtime-ubuntu22.04)
- vLLM (OpenAI-compatible server) set to auto-download and serve $JUDGE_MODEL
- LiteLLM (OpenAI-compatible proxy/router) set to auto-serve vLLM model
- s6-overlay (in-container orchestration for servers) for switching models or killing vLLM/LiteLLM
- uv-based python virtual environment in /opt/venv/ auto-activated with pyTorch, Tensorflow, Unsloth (LLM inference and fine-tuning libraries)
- Many UNIX tools (tmux, htop, nvtop, jnettop, jq, curl, net-tools, build-essential, nano, zip, less)
- 6 hour countdown time from pod start in bash prompt (for NRP interactive pods, which are killed after 6h)

The image uses **s6-overlay** for process supervision so vLLM and LiteLLM run as supervised long-running services inside a single container.

## What’s In The Image

Key entrypoints/scripts (scripts in /usr/local/bin/ can be run from any directory):

- `/usr/local/bin/start_services.sh` — launches the supervised stack (execs s6-overlay `/init`).
- `/usr/local/bin/change_model.sh <model> [KEY=VALUE ...]` — hot-swaps the served model by:
  1) updating `/workspace/service_env.sh` and
  2) restarting vLLM (and LiteLLM when present) via `s6-svc`.
- `/usr/local/bin/entrypoint.sh` — lightweight wrapper that records pod start time, then execs the command (kept for compatibility with existing K8s patterns).

Runtime state/logging:

- `/workspace/service_env.sh` — the “current service state” file (model, ports, parallelism, etc.).
- `/workspace/litellm.yaml` — generated LiteLLM config (rewritten when models change).
- `/workspace/logs/` — mirrored logs (in addition to `kubectl logs` / stdout).

## Endpoints

Defaults (override with env vars):

- vLLM: `http://localhost:8000/v1`
- LiteLLM: `http://localhost:4000/v1`

Both expose OpenAI-compatible routes like:

- `GET /v1/models`
- `POST /v1/chat/completions`

## Configuration (K8s env vars)

Configure the initial model and parallelism with environment variables in your pod spec:

```yaml
env:
  - name: JUDGE_MODEL
    value: Qwen/Qwen3-32B
  - name: JUDGE_PORT
    value: "8000"
  - name: LITELLM_PORT
    value: "4000"

  # Parallelism / sizing (optional)
  - name: JUDGE_PARALLEL
    value: "2"          # tensor parallel size (GPUs per replica)
  - name: DATA_PARALLEL_SIZE
    value: "1"          # data-parallel replicas (vLLM DP mode)
  - name: VLLM_MAX_MODEL_LEN
    value: "12000"
  - name: VLLM_GPU_MEM_UTIL
    value: "0.90"
```

At container startup, `/workspace/service_env.sh` is seeded if missing; afterwards, `change_model.sh` owns updates.

## Recommended K8s Command Pattern (clone + start)

This image is commonly used as a “clone on start” pod: the container clones whatever repo you want to work in, then starts the service stack.

```yaml
command: ["/bin/bash", "-lc"]
args:
  - |
    git clone https://$GITHUB_USER:$GITHUB_PAT@github.com/$GITHUB_REPO_TO_CLONE && exec /usr/local/bin/entrypoint.sh /usr/local/bin/start_services.sh
```

You can set any repo name in `GITHUB_REPO_TO_CLONE` (or replace the clone step entirely).

## Hot-Swapping Models

Hot-swap the model without redeploying the pod:

```bash
kubectl exec -it <pod> -- change_model.sh Qwen/Qwen3-4B
```

You can also pass overrides that should persist into `/workspace/service_env.sh`:

```bash
kubectl exec -it <pod> -- change_model.sh Qwen/Qwen3-4B JUDGE_PARALLEL=2 DATA_PARALLEL_SIZE=1
```

## Using As A General vLLM Endpoint

Once the pod is running, you can point any OpenAI-compatible client at it:

- vLLM directly: `http://<pod-ip>:8000/v1`
- via LiteLLM: `http://<pod-ip>:4000/v1`

Swap models with `change_model.sh` as needed.

## Building

```bash
docker build -t staeiou/vllm-unsloth-aio:latest .
docker push staeiou/vllm-unsloth-aio:latest
```
