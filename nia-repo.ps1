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
pip install pytest
pytest tests -q
# Stage 1 - builder
FROM python:3.12-slim AS builder
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

# Stage 2 - runtime
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create non-root user
RUN useradd -m nia
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /app /app

RUN chown -R nia:nia /app
USER nia

ENV PATH="/home/nia/.local/bin:$PATH"

EXPOSE 8000
docker build -t nia-decision-engine:local .
docker run --rm -p 8000:8000 --env-file .env nia-decision-engine:local
helm/
  nia-decision-engine/
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
      hpa.yaml
      secret.yaml
apiVersion: v2
name: nia-decision-engine
description: Nia Decision Engine
type: application
version: 0.1.0
appVersion: "0.1.0"
replicaCount: 1

image:
  repository: ghcr.io/<GH_OWNER>/nia-decision-engine
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8000

env:
  XAI_API_KEY: ""

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

resources: {}
nodeSelector: {}
tolerations: []
affinity: {}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nia-decision-engine.fullname" . }}
  labels:
    app: {{ include "nia-decision-engine.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "nia-decision-engine.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "nia-decision-engine.name" . }}
    spec:
      containers:
        - name: nia
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
              name: http
          env:
            - name: XAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ include "nia-decision-engine.fullname" . }}-secret
                  key: XAI_API_KEY
          resources: {{ toYaml .Values.resources | nindent 12 }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "nia-decision-engine.fullname" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ include "nia-decision-engine.name" . }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "nia-decision-engine.fullname" . }}-secret
type: Opaque
stringData:
  XAI_API_KEY: "{{ .Values.env.XAI_API_KEY | default "" }}"
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "nia-decision-engine.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "nia-decision-engine.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
helm package helm/nia-decision-engine -d helm-packages
helm repo index helm-packages --url https://raw.githubusercontent.com/<GH_USER>/<REPO>/main/helm-packages/
name: NIA GitOps CI/CD

on:
  push:
    branches: [ main ]
    tags:
      - 'v*'
  pull_request:
    branches: [ main ]

env:
  IMAGE_NAME: ghcr.io/${{ github.repository_owner }}/nia-decision-engine
  HELM_CHART_DIR: ./helm/nia-decision-engine
  CHART_PACKAGES_DIR: ./helm-packages

jobs:
  build-test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: fetch-depth: 0

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Run Tests
        run: pytest tests -q

      - name: Build and push Docker image
        if: github.event_name == 'push'
        uses: docker/build-push-action@v6
        with:
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ${{ env.IMAGE_NAME }}:latest
            ${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Run Trivy scan
        if: github.event_name == 'push'
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: table
          exit-code: '1'
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'

  helm:
    needs: build-test
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: fetch-depth: 0

      - name: Setup Helm
        uses: azure/setup-helm@v4

      - name: Lint
        run: helm lint ${{ env.HELM_CHART_DIR }}

      - name: Package Chart
        run: |
          mkdir -p ${{ env.CHART_PACKAGES_DIR }}
          helm package ${{ env.HELM_CHART_DIR }} -d ${{ env.CHART_PACKAGES_DIR }}

      - name: Create index
        run: |
          cd ${{ env.CHART_PACKAGES_DIR }}
          helm repo index . --url https://raw.githubusercontent.com/${{ github.repository }}/main/helm-packages/

      - name: Push chart branch
        run: |
          git config user.name "${{ github.actor }}"
          git config user.email "${{ github.actor }}@users.noreply.github.com"
          git checkout -B helm-packages
          git add helm-packages/
          git commit -m "Release chart $(date +%Y%m%d-%H%M%S)" || echo "no changes"
          git push origin helm-packages --force
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: nia-charts
  namespace: flux-system
spec:
  url: https://raw.githubusercontent.com/<GH_USER>/<GITOPS_REPO>/main/helm-packages/
  interval: 1m
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nia-decision-engine
  namespace: nia
spec:
  interval: 5m
  chart:
    spec:
      chart: nia-decision-engine
      sourceRef:
        kind: HelmRepository
        name: nia-charts
        namespace: flux-system
  valuesFrom:
    - kind: Secret
      name: nia-values
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: nia
  namespace: flux-system
resources:
  - ./flux-system/helm-repo.yaml
  - ./apps/nia-helmrelease.yaml
{
  "nia-values": {
    "namespace": "nia",
    "values": {
      "XAI_API_KEY": "REPLACE_ME_WITH_REAL_KEY"
    }
  }
}
# Example: generate sealed secret YAML using kubeseal (controller must be reachable or --cert used)
$json = Get-Content clusters/dev/plaintext-secrets.json -Raw | ConvertFrom-Json
foreach ($name in $json.PSObject.Properties.Name) {
  $entry = $json.$name
  $ns = $entry.namespace
  $vals = $entry.values

  $secret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{ name = $name; namespace = $ns }
    type = 'Opaque'
    stringData = $vals
  } | ConvertTo-Yaml

  $tmp = New-TemporaryFile
  $secret | Out-File -FilePath $tmp -Encoding utf8

  # If kubeseal controller accessible:
  kubeseal --controller-namespace kube-system --controller-name sealed-secrets-controller --format yaml < $tmp > clusters/dev/sealed/$name-sealedsecret.yaml

  Remove-Item $tmp
}
# login to GHCR
echo $env:GITHUB_TOKEN | docker login ghcr.io -u <GHACTOR> --password-stdin

# build and push
docker build -t ghcr.io/<GH_OWNER>/nia-decision-engine:latest .
docker push ghcr.io/<GH_OWNER>/nia-decision-engine:latest

# package helm chart
helm package helm/nia-decision-engine -d helm-packages
cd helm-packages
helm repo index . --url https://raw.githubusercontent.com/<GH_OWNER>/<GIT_REPO>/main/helm-packages/
git checkout -B helm-packages
git add .
git commit -m "Publish helm chart"
git push origin helm-packages --force
# Bootstrap Flux using the GitOps repo
flux bootstrap github \
  --owner=<GH_OWNER> \
  --repository=<GITOPS_REPO> \
  --branch=main \
  --path=clusters/dev \
  --personal
flux check
flux get sources helm
flux get helmreleases --all-namespaces
kubectl get sealedsecrets -A

CMD ["uvicorn", "niabrain.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
