defmodule SymphonyElixir.LocalScriptsTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../..", __DIR__)

  test "dashboard helper loads env, runs preflight, and prints guarded dashboard command in dry run" do
    test_root = tmp_dir("symphony-local-helper")
    fake_bin = Path.join(test_root, "bin")
    env_file = Path.join(test_root, ".env")
    workspace_root = Path.join(test_root, "workspaces")

    File.mkdir_p!(fake_bin)
    File.write!(env_file, "LINEAR_API_KEY=lin_test_secret\nSYMPHONY_WORKSPACE_ROOT=#{workspace_root}\n")
    write_fake_tools!(fake_bin, gh_auth?: true)

    {output, status} =
      System.cmd("bash", ["scripts/run_symphony_dashboard.sh"],
        cd: @repo_root,
        stderr_to_stdout: true,
        env: script_env(fake_bin, env_file)
      )

    assert status == 0
    assert output =~ "Preflight passed"
    assert output =~ "Would start Symphony dashboard"
    assert output =~ "--i-understand-that-this-will-be-running-without-the-usual-guardrails"
    assert output =~ "--port 4000"
    assert output =~ "../WORKFLOW.md"
    assert output =~ "http://127.0.0.1:4000/"
    refute output =~ "lin_test_secret"
  end

  test "preflight fails on missing GitHub auth without leaking Linear key" do
    test_root = tmp_dir("symphony-preflight-gh-auth")
    fake_bin = Path.join(test_root, "bin")
    env_file = Path.join(test_root, ".env")

    File.mkdir_p!(fake_bin)
    File.write!(env_file, "LINEAR_API_KEY=lin_secret_should_not_print\n")
    write_fake_tools!(fake_bin, gh_auth?: false)

    {output, status} =
      System.cmd("bash", ["scripts/preflight.sh"],
        cd: @repo_root,
        stderr_to_stdout: true,
        env: script_env(fake_bin, env_file)
      )

    assert status != 0
    assert output =~ "GitHub authentication is unavailable"
    refute output =~ "lin_secret_should_not_print"
  end

  test "root workflow gives child workers network and writable workspace access" do
    workflow_path = Path.join(@repo_root, "WORKFLOW.md")

    assert {:ok, %{config: config}} = SymphonyElixir.Workflow.load(workflow_path)

    policy = get_in(config, ["codex", "turn_sandbox_policy"])

    assert policy["type"] == "workspaceWrite"
    assert policy["writableRoots"] == ["$SYMPHONY_WORKSPACE_ROOT"]
    assert policy["networkAccess"] == true
    assert policy["readOnlyAccess"] == %{"type" => "fullAccess"}
  end

  defp script_env(fake_bin, env_file) do
    [
      {"PATH", fake_bin <> ":" <> System.get_env("PATH", "")},
      {"SYMPHONY_ENV_FILE", env_file},
      {"SYMPHONY_TEST_REPO_ROOT", @repo_root},
      {"SYMPHONY_DRY_RUN", "1"}
    ]
  end

  defp tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf(path) end)

    path
  end

  defp write_fake_tools!(fake_bin, opts) do
    gh_auth? = Keyword.fetch!(opts, :gh_auth?)

    write_executable!(
      Path.join(fake_bin, "git"),
      """
      #!/usr/bin/env bash
      set -euo pipefail
      if [ "${1:-}" = "-C" ]; then
        shift 2
      fi
      case "${1:-} ${2:-} ${3:-}" in
        "rev-parse --show-toplevel ") echo "${SYMPHONY_TEST_REPO_ROOT}" ;;
        "remote get-url origin") echo "https://github.com/tblakex01/symphony.git" ;;
        "remote get-url upstream") echo "https://github.com/openai/symphony.git" ;;
        "ls-remote --exit-code origin") exit 0 ;;
        "push --dry-run origin") exit 0 ;;
        *) echo "unexpected git $*" >&2; exit 2 ;;
      esac
      """
    )

    gh_status =
      if gh_auth? do
        "exit 0"
      else
        "echo 'not logged in' >&2; exit 1"
      end

    write_executable!(
      Path.join(fake_bin, "gh"),
      """
      #!/usr/bin/env bash
      set -euo pipefail
      case "${1:-} ${2:-}" in
        "auth status") #{gh_status} ;;
        "repo view") echo "tblakex01/symphony" ;;
        *) echo "unexpected gh $*" >&2; exit 2 ;;
      esac
      """
    )

    write_executable!(
      Path.join(fake_bin, "curl"),
      """
      #!/usr/bin/env bash
      set -euo pipefail
      config="$(cat)"
      case "$config" in
        *'data = "{\\"query\\":\\"query { viewer { id name } }\\"}"'*) ;;
        *) echo "unexpected curl config" >&2; exit 2 ;;
      esac
      echo '{"data":{"viewer":{"id":"user-id","name":"Test User"}}}'
      """
    )

    write_executable!(
      Path.join(fake_bin, "mise"),
      """
      #!/usr/bin/env bash
      set -euo pipefail
      case "${1:-} ${2:-}" in
        "--version ") echo "mise test-version" ;;
        "trust --show") echo "${SYMPHONY_TEST_REPO_ROOT}/elixir: trusted" ;;
        *) echo "unexpected mise $*" >&2; exit 2 ;;
      esac
      """
    )

    write_executable!(
      Path.join(fake_bin, "lsof"),
      """
      #!/usr/bin/env bash
      exit 1
      """
    )
  end

  defp write_executable!(path, body) do
    File.write!(path, body)
    File.chmod!(path, 0o755)
  end
end
