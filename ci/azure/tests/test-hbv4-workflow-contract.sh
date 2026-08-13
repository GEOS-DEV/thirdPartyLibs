#!/usr/bin/env bash
# Validate the HBv4 workflow trust boundary without contacting GitHub or Azure.

set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

ruby - "${repository_root}" <<'RUBY'
require "json"
require "yaml"

root = ARGV.fetch(0)
workflow_path = File.join(root, ".github/workflows/_docker_build_tpls_hbv4_provider.yml")
entry_workflow_path = File.join(root, ".github/workflows/docker_build_tpls_hbv4.yml")
janitor_workflow_path = File.join(root, ".github/workflows/azure-janitor.yml")
provision_path = File.join(root, "ci/azure/actions/provision-hbv4-runner/action.yml")
cleanup_path = File.join(root, "ci/azure/actions/cleanup-runner/action.yml")
bootstrap_path = File.join(root, "ci/azure/scripts/runner-bootstrap.sh")
host_validator_path = File.join(root, "scripts/hbv4/validate-host.sh")
provider_manifest_paths = %w[openmpi mpich].to_h do |provider|
  [provider, File.join(root, "docker/ubuntu-hbv4-#{provider}-spack.yaml")]
end

def assert!(condition, message)
  raise "HBv4 workflow contract failure: #{message}" unless condition
end

def load_yaml(path)
  assert!(File.file?(path), "missing #{path}")
  value = YAML.safe_load(File.read(path), aliases: true, filename: path)
  assert!(value.is_a?(Hash), "#{path} must contain a YAML mapping")
  value
end

def steps_for(job)
  steps = job.fetch("steps", [])
  assert!(steps.is_a?(Array), "job steps must be an array")
  steps
end

def action_steps(action)
  steps = action.fetch("runs", {}).fetch("steps", [])
  assert!(steps.is_a?(Array), "composite action steps must be an array")
  steps
end

def find_one_step(steps, description)
  matches = steps.select { |step| yield(step) }
  assert!(matches.length == 1, "expected exactly one #{description}, found #{matches.length}")
  matches.first
end

def shell_without_comments(script)
  script.each_line.reject { |line| line.strip.start_with?("#") }.join
end

def find_steps_using(value, action_prefix, matches = [])
  case value
  when Hash
    uses = value["uses"]
    matches << value if uses.is_a?(String) && uses.start_with?(action_prefix)
    value.each_value { |child| find_steps_using(child, action_prefix, matches) }
  when Array
    value.each { |child| find_steps_using(child, action_prefix, matches) }
  end
  matches
end

workflow = load_yaml(workflow_path)
entry_workflow = load_yaml(entry_workflow_path)
janitor_workflow = load_yaml(janitor_workflow_path)
provision = load_yaml(provision_path)
cleanup = load_yaml(cleanup_path)
jobs = workflow.fetch("jobs")

# Keep JavaScript actions on their reviewed Node 24 revisions and prevent the
# deprecated numeric GitHub App ID input from returning anywhere in the Azure
# control plane.
auth_documents = [workflow, janitor_workflow, provision, cleanup]
azure_login_ref = "azure/login@f5d393ae46f8fde4be8b75f32e3fc50e654ad0ca"
azure_login_steps = auth_documents.flat_map { |document| find_steps_using(document, "azure/login@") }
assert!(azure_login_steps.length == 5,
        "expected all five Azure login call sites, found #{azure_login_steps.length}")
assert!(azure_login_steps.all? { |step| step["uses"] == azure_login_ref },
        "every Azure login must use the reviewed Node 24 v3.0.1 commit")

app_token_ref =
  "actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1"
app_token_steps = auth_documents.flat_map do |document|
  find_steps_using(document, "actions/create-github-app-token@")
end
assert!(app_token_steps.length == 3,
        "expected all three GitHub App token call sites, found #{app_token_steps.length}")
app_token_steps.each do |step|
  inputs = step.fetch("with", {})
  assert!(step["uses"] == app_token_ref,
          "GitHub App token action must remain immutable and Node 24 compatible")
  assert!(inputs.key?("client-id") && !inputs.key?("app-id"),
          "GitHub App token action must use client-id, never deprecated app-id")
end

auth_contract = JSON.generate(auth_documents)
assert!(!auth_contract.include?("AZURE_RUNNER_APP_ID") &&
        !auth_contract.include?("runner_app_id") &&
        !auth_contract.include?('"app-id"'),
        "legacy numeric GitHub App ID wiring must be absent")
assert!(auth_contract.include?("AZURE_RUNNER_APP_CLIENT_ID") &&
        auth_contract.include?("runner_app_client_id"),
        "GitHub App client ID variable must reach both composite actions")

# The trusted entry workflow must run the checked-in Azure fixtures before it
# authorizes either provider lifecycle to cross the paid provisioning boundary.
authorize_steps = steps_for(entry_workflow.fetch("jobs").fetch("authorize"))
control_checkout_index = authorize_steps.index do |step|
  step["name"] == "Checkout trusted HBv4 control-plane tests"
end
control_test_index = authorize_steps.index do |step|
  step["name"] == "Validate trusted HBv4 control plane"
end
source_index = authorize_steps.index do |step|
  step["name"] == "Validate trigger and live source identity"
end
assert!(!control_checkout_index.nil? && !control_test_index.nil? && !source_index.nil?,
        "entry workflow must checkout, test, and authorize its trusted control plane")
assert!(control_checkout_index < control_test_index && control_test_index < source_index,
        "trusted Azure fixtures must run before source authorization")
control_checkout = authorize_steps.fetch(control_checkout_index)
control_sparse_checkout = control_checkout.fetch("with", {}).fetch("sparse-checkout", "")
control_sparse_paths = control_sparse_checkout.lines.map(&:strip)
assert!(control_sparse_paths.include?("docker/tpl-ubuntu.Dockerfile"),
        "trusted control-plane checkout must include the Dockerfile inspected by resilience tests")
%w[openmpi mpich].each do |provider|
  manifest = "docker/ubuntu-hbv4-#{provider}-spack.yaml"
  assert!(control_sparse_paths.include?(manifest),
          "trusted control-plane checkout must include #{manifest} inspected by contract tests")
end
control_test_script = shell_without_comments(authorize_steps.fetch(control_test_index).fetch("run"))
assert!(control_test_script.include?("ci/azure/tests/test-*.sh") &&
        control_test_script.include?("test-render-runner-bootstrap.py"),
        "entry workflow must run all shell and Python Azure fixtures")

{
  "provision_builder" => "builder",
  "provision_tester" => "tester",
}.each do |job_name, role|
  job = jobs.fetch(job_name)
  permissions = job.fetch("permissions", {})
  assert!(permissions["contents"] == "read", "#{job_name} must grant contents: read")
  assert!(permissions["pull-requests"] == "read",
          "#{job_name} must grant pull-requests: read for live PR authorization")
  assert!(permissions["id-token"] == "write", "#{job_name} must retain Azure OIDC")

  steps = steps_for(job)
  provision_index = steps.index do |step|
    step["uses"] == "./ci/azure/actions/provision-hbv4-runner"
  end
  assert!(!provision_index.nil?, "#{job_name} must call the local provision action")
  assert!(provision_index.positive?, "#{job_name} must authorize before provisioning")
  authorization = steps.fetch(provision_index - 1)
  assert!(authorization.fetch("name", "").include?("Reauthorize live source"),
          "#{job_name} source authorization must immediately precede provisioning")

  authorization_env = authorization.fetch("env", {})
  assert!(authorization_env["GH_TOKEN"] == "${{ github.token }}",
          "#{job_name} source authorization must use the read-only job token")
  assert!(!authorization_env.values.include?("${{ steps.runner_app_token.outputs.token }}"),
          "#{job_name} must not expose the runner-administration App token")
  %w[EVENT_NAME EVENT_REF PR_NUMBER SOURCE_SHA].each do |key|
    assert!(authorization_env.key?(key), "#{job_name} source authorization omitted #{key}")
  end

  script = shell_without_comments(authorization.fetch("run"))
  assert!(script.include?("pull_request_target") && script.include?("workflow_dispatch"),
          "#{job_name} must preserve PR-label and manual-dispatch routes")
  assert!(script.include?('/pulls/${PR_NUMBER}') && script.include?('/commits/${SOURCE_SHA}'),
          "#{job_name} must read live PR and exact commit state")
  assert!(script.include?('.state == "open"') &&
          script.include?(".head.repo.full_name == $repository") &&
          script.include?(".head.sha == $sha") &&
          script.include?("ci: build HBv4 TPL"),
          "#{job_name} PR route must require open, same-repository, exact-head, labelled state")
  assert!(script.include?('refs/pull/${PR_NUMBER}/head'),
          "#{job_name} must bind PR authorization to the canonical head ref")
  assert!(script.include?('.sha // empty') && script.include?('== "${SOURCE_SHA}"'),
          "#{job_name} dispatch route must require the exact repository commit")

  provision_inputs = steps.fetch(provision_index).fetch("with", {})
  assert!(provision_inputs["runner_role"] == role,
          "#{job_name} must pass its exact lifecycle role")
end

provision_steps = action_steps(provision)
provision_text = provision_steps.map { |step| shell_without_comments(step.fetch("run", "")) }.join("\n")
assert!(!provision_text.include?("/pulls/") && !provision_text.include?("/commits/"),
        "provision composite must not perform source authorization with the App token")
assert!(!JSON.generate(provision).include?("github.token"),
        "provision composite must not receive the workflow source-read token")

provision_steps.each do |step|
  environment = step.fetch("env", {})
  assert!(!environment.key?("RUNNER_NAME"),
          "provision step '#{step.fetch("name", "unnamed")}' overrides protected RUNNER_NAME")
  script = shell_without_comments(step.fetch("run", ""))
  assert!(!script.include?('${RUNNER_NAME}'),
          "provision step '#{step.fetch("name", "unnamed")}' reads protected RUNNER_NAME")

  next unless environment.key?("GH_TOKEN")

  assert!(environment["GH_TOKEN"] == "${{ steps.runner_app_token.outputs.token }}",
          "provision composite GH_TOKEN must always be the runner-administration App token")
  endpoints = script.scan(%r{repos/\$\{GITHUB_REPOSITORY\}/[^"'[:space:]]+})
  assert!(!endpoints.empty?, "App-token step must invoke an explicit repository runner endpoint")
  assert!(endpoints.all? { |endpoint| endpoint.start_with?("repos/${GITHUB_REPOSITORY}/actions/runners") },
          "App token escaped the repository runner API: #{endpoints.join(', ')}")
end

create_vm = find_one_step(provision_steps, "paid VM creation step") do |step|
  step["id"] == "create_vm"
end
create_vm_env = create_vm.fetch("env", {})
create_vm_script = shell_without_comments(create_vm.fetch("run"))
assert!(!create_vm_env.key?("GH_TOKEN") && !create_vm_script.match?(/\bgh\s+api\b/),
        "paid VM creation must consume only previously authorized source metadata")
assert!(create_vm_env["HBV4_VM_NAME"] == "${{ steps.identity.outputs.vm_name }}",
        "Azure VM creation must use a task-specific HBV4_VM_NAME variable")
assert!(create_vm_script.include?('az vm create') &&
        create_vm_script.include?('--name "${HBV4_VM_NAME}"'),
        "paid boundary must create the exact validated VM identity")
assert!(create_vm_script.include?("validate-created-hbv4-vm.sh"),
        "paid boundary must validate the raw Azure VM response through the fixture-tested helper")
assert!(!create_vm_script.include?("diskSizeGb"),
        "paid boundary must not use Azure's incorrectly cased disk-size field")
assert!(create_vm_script.include?('.storageProfile.osDisk.managedDisk.id') &&
        create_vm_script.include?('.networkProfile.networkInterfaces[0].id'),
        "paid boundary must recover child resource IDs from the validated raw response")

jit = find_one_step(provision_steps, "JIT configuration step") { |step| step["id"] == "jit" }
jit_script = shell_without_comments(jit.fetch("run"))
assert!(jit.fetch("env", {})["HBV4_JIT_NAME"] == "${{ steps.identity.outputs.runner_name }}",
        "JIT configuration must use a semantic runner-name variable")
assert!(jit_script.include?("runner_id=") && jit_script.include?("runner.name == $name") &&
        jit_script.include?("labels[]"),
        "JIT response must bind runner ID, exact name, and exact label")
assert!(provision.fetch("outputs", {}).fetch("runner_id", {})["value"] ==
        "${{ steps.jit.outputs.runner_id }}",
        "cleanup identity must be captured before Azure VM creation can fail")

render = find_one_step(provision_steps, "bootstrap render step") { |step| step["id"] == "bootstrap" }
render_env = render.fetch("env", {})
render_script = shell_without_comments(render.fetch("run"))
assert!(render_env["BOOTSTRAP_IDENTITY"] == "${{ steps.identity.outputs.vm_name }}",
        "bootstrap output naming must avoid protected RUNNER_NAME")
assert!(render_env["RUNNER_STORAGE_PROFILE"] == "hbv4-nvme-raid0" ||
        render_script.include?("export RUNNER_STORAGE_PROFILE='hbv4-nvme-raid0'"),
        "HBv4 bootstrap rendering must select the reviewed RAID-0 storage profile")
assert!(render_script.include?("render-runner-bootstrap.py"),
        "provision action must call the reviewed renderer")

# Workload validation must prove a writable child of the RAID, never require
# the intentionally root-owned mount root itself to be world-writable.
builder_validation = find_one_step(steps_for(jobs.fetch("build_candidate")),
                                   "builder host validation step") do |step|
  step["name"] == "Validate fixed HBv4 host contract"
end
builder_validation_script = shell_without_comments(builder_validation.fetch("run"))
assert!(builder_validation_script.include?('--writable-path "${GITHUB_WORKSPACE}"'),
        "builder host validation must probe its runner-owned RAID workspace")

tester_validation = find_one_step(steps_for(jobs.fetch("test_candidate")),
                                  "tester candidate validation step") do |step|
  step["name"] == "Pull exact digest and run network-disabled validation"
end
tester_validation_script = shell_without_comments(tester_validation.fetch("run"))
assert!(tester_validation_script.include?('--writable-path "${GITHUB_WORKSPACE}"'),
        "tester host validation must probe its runner-owned RAID workspace")
assert!(tester_validation_script.include?('validation_scratch="${TMPDIR}/container-validation-'),
        "tester container scratch must remain below the writable RAID temporary directory")
assert!(!tester_validation_script.include?('validation_scratch="/mnt/hbv4-local/container-validation-'),
        "tester must not create scratch directly under the protected RAID mount root")

# The workflow declares its root spec alongside its other build configuration;
# provider manifests own Spack target selection and native compiler constraints.
workflow_env = workflow.fetch("env", {})
assert!(workflow_env["SPEC"] == "~pygeosx ~docs %gcc-13",
        "HBv4 workflow must declare the root spec with terminal %gcc-13")

# Source mirroring removes the paid build's dependency on dozens of upstream
# project hosts without permitting binary reuse or an installed upstream.
provider_manifest_paths.each do |provider, path|
  spack_config = load_yaml(path).fetch("spack")
  mirrors = spack_config.fetch("mirrors:")
  assert!(mirrors.keys == ["spack-public"],
          "#{provider} must override lower scopes with only the reviewed source mirror")
  public_mirror = mirrors.fetch("spack-public")
  assert!(public_mirror["url"] == "https://mirror.spack.io" &&
          public_mirror["source"] == true && public_mirror["binary"] == false,
          "#{provider} public mirror must be source-only")
  assert!(spack_config.fetch("upstreams:").empty?,
          "#{provider} must not reuse an installed Spack upstream")
end

builder_steps = steps_for(jobs.fetch("build_candidate"))
candidate_build = find_one_step(builder_steps, "candidate image build step") do |step|
  step["name"] == "Build without cache"
end
candidate_build_script = shell_without_comments(candidate_build.fetch("run"))
assert!(candidate_build_script.include?('--build-arg "SPEC=${SPEC}"'),
        "candidate build must forward the declarative HBv4 root spec")
assert!(!candidate_build_script.include?("hbv4_spec="),
        "candidate build must not hide the root spec in shell-local state")

# A successful immutable promotion must surface a copy/pasteable digest-pinned
# pull command both in the job summary and in the retained lifecycle artifact.
finalizer_steps = steps_for(jobs.fetch("finalize_candidate"))
lifecycle_evidence = find_one_step(finalizer_steps, "lifecycle evidence step") do |step|
  step["name"] == "Write sanitized lifecycle evidence"
end
lifecycle_script = shell_without_comments(lifecycle_evidence.fetch("run"))
assert!(lifecycle_script.include?('if [[ "${PROMOTE_OUTCOME}" == success ]]') &&
        lifecycle_script.include?('[[ "${final_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]'),
        "pull instructions must be emitted only for a valid promoted digest")
assert!(lifecycle_script.include?(
          'final_reference="${final_acr_registry}/${final_repository}@${final_digest}"'
        ) && lifecycle_script.include?("docker pull %s"),
        "pull instructions must use the immutable registry/repository@digest reference")
assert!(lifecycle_script.include?('${evidence_dir}/pull-instructions.md') &&
        lifecycle_script.include?('${GITHUB_STEP_SUMMARY}'),
        "digest-pinned pull instructions must reach the artifact and job summary")

lifecycle_upload = find_one_step(finalizer_steps, "lifecycle evidence upload step") do |step|
  step["name"] == "Upload sanitized lifecycle evidence"
end
assert!(lifecycle_upload.fetch("with", {})["path"] ==
        "${{ runner.temp }}/hbv4-lifecycle-evidence",
        "lifecycle artifact must retain the generated pull instructions")

cleanup_steps = action_steps(cleanup)
cleanup_steps.each do |step|
  environment = step.fetch("env", {})
  next unless environment.key?("GH_TOKEN")

  assert!(environment["GH_TOKEN"] == "${{ steps.runner_app_token.outputs.token }}",
          "cleanup GH_TOKEN must be the runner-administration App token")
  script = shell_without_comments(step.fetch("run", ""))
  endpoints = script.scan(%r{repos/\$\{GITHUB_REPOSITORY\}/[^"'[:space:]]+})
  assert!(!endpoints.empty? &&
          endpoints.all? { |endpoint| endpoint.start_with?("repos/${GITHUB_REPOSITORY}/actions/runners") },
          "cleanup App token may call only repository runner endpoints")
end
cleanup_text = cleanup_steps.map { |step| shell_without_comments(step.fetch("run", "")) }.join("\n")
assert!(cleanup_text.include?("expected_label") && cleanup_text.include?(".labels[]?") &&
        (cleanup_text.include?(".name == $label") || cleanup_text.include?(". == $label")),
        "cleanup must recover a pre-VM registration through its exact lifecycle label")

bootstrap = File.read(bootstrap_path)
assert!(!bootstrap.match?(/^RUNNER_NAME=/) && !bootstrap.include?("@@RUNNER_NAME@@"),
        "guest bootstrap must not define or render GitHub's protected RUNNER_NAME")
assert!(bootstrap.include?('sudo -u "${RUNNER_USER}" -H "${TRUSTED_VALIDATION_ROOT}/validate-host.sh"') &&
        bootstrap.include?('--writable-path "${RUNNER_HOME}"'),
        "guest bootstrap must validate storage as the runner user in its RAID-backed home")

host_validator = File.read(host_validator_path)
assert!(host_validator.include?("--writable-path") &&
        host_validator.include?('mktemp "$writable_path/.hbv4-write-test.XXXXXX"'),
        "host validator must probe an explicit writable workload path")
assert!(!host_validator.include?('mktemp "$mount_path/.hbv4-write-test.XXXXXX"'),
        "host validator must not require write permission on the protected RAID mount root")

puts "HBv4 workflow/token/name contract passed."
RUBY
