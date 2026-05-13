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

    write_fake_tools!(fake_bin,
      gh_auth?: true,
      origin_url: "https://github.com/symphony/symphony.git"
    )

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

  test "dashboard helper runs preflight before preparing the Elixir runtime" do
    test_root = tmp_dir("symphony-local-helper-order")
    fake_bin = Path.join(test_root, "bin")
    env_file = Path.join(test_root, ".env")
    event_log = Path.join(test_root, "events.log")

    File.mkdir_p!(fake_bin)
    File.write!(env_file, "LINEAR_API_KEY=lin_test_secret\n")
    write_fake_tools!(fake_bin, gh_auth?: true)

    {output, status} =
      System.cmd("bash", ["scripts/run_symphony_dashboard.sh"],
        cd: @repo_root,
        stderr_to_stdout: true,
        env:
          script_env(fake_bin, env_file,
            dry_run?: false,
            extra_env: [{"SYMPHONY_EVENT_LOG", event_log}]
          )
      )

    assert status == 0
    assert output =~ "Preflight passed"
    assert output =~ "Starting Symphony dashboard at http://127.0.0.1:4000/"

    events = event_log |> File.read!() |> String.split("\n", trim: true)

    assert event_index(events, "git:push --dry-run origin") < exact_event_index(events, "mise:trust")
    assert exact_event_index(events, "mise:trust --show") < exact_event_index(events, "mise:trust")
    assert exact_event_index(events, "mise:trust --show") < event_index(events, "mise:exec -- mix setup")
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

  defp script_env(fake_bin, env_file, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run?, true)
    extra_env = Keyword.get(opts, :extra_env, [])

    base_env = [
      {"PATH", fake_bin <> ":" <> System.get_env("PATH", "")},
      {"SYMPHONY_ENV_FILE", env_file},
      {"SYMPHONY_TEST_REPO_ROOT", @repo_root},
      {"SYMPHONY_DRY_RUN", if(dry_run?, do: "1", else: "0")}
    ]

    base_env ++ extra_env
  end

  defp event_index(events, prefix) do
    index = Enum.find_index(events, &String.starts_with?(&1, prefix))

    assert index != nil, "missing event with prefix #{inspect(prefix)} in #{inspect(events)}"

    index
  end

  defp exact_event_index(events, event) do
    index = Enum.find_index(events, &(&1 == event))

    assert index != nil, "missing event #{inspect(event)} in #{inspect(events)}"

    index
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
    origin_url = Keyword.get(opts, :origin_url, "https://github.com/tblakex01/symphony.git")

    write_executable!(
      Path.join(fake_bin, "git"),
      """
      #!/usr/bin/env bash
      set -euo pipefail
      if [ "${1:-}" = "-C" ]; then
        shift 2
      fi
      if [ -n "${SYMPHONY_EVENT_LOG:-}" ]; then
        printf 'git:%s\\n' "$*" >> "$SYMPHONY_EVENT_LOG"
      fi
      case "${1:-} ${2:-} ${3:-}" in
        "rev-parse --show-toplevel ") echo "${SYMPHONY_TEST_REPO_ROOT}" ;;
        "remote get-url origin") echo "#{origin_url}" ;;
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
      if [ -n "${SYMPHONY_EVENT_LOG:-}" ]; then
        printf 'gh:%s\\n' "$*" >> "$SYMPHONY_EVENT_LOG"
      fi
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
      if [ -n "${SYMPHONY_EVENT_LOG:-}" ]; then
        printf 'curl:%s\\n' "$*" >> "$SYMPHONY_EVENT_LOG"
      fi
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
      if [ -n "${SYMPHONY_EVENT_LOG:-}" ]; then
        printf 'mise:%s\\n' "$*" >> "$SYMPHONY_EVENT_LOG"
      fi
      case "$*" in
        "--version") echo "mise test-version" ;;
        "trust --show") echo "${SYMPHONY_TEST_REPO_ROOT}/elixir: trusted" ;;
        "trust") exit 0 ;;
        "install") exit 0 ;;
        "exec -- mix setup") exit 0 ;;
        "exec -- mix build") exit 0 ;;
        "exec -- ./bin/symphony"*) exit 0 ;;
        *) echo "unexpected mise $*" >&2; exit 2 ;;
      esac
      """
    )

    write_executable!(
      Path.join(fake_bin, "lsof"),
      """
      #!/usr/bin/env bash
      if [ -n "${SYMPHONY_EVENT_LOG:-}" ]; then
        printf 'lsof:%s\\n' "$*" >> "$SYMPHONY_EVENT_LOG"
      fi
      exit 1
      """
    )
  end

  defp write_executable!(path, body) do
    File.write!(path, body)
    File.chmod!(path, 0o755)
  end
end
