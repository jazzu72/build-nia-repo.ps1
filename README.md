# build-nia-repo.ps1
nia AI CEO
helm/
  nia-decision-engine/
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
      hpa.yaml
      secret.yaml
# 1. Enter repo
cd .\NiaBrain-Core

# 2. Copy env sample and edit .env
copy .env.example .env
notepad .env     # or edit using your preferred editor: fill XAI_API_KEY if needed

# 3. Create Python venv and install deps
python -m venv .venv
. .\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r requirements.txt

# 4. Run the API server (development)
uvicorn niabrain.api.main:app --reload

# App endpoints:
#  - GET  /health
#  - POST /think   (body { "message": "<text>" })
#  - GET  /memory
