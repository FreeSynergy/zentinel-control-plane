defmodule SentinelCpWeb.Api.ConfigExportController do
  use SentinelCpWeb, :controller

  alias SentinelCp.ConfigExport

  def export(conn, %{"project_id" => project_id}) do
    case ConfigExport.export(project_id) do
      {:ok, config} ->
        json(conn, config)

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  def import(conn, %{"project_id" => project_id} = params) do
    config = Map.drop(params, ["project_id"])

    case ConfigExport.import_config(project_id, config) do
      {:ok, summary} ->
        json(conn, %{
          status: "ok",
          created: summary.created,
          updated: summary.updated,
          skipped: summary.skipped,
          errors: length(summary.errors)
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def diff(conn, %{"project_id" => project_id} = params) do
    config = Map.drop(params, ["project_id"])

    case ConfigExport.diff(project_id, config) do
      {:ok, changes} ->
        formatted =
          Enum.map(changes, fn {action, resource_type, name} ->
            %{action: action, resource_type: resource_type, name: name}
          end)

        json(conn, %{changes: formatted})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end
end
