# .github/workflows/deploy-nia.yml
name: Deploy Nia — PowerShell + Python

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: windows-latest     # ← THIS IS THE FIX (Windows runner for PowerShell)

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Python deps
        run: |
          python -m venv .venv
          .\.venv\Scripts\Activate.ps1
          pip install -r requirements.txt
          pip install sentence-transformers torch --quiet

      - name: Run Nia Build Script
        run: |
          .\.venv\Scripts\Activate.ps1
          powershell -File "build-nia-repo.ps1"   # ← your actual script name

      - name: Start Nia (test)
        run: |
          .\.venv\Scripts\Activate.ps1
          python niabrain/api/main.py &
          Start-Sleep -Seconds 10
          curl http://localhost:8000

      - name: Success message
        run: Write-Host "Nia is ALIVE and deployed!" -ForegroundColor Green
