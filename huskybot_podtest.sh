#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   Automated Local AI Stack Installer      "
echo "==========================================="

# 1. Hardware & GPU Check
if ! command -v nvidia-smi &> /dev/null; then
    echo "[!] NVIDIA driver not found. Please install NVIDIA proprietary drivers first."
    exit 1
fi

VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
echo "[+] Detected NVIDIA GPU with ${VRAM_MB} MB VRAM."

# 2. Update and Base Dependencies
echo "[+] Updating apt repositories and installing utilities..."
sudo apt update -y
sudo apt install -y curl git jq python3 python3-venv

# 3. Docker Installation
if ! command -v docker &> /dev/null; then
    echo "[+] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker "$USER"
    rm get-docker.sh
else
    echo "[+] Docker is already installed."
fi

# 4. Install Ollama and Set Keep-Alive
if ! command -v ollama &> /dev/null; then
    echo "[+] Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

echo "[+] Configuring Ollama memory release..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<EOF
[Service]
Environment="OLLAMA_KEEP_ALIVE=2m"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama

# 5. Launch Open WebUI via Docker
echo "[+] Launching Open WebUI container..."
if docker ps -a --format '{{.Names}}' | grep -q "^open-webui$"; then
    docker restart open-webui
else
    docker run -d \
      --network=host \
      -v open-webui:/app/backend/data \
      -e OLLAMA_BASE_URL="http://127.0.0.1:11434" \
      --name open-webui \
      --restart always \
      ghcr.io/open-webui/open-webui:main
fi

# 6. Setup ComfyUI Environment
if [ ! -d "$HOME/ComfyUI" ]; then
    echo "[+] Cloning and setting up ComfyUI in $HOME/ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$HOME/ComfyUI"
    python3 -m venv "$HOME/ComfyUI/venv"
    "$HOME/ComfyUI/venv/bin/pip" install --upgrade pip
    "$HOME/ComfyUI/venv/bin/pip" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    "$HOME/ComfyUI/venv/bin/pip" install -r "$HOME/ComfyUI/requirements.txt"
fi

# 7. Adaptive Model Pulling based on VRAM
echo "[+] Selecting optimal models for detected VRAM..."
ollama pull nomic-embed-text

if [ "$VRAM_MB" -ge 22000 ]; then
    # 24GB GPUs (RTX 3090, 4090)
    ollama pull gemma2:27b
    ollama pull qwen2.5-coder:14b
elif [ "$VRAM_MB" -ge 15000 ]; then
    # 16GB GPUs (RTX 5080, 4080, 4070 Ti Super)
    ollama pull qwen2.5-coder:14b
    ollama pull gemma2:9b
else
    # 8GB - 12GB GPUs
    ollama pull qwen2.5-coder:7b
    ollama pull llama3.1:8b
fi

echo "==========================================="
echo " Installation Complete!"
echo " Open WebUI: http://localhost:3000"
echo " Ollama:     http://localhost:11434"
echo " ComfyUI:    cd ~/ComfyUI && source venv/bin/activate && python3 main.py"
echo "==========================================="