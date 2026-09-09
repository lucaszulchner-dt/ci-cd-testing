# 🧪 CI/CD & Terraform Sandbox Test Harness

This self-contained test directory allows you to validate the **Trunk-Based Development** + **Zero-Rebuild Tag Promotion** pipeline end-to-end inside your sandbox project (**`lucas--rios-sandbox`**) before applying it to production.

---

## 📁 Directory Structure

```text
cicdterraform_test/
├── README.md               <-- Step-by-step Runbook & Memo for tomorrow
├── app.py                  <-- Ultra-lightweight Python HTTP server (displays env, version, commit SHA)
├── Dockerfile              <-- Alpine image (builds in ~2 seconds, no npm install needed)
├── .github/
│   └── workflows/
│       └── deploy.yml      <-- Complete pipeline adapted for your sandbox project
└── terraform/
    ├── versions.tf         <-- Google provider (~> 6.0)
    ├── variables.tf        <-- Project ID (lucas--rios-sandbox), region, service names
    ├── main.tf             <-- Creates Artifact Registry, IAM, & 2 Cloud Run services (Dev & Prod)
    ├── outputs.tf          <-- URLs of the Cloud Run services, registry path, SA emails
    └── terraform.tfvars    <-- Default variable values
```

---

## 📋 Memo: Step-by-Step Test Procedure for Tomorrow

Follow these numbered steps in order.

---

### Phase 1: Set Active GCP Project

Run these commands in your local terminal:

```bash
# 1. Authenticate and point gcloud to your sandbox project
gcloud auth login
gcloud config set project lucas--rios-sandbox

# 2. Ensure billing and essential APIs are enabled
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com
```

---

### Phase 2: Provision Infrastructure with Terraform

```bash
cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test/terraform

# 1. Initialize Terraform
terraform init

# 2. Review the plan
terraform plan

# 3. Apply the infrastructure
terraform apply -auto-approve
```

> [!NOTE]
> **Why Day 1 succeeds automatically**:
> The Cloud Run services are bootstrapped with Google's public container (`us-docker.pkg.dev/cloudrun/container/hello`). Because both services include:
> ```hcl
> lifecycle {
>   ignore_changes = [
>     template[0].containers[0].image,
>     template[0].containers[0].env,
>   ]
> }
> ```
> Terraform succeeds immediately without needing an image in your private registry first. When GitHub Actions deploys later, Terraform will never overwrite your deployments!

---

### Phase 3: Create GitHub Deployer Credentials

For testing in your sandbox, the simplest authentication method is a Service Account Key:

```bash
# 1. Generate a JSON key for the deployer service account created by Terraform
gcloud iam service-accounts keys create ~/mock-app-deployer-key.json \
  --iam-account=mock-app-deployer@lucas--rios-sandbox.iam.gserviceaccount.com

# 2. Copy the JSON key content to your clipboard
cat ~/mock-app-deployer-key.json
```

---

### Phase 4: Configure the GitHub Test Repository

1. Create a new test repository on GitHub (e.g. `lucas-rios/cicd-tag-test`).
2. Push the contents of `cicdterraform_test` to that repository:
   ```bash
   cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test
   git init
   git add .
   git commit -m "feat: initial test harness setup"
   git branch -M main
   git remote add origin git@github.com:<YOUR_USER>/cicd-tag-test.git
   git push -u origin main
   ```
3. **Set Repository Secret**:
   * In GitHub: **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions** $\rightarrow$ **New repository secret**.
   * **Name**: `GCP_SA_KEY`
   * **Value**: Paste the entire JSON content from `~/mock-app-deployer-key.json`.
4. **Set Up GitHub Environments**:
   * In GitHub: **Settings** $\rightarrow$ **Environments** $\rightarrow$ **New environment**.
   * Create **`dev`**:
     * No protection rules needed (fully automated).
   * Create **`prod`**:
     * Check **Required reviewers**.
     * Add yourself (`lucas-rios`).
     * Click **Save protection rules**.

---

### Phase 5: Run the 3 Verification Tests

#### ✅ Test 1: Auto-Deploy to Dev on Merge to `main`
1. Make a small edit to `app.py` or trigger the workflow via `workflow_dispatch` (target `dev`).
2. Go to **Actions** $\rightarrow$ **Mock App CI/CD Test Harness**:
   * Job `build-and-deploy-dev` will execute.
   * Builds the container in ~2 seconds.
   * Pushes tags `:sha-<short-sha>` and `:dev-latest` to Artifact Registry.
   * Updates `mock-app-dev` Cloud Run service.
3. Open the Dev Cloud Run URL from your Terraform output:
   ```bash
   curl $(terraform -chdir=terraform output -raw dev_service_url)
   ```
   * You will see the HTML card showing:
     * **Environment**: `DEV`
     * **App Version**: `sha-xxxx`
     * **Git SHA**: `<commit-sha>`

#### ✅ Test 2: Zero-Rebuild Release with Manual Gate to `prod`
1. Mark the commit as releasable by pushing a semantic version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. Go to GitHub $\rightarrow$ **Actions** $\rightarrow$ **Mock App CI/CD Test Harness** $\rightarrow$ **Run workflow**:
   * **Use workflow from**: select tag `v1.0.0`.
   * **Target environment**: select `prod`.
   * Click **Run workflow**.
3. **Observe the Manual Gate**:
   * The workflow starts `promote-and-deploy-prod` and immediately enters **"Waiting for review"**.
   * Click **Review deployments** $\rightarrow$ select `prod` $\rightarrow$ click **Approve and deploy**.
4. **Observe the Promotion**:
   * Runs in **~15 seconds**.
   * **NO Docker build occurs**.
   * It stamps `:v1.0.0` and `:prod-latest` onto the pre-built Dev image.
   * Updates `mock-app-prod`.
5. Verify in Artifact Registry:
   ```bash
   gcloud artifacts docker images list-tags europe-west1-docker.pkg.dev/lucas--rios-sandbox/mock-app-repo/mock-app
   ```
   * You will see `:sha-xxxx`, `:dev-latest`, `:v1.0.0`, and `:prod-latest` all pointing to the respective digests!
6. Open the Prod Cloud Run URL:
   ```bash
   curl $(terraform -chdir=terraform output -raw prod_service_url)
   ```
   * You will see:
     * **Environment**: `PROD`
     * **App Version**: `v1.0.0`

#### ✅ Test 3: 1-Click Rollback Test
1. In GitHub Actions $\rightarrow$ **Run workflow**:
   * Select `prod`.
   * Under **image_tag**, enter: `v1.0.0` (or any specific earlier SHA).
   * Click **Run workflow** and approve.
2. It verifies the image exists and immediately points `mock-app-prod` back to that tag!

---

### Phase 6: Teardown / Cleanup

When you are finished testing, clean up all sandbox resources with one command:

```bash
cd /home/lnx/wrk/ai-career-advisor/cicdterraform_test/terraform
terraform destroy -auto-approve

# Remove local key file
rm -f ~/mock-app-deployer-key.json
```
