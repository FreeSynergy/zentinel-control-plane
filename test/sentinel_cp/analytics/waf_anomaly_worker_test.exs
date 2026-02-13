defmodule SentinelCp.Analytics.WafAnomalyWorkerTest do
  use SentinelCp.DataCase

  alias SentinelCp.Analytics
  alias SentinelCp.Analytics.{WafBaselineWorker, WafAnomalyWorker}

  defp create_project_with_events(_) do
    {:ok, org} = SentinelCp.Orgs.create_org(%{name: "Worker Org", slug: "worker-org"})

    {:ok, project} =
      SentinelCp.Projects.create_project(%{
        name: "Worker Project",
        slug: "worker-proj",
        org_id: org.id
      })

    now = DateTime.utc_now()

    # Create baseline WAF events (simulating 7 days of normal activity)
    base_events =
      for _i <- 1..50 do
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(DateTime.add(now, -Enum.random(1..168) * 3600, :second)),
          "rule_type" => Enum.random(["sqli", "xss"]),
          "action" => "blocked",
          "severity" => "medium",
          "client_ip" => "10.0.0.#{Enum.random(1..5)}",
          "method" => "GET",
          "path" => "/api/test"
        }
      end

    {:ok, _} = Analytics.ingest_waf_events(base_events)

    %{project: project}
  end

  describe "WafBaselineWorker" do
    setup [:create_project_with_events]

    test "computes baselines from events", %{project: project} do
      assert :ok = WafBaselineWorker.perform(%Oban.Job{args: %{}})

      baselines = Analytics.get_waf_baselines(project.id)
      assert length(baselines) > 0

      # Should have at least total_blocks baseline
      types = Enum.map(baselines, & &1.metric_type)
      assert "total_blocks" in types
    end
  end

  describe "WafAnomalyWorker" do
    setup [:create_project_with_events]

    test "runs without errors when baselines exist", %{project: _project} do
      # First compute baselines
      WafBaselineWorker.perform(%Oban.Job{args: %{}})

      # Then run anomaly detection
      assert :ok = WafAnomalyWorker.perform(%Oban.Job{args: %{}})
    end

    test "runs without errors when no baselines exist" do
      assert :ok = WafAnomalyWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
