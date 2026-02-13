defmodule SentinelCp.ConfigExportTest do
  use SentinelCp.DataCase, async: false

  alias SentinelCp.ConfigExport
  alias SentinelCp.GraphQL.Schema, as: GraphQLSchema

  import SentinelCp.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  # ─── 18.3 Config Export ──────────────────────────────────────────

  describe "config export" do
    test "exports a project configuration", %{project: project} do
      {:ok, config} = ConfigExport.export(project.id)

      assert config["version"] == "1.0"
      assert config["project"]["name"] == project.name
      assert config["project"]["slug"] == project.slug
      assert is_list(config["environments"])
      assert is_list(config["services"])
      assert is_list(config["upstream_groups"])
      assert is_list(config["certificates"])
      assert is_list(config["auth_policies"])
      assert is_list(config["middlewares"])
    end

    test "exports with services", %{project: project} do
      # Create a service
      create_service(project, "api-gateway", "/api")

      {:ok, config} = ConfigExport.export(project.id)

      assert length(config["services"]) == 1
      svc = hd(config["services"])
      assert svc["name"] == "api-gateway"
      assert svc["route_path"] == "/api"
    end

    test "exports with environments", %{project: project} do
      create_environment(project, "staging")
      create_environment(project, "production")

      {:ok, config} = ConfigExport.export(project.id)

      assert length(config["environments"]) == 2
      names = Enum.map(config["environments"], & &1["name"])
      assert "staging" in names
      assert "production" in names
    end

    test "exported config has timestamp", %{project: project} do
      {:ok, config} = ConfigExport.export(project.id)
      assert config["exported_at"] != nil
    end
  end

  # ─── 18.3 Config Import ─────────────────────────────────────────

  describe "config import" do
    test "imports environments", %{project: project} do
      config = %{
        "environments" => [
          %{"name" => "staging"},
          %{"name" => "production"}
        ]
      }

      {:ok, summary} = ConfigExport.import_config(project.id, config)
      assert summary.created == 2
      assert summary.errors == []
    end

    test "skips existing resources on reimport", %{project: project} do
      create_environment(project, "staging")

      config = %{
        "environments" => [
          %{"name" => "staging"},
          %{"name" => "production"}
        ]
      }

      {:ok, summary} = ConfigExport.import_config(project.id, config)
      assert summary.created == 1
      assert summary.skipped == 1
    end

    test "imports with empty config", %{project: project} do
      {:ok, summary} = ConfigExport.import_config(project.id, %{})
      assert summary.created == 0
      assert summary.skipped == 0
    end
  end

  # ─── 18.3 Config Diff ───────────────────────────────────────────

  describe "config diff" do
    test "detects additions", %{project: project} do
      config = %{
        "environments" => [%{"name" => "new-env"}],
        "services" => [%{"name" => "new-service", "route_path" => "/new"}]
      }

      {:ok, changes} = ConfigExport.diff(project.id, config)

      additions = Enum.filter(changes, fn {action, _, _} -> action == :add end)
      assert length(additions) >= 2
    end

    test "detects removals", %{project: project} do
      create_environment(project, "old-env")

      config = %{
        "environments" => []
      }

      {:ok, changes} = ConfigExport.diff(project.id, config)

      removals = Enum.filter(changes, fn {action, _, _} -> action == :remove end)
      assert length(removals) >= 1
    end

    test "detects no changes for matching config", %{project: project} do
      {:ok, current} = ConfigExport.export(project.id)

      {:ok, changes} = ConfigExport.diff(project.id, current)
      assert changes == []
    end
  end

  # ─── 18.3 Round-trip ────────────────────────────────────────────

  describe "export/import round-trip" do
    test "export then reimport is idempotent", %{project: project} do
      create_environment(project, "staging")
      create_service(project, "api", "/api")

      {:ok, config} = ConfigExport.export(project.id)

      # Import into same project — should skip everything
      {:ok, summary} = ConfigExport.import_config(project.id, config)
      assert summary.created == 0
      assert summary.skipped >= 2
    end
  end

  # ─── 18.4 GraphQL Schema ────────────────────────────────────────

  describe "GraphQL schema" do
    test "defines query fields" do
      fields = GraphQLSchema.query_fields()
      assert :project in fields
      assert :services in fields
      assert :nodes in fields
      assert :bundles in fields
      assert :rollouts in fields
      assert :alert_rules in fields
      assert :slos in fields
      assert :policies in fields
    end

    test "defines mutation fields" do
      fields = GraphQLSchema.mutation_fields()
      assert :create_rollout in fields
      assert :pause_rollout in fields
      assert :create_bundle in fields
    end

    test "defines subscription fields" do
      fields = GraphQLSchema.subscription_fields()
      assert :rollout_progress in fields
      assert :node_status in fields
      assert :alert_state in fields
    end

    test "defines type names" do
      types = GraphQLSchema.type_names()
      assert :project in types
      assert :service in types
      assert :node in types
      assert :bundle in types
      assert :rollout in types
      assert :alert_rule in types
      assert :slo in types
      assert :policy in types
    end

    test "type definitions include resolvers" do
      defs = GraphQLSchema.type_definitions()
      assert defs.query.project.resolver != nil
      assert defs.mutation.create_rollout.resolver != nil
    end

    test "subscription topics are defined" do
      defs = GraphQLSchema.type_definitions()
      assert defs.subscription.rollout_progress.topic == "rollout:*"
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────

  defp create_service(project, name, route_path) do
    {:ok, service} =
      %SentinelCp.Services.Service{}
      |> Ecto.Changeset.change(%{
        project_id: project.id,
        name: name,
        slug: name,
        route_path: route_path
      })
      |> Repo.insert()

    service
  end

  defp create_environment(project, name) do
    {:ok, env} =
      %SentinelCp.Projects.Environment{}
      |> SentinelCp.Projects.Environment.create_changeset(%{
        project_id: project.id,
        name: name
      })
      |> Repo.insert()

    env
  end
end
