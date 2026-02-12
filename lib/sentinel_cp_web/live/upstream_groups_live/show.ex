defmodule SentinelCpWeb.UpstreamGroupsLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => group_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         group when not is_nil(group) <- Services.get_upstream_group(group_id),
         true <- group.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Upstream Group #{group.name} — #{project.name}",
         org: org,
         project: project,
         group: group
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    group = socket.assigns.group
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_upstream_group(group) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "upstream_group", group.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Upstream group deleted.")
         |> push_navigate(to: groups_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete upstream group.")}
    end
  end

  @impl true
  def handle_event("add_target", params, socket) do
    group = socket.assigns.group

    attrs = %{
      upstream_group_id: group.id,
      host: params["host"],
      port: parse_int(params["port"]),
      weight: parse_int(params["weight"]) || 100
    }

    case Services.add_upstream_target(attrs) do
      {:ok, _target} ->
        group = Services.get_upstream_group!(group.id)
        {:noreply, assign(socket, group: group) |> put_flash(:info, "Target added.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  @impl true
  def handle_event("remove_target", %{"id" => target_id}, socket) do
    target = Services.get_upstream_target(target_id)

    if target do
      Services.remove_upstream_target(target)
      group = Services.get_upstream_group!(socket.assigns.group.id)
      {:noreply, assign(socket, group: group) |> put_flash(:info, "Target removed.")}
    else
      {:noreply, put_flash(socket, :error, "Target not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@group.name}
        resource_type="upstream group"
        back_path={groups_path(@org, @project)}
      >
        <:action>
          <.link
            navigate={group_edit_path(@org, @project, @group)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this upstream group?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Configuration">
          <.definition_list>
            <:item label="Name">{@group.name}</:item>
            <:item label="Slug"><span class="font-mono">{@group.slug}</span></:item>
            <:item label="Algorithm">{@group.algorithm}</:item>
            <:item label="Description">{@group.description || "—"}</:item>
            <:item label="Health Check">{format_map(@group.health_check)}</:item>
            <:item label="Circuit Breaker">{format_map(@group.circuit_breaker)}</:item>
            <:item label="Sticky Sessions">{format_map(@group.sticky_sessions)}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Targets">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="text-xs">Host</th>
                <th class="text-xs">Port</th>
                <th class="text-xs">Weight</th>
                <th class="text-xs">Enabled</th>
                <th class="text-xs"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={target <- @group.targets}>
                <td class="font-mono text-sm">{target.host}</td>
                <td class="text-sm">{target.port}</td>
                <td class="text-sm">{target.weight}</td>
                <td>
                  <span class={["badge badge-xs", (target.enabled && "badge-success") || "badge-ghost"]}>
                    {if target.enabled, do: "yes", else: "no"}
                  </span>
                </td>
                <td>
                  <button
                    phx-click="remove_target"
                    phx-value-id={target.id}
                    data-confirm="Remove this target?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Remove
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@group.targets == []} class="text-center py-4 text-base-content/50 text-sm">
            No targets yet.
          </div>

          <form phx-submit="add_target" class="flex items-end gap-2 mt-4 pt-4 border-t border-base-300">
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Host</span></label>
              <input type="text" name="host" required class="input input-bordered input-xs w-40" placeholder="api.internal" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Port</span></label>
              <input type="number" name="port" required class="input input-bordered input-xs w-20" placeholder="8080" min="1" max="65535" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Weight</span></label>
              <input type="number" name="weight" class="input input-bordered input-xs w-20" placeholder="100" min="1" />
            </div>
            <button type="submit" class="btn btn-outline btn-xs">Add Target</button>
          </form>
        </.k8s_section>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp groups_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups"

  defp groups_path(nil, project),
    do: ~p"/projects/#{project.slug}/upstream-groups"

  defp group_edit_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}/edit"

  defp group_edit_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}/edit"

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n

  defp format_map(nil), do: "—"
  defp format_map(map) when map == %{}, do: "—"
  defp format_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end
end
