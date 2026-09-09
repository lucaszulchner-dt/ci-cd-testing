# 🧪 CI/CD & Terraform Sandbox Test Harness

This directory is a **1-to-1 mirror** of the production architecture designed to test the **Trunk-Based Development** + **Zero-Rebuild Tag Promotion** pipeline end-to-end in your sandbox project (**`lucas--rios-sandbox`**).

The GitHub Actions workflow (`.github/workflows/deploy.yml`) is **100% identical in structure, variables, and authentication (WIF)** to the frontend repository workflow.

---

## 🔒 How Production Gating Works ("GH Actions Gated")

On GitHub personal accounts (free tier), GitHub disables the UI checkbox "Required reviewers" in Environments (which requires GitHub Team/Enterprise or a public repo).

**In our architecture, the release gate is enforced in GitHub Actions code:**
1. **Push to `main`**: Automatically builds and deploys to **Dev** only.
2. **Pushing a tag (`git push origin v1.0.0`)**: Does **NOT** trigger any deployment (the tag push trigger was intentionally removed).
3. **Deploying to Prod**: Requires manual execution via **`workflow_dispatch`**:
   ```yaml
   if: github.event_name == 'workflow_dispatch' && inputs.target_env == 'prod'
   ```
   Prod deployment is **strictly gated** because it cannot run on its own—it requires an authorized developer to go into the Actions tab, select the release tag, choose `target_env: prod`, and click **Run workflow**.

---

## 📁 Directory Structure

```text
cicdterraform_test/
├── README.md               <-- Complete Step-by-Step Runbook
├── app.py                  <-- Tiny Python server that displays ENV, version, & commit SHA
├── Dockerfile              <-- Alpine container (builds in ~2s, no npm needed)
├── .github/
│   └── workflows/
│       └── deploy.yml      <-- IDENTICAL workflow to the real frontend repository
└── terraform/
    ├── versions.tf         <-- Google provider (~> 6.0)
    ├── variables.tf        <-- Defaulted to project: lucas--rios-sandbox
    ├── main.tf             <-- WIF Pool & Provider + Artifact Registry + 2 Cloud Run services (512Mi) + IAM
    ├── outputs.tf          <-- Outputs all exact GitHub Actions variables
    └── terraform.tfvars    <-- Pre-filled configuration
```

---

## 📋 Step-by-Step Execution Guide

### Step 1: Run Terraform Apply in Sandbox

```bash
cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test/terraform
terraform init
terraform apply -auto-approve
```

This provisions:
- Workload Identity Federation (WIF) pool & provider (`test-github-pool`/`github-oidc`)
- Artifact Registry repository (`mock-app-repo`)
- GitHub Deployer Service Account (`mock-app-deployer@lucas--rios-sandbox.iam.gserviceaccount.com`)
- Cloud Run Dev service (`mock-app-dev`) with 512Mi memory
- Cloud Run Prod service (`mock-app-prod`) with 512Mi memory

---

### Step 2: Retrieve the GitHub Actions Variables

Run this command in the `terraform` directory:

```bash
terraform output github_action_vars
```

You will see the 5 variables that match the real repository:
* `WIF_PROVIDER`: `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/test-github-pool/providers/github-oidc`
* `WIF_SERVICE_ACCOUNT`: `mock-app-deployer@lucas--rios-sandbox.iam.gserviceaccount.com`
* `GCP_REGION`: `europe-west1`
* `GAR_REGISTRY`: `europe-west1-docker.pkg.dev/lucas--rios-sandbox/mock-app-repo`
* `GCP_PROJECT_ID`: `lucas--rios-sandbox`

---

### Step 3: Configure Variables in Your GitHub Test Repo

Create a test repository on GitHub (e.g. `cicd-tag-test`).

Push the test code:
```bash
cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test
git init
git add .
git commit -m "feat: initial test harness setup"
git branch -M main
git remote add origin git@github.com:<YOUR_USER>/cicd-tag-test.git
git push -u origin main
```

#### Option A: Set via GitHub CLI (Fastest — 5 seconds)
```bash
# In the test repo directory:
gh variable set WIF_PROVIDER --body "$(terraform -chdir=terraform output -raw github_action_vars | jq -r .WIF_PROVIDER)"
gh variable set WIF_SERVICE_ACCOUNT --body "mock-app-deployer@lucas--rios-sandbox.iam.gserviceaccount.com"
gh variable set GCP_REGION --body "europe-west1"
gh variable set GAR_REGISTRY --body "europe-west1-docker.pkg.dev/lucas--rios-sandbox/mock-app-repo"
gh variable set GCP_PROJECT_ID --body "lucas--rios-sandbox"
```

#### Option B: Set via GitHub Web UI
In your test repository:
1. Go to **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions** $\rightarrow$ **Variables** tab.
2. Click **New repository variable** and add each of the 5 variables:
   * **`WIF_PROVIDER`**: (from `terraform output`)
   * **`WIF_SERVICE_ACCOUNT`**: `mock-app-deployer@lucas--rios-sandbox.iam.gserviceaccount.com`
   * **`GCP_REGION`**: `europe-west1`
   * **`GAR_REGISTRY`**: `europe-west1-docker.pkg.dev/lucas--rios-sandbox/mock-app-repo`
   * **`GCP_PROJECT_ID`**: `lucas--rios-sandbox`

---

### Step 4: Run the 3 Verification Tests

#### ✅ Test 1: Auto-Deploy to Dev on Merge to `main`
1. Make a small edit to `app.py` or trigger the workflow via `workflow_dispatch` (target `dev`).
2. Go to **Actions** $\rightarrow$ **Mock App CI/CD Test Harness**:
   * Job `build-and-deploy-dev` executes.
   * Authenticates via WIF without any service account key!
   * Builds container once, tags with `:sha-<short-sha>` and `:dev-latest`.
   * Deploys to `mock-app-dev`.
3. Check the Dev service:
   ```bash
   curl $(terraform -chdir=terraform output -raw dev_service_url)
   ```
   * Displays `APP_VERSION: 1.0.0-dev.<sha>` and `GIT_SHA: <sha>`.

#### ✅ Test 2: Release Tag + Manual Gate (Zero-Rebuild Prod Promotion)
1. Mark the commit as releasable by pushing a semantic version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
   *(Notice: Pushing the tag does NOT deploy to prod on its own).*
2. Go to GitHub $\rightarrow$ **Actions** $\rightarrow$ **Mock App CI/CD Test Harness** $\rightarrow$ **Run workflow**:
   * **Use workflow from**: select tag `v1.0.0`.
   * **Target environment**: select `prod`.
   * Click **Run workflow**.
3. **Observe the Promotion**:
   * Job `promote-and-deploy-prod` executes.
   * **Zero rebuild**: Verifies `:sha-<short-sha>` in Artifact Registry.
   * Stamps `:v1.0.0` and `:prod-latest` via `gcloud artifacts docker tags add`.
   * Deploys to `mock-app-prod` in ~15 seconds.
4. Verify tags in Artifact Registry:
   ```bash
   gcloud artifacts docker images list-tags europe-west1-docker.pkg.dev/lucas--rios-sandbox/mock-app-repo/mock-app
   ```
5. Check the Prod service:
   ```bash
   curl $(terraform -chdir=terraform output -raw prod_service_url)
   ```
   * Displays `APP_VERSION: v1.0.0`.

#### ✅ Test 3: Instant 1-Click Rollback
1. In GitHub Actions $\rightarrow$ **Run workflow**:
   * Target environment: `prod`.
   * **image_tag**: enter `v1.0.0` (or any earlier SHA).
   * Click **Run workflow**.
2. Immediately rolls back `mock-app-prod` to that exact revision!

---

### Step 5: Teardown / Cleanup
```bash
cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test/terraform
terraform destroy -auto-approve
```
